//! Parsing for user-supplied dictionary files.
//!
//! A realistic exported dictionary contains the occasional unusable row. The
//! earlier parser rejected the whole file on the first one and reported a single
//! opaque string, so a user had to find and fix that row blind. This module
//! skips unusable rows, counts them, and names the first few by line number.
//!
//! Every bound the previous parser enforced is preserved: this reads
//! user-supplied files, so the key alphabets, length limits and control
//! character rules are load-bearing, not cosmetic.

use serde::{Deserialize, Serialize};
use thiserror::Error;

/// Rows accepted from one file. Beyond this the remainder is reported as
/// truncated rather than silently dropped or rejected wholesale, because each
/// import holds the dictionary maintenance lock.
pub const MAX_ENTRIES: usize = 1000;
const MAX_VALUE_BYTES: usize = 1024;
/// Quick phrases are delivered through editors that count UTF-16 units.
const MAX_QUICK_PHRASE_UTF16: usize = 199;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportKind {
    Pinyin,
    Wubi,
    QuickPhrase,
    English,
}

impl ImportKind {
    fn key_limit(self) -> usize {
        match self {
            ImportKind::Pinyin => 256,
            ImportKind::Wubi => 4,
            ImportKind::QuickPhrase => 32,
            ImportKind::English => 64,
        }
    }

    fn key_is_well_formed(self, key: &str, format: ImportFormat) -> bool {
        match self {
            ImportKind::Pinyin => key.bytes().all(|byte| {
                byte.is_ascii_lowercase()
                    || byte == b'\''
                    || (format == ImportFormat::Rime && byte == b' ')
            }),
            ImportKind::Wubi => key.bytes().all(|byte| byte.is_ascii_lowercase()),
            ImportKind::QuickPhrase => key
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit()),
            ImportKind::English => key.bytes().all(|byte| byte.is_ascii_alphabetic()),
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportFormat {
    Standard,
    Windows,
    Rime,
}

impl ImportFormat {
    pub fn parse(value: &str) -> Option<Self> {
        match value {
            "standard" => Some(ImportFormat::Standard),
            "windows" => Some(ImportFormat::Windows),
            "rime" => Some(ImportFormat::Rime),
            _ => None,
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ImportEntry {
    pub key: String,
    pub value: String,
    pub weight: i64,
    /// 1-based line in the submitted text. Carried so a row the Engine refuses
    /// later can be reported by line, exactly as a parse failure is.
    #[serde(default)]
    pub line: usize,
}

/// Why one row was skipped. Deliberately describes the shape of the problem and
/// never echoes the row, which may be private user text.
#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ImportIssue {
    ColumnCount,
    EmptyKey,
    KeyTooLong,
    KeyAlphabet,
    EmptyValue,
    ValueTooLong,
    QuickPhraseTooLong,
    Weight,
    /// Parsed cleanly, but the Engine refused it - typically a jianpin code, or
    /// a syllable count that does not match the number of Han characters.
    Rejected,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ImportFailure {
    /// 1-based line number in the submitted text, so a user can find the row.
    pub line: usize,
    pub issue: ImportIssue,
}

/// The envelope was unusable, so no row was examined.
#[derive(Clone, Copy, Debug, Error, Eq, PartialEq)]
pub enum ImportError {
    #[error("dictionary import format is not supported")]
    UnsupportedFormat,
    #[error("dictionary import is empty")]
    Empty,
    #[error("dictionary import is too large")]
    TooLarge,
    #[error("dictionary import contains unsupported control characters")]
    ControlCharacters,
    #[error("dictionary import contains no usable rows")]
    NoUsableRows,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct ImportReport {
    pub entries: Vec<ImportEntry>,
    /// Rows examined and rejected.
    pub failed: usize,
    /// The first few failures, for a message a user can act on.
    pub first_failures: Vec<ImportFailure>,
    /// Rows beyond [`MAX_ENTRIES`] were not examined.
    pub truncated: bool,
}

pub const REPORTED_FAILURES: usize = 5;

impl ImportReport {
    /// Fold rows the Engine refused into this report.
    ///
    /// The parser only checks the key alphabet and length; the Engine also
    /// demands complete pinyin syllables and one syllable per Han character,
    /// so ordinary real files contain rows that parse but are then refused.
    /// Those belong in the same counters the user already sees, named by line,
    /// rather than aborting an import that has already written part of itself.
    pub fn record_rejected(&mut self, lines: &[usize]) {
        self.failed += lines.len();
        for line in lines {
            if self.first_failures.len() >= REPORTED_FAILURES {
                break;
            }
            self.first_failures.push(ImportFailure {
                line: *line,
                issue: ImportIssue::Rejected,
            });
        }
        // Parse failures are reported in line order; keep the combined list in
        // line order too, so "first appeared at line N" stays true.
        self.first_failures.sort_by_key(|failure| failure.line);
    }
}

/// Parse a user-supplied dictionary file.
///
/// Returns `Err` only when the envelope itself is unusable. Individual bad rows
/// are skipped and counted, so one stray line cannot reject an entire file.
pub fn parse(
    kind: ImportKind,
    format: &str,
    text: &str,
    max_bytes: usize,
) -> Result<ImportReport, ImportError> {
    let format = ImportFormat::parse(format).ok_or(ImportError::UnsupportedFormat)?;
    if text.is_empty() {
        return Err(ImportError::Empty);
    }
    if text.len() > max_bytes {
        return Err(ImportError::TooLarge);
    }
    // A NUL or stray control byte means the file is not the text format claimed;
    // examining rows from it would be guesswork.
    if text.contains('\0')
        || text
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
    {
        return Err(ImportError::ControlCharacters);
    }

    let mut report = ImportReport {
        entries: Vec::new(),
        failed: 0,
        first_failures: Vec::new(),
        truncated: false,
    };
    let mut in_yaml_header = false;
    for (index, line) in text.lines().enumerate() {
        if report.entries.len() >= MAX_ENTRIES {
            report.truncated = true;
            break;
        }
        let line = line.trim_end_matches('\r');
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if format == ImportFormat::Rime {
            if trimmed == "---" {
                in_yaml_header = true;
                continue;
            }
            if trimmed == "..." {
                in_yaml_header = false;
                continue;
            }
            if in_yaml_header {
                continue;
            }
        }
        match parse_row(kind, format, line) {
            Ok(mut entry) => {
                entry.line = index + 1;
                report.entries.push(entry);
            }
            Err(issue) => {
                report.failed += 1;
                if report.first_failures.len() < REPORTED_FAILURES {
                    report.first_failures.push(ImportFailure {
                        line: index + 1,
                        issue,
                    });
                }
            }
        }
    }
    if report.entries.is_empty() {
        return Err(ImportError::NoUsableRows);
    }
    Ok(report)
}

fn parse_row(
    kind: ImportKind,
    format: ImportFormat,
    line: &str,
) -> Result<ImportEntry, ImportIssue> {
    let columns: Vec<_> = line.split('\t').collect();
    if !(2..=3).contains(&columns.len()) {
        return Err(ImportIssue::ColumnCount);
    }
    // Windows exports put the code first; the other formats put the word first.
    let (word, key) = if format == ImportFormat::Windows {
        (columns[1].trim(), columns[0].trim())
    } else {
        (columns[0].trim(), columns[1].trim())
    };
    let key = key.to_ascii_lowercase();
    let weight = match columns.get(2).map(|value| value.trim()) {
        None | Some("") => 10000,
        // Rime carries metadata such as `c=3` in the third column.
        Some(value) if format == ImportFormat::Rime && value.contains('=') => 10000,
        Some(value) => value.parse::<i64>().map_err(|_| ImportIssue::Weight)?,
    };

    if key.is_empty() {
        return Err(ImportIssue::EmptyKey);
    }
    if key.len() > kind.key_limit() {
        return Err(ImportIssue::KeyTooLong);
    }
    if !kind.key_is_well_formed(&key, format) || key.chars().any(char::is_control) {
        return Err(ImportIssue::KeyAlphabet);
    }
    if word.is_empty() {
        return Err(ImportIssue::EmptyValue);
    }
    if word.len() > MAX_VALUE_BYTES || word.chars().any(char::is_control) {
        return Err(ImportIssue::ValueTooLong);
    }
    if kind == ImportKind::QuickPhrase && word.encode_utf16().count() > MAX_QUICK_PHRASE_UTF16 {
        return Err(ImportIssue::QuickPhraseTooLong);
    }
    if weight < 0 {
        return Err(ImportIssue::Weight);
    }
    Ok(ImportEntry {
        key,
        value: word.to_owned(),
        weight,
        line: 0, // Filled in by the caller, which knows the line number.
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    const LIMIT: usize = 1 << 20;

    fn parse_ok(kind: ImportKind, format: &str, text: &str) -> ImportReport {
        parse(kind, format, text, LIMIT).expect("envelope is usable")
    }

    #[test]
    fn standard_and_windows_rows_use_opposite_column_order() {
        let standard = parse_ok(
            ImportKind::Pinyin,
            "standard",
            "你好\tni'hao\t7\n# comment\n西安\txi'an\n",
        );
        assert_eq!(standard.entries.len(), 2);
        assert_eq!(standard.entries[0].key, "ni'hao");
        assert_eq!(standard.entries[0].value, "你好");
        assert_eq!(standard.entries[0].weight, 7);
        // An omitted weight uses the shared default.
        assert_eq!(standard.entries[1].weight, 10000);
        assert_eq!(standard.failed, 0);

        let windows = parse_ok(ImportKind::Wubi, "windows", "wq\t你好\t9\n");
        assert_eq!(windows.entries[0].key, "wq");
        assert_eq!(windows.entries[0].value, "你好");
    }

    #[test]
    fn one_unusable_row_no_longer_rejects_the_whole_file() {
        // The previous parser returned Err here and imported nothing.
        let report = parse_ok(
            ImportKind::Pinyin,
            "standard",
            "你好\tni'hao\n坏行没有制表符\n世界\tshi'jie\n再见\tZAI JIAN\n",
        );
        assert_eq!(report.entries.len(), 2);
        assert_eq!(report.failed, 2);
        assert_eq!(
            report.first_failures,
            vec![
                ImportFailure {
                    line: 2,
                    issue: ImportIssue::ColumnCount
                },
                ImportFailure {
                    line: 4,
                    issue: ImportIssue::KeyAlphabet
                },
            ]
        );
        assert!(!report.truncated);
    }

    #[test]
    fn rime_skips_its_yaml_header_and_metadata_weights() {
        let report = parse_ok(
            ImportKind::Pinyin,
            "rime",
            "---\nname: demo\n...\n你好\tni hao\tc=3\n世界\tshi jie\n",
        );
        assert_eq!(report.entries.len(), 2);
        // Metadata in the weight column falls back to the default.
        assert_eq!(report.entries[0].weight, 10000);
        // Rime keys may contain spaces; the other formats may not.
        assert_eq!(report.entries[0].key, "ni hao");
        assert_eq!(report.failed, 0);

        let standard = parse(ImportKind::Pinyin, "standard", "你好\tni hao\n", LIMIT);
        assert_eq!(standard, Err(ImportError::NoUsableRows));
    }

    #[test]
    fn every_key_alphabet_and_length_bound_is_preserved() {
        // Wubi keys are at most four lowercase letters.
        assert_eq!(
            parse(ImportKind::Wubi, "windows", "abcde\t你好\n", LIMIT),
            Err(ImportError::NoUsableRows)
        );
        // English keys are letters only.
        assert_eq!(
            parse(ImportKind::English, "standard", "hello\th3llo\n", LIMIT),
            Err(ImportError::NoUsableRows)
        );
        // Quick phrase keys allow digits.
        assert_eq!(
            parse_ok(ImportKind::QuickPhrase, "standard", "你好\tnh1\n")
                .entries
                .len(),
            1
        );
        // Negative weights are refused.
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "你好\tni\t-1\n", LIMIT),
            Err(ImportError::NoUsableRows)
        );
        // A non-numeric weight is refused.
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "你好\tni\tmuch\n", LIMIT),
            Err(ImportError::NoUsableRows)
        );
        // Quick phrases are bounded in UTF-16 units.
        let long = "字".repeat(MAX_QUICK_PHRASE_UTF16 + 1);
        assert_eq!(
            parse(
                ImportKind::QuickPhrase,
                "standard",
                &format!("{long}\tnh\n"),
                LIMIT
            ),
            Err(ImportError::NoUsableRows)
        );
        let allowed = "字".repeat(MAX_QUICK_PHRASE_UTF16);
        assert_eq!(
            parse_ok(
                ImportKind::QuickPhrase,
                "standard",
                &format!("{allowed}\tnh\n")
            )
            .entries
            .len(),
            1
        );
    }

    #[test]
    fn envelope_problems_are_distinguished_from_row_problems() {
        assert_eq!(
            parse(ImportKind::Pinyin, "hans", "你好\tni'hao\n", LIMIT),
            Err(ImportError::UnsupportedFormat)
        );
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "", LIMIT),
            Err(ImportError::Empty)
        );
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "你好\tni'hao\n", 4),
            Err(ImportError::TooLarge)
        );
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "你好\tni\u{7}hao\n", LIMIT),
            Err(ImportError::ControlCharacters)
        );
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "\0", LIMIT),
            Err(ImportError::ControlCharacters)
        );
        // A file of comments examines no rows at all.
        assert_eq!(
            parse(ImportKind::Pinyin, "standard", "# only comments\n", LIMIT),
            Err(ImportError::NoUsableRows)
        );
    }

    #[test]
    fn rows_beyond_the_cap_are_reported_rather_than_rejected() {
        // The previous parser failed the entire import at this point.
        let mut text = String::new();
        for index in 0..(MAX_ENTRIES + 10) {
            text.push_str(&format!("词{index}\tni'hao\n"));
        }
        let report = parse_ok(ImportKind::Pinyin, "standard", &text);
        assert_eq!(report.entries.len(), MAX_ENTRIES);
        assert!(report.truncated);
        assert_eq!(report.failed, 0);
    }

    #[test]
    fn engine_rejections_join_the_same_report() {
        let mut report = parse_ok(
            ImportKind::Pinyin,
            "standard",
            "你好	ni'hao
坏行没有制表符
世界	shi'jie
",
        );
        assert_eq!(report.entries.len(), 2);
        assert_eq!(report.failed, 1);
        // Every accepted row knows which line it came from, so a row the Engine
        // refuses later can be named the same way a parse failure is.
        assert_eq!(report.entries[0].line, 1);
        assert_eq!(report.entries[1].line, 3);

        report.record_rejected(&[3]);
        assert_eq!(report.failed, 2);
        // Both kinds of failure sit in one list, in line order.
        assert_eq!(
            report.first_failures,
            vec![
                ImportFailure { line: 2, issue: ImportIssue::ColumnCount },
                ImportFailure { line: 3, issue: ImportIssue::Rejected },
            ]
        );
    }

    #[test]
    fn rejections_respect_the_reporting_cap() {
        let mut report = parse_ok(ImportKind::Pinyin, "standard", "你好	ni'hao
");
        let lines: Vec<usize> = (1..=REPORTED_FAILURES + 4).collect();
        report.record_rejected(&lines);
        // Every rejection is counted...
        assert_eq!(report.failed, REPORTED_FAILURES + 4);
        // ...but only the first few are named, as with parse failures.
        assert_eq!(report.first_failures.len(), REPORTED_FAILURES);
        assert!(report
            .first_failures
            .iter()
            .all(|failure| failure.issue == ImportIssue::Rejected));
    }

    #[test]
    fn only_the_first_few_failures_are_named() {
        let mut text = String::from("你好\tni'hao\n");
        for _ in 0..(REPORTED_FAILURES + 3) {
            text.push_str("没有制表符\n");
        }
        let report = parse_ok(ImportKind::Pinyin, "standard", &text);
        assert_eq!(report.entries.len(), 1);
        assert_eq!(report.failed, REPORTED_FAILURES + 3);
        assert_eq!(report.first_failures.len(), REPORTED_FAILURES);
    }
}
