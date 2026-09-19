//! Pure validation before any clipboard or foreground-window side effects.

pub(super) fn valid_paste_text(text: &str, max_bytes: usize) -> bool {
    !text.is_empty() && text.len() <= max_bytes && !text.contains('\0')
}
