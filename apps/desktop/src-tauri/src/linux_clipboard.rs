//! Bounded transfers through the Linux session's clipboard tools.

use std::time::Duration;

use msime_client_core::clipboard::{normalize_text, MAX_TEXT_BYTES};

pub fn read_text(program: &str, arguments: &[&str]) -> Option<String> {
    crate::linux_process::read_text_prefix(program, arguments, MAX_TEXT_BYTES, Duration::from_secs(1))
        .map(|text| normalize_text(&text))
}

pub fn write_text(program: &str, arguments: &[&str], text: &str) -> bool {
    crate::linux_process::write_input(program, arguments, text.as_bytes(), Duration::from_secs(2))
}
