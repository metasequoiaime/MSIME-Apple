//! Bounded transfers through the Linux session's clipboard tools.

use std::time::Duration;

use msime_client_core::clipboard::{normalize_text, MAX_TEXT_BYTES};

pub fn read_text(program: &str, arguments: &[&str]) -> Option<String> {
    super::linux_process::read_text_prefix(
        program,
        arguments,
        MAX_TEXT_BYTES,
        Duration::from_secs(1),
    )
    .map(|text| normalize_text(&text))
}

pub fn write_text(program: &str, arguments: &[&str], text: &str) -> bool {
    super::linux_process::write_input(program, arguments, text.as_bytes(), Duration::from_secs(2))
}

/// Whether the clipboard owner marks its offer as a secret. KeePassXC, KWallet
/// and Bitwarden set `x-kde-passwordManagerHint`; its presence is the signal.
/// The nspasteboard.org names match what the macOS reader refuses.
pub fn targets_mark_secret(targets: &str) -> bool {
    targets.lines().map(str::trim).any(|target| {
        matches!(
            target,
            "x-kde-passwordManagerHint"
                | "org.nspasteboard.ConcealedType"
                | "org.nspasteboard.TransientType"
        )
    })
}

pub fn offers_secret(program: &str, arguments: &[&str]) -> bool {
    super::linux_process::read_text_prefix(program, arguments, 4096, Duration::from_secs(1))
        .is_some_and(|targets| targets_mark_secret(&targets))
}

#[cfg(test)]
mod tests {
    use super::targets_mark_secret;

    #[test]
    fn password_manager_targets_mark_the_copy_secret() {
        assert!(targets_mark_secret(
            "text/plain\nx-kde-passwordManagerHint\nUTF8_STRING\n"
        ));
        assert!(targets_mark_secret(
            "TARGETS\r\norg.nspasteboard.ConcealedType\r\n"
        ));
        assert!(!targets_mark_secret("text/plain\nUTF8_STRING\nTARGETS\n"));
        assert!(!targets_mark_secret("x-kde-passwordManagerHint-other\n"));
        assert!(!targets_mark_secret(""));
    }
}
