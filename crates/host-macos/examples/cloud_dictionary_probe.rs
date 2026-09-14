//! Synthetic cross-process account/export fixture, with no account access.
#[cfg(target_os = "macos")]
fn main() {
    use msime_host_macos::cloud_clipboard::{CloudClipboardError, CloudClipboardSession};
    use std::io::Read;
    let mut ready = [0];
    std::io::stdin().read_exact(&mut ready).unwrap();
    let session = CloudClipboardSession::parse(
        &std::env::var("MSIME_CLIENT_CLOUD_DICTIONARY_SESSION").unwrap(),
    )
    .unwrap();
    assert!(std::env::var("MSIME_CLIENT_CLOUD_CLIPBOARD_SESSION").is_err());
    let listed = session
        .request_dictionary(
            &serde_json::json!({"operation":"list","kind":"pinyin","offset":100,"search":"合成"}),
        )
        .unwrap();
    assert_eq!(listed["offset"], 100);
    let imported = session.request_dictionary(&serde_json::json!({"operation":"import","kind":"pinyin","format":"standard","text":"\t".repeat(65536)})).unwrap();
    assert_eq!(imported["imported"], 1);
    assert_eq!(
        session.request_dictionary(&serde_json::json!({"operation":"update"})),
        Err(CloudClipboardError::Conflict)
    );
    let exported = session
        .request_dictionary(
            &serde_json::json!({"operation":"export","kind":"pinyin","format":"standard"}),
        )
        .unwrap();
    let path = exported["export_file"]["path"].as_str().unwrap();
    let size = exported["export_file"]["bytes"].as_u64().unwrap();
    let text = msime_host_macos::cloud_dictionary::read_export(
        std::path::Path::new(path),
        "dictionary-pinyin.tsv",
        size,
    )
    .unwrap();
    assert_eq!(text, "synthetic\t合成\t100\n".repeat(150_000));
}

#[cfg(not(target_os = "macos"))]
fn main() {}
