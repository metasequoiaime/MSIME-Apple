//! Safe discovery and validation of external candidate-skin manifests.
//!
//! `read_resource` supplies bytes for host resource delivery analogous to the
//! Windows `candidate-skins` virtual-folder mapping (settings_app.cpp at
//! 04a8df56f86312474a069f4335a1b58da7afaa9e). It does not register a protocol,
//! authorize a webview origin, sanitize CSS/SVG, or execute resource content.

use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Read;
use std::path::Path;
use toml::Value;

/// Manifest values, not trusted CSS. Renderers must validate color syntax before
/// inserting these strings into styles; scanning does not authorize CSS execution.
#[derive(Debug, Default, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(default)]
pub struct CandidatePalette {
    pub accent: Option<String>,
    pub selected: Option<String>,
    pub hover: Option<String>,
    pub surface: Option<String>,
    pub border: Option<String>,
    pub text: Option<String>,
    pub number: Option<String>,
    #[serde(rename(serialize = "showSelectedBar", deserialize = "show_selected_bar"))]
    pub show_selected_bar: Option<bool>,
}

#[derive(Debug, Default, Clone, PartialEq, Eq, Deserialize, Serialize)]
#[serde(default)]
pub struct CandidateColors {
    pub dark: CandidatePalette,
    pub light: CandidatePalette,
}

fn read_colors(table: &toml::map::Map<String, Value>) -> Result<CandidateColors, String> {
    let Some(value) = table.get("candidate") else {
        return Ok(CandidateColors::default());
    };
    let candidate = value.as_table().ok_or("invalid candidate colors")?;
    for theme in ["dark", "light"] {
        if candidate
            .get(theme)
            .is_some_and(|palette| !palette.is_table())
        {
            return Err("invalid candidate colors".into());
        }
    }
    let colors: CandidateColors = value
        .clone()
        .try_into()
        .map_err(|_| "invalid candidate colors")?;
    for palette in [&colors.dark, &colors.light] {
        for color in [
            &palette.accent,
            &palette.selected,
            &palette.hover,
            &palette.surface,
            &palette.border,
            &palette.text,
            &palette.number,
        ]
        .into_iter()
        .flatten()
        {
            if color.len() > 80 {
                return Err("candidate color exceeds 80 bytes".into());
            }
        }
    }
    Ok(colors)
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SkinSummary {
    pub id: String,
    pub name: String,
    pub version: String,
    pub base: String,
    pub author: Option<String>,
    pub description: Option<String>,
    pub layouts: Vec<String>,
    pub themes: Vec<String>,
    pub min_width_dip: f64,
    pub decoration_top_dip: f64,
    pub decoration_width_dip: f64,
    pub toolbar_stylesheet: Option<String>,
    pub preview: Option<String>,
    pub candidate: CandidateColors,
}

impl SkinSummary {
    /// Compatibility comes from the manifest, not the base skin's capabilities.
    pub fn supports(&self, layout: &str, theme: &str) -> bool {
        self.layouts.iter().any(|value| value == layout)
            && self.themes.iter().any(|value| value == theme)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct SkinIssue {
    pub folder: String,
    pub reason: String,
}

#[derive(Debug, Default, Clone, PartialEq, Serialize)]
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

fn enum_array(
    table: &toml::map::Map<String, Value>,
    key: &str,
    allowed: &[&str],
) -> Option<Vec<String>> {
    let items = table.get(key)?.as_array()?;
    if items.is_empty() {
        return None;
    }
    let mut values = Vec::new();
    for item in items {
        let value = item.as_str()?;
        if !allowed.contains(&value) || values.iter().any(|existing| existing == value) {
            return None;
        }
        values.push(value.to_owned());
    }
    Some(values)
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
    let layouts =
        enum_array(supports, "layouts", &["horizontal", "vertical"]).ok_or("invalid supports")?;
    let themes = enum_array(supports, "themes", &["dark", "light"]).ok_or("invalid supports")?;
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
    let toolbar_stylesheet = optional_string(table, "toolbar_stylesheet", 128)?;
    if let Some(stylesheet) = &toolbar_stylesheet {
        if !safe_resource(stylesheet, 128)
            || stylesheet.contains('/')
            || stylesheet.len() <= 4
            || !stylesheet.ends_with(".css")
            || !contained(&dir, &dir.join(stylesheet))
            || !dir.join(stylesheet).is_file()
        {
            return Err("invalid toolbar_stylesheet".into());
        }
    }
    let preview = optional_string(table, "preview", 256)?;
    if let Some(preview) = &preview {
        if !safe_resource(preview, 256) || !contained(&dir, &dir.join(preview)) {
            return Err("invalid preview".into());
        }
    }
    let candidate = read_colors(table)?;
    Ok(SkinSummary {
        id,
        name,
        version,
        base,
        author,
        description,
        layouts,
        themes,
        min_width_dip: min_width,
        decoration_top_dip: top,
        decoration_width_dip: width,
        toolbar_stylesheet,
        preview,
        candidate,
    })
}

/// Maximum bytes returned for one skin asset, including stylesheets and fonts.
pub const MAX_RESOURCE_BYTES: usize = 8 * 1024 * 1024;

#[derive(Debug, PartialEq, Eq)]
pub enum ResourceError {
    InvalidPath,
    InvalidPackage,
    UnsupportedType,
    Unavailable,
    TooLarge,
    InvalidEncoding,
}

/// Read only the toolbar stylesheet declared by the current manifest. The
/// caller chooses a package, not a filesystem path. None means inheritance of
/// the built-in toolbar; an empty stylesheet is Some(""). Returned CSS is
/// untrusted and must be parsed/scoped by the host before applying it.
pub fn read_toolbar_stylesheet(
    root: impl AsRef<Path>,
    id: &str,
) -> Result<Option<String>, ResourceError> {
    if !safe_id(id) {
        return Err(ResourceError::InvalidPath);
    }
    let root = root.as_ref();
    let directory = root.join(id);
    if !fs::symlink_metadata(directory)
        .map(|metadata| metadata.file_type().is_dir())
        .unwrap_or(false)
    {
        return Err(ResourceError::InvalidPackage);
    }
    let package = load(root, id).map_err(|_| ResourceError::InvalidPackage)?;
    let Some(relative) = package.toolbar_stylesheet else {
        return Ok(None);
    };
    let resource = read_resource(root, id, &relative)?;
    let text = String::from_utf8(resource.bytes).map_err(|_| ResourceError::InvalidEncoding)?;
    // A UTF-8 BOM is an encoding marker, not part of the first selector.
    Ok(Some(
        text.strip_prefix('\u{feff}').unwrap_or(&text).to_owned(),
    ))
}

/// Untrusted resource data. Hosts must set the content type, disable MIME
/// sniffing, and isolate styles/SVG rather than inserting them as page markup.
#[derive(Debug, PartialEq, Eq)]
pub struct SkinResource {
    pub content_type: &'static str,
    pub bytes: Vec<u8>,
}

/// Read an asset from a currently valid package under a host-selected root.
/// Paths are decoded relative names, never URLs. Canonical containment rejects
/// symlink escapes, but is not a sandbox against concurrent hostile filesystem
/// mutation; hosts must not use this API to expose attacker-writable trees
/// across a privilege boundary.
pub fn read_resource(
    root: impl AsRef<Path>,
    id: &str,
    relative: &str,
) -> Result<SkinResource, ResourceError> {
    if !safe_id(id) || !safe_resource(relative, 256) {
        return Err(ResourceError::InvalidPath);
    }
    let content_type = match relative
        .rsplit('.')
        .next()
        .unwrap_or("")
        .to_ascii_lowercase()
        .as_str()
    {
        "css" => "text/css; charset=utf-8",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "gif" => "image/gif",
        "webp" => "image/webp",
        "svg" => "image/svg+xml",
        "ico" => "image/x-icon",
        "bmp" => "image/bmp",
        "avif" => "image/avif",
        "woff" => "font/woff",
        "woff2" => "font/woff2",
        "ttf" => "font/ttf",
        "otf" => "font/otf",
        _ => return Err(ResourceError::UnsupportedType),
    };
    let root = root.as_ref();
    let directory = root.join(id);
    // Match scan(): symlinked package directories are not catalog entries.
    if !fs::symlink_metadata(&directory)
        .map(|metadata| metadata.file_type().is_dir())
        .unwrap_or(false)
        || load(root, id).is_err()
    {
        return Err(ResourceError::InvalidPackage);
    }
    let directory = directory
        .canonicalize()
        .map_err(|_| ResourceError::Unavailable)?;
    let target = directory
        .join(relative)
        .canonicalize()
        .map_err(|_| ResourceError::Unavailable)?;
    if !target.starts_with(&directory) {
        return Err(ResourceError::InvalidPath);
    }
    if !target.is_file() {
        return Err(ResourceError::Unavailable);
    }
    let input = fs::File::open(&target).map_err(|_| ResourceError::Unavailable)?;
    let metadata = input.metadata().map_err(|_| ResourceError::Unavailable)?;
    if !metadata.is_file() {
        return Err(ResourceError::Unavailable);
    }
    if metadata.len() > MAX_RESOURCE_BYTES as u64 {
        return Err(ResourceError::TooLarge);
    }
    let mut bytes = Vec::new();
    input
        .take(MAX_RESOURCE_BYTES as u64 + 1)
        .read_to_end(&mut bytes)
        .map_err(|_| ResourceError::Unavailable)?;
    if bytes.len() > MAX_RESOURCE_BYTES {
        return Err(ResourceError::TooLarge);
    }
    Ok(SkinResource {
        content_type,
        bytes,
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

    fn resource_package(root: &Path) -> std::path::PathBuf {
        let skin = root.join("sample");
        fs::create_dir_all(skin.join("images")).unwrap();
        fs::write(skin.join("skin.toml"), manifest("sample")).unwrap();
        skin
    }

    #[test]
    fn toolbar_source_distinguishes_absent_empty_and_declared_utf8_text() {
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        fs::write(skin.join("undeclared.css"), ".other {}").unwrap();
        assert_eq!(read_toolbar_stylesheet(root.path(), "sample"), Ok(None));
        fs::write(skin.join("toolbar.css"), "").unwrap();
        fs::write(
            skin.join("skin.toml"),
            format!("toolbar_stylesheet = 'toolbar.css'\n{}", manifest("sample")),
        )
        .unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Ok(Some(String::new()))
        );
        fs::write(
            skin.join("toolbar.css"),
            "\u{feff}.status-bar { color: #123456; } /* 示例 */",
        )
        .unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Ok(Some(".status-bar { color: #123456; } /* 示例 */".into()))
        );
    }

    #[test]
    fn toolbar_source_rechecks_manifest_and_rejects_invalid_encoding_and_size() {
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        fs::write(skin.join("toolbar.css"), [0xff, 0xfe]).unwrap();
        fs::write(
            skin.join("skin.toml"),
            format!("toolbar_stylesheet = 'toolbar.css'\n{}", manifest("sample")),
        )
        .unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Err(ResourceError::InvalidEncoding)
        );
        fs::File::create(skin.join("toolbar.css"))
            .unwrap()
            .set_len(MAX_RESOURCE_BYTES as u64 + 1)
            .unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Err(ResourceError::TooLarge)
        );
        fs::write(skin.join("replacement.css"), ".replacement {}").unwrap();
        fs::write(
            skin.join("skin.toml"),
            format!(
                "toolbar_stylesheet = 'replacement.css'\n{}",
                manifest("sample")
            ),
        )
        .unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Ok(Some(".replacement {}".into()))
        );
        fs::write(skin.join("skin.toml"), "invalid").unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Err(ResourceError::InvalidPackage)
        );
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "../sample"),
            Err(ResourceError::InvalidPath)
        );
    }

    #[cfg(unix)]
    #[test]
    fn toolbar_source_rejects_package_alias_and_escaping_stylesheet() {
        use std::os::unix::fs::symlink;
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        let outside = tempdir().unwrap();
        fs::write(outside.path().join("outside.css"), ".outside {}").unwrap();
        symlink(outside.path().join("outside.css"), skin.join("toolbar.css")).unwrap();
        fs::write(
            skin.join("skin.toml"),
            format!("toolbar_stylesheet = 'toolbar.css'\n{}", manifest("sample")),
        )
        .unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "sample"),
            Err(ResourceError::InvalidPackage)
        );
        symlink(&skin, root.path().join("alias")).unwrap();
        assert_eq!(
            read_toolbar_stylesheet(root.path(), "alias"),
            Err(ResourceError::InvalidPackage)
        );
    }

    #[test]
    fn resource_reader_preserves_bytes_and_assigns_supported_content_types() {
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        for (extension, content_type) in [
            ("css", "text/css; charset=utf-8"),
            ("PNG", "image/png"),
            ("jpg", "image/jpeg"),
            ("jpeg", "image/jpeg"),
            ("gif", "image/gif"),
            ("webp", "image/webp"),
            ("svg", "image/svg+xml"),
            ("ico", "image/x-icon"),
            ("bmp", "image/bmp"),
            ("avif", "image/avif"),
            ("woff", "font/woff"),
            ("woff2", "font/woff2"),
            ("ttf", "font/ttf"),
            ("otf", "font/otf"),
        ] {
            let relative = format!("images/sample.{extension}");
            fs::write(skin.join(&relative), [0, 1, 255]).unwrap();
            let result = read_resource(root.path(), "sample", &relative).unwrap();
            assert_eq!(result.content_type, content_type);
            assert_eq!(result.bytes, [0, 1, 255]);
        }
    }

    #[test]
    fn resource_reader_rejects_paths_urls_and_non_asset_types() {
        let root = tempdir().unwrap();
        resource_package(root.path());
        for relative in [
            "",
            "../sample.png",
            "/sample.png",
            "C:/sample.png",
            "images\\sample.png",
            "images//sample.png",
            "./sample.png",
            "%2e%2e/sample.png",
            "https://example.invalid/a.png",
            "sample.png?x=1",
        ] {
            assert_eq!(
                read_resource(root.path(), "sample", relative),
                Err(ResourceError::InvalidPath)
            );
        }
        assert_eq!(
            read_resource(root.path(), "../sample", "sample.png"),
            Err(ResourceError::InvalidPath)
        );
        for relative in [
            "skin.toml",
            "code.js",
            "page.html",
            "settings.json",
            "program.exe",
            "unknown",
        ] {
            assert_eq!(
                read_resource(root.path(), "sample", relative),
                Err(ResourceError::UnsupportedType)
            );
        }
    }

    #[test]
    fn resource_reader_requires_current_valid_manifest() {
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        fs::write(skin.join("sample.png"), b"synthetic").unwrap();
        assert!(read_resource(root.path(), "sample", "sample.png").is_ok());
        fs::write(skin.join("skin.toml"), "invalid").unwrap();
        assert_eq!(
            read_resource(root.path(), "sample", "sample.png"),
            Err(ResourceError::InvalidPackage)
        );
        assert_eq!(
            read_resource(root.path(), "absent", "sample.png"),
            Err(ResourceError::InvalidPackage)
        );
    }

    #[test]
    fn resource_reader_rejects_missing_directory_and_oversized_assets() {
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        assert_eq!(
            read_resource(root.path(), "sample", "absent.png"),
            Err(ResourceError::Unavailable)
        );
        fs::create_dir(skin.join("directory.png")).unwrap();
        assert_eq!(
            read_resource(root.path(), "sample", "directory.png"),
            Err(ResourceError::Unavailable)
        );
        let file = fs::File::create(skin.join("large.png")).unwrap();
        file.set_len(MAX_RESOURCE_BYTES as u64).unwrap();
        assert_eq!(
            read_resource(root.path(), "sample", "large.png")
                .unwrap()
                .bytes
                .len(),
            MAX_RESOURCE_BYTES
        );
        file.set_len(MAX_RESOURCE_BYTES as u64 + 1).unwrap();
        assert_eq!(
            read_resource(root.path(), "sample", "large.png"),
            Err(ResourceError::TooLarge)
        );
    }

    #[cfg(unix)]
    #[test]
    fn resource_reader_rejects_symlink_escapes_and_package_aliases() {
        use std::os::unix::fs::symlink;
        let root = tempdir().unwrap();
        let skin = resource_package(root.path());
        let outside = tempdir().unwrap();
        fs::write(outside.path().join("sample.png"), b"synthetic").unwrap();
        symlink(outside.path().join("sample.png"), skin.join("escape.png")).unwrap();
        symlink(outside.path(), skin.join("escape")).unwrap();
        for relative in ["escape.png", "escape/sample.png"] {
            assert_eq!(
                read_resource(root.path(), "sample", relative),
                Err(ResourceError::InvalidPath)
            );
        }
        symlink(&skin, root.path().join("alias")).unwrap();
        assert_eq!(
            read_resource(root.path(), "alias", "escape.png"),
            Err(ResourceError::InvalidPackage)
        );
        fs::write(skin.join("images/local.png"), b"local").unwrap();
        symlink(skin.join("images/local.png"), skin.join("local.png")).unwrap();
        assert_eq!(
            read_resource(root.path(), "sample", "local.png")
                .unwrap()
                .bytes,
            b"local"
        );
    }

    fn scan_manifest(body: &str) -> SkinCatalog {
        let root = tempdir().unwrap();
        let skin = root.path().join("sample");
        fs::create_dir(&skin).unwrap();
        fs::write(skin.join("skin.toml"), body).unwrap();
        scan(root.path())
    }

    #[test]
    fn candidate_palettes_preserve_both_themes_and_serialize_host_names() {
        let body = format!("{}\n[candidate.dark]\naccent = '#123456'\nselected = '#234567'\nhover = '#345678'\nsurface = '#456789'\nborder = '#56789a'\ntext = '#6789ab'\nnumber = '#789abc'\nshow_selected_bar = false\n[candidate.light]\ntext = '#123'\nshow_selected_bar = true\n", manifest("sample"));
        let catalog = scan_manifest(&body);
        assert!(catalog.issues.is_empty(), "{catalog:?}");
        let json = serde_json::to_value(&catalog.packages[0]).unwrap();
        assert_eq!(
            json["candidate"]["dark"],
            serde_json::json!({
                "accent": "#123456", "selected": "#234567", "hover": "#345678",
                "surface": "#456789", "border": "#56789a", "text": "#6789ab",
                "number": "#789abc", "showSelectedBar": false,
            })
        );
        assert_eq!(json["candidate"]["light"]["text"], "#123");
        assert_eq!(json["candidate"]["light"]["showSelectedBar"], true);
        assert!(json["candidate"]["light"]["accent"].is_null());
        assert_eq!(
            scan_manifest(&manifest("sample")).packages[0].candidate,
            CandidateColors::default()
        );
    }

    #[test]
    fn candidate_color_fields_enforce_types_and_utf8_byte_limits() {
        for theme in ["dark", "light"] {
            for key in [
                "accent", "selected", "hover", "surface", "border", "text", "number",
            ] {
                for value in [
                    "false".to_owned(),
                    "7".to_owned(),
                    "[]".to_owned(),
                    "{}".to_owned(),
                    format!("'{}'", "a".repeat(81)),
                    format!("'{}'", "色".repeat(27)),
                ] {
                    let body = format!(
                        "{}\n[candidate.{theme}]\n{key} = {value}\n",
                        manifest("sample")
                    );
                    let catalog = scan_manifest(&body);
                    assert!(catalog.packages.is_empty(), "accepted {theme}.{key}");
                    assert_eq!(catalog.issues.len(), 1);
                }
                for value in [String::new(), "a".repeat(80)] {
                    let body = format!(
                        "{}\n[candidate.{theme}]\n{key} = '{value}'\n",
                        manifest("sample")
                    );
                    assert_eq!(scan_manifest(&body).packages.len(), 1);
                }
            }
        }
    }

    #[test]
    fn candidate_tables_and_selected_bar_reject_wrong_types() {
        for suffix in [
            "[candidate]\ndark = false",
            "[candidate]\nlight = []",
            "[candidate.dark]\nshow_selected_bar = 'false'",
            "[candidate.light]\nshow_selected_bar = 1",
        ] {
            let catalog = scan_manifest(&format!("{}\n{suffix}\n", manifest("sample")));
            assert!(catalog.packages.is_empty());
            assert_eq!(catalog.issues[0].reason, "invalid candidate colors");
        }
        let body = format!("candidate = false\n{}", manifest("sample"));
        assert!(scan_manifest(&body).packages.is_empty());
    }

    #[test]
    fn preserves_capabilities_dimensions_and_relative_resources_for_hosts() {
        let root = tempdir().unwrap();
        let skin = root.path().join("sample");
        fs::create_dir_all(skin.join("images")).unwrap();
        fs::write(skin.join("toolbar.css"), "/* fixture */").unwrap();
        fs::write(skin.join("images/preview.svg"), "<svg/>").unwrap();
        let body = format!(
            "toolbar_stylesheet = 'toolbar.css'\npreview = 'images/preview.svg'\n{}",
            manifest("sample")
        )
        .replace("['vertical']", "['vertical', 'horizontal']")
        .replace("min_width_dip = 10", "min_width_dip = 320.5")
        .replace("top_inset_dip = 0", "top_inset_dip = 24.5")
        .replace("width_dip = 0", "width_dip = 180");
        fs::write(skin.join("skin.toml"), body).unwrap();
        let catalog = scan(root.path());
        assert!(catalog.issues.is_empty(), "{catalog:?}");
        let package = &catalog.packages[0];
        assert_eq!(package.layouts, ["vertical", "horizontal"]);
        assert_eq!(package.themes, ["light"]);
        assert!(package.supports("vertical", "light"));
        assert!(package.supports("horizontal", "light"));
        assert!(!package.supports("vertical", "dark"));
        assert!(!package.supports("unknown", "light"));
        let json = serde_json::to_value(&catalog).unwrap();
        let package = &json["packages"][0];
        assert_eq!(package["minWidthDip"], 320.5);
        assert_eq!(package["decorationTopDip"], 24.5);
        assert_eq!(package["decorationWidthDip"], 180.0);
        assert_eq!(package["toolbarStylesheet"], "toolbar.css");
        assert_eq!(package["preview"], "images/preview.svg");
        assert_eq!(
            package["layouts"],
            serde_json::json!(["vertical", "horizontal"])
        );
    }

    #[test]
    fn compatibility_does_not_inherit_unlisted_base_modes() {
        let catalog = scan_manifest(&manifest("sample"));
        let package = &catalog.packages[0];
        assert_eq!(package.base, "fluent");
        assert!(package.supports("vertical", "light"));
        assert!(!package.supports("horizontal", "light"));
        assert!(!package.supports("vertical", "dark"));
        assert_eq!(package.toolbar_stylesheet, None);
        assert_eq!(package.preview, None);
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
                layouts: vec!["vertical".into()],
                themes: vec!["light".into()],
                min_width_dip: 0.0,
                decoration_top_dip: 0.0,
                decoration_width_dip: 0.0,
                toolbar_stylesheet: None,
                preview: None,
                candidate: CandidateColors::default(),
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
