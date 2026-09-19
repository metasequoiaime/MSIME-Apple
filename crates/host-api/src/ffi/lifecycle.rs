//! Updating a live session, tearing it down, and freeing what the library returned.
//!
//! Part of the C ABI; see the parent module for what these shims guarantee.

use crate::*;

/// Queue a validated preference snapshot without interrupting composition.
/// # Safety
/// `snapshot` must point to `length` readable bytes for this call. Null is rejected.
#[no_mangle]
pub unsafe extern "C" fn msime_client_update_preferences(
    handle: u64,
    snapshot: *const u8,
    length: usize,
) -> *mut c_char {
    response(|| {
        if snapshot.is_null() || length > 16384 {
            return Err("invalid preferences buffer".into());
        }
        // SAFETY: guaranteed by the caller's buffer contract.
        let bytes = unsafe { std::slice::from_raw_parts(snapshot, length) };
        let snapshot = serde_json::from_slice(bytes).map_err(|_| "invalid preferences document")?;
        with_session(handle, |session| session.update(snapshot))
    })
}

#[no_mangle]
pub extern "C" fn msime_client_destroy(handle: u64) -> *mut c_char {
    response(|| {
        SESSIONS.with(|sessions| {
            sessions
                .try_borrow_mut()
                .map_err(|_| "reentrant host call")?
                .remove(&handle)
                .ok_or("unknown session or wrong thread")?;
            Ok(Value::Null)
        })
    })
}

/// # Safety
/// `value` must be null or an allocation returned by this library, not yet freed.
#[no_mangle]
pub unsafe extern "C" fn msime_client_string_free(value: *mut c_char) {
    if !value.is_null() {
        // SAFETY: ownership is transferred back exactly once by the C caller.
        drop(unsafe { CString::from_raw(value) });
    }
}
