//! Native management requests. Caller owns authorized paths and never logs payloads.
use super::{edit_personal_dictionary, response, DictionaryAccess, HostOptions};
use msime_engine_bridge::{DictionaryEntry, DictionaryKind};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::ffi::c_char;
use std::path::Path;

#[derive(Deserialize, Serialize)]
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
}
#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    options: HostOptions,
    action: Operation,
}

/// Native requests are bounded and return only redacted failures.
/// # Safety
/// request must reference length readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_dictionary(request: *const u8, length: usize) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: the caller guarantees the readable buffer above.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        dictionary_request_json(bytes)
    })
}

pub fn dictionary_request_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    if bytes.len() > 65536 {
        return Err("invalid dictionary buffer".into());
    }
    let request: Request =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary request")?;
    if request.options.api_version != 1 {
        return Err("unsupported host API version".into());
    }
    request
        .options
        .preferences
        .validate()
        .map_err(|_| "invalid dictionary options")?;
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
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn malformed_and_oversized_requests_are_redacted() {
        for bytes in [b"invalid-fixture".as_slice(), b"{}", b"{\"options\":null}"] {
            let result =
                crate::tests::read(unsafe { msime_client_dictionary(bytes.as_ptr(), bytes.len()) });
            assert_eq!(result["error"], "invalid dictionary request");
        }
        let result = crate::tests::read(unsafe { msime_client_dictionary(std::ptr::null(), 0) });
        assert_eq!(result["error"], "invalid dictionary buffer");
        let bytes = vec![0u8; 65537];
        let result =
            crate::tests::read(unsafe { msime_client_dictionary(bytes.as_ptr(), bytes.len()) });
        assert_eq!(result["error"], "invalid dictionary buffer");
    }
}
