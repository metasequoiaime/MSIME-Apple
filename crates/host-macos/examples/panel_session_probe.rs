//! Synthetic interoperability probe: never sends user input or activates apps.
#[cfg(target_os = "macos")]
fn main() {
    use msime_host_macos::panel_session::PanelSession;
    use std::io::Read;
    let mut gate = [0_u8];
    std::io::stdin().read_exact(&mut gate).expect("probe gate");
    let value = std::env::var("MSIME_CLIENT_PANEL_SESSION").expect("probe configuration");
    let session = PanelSession::parse(&value).expect("probe session");
    if session.submit("synthetic").is_err() {
        std::process::exit(1);
    }
}

#[cfg(not(target_os = "macos"))]
fn main() {}
