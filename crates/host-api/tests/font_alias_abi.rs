// Integration tests and examples are their own crates, so the exemption the
// library root carries does not reach them. Same boundary, same reason: this
// target drives the C ABI directly.
#![allow(unsafe_code)]
use msime_host_api::{msime_client_resolve_font_families, msime_client_string_free};
use std::ffi::{c_char, CStr};

unsafe fn take_response(pointer: *mut c_char) -> serde_json::Value {
    assert!(!pointer.is_null());
    // SAFETY: owned NUL-terminated response returned by this library.
    let bytes = unsafe { CStr::from_ptr(pointer) }.to_bytes().to_vec();
    unsafe { msime_client_string_free(pointer) };
    serde_json::from_slice(&bytes).unwrap()
}

#[test]
fn boundary_rejects_invalid_buffers_and_documents() {
    // SAFETY: null is explicitly rejected without dereference.
    let null = unsafe { take_response(msime_client_resolve_font_families(std::ptr::null(), 0)) };
    assert_eq!(null["ok"], false);
    for request in [
        b"{}".as_slice(),
        b"null",
        b"[1]",
        b"[\"\"]",
        b"[\"bad\\u0000name\"]",
        &[0xff],
    ] {
        // SAFETY: request remains alive over the synchronous call.
        let result = unsafe {
            take_response(msime_client_resolve_font_families(
                request.as_ptr(),
                request.len(),
            ))
        };
        assert_eq!(result["ok"], false);
        assert_eq!(result["error"], "font_family");
    }
    let oversized = vec![b' '; 32 * 1024 + 1];
    let result = unsafe {
        take_response(msime_client_resolve_font_families(
            oversized.as_ptr(),
            oversized.len(),
        ))
    };
    assert_eq!(result["ok"], false);
}

#[test]
fn empty_list_roundtrips_and_response_is_owned() {
    let request = b"[]";
    let result = unsafe {
        take_response(msime_client_resolve_font_families(
            request.as_ptr(),
            request.len(),
        ))
    };
    assert_eq!(result, serde_json::json!({"ok": true, "value": []}));
}

#[cfg(not(windows))]
#[test]
fn non_windows_abi_preserves_names() {
    let names = serde_json::json!(["Synthetic W03", "示例字体"]);
    let request = serde_json::to_vec(&names).unwrap();
    let result = unsafe {
        take_response(msime_client_resolve_font_families(
            request.as_ptr(),
            request.len(),
        ))
    };
    assert_eq!(result["value"], names);
}
