//! Safe, host-independent contract for the Windows cloud-candidate service.

use serde_json::Value;

const MAX_INPUT: usize = 256;
const MAX_RESPONSE: usize = 256 * 1024;
const MAX_CANDIDATE: usize = 512;

pub fn build_google_url(input: &str, japanese: bool) -> Option<String> {
    if input.is_empty() || input.len() > MAX_INPUT || input.chars().any(|c| c.is_control()) {
        return None;
    }
    let scheme = if japanese {
        "ja-t-i0-und"
    } else {
        "zh-t-i0-pinyin"
    };
    Some(format!(
        "https://inputtools.google.com/request?text={}&itc={scheme}&num=1&ie=utf-8&oe=utf-8",
        urlencoding(input)
    ))
}

pub fn parse_google_response(response: &[u8]) -> Option<String> {
    if response.len() > MAX_RESPONSE {
        return None;
    }
    let root: Value = serde_json::from_slice(response).ok()?;
    if root.get(0)?.as_str()? != "SUCCESS" {
        return None;
    }
    let candidate = root.get(1)?.get(0)?.get(1)?.get(0)?.as_str()?;
    let candidate = candidate.trim();
    if candidate.is_empty()
        || candidate.len() > MAX_CANDIDATE
        || candidate.chars().any(|c| c.is_control())
    {
        return None;
    }
    Some(candidate.to_owned())
}

fn urlencoding(input: &str) -> String {
    const HEX: &[u8; 16] = b"0123456789ABCDEF";
    let mut out = String::with_capacity(input.len());
    for byte in input.bytes() {
        if byte.is_ascii_alphanumeric() || matches!(byte, b'-' | b'_' | b'.' | b'~') {
            out.push(byte as char);
        } else {
            out.push('%');
            out.push(HEX[(byte >> 4) as usize] as char);
            out.push(HEX[(byte & 15) as usize] as char);
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn url_and_parse_match_google_contract() {
        assert_eq!(build_google_url("ni hao", false).unwrap(), "https://inputtools.google.com/request?text=ni%20hao&itc=zh-t-i0-pinyin&num=1&ie=utf-8&oe=utf-8");
        let response = serde_json::json!(["SUCCESS", [["ni hao", ["你好", "你号"]]]]).to_string();
        assert_eq!(
            parse_google_response(response.as_bytes()),
            Some("你好".into())
        );
    }
    #[test]
    fn rejects_unsafe_input_and_response() {
        assert!(build_google_url("bad\n", false).is_none());
        assert!(parse_google_response(br#"["ERROR",[]]"#).is_none());
    }
}
