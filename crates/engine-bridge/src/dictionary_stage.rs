use crate::{ffi, DictionaryKind, EngineOptions};

/// Complete durable dictionary state, distinct from a page of user-inserted entries.
#[derive(Clone)]
pub enum DictionaryStateRecord {
    Entry {
        kind: DictionaryKind,
        key: String,
        value: String,
        weight: i64,
        display: String,
        deleted: bool,
        user_inserted: bool,
    },
    Position {
        context: String,
        key: String,
        value: String,
        position: i64,
    },
    Selection {
        context: String,
        key: String,
        value: String,
        count: i64,
    },
}

/// Sanitized transport failure (including cancellation, truncation and bad checksum).
#[derive(Debug, thiserror::Error)]
#[error("Snapshot record stream failed")]
pub struct SnapshotReadError;

pub(crate) struct DictionaryRecordStream {
    records: Box<dyn Iterator<Item = Result<DictionaryStateRecord, SnapshotReadError>>>,
}

impl DictionaryRecordStream {
    pub(crate) fn next(&mut self) -> Result<ffi::DictionaryStateWire, SnapshotReadError> {
        let mut out = ffi::DictionaryStateWire {
            record_type: 0,
            kind: DictionaryKind::Pinyin,
            context: String::new(),
            key: String::new(),
            value: String::new(),
            number: 0,
            display: String::new(),
            deleted: false,
            user_inserted: false,
        };
        let Some(record) = self.records.next() else {
            return Ok(out);
        };
        match record? {
            DictionaryStateRecord::Entry {
                kind,
                key,
                value,
                weight,
                display,
                deleted,
                user_inserted,
            } => {
                out.record_type = 1;
                out.kind = kind;
                out.key = key;
                out.value = value;
                out.number = weight;
                out.display = display;
                out.deleted = deleted;
                out.user_inserted = user_inserted;
            }
            DictionaryStateRecord::Position {
                context,
                key,
                value,
                position,
            } => {
                out.record_type = 2;
                out.context = context;
                out.key = key;
                out.value = value;
                out.number = position;
            }
            DictionaryStateRecord::Selection {
                context,
                key,
                value,
                count,
            } => {
                out.record_type = 3;
                out.context = context;
                out.key = key;
                out.value = value;
                out.number = count;
            }
        }
        Ok(out)
    }
}

/// Rebuild a complete replacement in a new, exclusively created directory.
///
/// The iterator must return `None` only after verifying the transport envelope,
/// count and checksum, and return `Err` on cancellation or malformed input. It
/// must not panic. Records are consumed incrementally, not collected in memory.
/// `maximum_records` is a nonzero, caller-validated transport limit.
///
/// The caller must verify immutable resources before this call. Engine validates
/// paths, record constraints and duplicate identities, and removes only its newly
/// created generation on failure. Existing generations are never overwritten.
/// Returned options preserve input settings but target the new journal/cache and
/// rebuilt dictionaries. Nothing is activated: the host still owns lease/CAS,
/// session quiescence, publication, and inactive-generation cleanup.
pub fn stage_dictionary_state(
    options: &EngineOptions,
    generation: &str,
    content_id: &str,
    maximum_records: usize,
    records: impl Iterator<Item = Result<DictionaryStateRecord, SnapshotReadError>> + 'static,
) -> Result<EngineOptions, cxx::Exception> {
    let mut stream = DictionaryRecordStream {
        records: Box::new(records),
    };
    ffi::stage_dictionary_state(
        options,
        generation,
        content_id,
        maximum_records,
        &mut stream,
    )
}

#[cfg(test)]
mod tests;
