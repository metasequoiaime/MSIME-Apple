//! Synthetic native/Rust transport regression; no account or network access.
#[cfg(target_os = "macos")]
fn main() {
    use msime_host_macos::cloud_clipboard::CloudClipboardSession;
    use std::io::Read;
    let mut gate = [0];
    std::io::stdin().read_exact(&mut gate).unwrap();
    let session = CloudClipboardSession::parse(
        &std::env::var("MSIME_CLIENT_CLOUD_CLIPBOARD_SESSION").unwrap(),
    )
    .unwrap();
    for action in [
        serde_json::json!({"operation":"list","search":""}),
        serde_json::json!({"operation":"add","text":"中".repeat(3997) + "\n\r\t"}),
        serde_json::json!({"operation":"delete","id":"a".repeat(64)}),
        serde_json::json!({"operation":"set_enabled","enabled":false}),
    ] {
        let response = session.request(&action).unwrap();
        assert_eq!(response["operation"], action["operation"]);
    }
    if let Ok(configuration) = std::env::var("MSIME_CLIENT_PANEL_SESSION") {
        use msime_host_macos::panel_session::{PanelSession, SessionError};
        let input = PanelSession::parse(&configuration).unwrap();
        assert!(input.accepts_clipboard());
        input.submit(&("中".repeat(3997) + "\n\r\t")).unwrap();
        assert_eq!(
            input.submit("synthetic-duplicate"),
            Err(SessionError::Rejected)
        );
    }
}

#[cfg(not(target_os = "macos"))]
fn main() {}
