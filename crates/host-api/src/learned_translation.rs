//! Bounded worker-thread operations on the private learned-gloss store.
use msime_client_core::translation_store::{
    GlossDirection, GlossStoreError, TranslationGlossStore,
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::path::Path;

#[derive(Deserialize, PartialEq)]
#[serde(rename_all = "snake_case")]
enum Action {
    Lookup,
    Remember,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Item {
    text: String,
    direction: GlossDirection,
    translation: Option<String>,
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Request {
    directory: String,
    target_language: String,
    generation: u64,
    action: Action,
    items: Vec<Item>,
}

pub fn execute(bytes: &[u8]) -> Result<Value, &'static str> {
    let request: Request =
        serde_json::from_slice(bytes).map_err(|_| "invalid learned translation request")?;
    let directory = Path::new(&request.directory);
    if request.directory.len() > 4096
        || request.directory.chars().any(char::is_control)
        || !directory.is_absolute()
        || directory.parent().is_none()
        || !["en", "fr", "ja", "es", "ru", "de", "ko"].contains(&request.target_language.as_str())
        || request.items.len() > 9
        || request.items.iter().any(|item| {
            item.text.is_empty()
                || item.text.len() > 160
                || item.text.chars().count() > 40
                || item.text.chars().any(char::is_control)
                || match request.action {
                    Action::Lookup => item.translation.is_some(),
                    Action::Remember => item.translation.as_ref().is_none_or(|s| s.len() > 4096),
                }
        })
    {
        return Err("invalid learned translation parameters");
    }
    let store = TranslationGlossStore::new(directory);
    let mut translations = Vec::new();
    let mut saved = 0;
    for item in request.items {
        match request.action {
            Action::Lookup => {
                match store.lookup(&request.target_language, item.direction, &item.text) {
                    Ok(Some(translation)) => {
                        translations.push(json!({"text":item.text,"translation":translation}))
                    }
                    Ok(None) | Err(GlossStoreError::InvalidRecord) => {}
                    Err(_) => return Err("learned translation storage unavailable"),
                }
            }
            Action::Remember => {
                // Entire batch shape was validated before any disk changes.
                saved += usize::from(
                    store
                        .remember(
                            &request.target_language,
                            item.direction,
                            &item.text,
                            item.translation.as_deref().unwrap_or_default(),
                        )
                        .map_err(|_| "learned translation storage unavailable")?,
                );
            }
        }
    }
    Ok(json!({"generation":request.generation,"translations":translations,"saved":saved}))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn request(root: &Path, action: &str, items: Value) -> Value {
        json!({"directory":root,"action":action,"generation":17,"target_language":"en","items":items})
    }
    fn run(value: &Value) -> Result<Value, &'static str> {
        execute(&serde_json::to_vec(value).unwrap())
    }
    #[test]
    fn roundtrip_both_directions_and_target_gate() {
        let root = tempfile::tempdir().unwrap();
        let write = request(
            root.path(),
            "remember",
            json!([
            {"text":"Hello","direction":"english_to_chinese","translation":"你好"},
            {"text":"测试","direction":"chinese_to_english","translation":"test"}]),
        );
        assert_eq!(run(&write).unwrap()["saved"], 2);
        let mut read = request(
            root.path(),
            "lookup",
            json!([
            {"text":"HELLO","direction":"english_to_chinese"},
            {"text":"测试","direction":"chinese_to_english"}]),
        );
        assert_eq!(
            run(&read).unwrap(),
            json!({"generation":17,"saved":0,"translations":[
            {"text":"HELLO","translation":"你好"},{"text":"测试","translation":"test"}]})
        );
        read["target_language"] = json!("fr");
        assert_eq!(run(&read).unwrap()["translations"], json!([]));
    }
    #[test]
    fn malformed_batch_never_partially_writes() {
        let root = tempfile::tempdir().unwrap();
        let valid = request(
            root.path(),
            "remember",
            json!([
            {"text":"Hello","direction":"english_to_chinese","translation":"你好"}]),
        );
        for (field, value) in [
            ("directory", json!("relative")),
            ("target_language", json!("invalid")),
            ("action", json!("invalid")),
            ("generation", json!(-1)),
        ] {
            let mut bad = valid.clone();
            bad[field] = value;
            assert!(run(&bad).is_err());
        }
        let mut bad = valid.clone();
        bad["items"]
            .as_array_mut()
            .unwrap()
            .push(json!({"text":"world","direction":"english_to_chinese"}));
        assert!(run(&bad).is_err());
        bad["items"] = json!(vec![valid["items"][0].clone(); 10]);
        assert!(run(&bad).is_err());
        assert!(!root.path().join("learned-translations-v1").exists());
    }
}
