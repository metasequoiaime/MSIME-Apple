//! Parsing and validation helpers for DeepLX-compatible custom translation services.

use serde_json::Value;
use hmac::{Hmac, Mac};
use sha2::Sha256;
use std::io::Read;
use std::time::{Duration, Instant};

const MAX_RESPONSE_BYTES: usize = 1024 * 1024;
const REQUEST_TIMEOUT: Duration = Duration::from_millis(2500);
const BATCH_BUDGET: Duration = Duration::from_secs(6);

/// Tencent TC3 signing primitive. The caller owns credential lifetime.
pub fn tencent_tc3_derive(secret_key: &str, date: &str, service: &str, message: &str) -> String {
    type HmacSha256 = Hmac<Sha256>;
    let sign = |key: &[u8], data: &str| -> Vec<u8> {
        let mut mac = HmacSha256::new_from_slice(key).expect("HMAC accepts arbitrary keys");
        mac.update(data.as_bytes());
        mac.finalize().into_bytes().to_vec()
    };
    let date_key = sign(format!("TC3{secret_key}").as_bytes(), date);
    let service_key = sign(&date_key, service);
    let signing_key = sign(&service_key, "tc3_request");
    hex::encode(sign(&signing_key, message))
}

#[derive(Clone, PartialEq, Eq)]
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
        .connect_timeout(REQUEST_TIMEOUT)
        .timeout(REQUEST_TIMEOUT)
        .redirect(reqwest::redirect::Policy::none())
        .build()
    {
        Ok(client) => client,
        Err(_) => return results,
    };
    let started = Instant::now();
    for (index, text) in texts.iter().enumerate() {
        let timeout = request_timeout(started.elapsed());
        if timeout.is_zero() {
            break;
        }
        let mut request = client
            .post(&config.endpoint)
            .timeout(timeout)
            .json(&serde_json::json!({
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
        results[index] = read_translation_response(response);
    }
    results
}

fn request_timeout(elapsed: Duration) -> Duration {
    BATCH_BUDGET.saturating_sub(elapsed).min(REQUEST_TIMEOUT)
}

fn read_translation_response(reader: impl Read) -> Option<String> {
    let mut body = Vec::new();
    reader
        .take((MAX_RESPONSE_BYTES + 1) as u64)
        .read_to_end(&mut body)
        .ok()?;
    if body.len() > MAX_RESPONSE_BYTES {
        return None;
    }
    parse_translation_response(std::str::from_utf8(&body).ok()?)
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
    fn response_limit_is_enforced_while_reading() {
        struct Endless {
            read: usize,
        }
        impl Read for Endless {
            fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
                buffer.fill(b' ');
                self.read += buffer.len();
                Ok(buffer.len())
            }
        }
        let mut endless = Endless { read: 0 };
        assert!(read_translation_response(&mut endless).is_none());
        assert_eq!(endless.read, MAX_RESPONSE_BYTES + 1);
        let mut boundary = br#"{"data":"synthetic"}"#.to_vec();
        boundary.resize(MAX_RESPONSE_BYTES, b' ');
        assert_eq!(
            read_translation_response(boundary.as_slice()).as_deref(),
            Some("synthetic")
        );
        boundary.push(b' ');
        assert!(read_translation_response(boundary.as_slice()).is_none());
        assert!(read_translation_response(&b"\xff"[..]).is_none());
    }

    #[test]
    fn request_timeout_respects_remaining_batch_budget() {
        assert_eq!(request_timeout(Duration::ZERO), REQUEST_TIMEOUT);
        assert_eq!(
            request_timeout(Duration::from_millis(5500)),
            Duration::from_millis(500)
        );
        assert_eq!(request_timeout(BATCH_BUDGET), Duration::ZERO);
        assert_eq!(request_timeout(Duration::from_secs(7)), Duration::ZERO);
    }

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
        use std::io::{BufRead, BufReader, Write};
        use std::net::TcpListener;
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let server = std::thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            stream
                .set_read_timeout(Some(Duration::from_secs(3)))
                .unwrap();
            let mut reader = BufReader::new(&mut stream);
            let mut request = String::new();
            let mut content_length = None;
            loop {
                let mut line = String::new();
                assert_ne!(reader.read_line(&mut line).unwrap(), 0);
                if line == "\r\n" {
                    break;
                }
                if let Some(value) = line.to_ascii_lowercase().strip_prefix("content-length:") {
                    content_length = Some(value.trim().parse::<usize>().unwrap());
                }
                request.push_str(&line);
            }
            let mut body = vec![0; content_length.unwrap()];
            reader.read_exact(&mut body).unwrap();
            request.push_str(std::str::from_utf8(&body).unwrap());
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
