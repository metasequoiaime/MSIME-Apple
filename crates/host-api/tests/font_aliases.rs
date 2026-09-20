use msime_host_api::system_fonts::resolve_css_families;

#[test]
fn invalid_font_requests_are_rejected_before_platform_calls() {
    for names in [
        vec![String::new()],
        vec!["x".repeat(129)],
        vec!["bad\0name".into()],
        vec!["Synthetic".into(); 34],
    ] {
        assert_eq!(resolve_css_families(names), Err("font_family"));
    }
    assert_eq!(resolve_css_families(Vec::new()), Ok(Vec::new()));
}

#[cfg(not(windows))]
#[test]
fn a_name_no_font_system_knows_is_left_alone() {
    // On the hosts that resolve nothing this is the whole behaviour. On macOS it is the interesting
    // half: CoreText answers a name it does not know with a substituted font rather than an error, so
    // an unrecognised preference would come back as whatever the system fell back to.
    let names = vec![
        "Synthetic W03".into(),
        "示例字体".into(),
        "Synthetic W03".into(),
    ];
    assert_eq!(resolve_css_families(names.clone()), Ok(names));
}

#[cfg(target_os = "macos")]
#[test]
fn a_face_name_resolves_to_the_family_a_stylesheet_matches() {
    // Helvetica ships with every macOS, so its bold face is a pair that exists on any machine this
    // runs on. Skipped rather than failed if the catalogue says otherwise: the assertion is about
    // resolution, not about which fonts are installed.
    let installed = msime_host_api::system_fonts::list().expect("the font catalogue");
    if !installed.iter().any(|family| family == "Helvetica") {
        return;
    }
    assert_eq!(
        resolve_css_families(vec!["Helvetica-Bold".into()]),
        Ok(vec!["Helvetica".into()])
    );
    // A name that is already a family comes back as itself rather than as the family of whichever
    // face CoreText picked to represent it.
    assert_eq!(
        resolve_css_families(vec!["Helvetica".into()]),
        Ok(vec!["Helvetica".into()])
    );
}

#[cfg(target_os = "macos")]
#[test]
fn resolution_keeps_the_order_and_count_it_was_given() {
    // The caller pairs the answers with the fields it asked about by position - candidate font,
    // English font, fallback font - so a dropped or reordered entry would put one font's family on
    // another font's setting.
    let names = vec![
        "Synthetic W03".to_owned(),
        "Helvetica-Bold".to_owned(),
        "Synthetic W03".to_owned(),
    ];
    let resolved = resolve_css_families(names.clone()).expect("resolution");
    assert_eq!(resolved.len(), names.len());
    assert_eq!(resolved[0], names[0]);
    assert_eq!(resolved[2], names[2]);
}
