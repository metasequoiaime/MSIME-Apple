//! Network transport boundary for account-backed dictionary operations.

use crate::cloud_dictionary::{DictionaryChange, DictionaryEntry, DictionaryKind, DictionaryValue};
use std::future::Future;

pub struct DictionaryPage {
    pub entries: Vec<DictionaryEntry>,
    pub offset: usize,
    pub has_more: bool,
}
pub enum DictionaryOperation<'a> {
    List {
        kind: DictionaryKind,
        offset: usize,
        search: &'a str,
    },
    Add {
        kind: DictionaryKind,
        value: &'a DictionaryValue,
    },
    Update {
        entry: &'a DictionaryEntry,
        value: &'a DictionaryValue,
    },
    Delete {
        entry: &'a DictionaryEntry,
    },
    Import {
        kind: DictionaryKind,
        format: &'a str,
        text: &'a str,
    },
    Export {
        kind: DictionaryKind,
        format: &'a str,
    },
    Changes {
        after: i64,
        limit: usize,
    },
}
pub enum DictionaryResult {
    Page(DictionaryPage),
    Change(DictionaryChange),
    Export(Vec<u8>),
}

pub trait DictionaryTransport {
    type Error;
    fn execute(
        &self,
        operation: DictionaryOperation<'_>,
    ) -> impl Future<Output = Result<DictionaryResult, Self::Error>> + Send;
}
