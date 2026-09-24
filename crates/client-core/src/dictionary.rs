//! Local dictionary storage, import and access policy.
//!
//! The account-synchronised side lives under [`crate::cloud::dictionary`]: the
//! split follows where the data lives, because the two have different failure
//! modes and different validation.

pub mod access;
pub mod import;
pub mod personal;
pub mod quiesce;

/// Whether `code` is a usable English input code.
///
/// The code is what the user types; the word beside it is what that types out, and the two need
/// not be the same text - `dont` types out `don't`. The reference accepts any non-empty word
/// beside a code of letters, hyphens and apostrophes (`IsAsciiWord` in its `dictionary_manager`),
/// and the Engine agrees since `scripts/apply_engine_english_display.py`.
///
/// One predicate because five places ask this question - the import parser, the personal-word
/// transport check, both sides of the account validator, and the host API's own entry check - and
/// a code accepted by one and refused by another is an entry that imports and then fails to sync,
/// or one the API refuses after the file it came from was read successfully.
pub fn english_code_is_well_formed(code: &str) -> bool {
    code.bytes()
        .all(|byte| byte.is_ascii_alphabetic() || byte == b'-' || byte == b'\'')
}
