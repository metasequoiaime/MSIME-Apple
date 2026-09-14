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
fn other_hosts_keep_names_and_order() {
    let names = vec![
        "Synthetic W03".into(),
        "示例字体".into(),
        "Synthetic W03".into(),
    ];
    assert_eq!(resolve_css_families(names.clone()), Ok(names));
}
