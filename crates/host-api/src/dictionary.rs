//! Native management requests. The native caller owns and authorizes all paths.

use super::{
    edit_personal_dictionary, invalid_dictionary_entry, response, DictionaryAccess, HostOptions,
};
use msime_client_core::dictionary::import::{dictionary_row_matches, PageSelector};
use msime_client_core::dictionary::personal::{
    PersonalDictionaryError, PersonalDictionaryStore, PersonalWord, PersonalWordKind,
    PersonalWordRequestStatus,
};
use msime_engine_bridge::{DictionaryEntry, DictionaryKind};
use serde::{Deserialize, Serialize};
use serde_json::json;
use std::ffi::c_char;
use std::path::Path;

#[derive(Clone, Copy, Deserialize, Serialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
enum Kind {
    Pinyin,
    Wubi,
    QuickPhrase,
    English,
}

/// Where a listed row comes from. A bundled row shipped with the dictionary (or was learned from typing rather than added): its code and word are fixed, so it can only be given another weight or deleted.
#[derive(Clone, Copy, Debug, Deserialize, Serialize, Eq, PartialEq)]
#[serde(rename_all = "snake_case")]
enum Source {
    User,
    Bundled,
}

#[derive(Deserialize, Serialize)]
#[serde(deny_unknown_fields)]
struct Entry {
    kind: Kind,
    key: String,
    value: String,
    weight: i64,
    /// Set on every row a list returns, and sent back with it as `previous`. Absent means a user entry, which is what every caller predating bundled rows sends.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    source: Option<Source>,
}

/// The refusal for an edit that would change what a bundled row types rather than its weight.
const BUNDLED_READ_ONLY: &str = "bundled dictionary entry is read-only";

impl Entry {
    fn is_bundled(&self) -> bool {
        self.source == Some(Source::Bundled)
    }

    fn with_source(mut self, source: Source) -> Self {
        self.source = Some(source);
        self
    }

    /// The entry as the Engine will store it: the code lowercased, and a weight inside the range
    /// it accepts.
    ///
    /// Both are the Engine's rules (`validate_personal_dictionary_entry`), applied here so a value
    /// this layer would otherwise hand on and have refused - with an error naming neither the
    /// field nor the reason - becomes the entry the user meant. A weight of zero is the one the
    /// reference writes for an imported English row, and losing the row over a rank difference of
    /// one would be the worse trade.
    fn normalized_for_engine(mut self) -> Self {
        self.key = self.key.to_ascii_lowercase();
        self.weight = self.weight.max(MINIMUM_WEIGHT);
        self
    }

    /// A pinyin entry with its key cut into the syllables the Engine stores, the same way an imported row is.
    ///
    /// The Engine only accepts separated syllables (`ni'hao`), and the reference's settings page accepts `nihao` by normalizing it against the word's length first. Without this the add form refused the way almost everyone types pinyin, with a message that did not say why. A key that cannot be cut is passed on unchanged for the Engine to judge: its refusal names the rule, and a word containing a character outside the Han ranges counted here (`〇`) can still be saved with explicitly separated syllables, as before.
    fn with_full_pinyin(mut self) -> Self {
        if self.kind == Kind::Pinyin {
            if let Some(key) = full_pinyin_key(&self.key, &self.value) {
                self.key = key;
            }
        }
        self
    }

    /// Does this row belong on a page filtered by `kind` and code `prefix`?
    fn matches(&self, kind: Option<Kind>, prefix: &str) -> bool {
        let same_kind = kind.map(|wanted| wanted == self.kind).unwrap_or(true);
        dictionary_row_matches(same_kind, (&self.kind).into(), &self.key, prefix)
    }
}

/// The smallest weight the Engine stores; anything below it is refused outright.
const MINIMUM_WEIGHT: i64 = 1;

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
            source: None,
        })
    }
}

#[derive(Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case", deny_unknown_fields)]
enum Operation {
    List {
        offset: usize,
        limit: usize,
        /// Restrict the page to one dictionary. Absent means every kind, which
        /// is what older callers sent.
        #[serde(default)]
        kind: Option<Kind>,
        /// Code prefix to search for, matched case-insensitively. Pinyin separators are ignored on both sides, so `nihao` and `nih` find `ni'hao`. With a kind, a prefix searches the working dictionary itself, bundled words included, as does the quick-phrase list with no prefix; every other page lists the user's own words only.
        #[serde(default)]
        query: Option<String>,
        /// Keep the page to the user's own words even with a kind and a prefix. The mobile personal dictionary queue sets this: its edits cannot carry a bundled row, which may only be re-weighted or deleted in place.
        #[serde(default)]
        user_only: bool,
    },
    Edit {
        previous: Option<Entry>,
        replacement: Option<Entry>,
        request_id: String,
    },
    QueueEdit {
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
    ImportPersonal {
        text: String,
        request_id: String,
    },
    Reset,
    Export {
        kind: Kind,
        format: String,
        offset: usize,
        limit: usize,
    },
    Retry {
        request_id: String,
    },
    DismissFailure {
        request_id: String,
    },
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    options: HostOptions,
    action: Operation,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct PersonalDictionaryImport {
    format: String,
    version: u32,
    entries: Vec<PersonalWord>,
}

fn parse_personal_dictionary_import(text: &str) -> Result<Vec<PersonalWord>, String> {
    if text.len() > 1_048_576 {
        return Err("personal dictionary file is too large".into());
    }
    let file: PersonalDictionaryImport =
        serde_json::from_str(text).map_err(|_| "invalid personal dictionary file".to_owned())?;
    if file.format != "msime-personal-dictionary" || file.version != 1 {
        return Err("unsupported personal dictionary file".into());
    }
    if file.entries.is_empty() || file.entries.len() > 128 {
        return Err("invalid personal dictionary entry count".into());
    }
    let mut identities = std::collections::HashSet::new();
    let mut entries = Vec::with_capacity(file.entries.len());
    for entry in file.entries {
        let entry = normalize_personal_word(entry)?;
        if !identities.insert(entry.identity()) {
            return Err("duplicate personal dictionary entry".into());
        }
        entries.push(entry);
    }
    Ok(entries)
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

/// The queued personal dictionary, for a host that cannot take the Engine's
/// maintenance lock when the request arrives.
///
/// `msime_client_dictionary` edits the Engine dictionary directly, which needs
/// the maintenance lock and therefore needs the keyboard not to be holding a
/// session. That is the right route for an edit made in a settings window while
/// nothing is being typed, and the wrong one for importing a file: the user is
/// as likely to do it with the keyboard up, and "dictionary maintenance busy"
/// is not an answer to "please add these words".
///
/// The queue is the answer the Apple and Android hosts already give. Entries go
/// into `<preferences_directory>/PersonalDictionary` and the keyboard applies
/// them the next time it starts a session, which is the one moment it is
/// certain no session is open. This entry point is the same dispatcher those
/// hosts call as Rust, published for the hosts that reach this crate through
/// the C ABI.
/// # Safety
/// `request` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_personal_dictionary_request(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        // The Apple-compatible import file is bounded at 1 MiB and the request framing needs room
        // on top of it; `personal_dictionary_request_json` applies the same ceiling itself.
        if request.is_null() || length > 1_200_000 {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: guaranteed by the caller contract above.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        personal_dictionary_request_json(bytes)
    })
}

/// Validate and normalize one entry without opening or changing dictionary state.
/// Engine diagnostics are redacted because they can contain submitted text.
/// # Safety
/// `request` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_dictionary_validate(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: guaranteed by the caller contract above.
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        let entry: Entry =
            serde_json::from_slice(bytes).map_err(|_| "invalid dictionary entry".to_owned())?;
        let normalized = msime_engine_bridge::dictionary_validate(&entry.into())
            .map_err(|_| "invalid dictionary entry".to_owned())?;
        Ok(json!(Entry::try_from(normalized)?))
    })
}

/// Read plain Chinese words, one per line, and answer the pinyin entries they would import as, without opening or changing any dictionary state.
///
/// For a host whose settings surface cannot take the Engine's maintenance lock or run `msime_client_prepare_host` while the keyboard may hold a session: iOS shows the result for confirmation and then queues it itself. The readings come from the packaged main dictionary under `resources`, opened read-only, and follow the same rules as the `hans` import format.
/// # Safety
/// Both pointers must reference readable buffers of the stated lengths. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_dictionary_hans_entries(
    text: *const u8,
    text_length: usize,
    resources: *const u8,
    resources_length: usize,
) -> *mut c_char {
    response(|| {
        if text.is_null()
            || resources.is_null()
            || text_length > msime_client_core::cloud::dictionary::MAX_IMPORT_BYTES
            || resources_length > 4096
        {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: guaranteed by the caller contract above.
        let text = std::str::from_utf8(unsafe { std::slice::from_raw_parts(text, text_length) })
            .map_err(|_| "invalid dictionary import")?;
        // SAFETY: guaranteed by the caller contract above.
        let resources =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(resources, resources_length) })
                .map_err(|_| "resources path is not UTF-8")?;
        hans_entries_json(text, resources)
    })
}

fn hans_entries_json(text: &str, resources: &str) -> Result<serde_json::Value, String> {
    let options = read_only_options(resources)?;
    let entries = parse_hans_import(&Kind::Pinyin, text, &options.into_engine_options())?
        .into_iter()
        .map(Entry::try_from)
        .collect::<Result<Vec<_>, _>>()?;
    Ok(json!({ "entries": entries }))
}

/// Parse a dictionary file into the words the personal dictionary queue accepts, with the report the settings page shows for it, without opening or changing any dictionary state.
///
/// `request` is `{kind, format, text}` in the shape of the `import` dictionary action. For the iOS host, whose Tauri settings page queues the words itself in the App Group store the keyboard reads; the readings for `hans` come from the packaged main dictionary under `resources`, opened read-only.
/// # Safety
/// Both pointers must reference readable buffers of the stated lengths. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_dictionary_import_entries(
    request: *const u8,
    request_length: usize,
    resources: *const u8,
    resources_length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null()
            || resources.is_null()
            || request_length > 1_200_000
            || resources_length > 4096
        {
            return Err("invalid dictionary buffer".into());
        }
        // SAFETY: guaranteed by the caller contract above.
        let bytes = unsafe { std::slice::from_raw_parts(request, request_length) };
        // SAFETY: guaranteed by the caller contract above.
        let resources =
            std::str::from_utf8(unsafe { std::slice::from_raw_parts(resources, resources_length) })
                .map_err(|_| "resources path is not UTF-8")?;
        import_entries_json(bytes, resources)
    })
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct ImportEntriesRequest {
    kind: Kind,
    format: String,
    text: String,
}

fn import_entries_json(bytes: &[u8], resources: &str) -> Result<serde_json::Value, String> {
    let request: ImportEntriesRequest =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary import".to_owned())?;
    let options = read_only_options(resources)?;
    let (words, mut result) = queued_import(
        &request.kind,
        &request.format,
        &request.text,
        &options.into_engine_options(),
    )?;
    result["entries"] = json!(words
        .into_iter()
        .map(personal_to_entry)
        .collect::<Result<Vec<_>, _>>()?);
    Ok(result)
}

/// Host options that open nothing but the packaged, read-only main dictionary.
fn read_only_options(resources: &str) -> Result<HostOptions, String> {
    if !Path::new(resources).is_absolute() {
        return Err("resources path must be absolute".into());
    }
    // The packaged directory stands in for every runtime path: only the read-only main dictionary is opened.
    serde_json::from_value(json!({
        "api_version": 1,
        "resources": resources,
        "user_data": resources,
        "cache": resources,
        "dictionaries": resources,
        "preferences": msime_client_core::preferences::Preferences::default(),
    }))
    .map_err(|_| "invalid dictionary options".into())
}

/// The personal dictionary queue takes at most this many words per import.
const MAX_QUEUED_IMPORT: usize = 128;

/// A dictionary file as the words the mobile queue accepts, and the import report the settings page shows for it.
///
/// The queue refuses a whole batch for one invalid or repeated word, or for more than 128, where the desktop import applies what it can and names the rest. So rows the Engine would refuse are counted with their line, a repeated word is queued once, and rows past the queue's capacity are reported as truncated: a real file imports on a phone the way it does on a desktop.
fn queued_import(
    kind: &Kind,
    format: &str,
    text: &str,
    options: &msime_engine_bridge::EngineOptions,
) -> Result<(Vec<PersonalWord>, serde_json::Value), String> {
    let (entries, report) = if format == "hans" {
        (parse_hans_import(kind, text, options)?, None)
    } else {
        let (entries, report) = parse_import(kind, format, text, Some(options))?;
        (entries, Some(report))
    };
    // The bridge entry carries no line number; the parsed report lists the same rows in the same order.
    let source_lines: Vec<usize> = report
        .as_ref()
        .map(|parsed| parsed.entries.iter().map(|entry| entry.line).collect())
        .unwrap_or_default();
    let mut report = report.unwrap_or(msime_client_core::dictionary::import::ImportReport {
        entries: Vec::new(),
        failed: 0,
        first_failures: Vec::new(),
        truncated: false,
        swapped: false,
    });
    let mut words = Vec::new();
    let mut identities = std::collections::HashSet::new();
    let mut rejected_lines = Vec::new();
    for (index, entry) in entries.into_iter().enumerate() {
        let Ok(word) = normalize_personal_word(PersonalWord {
            kind: personal_kind(entry.kind),
            key: entry.key,
            value: entry.value,
            weight: entry.weight,
        }) else {
            rejected_lines.push(source_lines.get(index).copied().unwrap_or(0));
            continue;
        };
        if !identities.insert(word.identity()) {
            continue;
        }
        if words.len() == MAX_QUEUED_IMPORT {
            report.truncated = true;
            break;
        }
        words.push(word);
    }
    if words.is_empty() {
        return Err("dictionary import rejected".into());
    }
    report.record_rejected(&rejected_lines);
    let result = json!({
        "applied": words.len(),
        "failed": report.failed,
        "truncated": report.truncated,
        "swapped": report.swapped,
        "first_failures": serde_json::to_value(&report.first_failures).map_err(|error| error.to_string())?,
    });
    Ok((words, result))
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
        Operation::List {
            offset,
            limit,
            kind,
            query,
            user_only,
        } => {
            let _access = DictionaryAccess::try_session(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            if limit == 0 || limit > 1000 {
                return Err("invalid dictionary page".into());
            }
            let prefix = query.unwrap_or_default();
            if prefix.len() > 256 {
                return Err("invalid dictionary page".into());
            }
            // A code within one dictionary is looked up in the dictionary itself, the way the reference's manager searches, so a bundled word can be found and re-weighted. Quick phrases are few enough to list whole. Without a code the page stays the user's own words: the bundled pinyin tables alone hold hundreds of thousands of rows.
            if let Some(kind) = kind.filter(|kind| {
                !user_only
                    && (*kind == Kind::QuickPhrase
                        || prefix.bytes().any(|byte| {
                            !byte.is_ascii_whitespace() && (*kind != Kind::Pinyin || byte != b'\'')
                        }))
            }) {
                let page = msime_engine_bridge::dictionary_table_entries(
                    &options,
                    kind.into(),
                    prefix.trim(),
                    offset,
                    limit,
                )
                .map_err(|_| "dictionary read rejected")?;
                let entries = page
                    .entries
                    .into_iter()
                    .map(|row| {
                        let source = if row.user_inserted {
                            Source::User
                        } else {
                            Source::Bundled
                        };
                        Entry::try_from(row.entry).map(|entry| entry.with_source(source))
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                return Ok(json!({ "entries": entries, "has_more": page.has_more }));
            }
            let (entries, has_more) = user_entries_page(&options, offset, limit, kind, &prefix)?;
            Ok(json!({ "entries": entries, "has_more": has_more }))
        }
        Operation::Edit {
            previous,
            replacement,
            request_id,
        } => {
            if let Some(previous) = previous.as_ref().filter(|entry| entry.is_bundled()) {
                let weight = bundled_weight(previous, replacement.as_ref())?;
                return edit_bundled_entry(&options, previous, weight, &request_id);
            }
            if replacement.as_ref().is_some_and(Entry::is_bundled) {
                return Err(BUNDLED_READ_ONLY.into());
            }
            // The code is case-insensitive, and the Engine says so by folding it
            // (`validate_personal_dictionary_entry` lowercases the key before it checks anything
            // else); the reference's settings page lowercases it at its own boundary for the same
            // reason. This layer used to reject an uppercase letter instead, so a quick phrase
            // typed as `QQ` came back as "invalid dictionary entry" while the very same code
            // typed in lower case was fine - and an entry edited after being imported from a file
            // that had it in upper case could never be matched to the row it stored.
            let previous = previous.map(Entry::normalized_for_engine);
            if let Some(entry) = &previous {
                validate_entry(entry)?;
            }
            // Only the replacement is re-cut: the previous entry is a row the list returned, and it has to reach the Engine exactly as stored to be found.
            let replacement = replacement.map(replacement_for_engine).transpose()?;
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
            let (entries, report) = if format == "hans" {
                (parse_hans_import(&kind, &text, &options)?, None)
            } else {
                let (entries, report) = parse_import(&kind, &format, &text, Some(&options))?;
                (entries, Some(report))
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
            // Rows the Engine refuses are counted and named, not fatal. The
            // shared parser only checks the key alphabet and length, while the
            // Engine additionally demands complete pinyin syllables and one
            // syllable per Han character - so ordinary real files (jianpin
            // rows, a two-syllable code on a three-character word) contain
            // some. Aborting discarded the rows already committed and told the
            // user nothing but "check the format", leaving the dictionary
            // half-written with no way to know how far it got.
            let mut rejected_lines: Vec<usize> = Vec::new();
            // The bridge entry carries no line number, so the parsed report is
            // what maps a refused row back to the line the user has to fix.
            // The two lists are built from the same rows in the same order.
            let source_lines: Vec<usize> = report
                .as_ref()
                .map(|parsed| parsed.entries.iter().map(|entry| entry.line).collect())
                .unwrap_or_default();
            for (index, entry) in entries.iter().enumerate() {
                let receipt = format!("{request_id}-{index}");
                // The batch already owns the maintenance lock; use the Engine bridge directly.
                let result =
                    msime_engine_bridge::dictionary_edit(&options, None, Some(entry), &receipt);
                if result.is_err() {
                    // A hans import has no parsed report, so its rows have no
                    // line to name; they are still counted.
                    rejected_lines.push(source_lines.get(index).copied().unwrap_or(0));
                    continue;
                }
                applied += 1;
            }
            // Nothing landed and the Engine refused everything: that is a
            // failed import, not a partial one, and the caller should say so.
            if applied == 0 && !rejected_lines.is_empty() {
                return Err("dictionary import rejected".into());
            }
            let mut report =
                report.unwrap_or(msime_client_core::dictionary::import::ImportReport {
                    entries: Vec::new(),
                    failed: 0,
                    first_failures: Vec::new(),
                    truncated: false,
                    swapped: false,
                });
            report.record_rejected(&rejected_lines);
            let mut result = json!({ "applied": applied });
            // Tell the caller what was skipped instead of reporting a clean import.
            result["failed"] = json!(report.failed);
            result["truncated"] = json!(report.truncated);
            // The file turned out to be the other column order; the card says so rather than
            // leaving the user with a count they cannot explain.
            result["swapped"] = json!(report.swapped);
            result["first_failures"] =
                serde_json::to_value(&report.first_failures).map_err(|error| error.to_string())?;
            Ok(result)
        }
        Operation::QueueEdit { .. } | Operation::ImportPersonal { .. } => {
            Err("personal dictionary operation requires the mobile queue".into())
        }
        Operation::Reset => {
            let _access = DictionaryAccess::try_maintenance(
                Path::new(&options.user_data),
                Path::new(&options.dictionaries),
            )
            .map_err(|_| "dictionary access unavailable")?
            .ok_or("dictionary maintenance busy")?;
            msime_engine_bridge::reset_learned_data(&options)
                .map_err(|_| "learned-data reset rejected")?;
            Ok(json!({ "reset": true }))
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
                // The pinyin export also carries the weights learned or set for bundled words, and leaves out single characters, as the reference's does; the other dictionaries export the user's own words only.
                let page = msime_engine_bridge::dictionary_export_entries(
                    &options,
                    cursor,
                    1000,
                    kind == Kind::Pinyin,
                )
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
        Operation::Retry { .. } | Operation::DismissFailure { .. } => {
            Err("dictionary failure actions require the Android personal dictionary API".into())
        }
    }
}

/// Android settings use a shared host/keyboard queue rather than editing the
/// Engine while the IME may still own a session. The queue is intentionally a
/// separate entry point so desktop hosts retain their synchronous contract.
pub fn personal_dictionary_request_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    // JSON imports are bounded by the Apple-compatible 1 MiB file limit; the
    // small amount of request framing needs room in addition to the file.
    if bytes.len() > 1_200_000 {
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
    let directory = request
        .options
        .preferences_directory
        .as_deref()
        .filter(|path| Path::new(path).is_absolute())
        .ok_or("personal dictionary shared directory unavailable")?;
    let store = PersonalDictionaryStore::new(Path::new(directory).join("PersonalDictionary"));
    match request.action {
        // The kind and prefix travel with the page request, and the keyboard answers them from the user's whole store. The entries returned here are the last page it confirmed, which `page_kind` and `page_query` describe.
        Operation::List {
            offset,
            limit,
            kind,
            query,
            ..
        } => {
            if offset > 1_000_000 || !(1..=1000).contains(&limit) {
                return Err("invalid dictionary page".into());
            }
            store
                .request_page(
                    offset,
                    kind.map(|kind| personal_kind(kind.into())),
                    query.as_deref().unwrap_or_default(),
                )
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            let has_more = state.has_more;
            let pending_count = state.pending_count();
            let snapshot_date = state.snapshot_date.clone();
            let snapshot_error = state.snapshot_error.clone();
            let page_offset = state.page_offset;
            let requested_page_offset = state.requested_page_offset;
            let page_kind = state.page_kind.map(personal_to_kind);
            let page_query = state.page_query.clone();
            let failed_requests: Vec<_> = state
                .requests
                .iter()
                .filter(|request| request.status == PersonalWordRequestStatus::Failed)
                .map(|request| {
                    json!({
                        "request_id": request.id,
                        "label": request.replacement.as_ref()
                            .or(request.previous.as_ref())
                            .map(|word| word.value.clone())
                            .unwrap_or_else(|| "词条".to_owned()),
                        "error": request.error.as_deref().unwrap_or("同步失败"),
                    })
                })
                .collect();
            let entries = state
                .entries
                .into_iter()
                .map(personal_to_entry)
                .collect::<Result<Vec<_>, _>>()?;
            Ok(json!({
                "entries": entries,
                "has_more": has_more,
                "pending_count": pending_count,
                "snapshot_date": snapshot_date,
                "snapshot_error": snapshot_error,
                "page_offset": page_offset,
                "requested_page_offset": requested_page_offset,
                "page_kind": page_kind,
                "page_query": page_query,
                "failed_requests": failed_requests,
            }))
        }
        Operation::Edit {
            previous,
            replacement,
            request_id,
        }
        | Operation::QueueEdit {
            previous,
            replacement,
            request_id,
        } => {
            let previous = previous.map(personal_from_entry).transpose()?;
            let replacement = replacement.map(personal_from_entry).transpose()?;
            store
                .enqueue(previous, replacement, request_id)
                .map_err(personal_dictionary_error)?;
            let pending_count = store
                .read()
                .map_err(personal_dictionary_error)?
                .pending_count();
            Ok(json!({ "queued": true, "pending_count": pending_count }))
        }
        Operation::Import {
            kind,
            format,
            text,
            request_id,
        } => {
            let options = request.options.into_engine_options();
            let (words, mut result) = queued_import(&kind, &format, &text, &options)?;
            store
                .enqueue_import(words, request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            result["queued"] = json!(true);
            result["pending_count"] = json!(state.pending_count());
            Ok(result)
        }
        Operation::ImportPersonal { text, request_id } => {
            let entries = parse_personal_dictionary_import(&text)?;
            store
                .enqueue_import(entries, request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "queued": true, "pending_count": state.pending_count() }))
        }
        Operation::Reset => Err("learned-data reset is unavailable on mobile".into()),
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
            let state = store.read().map_err(personal_dictionary_error)?;
            let matching: Vec<_> = state
                .entries
                .into_iter()
                .filter(|entry| personal_to_kind(entry.kind) == kind)
                .collect();
            let has_more = matching.len() > offset.saturating_add(limit);
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
        Operation::Retry { request_id } => {
            store
                .retry(&request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "pending_count": state.pending_count() }))
        }
        Operation::DismissFailure { request_id } => {
            store
                .dismiss_failure(&request_id)
                .map_err(personal_dictionary_error)?;
            let state = store.read().map_err(personal_dictionary_error)?;
            Ok(json!({ "pending_count": state.pending_count() }))
        }
    }
}

/// One page of the user's own words, optionally within one dictionary and under one code prefix. The caller holds dictionary access.
fn user_entries_page(
    options: &msime_engine_bridge::EngineOptions,
    offset: usize,
    limit: usize,
    kind: Option<Kind>,
    prefix: &str,
) -> Result<(Vec<Entry>, bool), String> {
    // Unfiltered pages still go straight through, so the common case costs exactly what it did before.
    if kind.is_none() && prefix.is_empty() {
        let page = msime_engine_bridge::dictionary_entries(options, offset, limit)
            .map_err(|_| "dictionary read rejected")?;
        let entries: Vec<Entry> = page
            .entries
            .into_iter()
            .map(|entry| Entry::try_from(entry).map(|entry| entry.with_source(Source::User)))
            .collect::<Result<_, _>>()?;
        return Ok((entries, page.has_more));
    }
    // The Engine pages the whole store in one sequence with no kind or prefix filter, so the selection happens here. Doing it on the client meant asking for 100 rows and discarding most of them: a user with more than a page of pinyin words who selected 五笔 saw an empty page 1 even though wubi entries existed.
    let mut selector = PageSelector::new(offset, limit);
    let mut entries: Vec<Entry> = Vec::new();
    let mut has_more = false;
    let mut scanned = 0usize;
    // Bound the work: a store with very few matches must not turn one request into an unbounded scan. Reaching the budget is reported as "there may be more" rather than silently ending the list.
    const SCAN_BUDGET: usize = 20_000;
    const CHUNK: usize = 500;
    loop {
        let page = msime_engine_bridge::dictionary_entries(options, scanned, CHUNK)
            .map_err(|_| "dictionary read rejected")?;
        let count = page.entries.len();
        for raw in page.entries {
            let entry = Entry::try_from(raw)?.with_source(Source::User);
            if !entry.matches(kind, prefix) {
                continue;
            }
            if selector.full() {
                has_more = true;
                break;
            }
            if selector.accept() {
                entries.push(entry);
            }
        }
        scanned += count;
        if has_more || count == 0 || !page.has_more {
            break;
        }
        if scanned >= SCAN_BUDGET {
            has_more = true;
            break;
        }
    }
    Ok((entries, has_more))
}

/// Synchronize the queue with the Engine. The caller must invoke this
/// only after its Engine session has been destroyed; the shared dictionary lock
/// then prevents races with any other host.
///
/// The request is the bare HostOptions a host passes to `msime_client_create`, as the C header documents and as both the Android and HarmonyOS hosts send it. Parsing it as an `{options, action}` envelope refused every call, which Android swallowed and HarmonyOS answered by rebuilding its session every two seconds.
pub fn personal_dictionary_sync_json(bytes: &[u8]) -> Result<serde_json::Value, String> {
    if bytes.len() > 65536 {
        return Err("invalid dictionary buffer".into());
    }
    let options: HostOptions =
        serde_json::from_slice(bytes).map_err(|_| "invalid dictionary request".to_owned())?;
    if options.api_version != 1 {
        return Err("unsupported host API version".into());
    }
    options
        .preferences
        .validate()
        .map_err(|_| "invalid dictionary options".to_owned())?;
    let directory = options
        .preferences_directory
        .as_deref()
        .filter(|path| Path::new(path).is_absolute())
        .ok_or("personal dictionary shared directory unavailable")?;
    let store = PersonalDictionaryStore::new(Path::new(directory).join("PersonalDictionary"));
    let options = options.into_engine_options();
    store
        .synchronize(
            |queued| {
                let previous = queued.previous.as_ref().map(personal_engine_entry);
                let replacement = queued.replacement.as_ref().map(personal_engine_entry);
                edit_personal_dictionary(
                    &options,
                    previous.as_ref(),
                    replacement.as_ref(),
                    &queued.id,
                )
            },
            |request| {
                let (entries, has_more) = user_entries_page(
                    &options,
                    request.offset,
                    100,
                    request.kind.map(personal_to_kind),
                    &request.query,
                )?;
                Ok(msime_client_core::dictionary::personal::PersonalWordPage {
                    entries: entries
                        .into_iter()
                        .map(|entry| PersonalWord {
                            kind: personal_kind(entry.kind.into()),
                            key: entry.key,
                            value: entry.value,
                            weight: entry.weight,
                        })
                        .collect(),
                    has_more,
                })
            },
        )
        .map_err(personal_dictionary_error)?;
    let state = store.read().map_err(personal_dictionary_error)?;
    Ok(json!({
        "synchronized": true,
        "pending_count": state.pending_count(),
        "snapshot_error": state.snapshot_error,
    }))
}

/// JNI entry point for the Android IME worker.
///
/// # Safety
/// `request` must point to `length` readable bytes. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_personal_dictionary_sync(
    request: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if request.is_null() || length > 65536 {
            return Err("invalid dictionary buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(request, length) };
        personal_dictionary_sync_json(bytes)
    })
}

fn personal_dictionary_error(error: PersonalDictionaryError) -> String {
    error.to_string()
}

fn personal_from_entry(entry: Entry) -> Result<PersonalWord, String> {
    // The queue holds the user's own words; a bundled row is edited in place through `edit`.
    if entry.is_bundled() {
        return Err(BUNDLED_READ_ONLY.into());
    }
    normalize_personal_word(PersonalWord {
        kind: personal_kind(entry.kind.into()),
        key: entry.key,
        value: entry.value,
        weight: entry.weight,
    })
}

fn normalize_personal_word(word: PersonalWord) -> Result<PersonalWord, String> {
    let entry = msime_engine_bridge::dictionary_validate(&personal_engine_entry(&word))
        .map_err(|_| "invalid personal dictionary entry".to_owned())?;
    Ok(PersonalWord {
        kind: personal_kind(entry.kind),
        key: entry.key,
        value: entry.value,
        weight: entry.weight,
    })
}

fn personal_engine_entry(word: &PersonalWord) -> msime_engine_bridge::DictionaryEntry {
    msime_engine_bridge::DictionaryEntry {
        kind: match word.kind {
            PersonalWordKind::Pinyin => DictionaryKind::Pinyin,
            PersonalWordKind::Wubi => DictionaryKind::Wubi,
            PersonalWordKind::QuickPhrase => DictionaryKind::QuickPhrase,
            PersonalWordKind::English => DictionaryKind::English,
        },
        key: word.key.clone(),
        value: word.value.clone(),
        weight: word.weight,
    }
}

fn personal_to_entry(entry: PersonalWord) -> Result<Entry, String> {
    Ok(Entry {
        kind: personal_to_kind(entry.kind),
        key: entry.key,
        value: entry.value,
        weight: entry.weight,
        source: None,
    })
}

/// The weight a bundled row is set to, or `None` to delete it. Its code and word are what the dictionary shipped, so a replacement may change the weight and nothing else.
fn bundled_weight(previous: &Entry, replacement: Option<&Entry>) -> Result<Option<i64>, String> {
    let Some(replacement) = replacement else {
        return Ok(None);
    };
    if replacement.kind != previous.kind
        || replacement.key != previous.key
        || replacement.value != previous.value
    {
        return Err(BUNDLED_READ_ONLY.into());
    }
    let weight = replacement.weight.max(MINIMUM_WEIGHT);
    if weight > 100_000_000 {
        return Err(invalid_dictionary_entry("weight is outside 1 to 100000000"));
    }
    Ok(Some(weight))
}

/// Re-weight or delete a bundled row under the maintenance lock, journaled so the change survives replay onto a fresh dictionary. Engine diagnostics are withheld, as for a user entry.
fn edit_bundled_entry(
    options: &msime_engine_bridge::EngineOptions,
    previous: &Entry,
    weight: Option<i64>,
    request_id: &str,
) -> Result<serde_json::Value, String> {
    let _access = DictionaryAccess::try_maintenance(
        Path::new(&options.user_data),
        Path::new(&options.dictionaries),
    )
    .map_err(|_| "dictionary access unavailable")?
    .ok_or("dictionary maintenance busy")?;
    if request_id.is_empty() {
        return Err("dictionary request id required".into());
    }
    let previous = DictionaryEntry {
        kind: previous.kind.into(),
        key: previous.key.clone(),
        value: previous.value.clone(),
        weight: previous.weight,
    };
    msime_engine_bridge::dictionary_edit_bundled(options, &previous, weight, request_id)
        .map_err(|_| "dictionary edit rejected")?;
    Ok(json!({ "applied": true }))
}

fn personal_kind(kind: DictionaryKind) -> PersonalWordKind {
    match kind {
        DictionaryKind::Pinyin => PersonalWordKind::Pinyin,
        DictionaryKind::Wubi => PersonalWordKind::Wubi,
        DictionaryKind::QuickPhrase => PersonalWordKind::QuickPhrase,
        DictionaryKind::English => PersonalWordKind::English,
        _ => unreachable!("unsupported personal dictionary kind"),
    }
}

fn personal_to_kind(kind: PersonalWordKind) -> Kind {
    match kind {
        PersonalWordKind::Pinyin => Kind::Pinyin,
        PersonalWordKind::Wubi => Kind::Wubi,
        PersonalWordKind::QuickPhrase => Kind::QuickPhrase,
        PersonalWordKind::English => Kind::English,
    }
}

/// The entry a manual add or edit hands to the Engine: the code folded, the weight inside the Engine's range, the host's own bounds checked, and a pinyin key cut into syllables.
fn replacement_for_engine(entry: Entry) -> Result<Entry, String> {
    let entry = entry.normalized_for_engine();
    validate_entry(&entry)?;
    Ok(entry.with_full_pinyin())
}

/// The host's bounds on an entry, each refusal naming the rule it broke. The reasons are fixed text and never repeat the entry.
fn validate_entry(entry: &Entry) -> Result<(), String> {
    let key_limit = match entry.kind {
        Kind::Pinyin => 512,
        Kind::Wubi => 4,
        Kind::QuickPhrase => 32,
        Kind::English => 64,
    };
    let key_valid = match entry.kind {
        Kind::Pinyin => entry
            .key
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b == b'\'' || b == b' '),
        Kind::Wubi | Kind::QuickPhrase => entry.key.bytes().all(|b| {
            b.is_ascii_lowercase()
                || (matches!(entry.kind, Kind::QuickPhrase) && b.is_ascii_digit())
        }),
        Kind::English => msime_client_core::dictionary::english_code_is_well_formed(&entry.key),
    };
    let value_has_invalid_control = entry.value.chars().any(|character| {
        character.is_control()
            && !(matches!(entry.kind, Kind::QuickPhrase) && matches!(character, '\n' | '\t'))
    });
    let reason = if entry.key.is_empty() || entry.key.len() > key_limit {
        "code is empty or too long"
    } else if !key_valid {
        "code contains characters this dictionary does not accept"
    } else if entry.value.is_empty() || entry.value.len() > 4096 {
        "word is empty or too long"
    } else if value_has_invalid_control {
        "word contains a control character"
    } else if !(1..=100_000_000).contains(&entry.weight) {
        "weight is outside 1 to 100000000"
    } else {
        return Ok(());
    };
    Err(invalid_dictionary_entry(reason))
}

/// Cut a full pinyin key into one syllable per Han character of `value`, the form the Engine stores. `None` when the key is not complete syllables or the counts cannot agree.
fn full_pinyin_key(key: &str, value: &str) -> Option<String> {
    let expected_syllables = value
        .chars()
        .filter(|&character| is_han_character(character))
        .count();
    if !(1..=128).contains(&expected_syllables) {
        return None;
    }
    Some(msime_engine_bridge::normalize_full_pinyin(
        key,
        expected_syllables,
    ))
    .filter(|normalized| !normalized.is_empty())
}

impl From<&Kind> for msime_client_core::dictionary::import::ImportKind {
    fn from(kind: &Kind) -> Self {
        use msime_client_core::dictionary::import::ImportKind;
        match kind {
            Kind::Pinyin => ImportKind::Pinyin,
            Kind::Wubi => ImportKind::Wubi,
            Kind::QuickPhrase => ImportKind::QuickPhrase,
            Kind::English => ImportKind::English,
        }
    }
}

/// Entries ready for the Engine, plus what the shared parser skipped.
type ParsedImport = (
    Vec<DictionaryEntry>,
    msime_client_core::dictionary::import::ImportReport,
);

/// Parse a submitted dictionary file through the shared parser. Unusable rows
/// are skipped and counted there rather than rejecting the whole file, so the
/// report is returned alongside the entries.
fn parse_import(
    kind: &Kind,
    format: &str,
    text: &str,
    engine_options: Option<&msime_engine_bridge::EngineOptions>,
) -> Result<ParsedImport, String> {
    let mut report = msime_client_core::dictionary::import::parse(
        kind.into(),
        format,
        text,
        msime_client_core::cloud::dictionary::MAX_IMPORT_BYTES,
    )
    .map_err(|error| error.to_string())?;
    if matches!(kind, Kind::Pinyin) && engine_options.is_some() {
        let mut usable = Vec::with_capacity(report.entries.len());
        for mut entry in report.entries.drain(..) {
            let Some(normalized) = full_pinyin_key(&entry.key, &entry.value) else {
                report.failed += 1;
                if report.first_failures.len() < 5 {
                    report.first_failures.push(
                        msime_client_core::dictionary::import::ImportFailure {
                            line: entry.line,
                            issue: msime_client_core::dictionary::import::ImportIssue::Pinyin,
                        },
                    );
                }
                continue;
            };
            entry.key = normalized;
            usable.push(entry);
        }
        report.entries = usable;
    }
    let entries = report
        .entries
        .iter()
        .map(|entry| DictionaryEntry {
            kind: (*kind).into(),
            key: entry.key.clone(),
            value: entry.value.clone(),
            weight: entry.weight,
        })
        .collect();
    Ok((entries, report))
}

fn parse_hans_import(
    kind: &Kind,
    text: &str,
    options: &msime_engine_bridge::EngineOptions,
) -> Result<Vec<DictionaryEntry>, String> {
    if !matches!(kind, Kind::Pinyin)
        || text.is_empty()
        || text.len() > msime_client_core::cloud::dictionary::MAX_IMPORT_BYTES
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
        if entries.len() >= 1000 || word.len() > 1024 || !word.chars().all(is_han_character) {
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

    fn import_engine_options() -> msime_engine_bridge::EngineOptions {
        msime_engine_bridge::EngineOptions {
            resources: String::new(),
            user_data: String::new(),
            cache: String::new(),
            dictionaries: String::new(),
            scheme: 0,
            shuangpin_profile: 0,
            shuangpin_preedit_uses_raw: true,
            learning: false,
            autocorrect_transposition: true,
            autocorrect_neighbor: true,
            fuzzy_pinyin_rules: 0,
            wubi_mixed_pinyin: false,
            helpcode: false,
            show_helpcode: true,
            helpcode_schema: "ziranma".into(),
            chinese_punctuation: true,
            paired_punctuation: true,
            punctuation_lock: 0,
            frequency_mode: "promote".into(),
            frequency_trigger_count: 1,
            frequency_linear_step: 1,
            mixed_english: true,
            english_minimum_prefix: 2,
            mixed_emoji: false,
            mixed_kaomoji: false,
            local_unicode: true,
            local_date_time: true,
            local_quick_phrase: true,
            local_emoji: true,
            local_kaomoji: true,
            local_super_jianpin: true,
            local_temporary_english: true,
            local_temporary_japanese: true,
            sentence_alternatives: true,
        }
    }

    #[test]
    fn hans_entries_reject_what_the_import_format_rejects_without_touching_state() {
        let directory = tempfile::tempdir().unwrap();
        let resources = directory.path().to_str().unwrap();
        assert_eq!(
            hans_entries_json("你好", "relative/resources").unwrap_err(),
            "resources path must be absolute"
        );
        for text in ["", "# comment only\n", "hello", "你好\u{0}", "你好\t世界"] {
            assert_eq!(
                hans_entries_json(text, resources).unwrap_err(),
                "invalid dictionary import",
                "{text:?}"
            );
        }
        // No packaged dictionary: nothing to read a reading from, and nothing created in its place.
        assert_eq!(
            hans_entries_json("你好", resources).unwrap_err(),
            "dictionary pinyin unavailable"
        );
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);

        let read = |text: &[u8], resources: &[u8]| -> serde_json::Value {
            let pointer = unsafe {
                msime_client_dictionary_hans_entries(
                    text.as_ptr(),
                    text.len(),
                    resources.as_ptr(),
                    resources.len(),
                )
            };
            let value = unsafe { std::ffi::CStr::from_ptr(pointer) }
                .to_str()
                .unwrap()
                .to_owned();
            unsafe { crate::msime_client_string_free(pointer) };
            serde_json::from_str(&value).unwrap()
        };
        assert_eq!(read(b"\xff", resources.as_bytes())["ok"], false);
        assert_eq!(read("你好".as_bytes(), &[0xff])["ok"], false);
        let null = unsafe {
            msime_client_dictionary_hans_entries(std::ptr::null(), 0, std::ptr::null(), 0)
        };
        let value = unsafe { std::ffi::CStr::from_ptr(null) }
            .to_str()
            .unwrap()
            .to_owned();
        unsafe { crate::msime_client_string_free(null) };
        assert!(value.contains("\"ok\":false"));
    }

    fn pinyin(key: &str, value: &str) -> Entry {
        Entry {
            kind: Kind::Pinyin,
            key: key.into(),
            value: value.into(),
            weight: 10_000,
            source: None,
        }
    }

    #[test]
    fn a_pinyin_search_finds_the_separated_key_without_separators() {
        let stored = pinyin("ni'hao", "你好");
        for query in ["nihao", "nih", "ni hao", "NIHAO", "ni'hao"] {
            assert!(stored.matches(Some(Kind::Pinyin), query), "{query:?}");
            assert!(stored.matches(None, query), "{query:?}");
        }
        assert!(!stored.matches(Some(Kind::Pinyin), "nhao"));
        assert!(!stored.matches(Some(Kind::Wubi), "nihao"));
    }

    #[test]
    fn a_manual_pinyin_entry_is_cut_into_syllables_like_an_imported_one() {
        for typed in ["nihao", "NiHao", "ni hao", "ni'hao"] {
            let entry = replacement_for_engine(pinyin(typed, "你好")).unwrap();
            assert_eq!(entry.key, "ni'hao", "{typed:?}");
            // What this layer hands on is what the Engine accepts.
            msime_engine_bridge::dictionary_validate(&entry.into()).unwrap();
        }
        // The word's length picks the cut, as it does for an imported row.
        assert_eq!(
            replacement_for_engine(pinyin("xian", "西安")).unwrap().key,
            "xi'an"
        );
        assert_eq!(
            replacement_for_engine(pinyin("xian", "先")).unwrap().key,
            "xian"
        );
        // A key that cannot be cut reaches the Engine unchanged, and the Engine names the rule.
        assert_eq!(
            replacement_for_engine(pinyin("nhao", "你好")).unwrap().key,
            "nhao"
        );
    }

    #[test]
    fn a_refused_edit_says_which_rule_it_broke() {
        let directory = tempfile::tempdir().unwrap();
        let root = directory.path().to_str().unwrap();
        let edit = |replacement: Entry| {
            let request = json!({
                "options": {
                    "api_version": 1,
                    "resources": format!("{root}/resources"),
                    "user_data": format!("{root}/user"),
                    "cache": format!("{root}/cache"),
                    "dictionaries": format!("{root}/dictionaries"),
                    "preferences": msime_client_core::preferences::Preferences::default(),
                },
                "action": {
                    "operation": "edit",
                    "previous": null,
                    "replacement": replacement,
                    "request_id": "synthetic-edit",
                },
            });
            dictionary_request_json(&serde_json::to_vec(&request).unwrap()).unwrap_err()
        };
        // Jianpin is not a full reading: the Engine's own reason comes back under the stable prefix the settings page maps to one code, before anything is locked or created.
        let refused = edit(pinyin("nhao", "你好"));
        assert!(
            refused.starts_with("invalid dictionary entry: "),
            "{refused}"
        );
        assert!(!refused.contains("nhao") && !refused.contains("你好"));
        assert_eq!(std::fs::read_dir(directory.path()).unwrap().count(), 0);
        // Too many syllables for the word is the same kind of refusal.
        assert!(edit(pinyin("ni'hao'ma", "你好")).starts_with("invalid dictionary entry: "));
        // The host's own bounds name their rule too.
        let wubi = Entry {
            kind: Kind::Wubi,
            key: "abcde".into(),
            value: "测试".into(),
            weight: 1,
            source: None,
        };
        assert_eq!(
            edit(wubi),
            "invalid dictionary entry: code is empty or too long"
        );
        // `nihao` passes every entry rule; with no dictionary behind these paths it fails later, on storage, not as an invalid entry.
        let accepted = edit(pinyin("nihao", "你好"));
        assert!(
            !accepted.starts_with("invalid dictionary entry"),
            "{accepted}"
        );
    }

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
    fn import_maps_shared_entries_onto_the_requested_engine_kind() {
        // Row semantics are covered exhaustively in
        // client-core::dictionary_import, which is unit-testable without the
        // Engine. This asserts only the mapping this module is responsible for.
        let (standard, report) = parse_import(
            &Kind::Pinyin,
            "standard",
            "你好\tni'hao\t7\n# comment\n西安\txi'an\n",
            None,
        )
        .unwrap();
        assert_eq!(standard.len(), 2);
        assert_eq!(standard[0].value, "你好");
        assert_eq!(standard[0].key, "ni'hao");
        assert_eq!(standard[0].weight, 7);
        assert_eq!(standard[1].weight, 10000);
        assert!(standard
            .iter()
            .all(|entry| entry.kind == Kind::Pinyin.into()));
        assert_eq!(report.failed, 0);
        assert!(!report.truncated);

        let (windows, _) = parse_import(&Kind::Wubi, "windows", "wq\t你好\t9\n", None).unwrap();
        assert_eq!(windows[0].key, "wq");
        assert_eq!(windows[0].value, "你好");
        assert_eq!(windows[0].kind, Kind::Wubi.into());
    }

    #[test]
    fn engine_backed_pinyin_import_resolves_lengths_and_reports_invalid_rows() {
        let options = import_engine_options();
        let (entries, report) = parse_import(
            &Kind::Pinyin,
            "standard",
            "西安\txian\n坏词\tzzzz\n你好\tnihao\n",
            Some(&options),
        )
        .unwrap();

        assert_eq!(
            entries
                .iter()
                .map(|entry| entry.key.as_str())
                .collect::<Vec<_>>(),
            ["xi'an", "ni'hao"]
        );
        assert_eq!(report.failed, 1);
        assert_eq!(report.first_failures[0].line, 2);
        assert_eq!(
            report.first_failures[0].issue,
            msime_client_core::dictionary::import::ImportIssue::Pinyin
        );

        let (wubi, _) =
            parse_import(&Kind::Wubi, "windows", "wq\t你好\t9\n", Some(&options)).unwrap();
        assert_eq!(wubi[0].key, "wq");
    }

    #[test]
    fn personal_import_accepts_the_apple_envelope_and_rejects_duplicates() {
        let text = r#"{
          "format": "msime-personal-dictionary",
          "version": 1,
          "entries": [
            {"kind":"pinyin","key":"ni hao","value":"你好","weight":100000},
            {"kind":"quickPhrase","key":"hello1","value":"你好！","weight":2}
          ]
        }"#;
        let entries = parse_personal_dictionary_import(text).unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(entries[0].key, "ni'hao");
        assert_eq!(entries[1].kind, PersonalWordKind::QuickPhrase);

        let duplicate = text.replace(
            r#"{"kind":"quickPhrase","key":"hello1","value":"你好！","weight":2}"#,
            r#"{"kind":"pinyin","key":"ni hao","value":"你好","weight":3}"#,
        );
        assert_eq!(
            parse_personal_dictionary_import(&duplicate).unwrap_err(),
            "duplicate personal dictionary entry"
        );
    }

    #[test]
    fn personal_import_enforces_file_and_entry_bounds() {
        let empty = r#"{"format":"msime-personal-dictionary","version":1,"entries":[]}"#;
        assert_eq!(
            parse_personal_dictionary_import(empty).unwrap_err(),
            "invalid personal dictionary entry count"
        );
        let malformed = r#"{"format":"msime-personal-dictionary","version":1,"entries":[{"kind":"pinyin","key":"nihao","value":"坏词","weight":1}]}"#;
        assert_eq!(
            parse_personal_dictionary_import(malformed).unwrap_err(),
            "invalid personal dictionary entry"
        );
        assert_eq!(
            parse_personal_dictionary_import(&"x".repeat(1_048_577)).unwrap_err(),
            "personal dictionary file is too large"
        );
    }

    #[test]
    fn personal_import_normalizes_before_deduplicating_and_allows_multiline_quick_phrases() {
        let text = r#"{
            "format":"msime-personal-dictionary",
            "version":1,
            "entries":[
                {"kind":"pinyin","key":"NI HAO","value":"拟好","weight":100000},
                {"kind":"quickPhrase","key":"HELLO1","value":"第一行\n第二行\t末列","weight":100000}
            ]
        }"#;
        let entries = parse_personal_dictionary_import(text).unwrap();
        assert_eq!(entries[0].key, "ni'hao");
        assert_eq!(entries[1].key, "hello1");
        assert_eq!(entries[1].value, "第一行\n第二行\t末列");

        let large = json!({
            "format": "msime-personal-dictionary",
            "version": 1,
            "entries": [{
                "kind": "quickPhrase",
                "key": "large",
                "value": "你好\n".repeat(300),
                "weight": 100_000,
            }],
        })
        .to_string();
        assert_eq!(parse_personal_dictionary_import(&large).unwrap().len(), 1);

        let duplicate = r#"{
            "format":"msime-personal-dictionary",
            "version":1,
            "entries":[
                {"kind":"pinyin","key":"ni hao","value":"你好","weight":1},
                {"kind":"pinyin","key":"NI'HAO","value":"你好","weight":2}
            ]
        }"#;
        assert_eq!(
            parse_personal_dictionary_import(duplicate).unwrap_err(),
            "duplicate personal dictionary entry"
        );
    }

    #[test]
    fn a_single_unusable_row_is_reported_rather_than_failing_the_import() {
        let (entries, report) = parse_import(
            &Kind::Pinyin,
            "standard",
            "你好\tni'hao\n没有制表符\n世界\tshi'jie\n",
            None,
        )
        .unwrap();
        assert_eq!(entries.len(), 2);
        assert_eq!(report.failed, 1);
        assert_eq!(report.first_failures[0].line, 2);
    }

    #[test]
    fn an_unusable_envelope_is_still_rejected_outright() {
        assert!(parse_import(&Kind::Pinyin, "hans", "你好\tni'hao", None).is_err());
        assert!(parse_import(&Kind::Pinyin, "standard", "# only comments\n", None).is_err());
        // Every row unusable means nothing to import.
        assert!(parse_import(&Kind::Wubi, "windows", "abcde\t你好", None).is_err());
    }
}
