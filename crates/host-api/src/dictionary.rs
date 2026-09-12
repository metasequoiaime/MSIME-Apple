//! Native management requests. The native caller owns and authorizes all paths.

use super::{edit_personal_dictionary, response, DictionaryAccess, HostOptions};
use msime_engine_bridge::{DictionaryEntry, DictionaryKind};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::ffi::c_char;
use std::path::Path;

#[derive(Clone, Copy, Deserialize, Serialize)]
#[serde(rename_all = "snake_case")]
enum Kind {
    Pinyin,
    Wubi,
    QuickPhrase,
    English,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Entry {
    kind: Kind,
    key: String,
    value: String,
    weight: i64,
}

impl From<Entry> for DictionaryEntry {
    fn from(entry: Entry) -> Self {
        Self {
            kind: match entry.kind {
                Kind::Pinyin => DictionaryKind::Pinyin,
                Kind::Wubi => DictionaryKind::Wubi,
                Kind::QuickPhrase => DictionaryKind::QuickPhrase,
                Kind::English => DictionaryKind::English,
            },
            key: entry.key,
            value: entry.value,
            weight: entry.weight,
        }
    }
}

impl From<Kind> for msime_engine_bridge::DictionaryKind {
    fn from(kind: Kind) -> Self {
        match kind {
            Kind::Pinyin => Self::Pinyin,
            Kind::Wubi => Self::Wubi,
            Kind::QuickPhrase => Self::QuickPhrase,
            Kind::English => Self::English,
        }
    }
}

impl TryFrom<DictionaryEntry> for Entry {
    type Error = &'static str;

    fn try_from(entry: DictionaryEntry) -> Result<Self, Self::Error> {
        let kind = match entry.kind {
            DictionaryKind::Pinyin => Kind::Pinyin,
            DictionaryKind::Wubi => Kind::Wubi,
            DictionaryKind::QuickPhrase => Kind::QuickPhrase,
            DictionaryKind::English => Kind::English,
            _ => return Err("unsupported dictionary kind"),
        };
        Ok(Self {
            kind,
            key: entry.key,
            value: entry.value,
            weight: entry.weight,
        })
    }
}

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum Operation {
    List {
        offset: usize,
        limit: usize,
    },
    Edit {
        previous: Option<Entry>,
        replacement: Option<Entry>,
        request_id: String,
    },
    Import {
        kind: Kind,
        format: String,
        text: String,
        request_id: String,
    },
    Export {
        kind: Kind,
        format: String,
        offset: usize,
        limit: usize,
    },
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    options: HostOptions,
    action: Operation,
}

/// Native management requests return only redacted errors.
/// # Safety
/// `request` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_dictionary(request: *const u8, length: usize) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: guaranteed by the caller contract above.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        dictionary_request_json(bytes)
    })
}

pub fn dictionary_request_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    if bytes.len() > 65536 {
        return Err("invalid dictionary buffer".into());
    }
    let request: Request =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary request".to_owned())?;
    if request.options.api_version != 1 {
        return Err("unsupported host API version".into());
    }
    request
        .options
        .preferences
        .validate()
        .map_err(|_| "invalid dictionary options".to_owned())?;
    let options = request.options.into_engine_options();
    match request.action {
        Operation::List { offset, limit } => {
            let _access = DictionaryAccess::try_session(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            let page = msime_engine_bridge::dictionary_entries(&options, offset, limit)
                .map_err(|_| "dictionary read rejected")?;
            let entries: Vec<Entry> = page
                .entries
                .into_iter()
                .map(Entry::try_from)
                .collect::<Result<_, _>>()?;
            Ok(json!({ "entries": entries, "has_more": page.has_more }))
        }
        Operation::Edit {
            previous,
            replacement,
            request_id,
        } => {
            let previous = previous.map(DictionaryEntry::from);
            let replacement = replacement.map(DictionaryEntry::from);
            edit_personal_dictionary(
                &options,
                previous.as_ref(),
                replacement.as_ref(),
                &request_id,
            )?;
            Ok(json!({ "applied": true }))
        }
        Operation::Import {
            kind,
            format,
            text,
            request_id,
        } => {
            let entries = if format == "hans" {
                parse_hans_import(&kind, &text, &options)?
            } else {
                parse_import(&kind, &format, &text)?
            };
            if request_id.is_empty()
                || request_id.len() > 120
                || !request_id
                    .bytes()
                    .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_'))
            {
                return Err("invalid dictionary request ID".into());
            }
            let _access = DictionaryAccess::try_maintenance(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            let mut applied = 0usize;
            for (index, entry) in entries.iter().enumerate() {
                let receipt = format!("{request_id}-{index}");
                // The batch already owns the maintenance lock; use the Engine bridge directly.
                let result =
                    msime_engine_bridge::dictionary_edit(&options, None, Some(entry), &receipt);
                if result.is_err() {
                    return Err("dictionary import rejected".into());
                }
                applied += 1;
            }
            Ok(json!({ "applied": applied }))
        }
        Operation::Export {
            kind,
            format,
            offset,
            limit,
        } => {
            if !matches!(format.as_str(), "standard" | "windows")
                || offset > 1_000_000
                || !(1..=1000).contains(&limit)
            {
                return Err("invalid dictionary export".into());
            }
            let _access = DictionaryAccess::try_session(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            let mut cursor = 0usize;
            let mut matching = Vec::new();
            let mut source_has_more = true;
            while source_has_more && matching.len() < offset.saturating_add(limit) {
                let page = msime_engine_bridge::dictionary_entries(&options, cursor, 1000)
                    .map_err(|_| "dictionary read rejected")?;
                if page.entries.is_empty() {
                    source_has_more = false;
                    break;
                }
                cursor = cursor.saturating_add(page.entries.len());
                source_has_more = page.has_more;
                matching.extend(
                    page.entries
                        .into_iter()
                        .filter(|entry| entry.kind == kind.into()),
                );
                if cursor > 1_000_000 {
                    break;
                }
            }
            let has_more = matching.len() > offset.saturating_add(limit)
                || (source_has_more && matching.len() >= offset.saturating_add(limit));
            let text = matching
                .into_iter()
                .skip(offset)
                .take(limit)
                .map(|entry| {
                    if format == "windows" {
                        format!("{}\t{}\t{}", entry.key, entry.value, entry.weight)
                    } else {
                        format!("{}\t{}\t{}", entry.value, entry.key, entry.weight)
                    }
                })
                .collect::<Vec<_>>()
                .join("\n");
            let text = if text.is_empty() {
                text
            } else {
                format!("{text}\n")
            };
            Ok(json!({ "text": text, "has_more": has_more }))
        }
    }
}

fn parse_import(kind: &Kind, format: &str, text: &str) -> Result<Vec<DictionaryEntry>, String> {
    if !matches!(format, "standard" | "windows" | "rime")
        || text.is_empty()
        || text.len() > msime_client_core::cloud_dictionary::MAX_IMPORT_BYTES
        || text.contains('\0')
        || text
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
    {
        return Err("invalid dictionary import".into());
    }
    let mut entries = Vec::new();
    let mut in_yaml_header = false;
    for line in text.lines() {
        let line = line.trim_end_matches('\r');
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        if format == "rime" {
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
        let columns: Vec<_> = line.split('\t').collect();
        if !(2..=3).contains(&columns.len()) || entries.len() >= 1000 {
            return Err("invalid dictionary import".into());
        }
        let (word, key) = if format == "windows" {
            (columns[1].trim(), columns[0].trim())
        } else {
            (columns[0].trim(), columns[1].trim())
        };
        let key = key.to_ascii_lowercase();
        let weight = match columns.get(2).map(|value| value.trim()) {
            None | Some("") => 10000,
            Some(value) if format == "rime" && value.contains('=') => 10000,
            Some(value) => value
                .parse::<i64>()
                .map_err(|_| "invalid dictionary import")?,
        };
        let entry = DictionaryEntry {
            kind: (*kind).into(),
            key: key.clone(),
            value: word.to_owned(),
            weight,
        };
        let key_limit = match kind {
            Kind::Pinyin => 256,
            Kind::Wubi => 4,
            Kind::QuickPhrase => 32,
            Kind::English => 64,
        };
        let key_alphabet = match kind {
            Kind::Pinyin => key.bytes().all(|byte| {
                byte.is_ascii_lowercase() || byte == b'\'' || (format == "rime" && byte == b' ')
            }),
            Kind::Wubi => key.bytes().all(|byte| byte.is_ascii_lowercase()),
            Kind::QuickPhrase => key
                .bytes()
                .all(|byte| byte.is_ascii_lowercase() || byte.is_ascii_digit()),
            Kind::English => key.bytes().all(|byte| byte.is_ascii_alphabetic()),
        };
        if key.is_empty()
            || key.len() > key_limit
            || !key_alphabet
            || word.is_empty()
            || word.len() > 1024
            || weight < 0
            || key.chars().any(char::is_control)
            || word.chars().any(char::is_control)
        {
            return Err("invalid dictionary import".into());
        }
        entries.push(entry);
    }
    if entries.is_empty() {
        return Err("invalid dictionary import".into());
    }
    Ok(entries)
}

fn parse_hans_import(
    kind: &Kind,
    text: &str,
    options: &msime_engine_bridge::EngineOptions,
) -> Result<Vec<DictionaryEntry>, String> {
    if !matches!(kind, Kind::Pinyin)
        || text.is_empty()
        || text.len() > msime_client_core::cloud_dictionary::MAX_IMPORT_BYTES
        || text.contains('\0')
        || text
            .chars()
            .any(|character| character.is_control() && !matches!(character, '\n' | '\r'))
    {
        return Err("invalid dictionary import".into());
    }
    let mut entries = Vec::new();
    for line in text.lines() {
        let word = line.trim();
        if word.is_empty() || word.starts_with('#') {
            continue;
        }
        if entries.len() >= 1000
            || word.len() > 1024
            || !word.chars().all(is_han_character)
        {
            return Err("invalid dictionary import".into());
        }
        let key = msime_engine_bridge::hanzi_to_pinyin(options, word);
        if key.is_empty() || key.len() > 256 {
            return Err("dictionary pinyin unavailable".into());
        }
        entries.push(DictionaryEntry {
            kind: DictionaryKind::Pinyin,
            key,
            value: word.to_owned(),
            weight: 10000,
        });
    }
    if entries.is_empty() {
        return Err("invalid dictionary import".into());
    }
    Ok(entries)
}

fn is_han_character(character: char) -> bool {
    matches!(
        character as u32,
        0x3400..=0x4dbf
            | 0x4e00..=0x9fff
            | 0xf900..=0xfaff
            | 0x20000..=0x2fa1f
    )
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn malformed_and_oversized_requests_are_redacted() {
        for bytes in [b"invalid-fixture".as_slice(), b"{}", b"{\"options\":null}"] {
            assert_eq!(
                dictionary_request_json(bytes).unwrap_err(),
                "invalid dictionary request"
            );
        }
        assert_eq!(
            dictionary_request_json(&vec![0u8; 65537]).unwrap_err(),
            "invalid dictionary buffer"
        );
    }

    #[test]
    fn parses_standard_and_windows_rows_without_logging_content() {
        let standard = parse_import(
            &Kind::Pinyin,
            "standard",
            "你好\tni'hao\t7\n# comment\n西安\txi'an\n",
        )
        .unwrap();
        assert_eq!(standard.len(), 2);
        assert_eq!(standard[0].value, "你好");
        assert_eq!(standard[0].key, "ni'hao");
        assert_eq!(standard[1].weight, 10000);

        let windows = parse_import(&Kind::Wubi, "windows", "wq\t你好\t9\n").unwrap();
        assert_eq!(windows[0].key, "wq");
        assert_eq!(windows[0].value, "你好");
    }

    #[test]
    fn accepts_rime_yaml_front_matter_and_metadata_weights() {
        let entries = parse_import(
            &Kind::Pinyin,
            "rime",
            "---\nname: luna_pinyin\nsort: by_weight\n...\n你好\tni hao\tc=3 d=0.12 t=12345\n西安\txi'an\t5\n",
        )
        .unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].key, "ni hao");
        assert_eq!(entries[0].weight, 10000);
        assert_eq!(entries[1].weight, 5);
    }

    #[test]
    fn rejects_unsupported_or_unbounded_import_rows() {
        assert!(parse_import(&Kind::Pinyin, "hans", "你好\tni'hao").is_err());
        assert!(parse_import(&Kind::Wubi, "windows", "abcde\t你好").is_err());
        assert!(parse_import(&Kind::Pinyin, "standard", "你好\tni\t-1").is_err());
        assert!(parse_import(&Kind::Pinyin, "standard", "# only comments\n").is_err());
    }
}
