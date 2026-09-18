// Exercise the production guard on every host without accessing a clipboard.
#[path = "../src/paste_policy.rs"]
mod paste_policy;

use msime_client_core::clipboard::{normalize_text, MAX_TEXT_BYTES, MAX_TEXT_UTF16_UNITS};
use paste_policy::valid_paste_text;

#[test]
fn full_length_synthetic_history_can_be_pasted() {
    for text in [
        "x".repeat(MAX_TEXT_UTF16_UNITS),
        "测".repeat(MAX_TEXT_UTF16_UNITS),
        "😀".repeat(MAX_TEXT_UTF16_UNITS / 2),
    ] {
        assert_eq!(normalize_text(&text), text);
        assert!(valid_paste_text(&text, MAX_TEXT_BYTES));
    }
    let chinese = "测".repeat(MAX_TEXT_UTF16_UNITS);
    assert_eq!(chinese.len(), MAX_TEXT_BYTES);
    // This old ordinary-input bound rejected valid Chinese history records.
    assert!(!valid_paste_text(&chinese, 4096));
}

#[test]
fn paste_rejects_empty_nul_and_over_limit_without_truncation() {
    for limit in [4096, MAX_TEXT_BYTES] {
        assert!(valid_paste_text(&"x".repeat(limit), limit));
        assert!(!valid_paste_text(&"x".repeat(limit + 1), limit));
        assert!(!valid_paste_text("", limit));
        assert!(!valid_paste_text("synthetic\0text", limit));
    }
}
