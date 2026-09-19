//! Safe wrappers for Swift-owned iOS bridge exports.
//!
//! Swift exposes the two functions below with `@_cdecl`. The Tauri command
//! crate must not carry raw pointers or `unsafe extern` declarations, so this
//! package owns the narrow boundary and returns an owned byte buffer.

#[cfg(target_os = "ios")]
use std::ffi::{c_char, CStr};

#[cfg(target_os = "ios")]
pub fn personal_dictionary_request(request: &[u8]) -> Option<Vec<u8>> {
    call(
        request,
        msime_ios_personal_dictionary_request,
        msime_ios_personal_dictionary_string_free,
    )
}

#[cfg(not(target_os = "ios"))]
pub fn personal_dictionary_request(_request: &[u8]) -> Option<Vec<u8>> {
    None
}

#[cfg(target_os = "ios")]
pub fn dictionary_snapshot_request(request: &[u8]) -> Option<Vec<u8>> {
    call(
        request,
        msime_ios_dictionary_snapshot_request,
        msime_ios_dictionary_snapshot_string_free,
    )
}

#[cfg(not(target_os = "ios"))]
pub fn dictionary_snapshot_request(_request: &[u8]) -> Option<Vec<u8>> {
    None
}

#[cfg(target_os = "ios")]
fn call(
    request: &[u8],
    invoke: unsafe extern "C" fn(*const u8, usize) -> *mut c_char,
    release: unsafe extern "C" fn(*mut c_char),
) -> Option<Vec<u8>> {
    // The Swift exports return a malloc-owned, NUL-terminated UTF-8 string.
    // Copy it before releasing the allocation so callers never observe a raw
    // pointer or borrow memory owned by the native bridge.
    let pointer = unsafe { invoke(request.as_ptr(), request.len()) };
    if pointer.is_null() {
        return None;
    }
    let response = unsafe { CStr::from_ptr(pointer) }.to_bytes().to_vec();
    unsafe { release(pointer) };
    Some(response)
}

#[cfg(target_os = "ios")]
unsafe extern "C" {
    fn msime_ios_personal_dictionary_request(request: *const u8, length: usize) -> *mut c_char;
    fn msime_ios_personal_dictionary_string_free(value: *mut c_char);
    fn msime_ios_dictionary_snapshot_request(request: *const u8, length: usize) -> *mut c_char;
    fn msime_ios_dictionary_snapshot_string_free(value: *mut c_char);
}
