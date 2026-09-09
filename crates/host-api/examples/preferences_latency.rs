//! Isolated real-resource preference replacement probe, not a system latency benchmark.
use msime_host_api::*;
use serde_json::{json, Value};
use std::ffi::{c_char, CString};
use std::time::Instant;

fn read(pointer: *mut c_char) -> Value {
    // SAFETY: each fresh owned host response is consumed exactly once.
    let response = unsafe { CString::from_raw(pointer) };
    let value: Value = serde_json::from_slice(response.as_bytes()).unwrap();
    assert_eq!(value["ok"], true);
    value["value"].clone()
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let resources = std::env::args_os()
        .nth(1)
        .ok_or("usage: preferences_latency <verified-resources>")?;
    let state = tempfile::tempdir()?;
    let resources = std::fs::canonicalize(resources)?;
    let request = json!({"resources": resources, "state_root": state.path()}).to_string();
    let options =
        read(unsafe { msime_client_prepare_host(request.as_ptr(), request.len()) }).to_string();
    let started = Instant::now();
    let created = read(unsafe { msime_client_create(options.as_ptr(), options.len()) });
    let create_ms = started.elapsed().as_secs_f64() * 1000.0;
    let handle = created["session"].as_u64().unwrap();
    read(msime_client_focus(handle, true));
    let snapshot = json!({"format_version":1,"revision":1,"preferences":{"scheme":"quanpin","candidate_page_size":2,"learning":false,"chinese_punctuation":false}}).to_string();
    let started = Instant::now();
    let updated =
        read(unsafe { msime_client_update_preferences(handle, snapshot.as_ptr(), snapshot.len()) });
    let update_ms = started.elapsed().as_secs_f64() * 1000.0;
    assert_eq!(updated["deferred"], false);
    assert_eq!(updated["view"]["session"], handle);
    for byte in b"nihao" {
        read(msime_client_character(handle, *byte, false));
    }
    assert_eq!(
        read(msime_client_view(handle))["candidates"]
            .as_array()
            .unwrap()
            .len(),
        2
    );
    assert!(!read(msime_client_command(handle, 9))["commit"]
        .as_str()
        .unwrap()
        .is_empty());
    assert_eq!(
        read(msime_client_character(handle, b',', false))["handled"],
        false
    );
    read(msime_client_destroy(handle));
    println!("isolated real-resource probe: create={create_ms:.2}ms update={update_ms:.2}ms; changed page size and punctuation verified");
    Ok(())
}
