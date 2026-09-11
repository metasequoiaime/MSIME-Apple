use serde::Deserialize;

#[derive(Debug, Deserialize)]
#[serde(tag = "operation", rename_all = "snake_case")]
pub enum CloudDictionaryRequest {
    List { kind: String, offset: usize, search: String },
    Changes { after: i64, limit: usize },
    Add { kind: String, code: String, word: String, weight: i64 },
    Update { kind: String, id: String, code: String, word: String, weight: i64, revision: i64 },
    Delete { kind: String, id: String, revision: i64 },
    Import { kind: String, format: String, text: String },
    Export { kind: String, format: String },
}

pub fn validate_cloud_request(request: &CloudDictionaryRequest) -> Result<(), &'static str> {
    let valid_kind = |kind: &str| matches!(kind, "pinyin" | "wubi" | "quick" | "english");
    match request {
        CloudDictionaryRequest::List { kind, offset, search } => if valid_kind(kind) && *offset <= 1_000_000 && search.len() <= 1024 && !search.chars().any(char::is_control) { Ok(()) } else { Err("invalid cloud dictionary request") },
        CloudDictionaryRequest::Changes { after, limit } => if *after >= 0 && (1..=100).contains(limit) { Ok(()) } else { Err("invalid cloud dictionary request") },
        CloudDictionaryRequest::Add { kind, .. } | CloudDictionaryRequest::Import { kind, .. } | CloudDictionaryRequest::Export { kind, .. } => if valid_kind(kind) { Ok(()) } else { Err("invalid cloud dictionary request") },
        CloudDictionaryRequest::Update { kind, revision, .. } | CloudDictionaryRequest::Delete { kind, revision, .. } => if valid_kind(kind) && *revision > 0 { Ok(()) } else { Err("invalid cloud dictionary request") },
    }
}
