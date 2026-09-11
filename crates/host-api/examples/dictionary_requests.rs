//! Native management roundtrip with synthetic entries and isolated writable data.
use msime_host_api::*;
use serde_json::{json, Value};
use std::ffi::{c_char, CStr};

fn read(pointer: *mut c_char) -> Value {
    assert!(!pointer.is_null());
    // SAFETY: every pointer here is an owned host-api response.
    let value = unsafe { serde_json::from_slice(CStr::from_ptr(pointer).to_bytes()).unwrap() };
    unsafe { msime_client_string_free(pointer) };
    value
}
fn request(options: &Value, action: Value) -> Value {
    let bytes = serde_json::to_vec(&json!({ "options": options, "action": action })).unwrap();
    read(unsafe { msime_client_dictionary(bytes.as_ptr(), bytes.len()) })
}
fn create(options: &Value) -> u64 {
    let bytes = serde_json::to_vec(options).unwrap();
    let result = read(unsafe { msime_client_create(bytes.as_ptr(), bytes.len()) });
    assert_eq!(result["ok"], true);
    result["value"]["session"].as_u64().unwrap()
}
fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::path::PathBuf::from(
        std::env::args_os()
            .nth(1)
            .ok_or("usage: dictionary_requests <verified-resources>")?,
    );
    let state = tempfile::tempdir()?;
    let options: Value =
        serde_json::from_str(&prepare_host_configuration(&resources, state.path())?)?;
    let entry =
        json!({ "kind": "quick_phrase", "key": "fixture", "value": "测试短语", "weight": 12345 });
    let add = json!({ "operation": "edit", "previous": null, "replacement": entry, "request_id": "native-add" });
    let list = json!({ "operation": "list", "offset": 0, "limit": 100 });
    let session = create(&options);
    assert_eq!(request(&options, list.clone())["ok"], true);
    assert_eq!(
        request(&options, add.clone())["error"],
        "dictionary maintenance busy"
    );
    read(msime_client_destroy(session));
    assert_eq!(request(&options, add.clone())["value"]["applied"], true);
    assert_eq!(request(&options, add)["value"]["applied"], true);
    assert_eq!(
        request(&options, list.clone())["value"]["entries"],
        json!([entry])
    );
    let session = create(&options);
    read(msime_client_focus(session, true));
    read(msime_client_character(session, b'K', true));
    for byte in b"fixture" {
        read(msime_client_character(session, *byte, false));
    }
    let result = read(msime_client_command(session, 1));
    assert_eq!(result["value"]["commit"], "测试短语");
    read(msime_client_destroy(session));
    let remove = json!({ "operation": "edit", "previous": entry, "replacement": null, "request_id": "native-remove" });
    assert_eq!(request(&options, remove.clone())["ok"], true);
    assert_eq!(request(&options, remove)["ok"], true);
    assert_eq!(request(&options, list)["value"]["entries"], json!([]));
    println!("native list/busy/add/retry/recreate/commit/remove roundtrip passed");
    Ok(())
}
