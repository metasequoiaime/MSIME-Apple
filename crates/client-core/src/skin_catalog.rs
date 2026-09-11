//! Safe discovery and validation of external candidate-skin manifests.

use std::fs;
use std::io::Read;
use std::path::Path;
use toml::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkinSummary {
    pub id: String,
    pub name: String,
    pub version: String,
    pub base: String,
    pub author: Option<String>,
    pub description: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkinIssue {
    pub folder: String,
    pub reason: String,
}

#[derive(Debug, Default, Clone, PartialEq, Eq)]
pub struct SkinCatalog {
    pub packages: Vec<SkinSummary>,
    pub issues: Vec<SkinIssue>,
}

fn safe_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 64
        && id.as_bytes()[0].is_ascii_alphanumeric()
        && id.bytes().all(|b| {
            b.is_ascii_lowercase() || b.is_ascii_digit() || matches!(b, b'.' | b'_' | b'-')
        })
}

fn contained(root: &Path, child: &Path) -> bool {
    root.canonicalize()
        .ok()
        .and_then(|r| child.canonicalize().ok().map(|c| c.starts_with(r)))
        .unwrap_or(false)
}

fn required_string(
    table: &toml::map::Map<String, Value>,
    key: &str,
    max: usize,
) -> Result<String, String> {
    let value = table
        .get(key)
        .and_then(Value::as_str)
        .ok_or_else(|| format!("{key} must be a string"))?;
    if value.is_empty() || value.len() > max {
        return Err(format!("{key} has invalid length"));
    }
    Ok(value.to_owned())
}

fn optional_string(
    table: &toml::map::Map<String, Value>,
    key: &str,
    max: usize,
) -> Result<Option<String>, String> {
    let Some(value) = table.get(key) else {
        return Ok(None);
    };
    let value = value
        .as_str()
        .ok_or_else(|| format!("{key} must be a string"))?;
    if value.is_empty() || value.len() > max {
        return Err(format!("{key} has invalid length"));
    }
    Ok(Some(value.to_owned()))
}

fn safe_resource(value: &str, max: usize) -> bool {
    !value.is_empty()
        && value.len() <= max
        && !value.starts_with('/')
        && !value.starts_with('\\')
        && !value.contains('\\')
        && value.split('/').all(|part| {
            !part.is_empty()
                && part != "."
                && part != ".."
                && part
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || matches!(b, b'.' | b'_' | b'-'))
        })
}

fn enum_array(table: &toml::map::Map<String, Value>, key: &str, allowed: &[&str]) -> bool {
    table
        .get(key)
        .and_then(Value::as_array)
        .is_some_and(|items| {
            !items.is_empty()
                && items.iter().enumerate().all(|(index, item)| {
                    item.as_str().is_some_and(|value| allowed.contains(&value))
                        && !items[..index].contains(item)
                })
        })
}

fn load(root: &Path, folder: &str) -> Result<SkinSummary, String> {
    if !safe_id(folder) || matches!(folder, "fluent" | "wechat" | "graphite" | "willow_green") {
        return Err("invalid skin id".into());
    }
    let dir = root.join(folder);
    let manifest = dir.join("skin.toml");
    if !contained(root, &dir) || !contained(&dir, &manifest) {
        return Err("manifest escapes skin directory".into());
    }
    let input = fs::File::open(&manifest).map_err(|_| "missing skin.toml".to_owned())?;
    if !input
        .metadata()
        .map_err(|_| "unreadable skin.toml")?
        .is_file()
    {
        return Err("skin.toml is not a regular file".into());
    }
    let mut bytes = Vec::new();
    input
        .take(65_537)
        .read_to_end(&mut bytes)
        .map_err(|_| "unreadable skin.toml")?;
    if bytes.len() > 65_536 {
        return Err("skin.toml is too large".into());
    }
    let value: Value =
        toml::from_str(std::str::from_utf8(&bytes).map_err(|_| "skin.toml is not UTF-8")?)
            .map_err(|_| "invalid TOML")?;
    let table = value.as_table().ok_or("manifest must be a table")?;
    if table.get("schema_version").and_then(Value::as_integer) != Some(1) {
        return Err("unsupported schema_version".into());
    }
    let id = required_string(table, "id", 64)?;
    if id != folder || !safe_id(&id) {
        return Err("manifest id does not match folder".into());
    }
    let name = required_string(table, "name", 80)?;
    let version = required_string(table, "version", 32)?;
    let base = required_string(table, "base", 32)?;
    let author = optional_string(table, "author", 120)?;
    let description = optional_string(table, "description", 500)?;
    if !matches!(
        base.as_str(),
        "fluent" | "wechat" | "graphite" | "willow_green"
    ) {
        return Err("unsupported base skin".into());
    }
    let supports = table
        .get("supports")
        .and_then(Value::as_table)
        .ok_or("missing supports")?;
    if !enum_array(supports, "layouts", &["horizontal", "vertical"])
        || !enum_array(supports, "themes", &["dark", "light"])
    {
        return Err("invalid supports".into());
    }
    let window = table
        .get("candidate_window")
        .and_then(Value::as_table)
        .ok_or("missing candidate_window")?;
    let number = |value: Option<&Value>| match value {
        None => 0.0,
        Some(value) => value
            .as_float()
            .or_else(|| value.as_integer().map(|n| n as f64))
            .unwrap_or(f64::NAN),
    };
    let min_width = number(window.get("min_width_dip"));
    if !min_width.is_finite() || !(0.0..=1000.0).contains(&min_width) {
        return Err("invalid min_width_dip".into());
    }
    let decoration = window
        .get("decoration")
        .and_then(Value::as_table)
        .ok_or("missing decoration")?;
    let top = number(decoration.get("top_inset_dip"));
    let width = number(decoration.get("width_dip"));
    if !top.is_finite()
        || !width.is_finite()
        || !(0.0..=500.0).contains(&top)
        || !(0.0..=1000.0).contains(&width)
        || (top == 0.0) != (width == 0.0)
    {
        return Err("invalid decoration".into());
    }
    if let Some(stylesheet) = optional_string(table, "toolbar_stylesheet", 128)? {
        if !safe_resource(&stylesheet, 128)
            || stylesheet.contains('/')
            || stylesheet.len() <= 4
            || !stylesheet.ends_with(".css")
            || !contained(&dir, &dir.join(&stylesheet))
            || !dir.join(&stylesheet).is_file()
        {
            return Err("invalid toolbar_stylesheet".into());
        }
    }
    if let Some(preview) = optional_string(table, "preview", 256)? {
        if !safe_resource(&preview, 256) || !contained(&dir, &dir.join(&preview)) {
            return Err("invalid preview".into());
        }
    }
    Ok(SkinSummary {
        id,
        name,
        version,
        base,
        author,
        description,
    })
}

pub fn scan(root: impl AsRef<Path>) -> SkinCatalog {
    let root = root.as_ref();
    let mut out = SkinCatalog::default();
    let Ok(entries) = fs::read_dir(root) else {
        return out;
    };
    for entry in entries.flatten() {
        let Ok(kind) = entry.file_type() else {
            continue;
        };
        if !kind.is_dir() {
            continue;
        }
        let folder = entry.file_name().to_string_lossy().into_owned();
        match load(root, &folder) {
            Ok(package) => out.packages.push(package),
            Err(reason) => out.issues.push(SkinIssue { folder, reason }),
        }
    }
    out.packages.sort_by(|a, b| a.name.cmp(&b.name));
    out.issues.sort_by(|a, b| a.folder.cmp(&b.folder));
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;
    fn manifest(id: &str) -> String {
        format!("schema_version = 1\nid = '{id}'\nname = 'Sample'\nversion = '1.0'\nbase = 'fluent'\n[supports]\nlayouts = ['vertical']\nthemes = ['light']\n[candidate_window]\nmin_width_dip = 10\n[candidate_window.decoration]\ntop_inset_dip = 0\nwidth_dip = 0\n")
    }

    fn scan_manifest(body: &str) -> SkinCatalog {
        let root = tempdir().unwrap();
        let skin = root.path().join("sample");
        fs::create_dir(&skin).unwrap();
        fs::write(skin.join("skin.toml"), body).unwrap();
        scan(root.path())
    }

    #[test]
    fn rejects_duplicate_supported_layouts_and_themes() {
        for (from, to) in [
            ("['vertical']", "['vertical', 'vertical']"),
            ("['light']", "['light', 'light']"),
        ] {
            let result = scan_manifest(&manifest("sample").replace(from, to));
            assert!(result.packages.is_empty());
            assert_eq!(result.issues[0].reason, "invalid supports");
        }
    }

    #[test]
    fn rejects_wrong_numeric_types_and_nonfinite_or_out_of_range_dimensions() {
        for field in ["min_width_dip = 10", "top_inset_dip = 0", "width_dip = 0"] {
            let key = field.split(" = ").next().unwrap();
            for value in ["'10'", "false", "[]", "{}", "nan", "inf", "-1", "1001"] {
                let result =
                    scan_manifest(&manifest("sample").replace(field, &format!("{key} = {value}")));
                assert!(result.packages.is_empty(), "accepted {key}={value}");
                assert_eq!(result.issues.len(), 1);
            }
        }
        assert_eq!(scan_manifest(&manifest("sample")).packages.len(), 1);
        let defaults = manifest("sample")
            .replace("min_width_dip = 10\n", "")
            .replace("top_inset_dip = 0\n", "")
            .replace("width_dip = 0\n", "");
        assert_eq!(scan_manifest(&defaults).packages.len(), 1);
    }

    #[test]
    fn rejects_builtin_ids_as_external_skin_folders() {
        let root = tempdir().unwrap();
        for id in ["fluent", "wechat", "graphite", "willow_green"] {
            let skin = root.path().join(id);
            fs::create_dir(&skin).unwrap();
            fs::write(skin.join("skin.toml"), manifest(id)).unwrap();
        }
        let catalog = scan(root.path());
        assert!(catalog.packages.is_empty());
        assert_eq!(catalog.issues.len(), 4);
    }

    #[test]
    fn toolbar_stylesheet_must_be_a_single_regular_css_file() {
        for (resource, directory) in [
            ("toolbar.css", false),
            ("toolbar.css", true),
            ("nested/toolbar.css", false),
            (".css", false),
        ] {
            let root = tempdir().unwrap();
            let skin = root.path().join("sample");
            fs::create_dir_all(skin.join("nested")).unwrap();
            let path = skin.join(resource);
            if directory {
                fs::create_dir(path).unwrap();
            } else {
                fs::write(path, "/* fixture */").unwrap();
            }
            fs::write(
                skin.join("skin.toml"),
                format!("toolbar_stylesheet = '{resource}'\n{}", manifest("sample")),
            )
            .unwrap();
            let result = scan(root.path());
            assert_eq!(
                result.packages.len(),
                usize::from(resource == "toolbar.css" && !directory)
            );
        }
    }
    #[test]
    fn scans_valid_and_rejects_unsafe_manifests() {
        let dir = tempdir().unwrap();
        let skin = dir.path().join("sample_skin");
        fs::create_dir(&skin).unwrap();
        fs::write(skin.join("skin.toml"), "schema_version = 1\nid = 'sample_skin'\nname = 'Sample'\nversion = '1.0'\nbase = 'fluent'\nauthor = 'Test'\ndescription = 'Demo'\n[supports]\nlayouts = ['vertical']\nthemes = ['light']\n[candidate_window]\n[candidate_window.decoration]\n").unwrap();
        let catalog = scan(dir.path());
        assert_eq!(
            catalog.packages,
            vec![SkinSummary {
                id: "sample_skin".into(),
                name: "Sample".into(),
                version: "1.0".into(),
                base: "fluent".into(),
                author: Some("Test".into()),
                description: Some("Demo".into()),
            }],
            "{catalog:?}"
        );
    }

    #[test]
    fn reports_invalid_ids_and_oversized_manifests_without_loading_them() {
        let dir = tempdir().unwrap();
        let invalid = dir.path().join("Bad");
        fs::create_dir(&invalid).unwrap();
        fs::write(invalid.join("skin.toml"), "schema_version = 1").unwrap();
        let huge = dir.path().join("huge");
        fs::create_dir(&huge).unwrap();
        fs::write(huge.join("skin.toml"), vec![b'x'; 65_537]).unwrap();
        let catalog = scan(dir.path());
        assert!(catalog.packages.is_empty());
        assert!(catalog
            .issues
            .iter()
            .any(|issue| issue.folder == "huge" && issue.reason.contains("too large")));
    }

    #[test]
    fn rejects_manifest_id_mismatch_and_unsupported_base() {
        let dir = tempdir().unwrap();
        for (folder, body) in [
            ("mismatch", "schema_version = 1\nid = 'other'\nname = 'X'\nversion = '1'\nbase = 'fluent'"),
            ("unsupported", "schema_version = 1\nid = 'unsupported'\nname = 'X'\nversion = '1'\nbase = 'unknown'"),
        ] {
            let path = dir.path().join(folder);
            fs::create_dir(&path).unwrap();
            fs::write(path.join("skin.toml"), body).unwrap();
        }
        let catalog = scan(dir.path());
        assert!(catalog.packages.is_empty());
        assert_eq!(catalog.issues.len(), 2);
    }
}
