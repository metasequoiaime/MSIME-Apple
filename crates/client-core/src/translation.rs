//! Parsing and validation helpers for DeepLX-compatible custom translation services.

use serde_json::Value;
use std::time::{Duration, Instant};

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TranslationConfig {
    pub endpoint: String,
    pub api_key: String,
}

pub fn translate_batch(
    config: &TranslationConfig,
    texts: &[String],
    source: &str,
    target: &str,
) -> Vec<Option<String>> {
    let mut results = vec![None; texts.len()];
    if texts.is_empty()
        || source.is_empty()
        || target.is_empty()
        || !is_supported_endpoint(&config.endpoint)
    {
        return results;
    }
    let client = match reqwest::blocking::Client::builder()
        .connect_timeout(Duration::from_millis(2500))
        .timeout(Duration::from_millis(2500))
        .build()
    {
        Ok(client) => client,
        Err(_) => return results,
    };
    let started = Instant::now();
    for (index, text) in texts.iter().enumerate() {
        if started.elapsed() >= Duration::from_secs(6) {
            break;
        }
        let mut request = client.post(&config.endpoint).json(&serde_json::json!({
            "text": text,
            "source_lang": source.to_ascii_uppercase(),
            "target_lang": target.to_ascii_uppercase(),
        }));
        if !config.api_key.is_empty() {
            request = request.bearer_auth(&config.api_key);
        }
        let response = match request.send() {
            Ok(response) if response.status().is_success() => response,
            _ => continue,
        };
        let body = match response.bytes() {
            Ok(body) if body.len() <= 1024 * 1024 => body,
            _ => continue,
        };
        results[index] = parse_translation_response(std::str::from_utf8(&body).unwrap_or_default());
    }
    results
}

pub fn is_supported_endpoint(endpoint: &str) -> bool {
    !endpoint.is_empty()
        && endpoint.len() <= 2048
        && !endpoint.chars().any(char::is_control)
        && (endpoint.starts_with("https://") || endpoint.starts_with("http://"))
}

pub fn parse_translation_response(response: &str) -> Option<String> {
    let root: Value = serde_json::from_str(response).ok()?;
    if let Some(code) = root.get("code") {
        let valid = code.as_i64() == Some(200) || code.as_str() == Some("200");
        if !valid {
            return None;
        }
    }
    for key in ["data", "translation", "result"] {
        if let Some(value) = root.get(key) {
            if let Some(text) = value_as_text(value) {
                return Some(text);
            }
            if let Some(first) = value.as_array().and_then(|items| items.first()) {
                if let Some(text) = value_as_text(first) {
                    return Some(text);
                }
            }
        }
    }
    root.get("translations")
        .and_then(Value::as_array)
        .and_then(|items| items.first())
        .and_then(value_as_text)
}

fn value_as_text(value: &Value) -> Option<String> {
    value.as_str().map(str::to_owned).or_else(|| {
        value.as_object().and_then(|object| {
            ["text", "translation", "data"]
                .iter()
                .find_map(|key| object.get(*key).and_then(Value::as_str).map(str::to_owned))
        })
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn accepts_supported_endpoints_only() {
        assert!(is_supported_endpoint("https://translate.example/api"));
        assert!(is_supported_endpoint("http://localhost:8080/translate"));
        assert!(!is_supported_endpoint("ftp://translate.example"));
        assert!(!is_supported_endpoint("https://bad\n.example"));
    }

    #[test]
    fn parses_supported_response_shapes() {
        assert_eq!(
            parse_translation_response(r#"{"data":"hello"}"#).as_deref(),
            Some("hello")
        );
        assert_eq!(
            parse_translation_response(r#"{"translation":{"text":"hello"}}"#).as_deref(),
            Some("hello")
        );
        assert_eq!(
            parse_translation_response(r#"{"translations":[{"translation":"hello"}]}"#).as_deref(),
            Some("hello")
        );
        assert!(parse_translation_response(r#"{"code":500,"data":"nope"}"#).is_none());
    }

    #[test]
    fn translates_batch_with_deeplx_contract() {
        use std::io::{Read, Write};
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut buffer = [0_u8; 4096];
            let size = stream.read(&mut buffer).unwrap();
            let request = String::from_utf8_lossy(&buffer[..size]);
            assert!(request
                .to_ascii_lowercase()
                .contains("authorization: bearer test-key"));
            assert!(request.contains("source_lang\":\"EN\""));
            let body = r#"{"data":"你好"}"#;
            write!(
                stream,
                "HTTP/1.1 200 OK\r\nContent-Length: {}\r\n\r\n{}",
                body.len(),
                body
            )
            .unwrap();
        });
        let config = TranslationConfig {
            endpoint: format!("http://{address}"),
            api_key: "test-key".into(),
        };
        let result = translate_batch(&config, &["hello".into()], "en", "zh");
        server.join().unwrap();
        assert_eq!(result, vec![Some("你好".into())]);
    }
}
