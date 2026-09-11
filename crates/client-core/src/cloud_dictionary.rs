//! Host-independent validation and data contracts for account-backed dictionaries.
//! Network and credentials remain injected by the platform host.

use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum DictionaryKind {
    Pinyin,
    Wubi,
    Quick,
    English,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DictionaryValue {
    pub code: String,
    pub word: String,
    pub weight: i64,
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
pub struct DictionaryEntry {
    pub id: String,
    pub kind: DictionaryKind,
    pub value: DictionaryValue,
    pub revision: i64,
}

pub const MAX_IMPORT_BYTES: usize = 64 * 1024;

pub fn validate_value(value: &DictionaryValue) -> Result<(), &'static str> {
    if value.code.is_empty()
        || value.code.len() > 256
        || value.word.is_empty()
        || value.word.len() > 1024
    {
        return Err("invalid dictionary value");
    }
    if value.code.contains('\0')
        || value.word.contains('\0')
        || value.code.chars().any(char::is_control)
        || value.word.chars().any(char::is_control)
    {
        return Err("invalid dictionary value");
    }
    if value.weight < 0 {
        return Err("invalid dictionary weight");
    }
    Ok(())
}

pub fn validate_import(text: &str) -> Result<(), &'static str> {
    if text.is_empty()
        || text.len() > MAX_IMPORT_BYTES
        || text.contains('\0')
        || text
            .chars()
            .any(|c| c.is_control() && !matches!(c, '\n' | '\r' | '\t'))
    {
        return Err("invalid dictionary import");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_dictionary_values() {
        let value = DictionaryValue {
            code: "nihao".into(),
            word: "你好".into(),
            weight: 100,
        };
        assert!(validate_value(&value).is_ok());
        assert!(validate_value(&DictionaryValue {
            weight: -1,
            ..value.clone()
        })
        .is_err());
        assert!(validate_value(&DictionaryValue {
            code: "".into(),
            ..value
        })
        .is_err());
    }

    #[test]
    fn validates_bounded_import_text() {
        assert!(validate_import("你好\tnihao\n").is_ok());
        assert!(validate_import("bad\0").is_err());
        assert!(validate_import(&"x".repeat(MAX_IMPORT_BYTES + 1)).is_err());
    }
}
