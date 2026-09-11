//! Safe discovery and validation of external candidate-skin manifests.

use std::fs;
use std::path::Path;
use toml::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SkinSummary {
    pub id: String,
    pub name: String,
    pub version: String,
    pub base: String,
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

fn load(root: &Path, folder: &str) -> Result<SkinSummary, String> {
    if !safe_id(folder) {
        return Err("invalid skin id".into());
    }
    let dir = root.join(folder);
    let manifest = dir.join("skin.toml");
    if !contained(root, &dir) || !contained(&dir, &manifest) {
        return Err("manifest escapes skin directory".into());
    }
    let bytes = fs::read(&manifest).map_err(|_| "missing skin.toml".to_owned())?;
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
    if !matches!(
        base.as_str(),
        "fluent" | "wechat" | "graphite" | "willow_green"
    ) {
        return Err("unsupported base skin".into());
    }
    Ok(SkinSummary {
        id,
        name,
        version,
        base,
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
    #[test]
    fn scans_valid_and_rejects_unsafe_manifests() {
        let dir = tempdir().unwrap();
        let skin = dir.path().join("sample_skin");
        fs::create_dir(&skin).unwrap();
        fs::write(skin.join("skin.toml"), "schema_version = 1\nid = 'sample_skin'\nname = 'Sample'\nversion = '1.0'\nbase = 'fluent'\n").unwrap();
        fs::create_dir(dir.path().join("../escape")).ok();
        let catalog = scan(dir.path());
        assert_eq!(
            catalog.packages,
            vec![SkinSummary {
                id: "sample_skin".into(),
                name: "Sample".into(),
                version: "1.0".into(),
                base: "fluent".into()
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
