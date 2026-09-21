//! Unit tests for the parent module, in their own file because the module
//! is large enough that mixing them with the implementation obscured both.
//! Same `mod tests` as before, so `use super::*` still names the parent.

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
fn stylesheet_reader_accepts_only_package_local_utf8_css() {
    let root = tempdir().unwrap();
    let skin = resource_package(root.path());
    fs::create_dir_all(skin.join("styles")).unwrap();
    fs::write(
        skin.join("styles/imported.css"),
        b"\xEF\xBB\xBF.imported {}",
    )
    .unwrap();
    fs::write(skin.join("styles/broken.css"), [0xff, 0xfe]).unwrap();
    fs::write(skin.join("styles/image.png"), b"not-an-image-decoder-test").unwrap();
    assert_eq!(
        read_stylesheet(root.path(), "sample", "styles/imported.css").unwrap(),
        ".imported {}"
    );
    assert_eq!(
        read_stylesheet(root.path(), "sample", "styles/broken.css"),
        Err(ResourceError::InvalidEncoding)
    );
    assert_eq!(
        read_stylesheet(root.path(), "sample", "styles/image.png"),
        Err(ResourceError::UnsupportedType)
    );
    assert_eq!(
        read_stylesheet(root.path(), "sample", "../outside.css"),
        Err(ResourceError::InvalidPath)
    );
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
        (
            "mismatch",
            "schema_version = 1\nid = 'other'\nname = 'X'\nversion = '1'\nbase = 'fluent'",
        ),
        (
            "unsupported",
            "schema_version = 1\nid = 'unsupported'\nname = 'X'\nversion = '1'\nbase = 'unknown'",
        ),
    ] {
        let path = dir.path().join(folder);
        fs::create_dir(&path).unwrap();
        fs::write(path.join("skin.toml"), body).unwrap();
    }
    let catalog = scan(dir.path());
    assert!(catalog.packages.is_empty());
    assert_eq!(catalog.issues.len(), 2);
}
