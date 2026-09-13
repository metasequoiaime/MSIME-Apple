use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case")]
pub enum CloudDictionaryRequest {
    List {
        kind: String,
        offset: usize,
        search: String,
    },
    Catalog {
        kind: String,
        code: String,
        offset: usize,
        scheme: String,
        profile: String,
    },
    Changes {
        after: i64,
        limit: usize,
    },
    Add {
        kind: String,
        code: String,
        word: String,
        weight: i64,
    },
    Update {
        kind: String,
        id: String,
        code: String,
        word: String,
        weight: i64,
        revision: i64,
    },
    EditCatalog {
        kind: String,
        code: String,
        word: String,
        revision: i64,
        replacement: Option<CloudDictionaryValue>,
    },
    Delete {
        kind: String,
        id: String,
        revision: i64,
    },
    Import {
        kind: String,
        format: String,
        text: String,
    },
    Export {
        kind: String,
        format: String,
    },
}

#[derive(Debug, Deserialize)]
pub struct CloudDictionaryValue {
    pub code: String,
    pub word: String,
    pub weight: i64,
}

pub fn validate_cloud_request(request: &CloudDictionaryRequest) -> Result<(), &'static str> {
    let valid_kind = |kind: &str| matches!(kind, "pinyin" | "wubi" | "quick" | "english");
    let valid_value = |kind: &str, code: &str, word: &str, weight: i64| {
        let code_alphabet_ok = match kind {
            "quick" => code.bytes().all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()),
            "wubi" => code.bytes().all(|b| b.is_ascii_lowercase()),
            "english" => code.bytes().all(|b| b.is_ascii_alphabetic()),
            _ => code.bytes().all(|b| b.is_ascii_lowercase() || b == b'\'' || b == b' '),
        };
        code_alphabet_ok
            && !code.is_empty()
            && code.len() <= match kind { "wubi" => 4, "quick" => 32, "english" => 64, _ => 256 }
            && !code.chars().any(char::is_control)
            && !word.is_empty()
            && word.len() <= 1024
            && !word.chars().any(char::is_control)
            && weight >= 0
            && (kind != "quick" || word.encode_utf16().count() <= 199)
    };
    let valid_id = |id: &str| {
        id.len() == 64
            && id
                .bytes()
                .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
    };
    let valid_format = |kind: &str, format: &str| {
        matches!(format, "standard" | "windows") || (kind == "pinyin" && format == "hans")
    };
    match request {
        CloudDictionaryRequest::List {
            kind,
            offset,
            search,
        } => {
            if valid_kind(kind)
                && *offset <= 1_000_000
                && search.len() <= 1024
                && !search.chars().any(char::is_control)
            {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Catalog {
            kind,
            code,
            offset,
            scheme,
            profile,
        } => {
            if valid_kind(kind)
                && *offset <= 1_000_000
                && code.len() <= 256
                && !code.contains('\0')
                && !scheme.is_empty()
                && scheme.len() <= 64
                && !profile.is_empty()
                && profile.len() <= 64
                && !scheme.chars().any(char::is_control)
                && !profile.chars().any(char::is_control)
            {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Changes { after, limit } => {
            if *after >= 0 && (1..=100).contains(limit) {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Add {
            kind,
            code,
            word,
            weight,
        } => {
            if valid_kind(kind) && valid_value(kind, code, word, *weight) {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Update {
            kind,
            id,
            code,
            word,
            weight,
            revision,
        } => {
            if valid_kind(kind) && valid_id(id) && valid_value(kind, code, word, *weight) && *revision > 0
            {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Delete { kind, id, revision } => {
            if valid_kind(kind) && valid_id(id) && *revision > 0 {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::EditCatalog {
            kind,
            code,
            word,
            revision,
            replacement,
        } => {
            let identity_ok = valid_kind(kind)
                && !code.is_empty()
                && code.len() <= 256
                && !code.chars().any(char::is_control)
                && !word.is_empty()
                && word.len() <= 1024
                && !word.chars().any(char::is_control)
                && *revision >= 0;
            let replacement_ok = replacement.as_ref().is_none_or(|value| {
                valid_value(kind, &value.code, &value.word, value.weight)
            });
            if identity_ok && replacement_ok {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Import { kind, format, text } => {
            if valid_kind(kind)
                && valid_format(kind, format)
                && !text.is_empty()
                && text.len() <= msime_client_core::cloud_dictionary::MAX_IMPORT_BYTES
                && !text.contains('\0')
                && text.chars().all(|character| {
                    !character.is_control() || matches!(character, '\n' | '\r' | '\t')
                })
            {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
        CloudDictionaryRequest::Export { kind, format } => {
            if valid_kind(kind) && matches!(format.as_str(), "standard" | "windows") {
                Ok(())
            } else {
                Err("invalid cloud dictionary request")
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_dictionary_values_and_entry_identity() {
        assert!(validate_cloud_request(&CloudDictionaryRequest::Add {
            kind: "pinyin".into(),
            code: "ni".into(),
            word: "你".into(),
            weight: 100,
        })
        .is_ok());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Add {
            kind: "pinyin".into(),
            code: "".into(),
            word: "你".into(),
            weight: 100,
        })
        .is_err());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Delete {
            kind: "pinyin".into(),
            id: "a".repeat(64),
            revision: 2,
        })
        .is_ok());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Delete {
            kind: "pinyin".into(),
            id: "bad".into(),
            revision: 2,
        })
        .is_err());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Delete {
            kind: "pinyin".into(),
            id: "A".repeat(64),
            revision: 2,
        })
        .is_err());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Catalog {
            kind: "pinyin".into(),
            code: "nihc".into(),
            offset: 0,
            scheme: "shuangpin".into(),
            profile: "xiaohe".into(),
        })
        .is_ok());
        assert!(validate_cloud_request(&CloudDictionaryRequest::EditCatalog {
            kind: "pinyin".into(),
            code: "ni".into(),
            word: "你".into(),
            revision: 42,
            replacement: None,
        })
        .is_ok());
        assert!(validate_cloud_request(&CloudDictionaryRequest::EditCatalog {
            kind: "pinyin".into(),
            code: "ni".into(),
            word: "你".into(),
            revision: 42,
            replacement: Some(CloudDictionaryValue {
                code: "ni".into(),
                word: "你".into(),
                weight: 1,
            }),
        })
        .is_ok());
    }

    #[test]
    fn enforces_quick_phrase_utf16_limit() {
        let valid = "界".repeat(199);
        let invalid = "界".repeat(200);
        let request = |word| CloudDictionaryRequest::Add { kind: "quick".into(), code: "k".into(), word, weight: 1 };
        assert!(validate_cloud_request(&request(valid)).is_ok());
        assert!(validate_cloud_request(&request(invalid)).is_err());
    }

    #[test]
    fn rejects_invalid_quick_phrase_code_alphabet() {
        let request = |code| CloudDictionaryRequest::Add { kind: "quick".into(), code, word: "短语".into(), weight: 1 };
        assert!(validate_cloud_request(&request("k2".into())).is_ok());
        assert!(validate_cloud_request(&request("K2".into())).is_err());
        assert!(validate_cloud_request(&request("k-2".into())).is_err());
    }

    #[test]
    fn validates_import_and_export_formats() {
        assert!(validate_cloud_request(&CloudDictionaryRequest::Import {
            kind: "pinyin".into(),
            format: "hans".into(),
            text: "你好".into(),
        })
        .is_ok());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Import {
            kind: "wubi".into(),
            format: "hans".into(),
            text: "你好".into(),
        })
        .is_err());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Import {
            kind: "pinyin".into(),
            format: "standard".into(),
            text: "bad\u{0007}".into(),
        })
        .is_err());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Export {
            kind: "english".into(),
            format: "windows".into(),
        })
        .is_ok());
        assert!(validate_cloud_request(&CloudDictionaryRequest::Export {
            kind: "english".into(),
            format: "hans".into(),
        })
        .is_err());
    }
}
