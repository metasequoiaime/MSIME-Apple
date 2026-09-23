//! 背单词模式：词书、复习排程与复习进度。
//!
//! The review session is something the user opens, not something that happens while they type.
//! Nothing here reaches the Engine or the composition state machine — a host shows a card,
//! reports what the user answered, and reads back a count for its progress row. That is the whole
//! surface, and it is deliberately the whole surface: candidate ordering and learning belong to
//! the C++ Engine, and a second scheduler living in Rust and quietly disagreeing with it is the
//! failure this boundary exists to prevent.
//!
//! The split follows where the data comes from and how it fails, the same rule
//! [`crate::dictionary`] follows:
//!
//! - [`wordbook`] is the word list itself — bundled or imported, read-only once loaded.
//! - [`import`] turns a user's CSV/TXT file into wordbook entries, reporting bad rows per line
//!   without ever echoing them.
//! - [`schedule`] is the spaced-repetition arithmetic, pure and date-driven.
//! - [`progress`] is the per-user review state on disk, which is the only part that is written.
//!
//! Per-card state is deliberately NOT a preference. The shared preference document is capped at
//! 16 KiB by the iOS bridge, and a few thousand studied cards are far past that; the progress
//! store is its own file beside `typing-statistics.json` in the host-supplied directory.

pub mod import;
pub mod library;
pub mod progress;
pub mod schedule;
pub mod wordbook;

/// Whether `day` is a local day this module can store and compare.
///
/// One predicate because three layers ask it: the host boundary rejecting a request before it
/// touches anything, the scheduler refusing to date a card, and the progress store validating a
/// document it read. A day accepted by one and refused by another is a request that writes a book
/// to disk and then reports failure — which is the bug this function was extracted for.
pub fn day_is_well_formed(day: &str) -> bool {
    crate::calendar::is_valid_day(day)
}
