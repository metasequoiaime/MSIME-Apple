//! macOS platform operations for shared clients; no desktop or Engine dependency.
use msime_client_core::panels::KeyboardInputRequest;
#[cfg(target_os = "macos")]
pub mod cloud_clipboard;
#[cfg(target_os = "macos")]
pub mod cloud_dictionary;
#[cfg(target_os = "macos")]
pub mod panel_session;

/// Keeps WebKit detached while a desktop adapter changes a window's class.
/// Main-thread-only; dropping restores the view and its window observations.
#[cfg(target_os = "macos")]
pub struct DetachedWindowContent {
    token: usize,
    _main_thread: std::marker::PhantomData<std::rc::Rc<()>>,
}

#[cfg(target_os = "macos")]
pub fn detach_window_content(window_address: usize) -> Option<DetachedWindowContent> {
    unsafe extern "C" {
        fn msime_macos_detach_window_content(address: usize) -> usize;
    }
    // SAFETY: native code resolves this address against NSApp's live windows;
    // arbitrary caller addresses are never dereferenced.
    let token = unsafe { msime_macos_detach_window_content(window_address) };
    (token != 0).then_some(DetachedWindowContent {
        token,
        _main_thread: std::marker::PhantomData,
    })
}

#[cfg(target_os = "macos")]
impl Drop for DetachedWindowContent {
    fn drop(&mut self) {
        unsafe extern "C" {
            fn msime_macos_restore_window_content(token: usize);
        }
        // SAFETY: private, uniquely-owned native token; !Send keeps drop on main.
        unsafe { msime_macos_restore_window_content(self.token) };
    }
}

/// A process identity pinned by PID and launch time. The same identity is used
/// for startup focus restoration and for non-activating panel key delivery.
#[cfg(target_os = "macos")]
#[derive(Clone, Copy, Debug)]
pub struct LaunchTarget {
    pid: i32,
    launched: f64,
}

#[cfg(target_os = "macos")]
pub fn capture_launch_target() -> Option<LaunchTarget> {
    unsafe extern "C" {
        fn msime_macos_capture_launch_target(launched: *mut f64) -> i32;
    }
    let mut launched = 0.0;
    // SAFETY: native code writes one double to this valid local output pointer.
    let pid = unsafe { msime_macos_capture_launch_target(&mut launched) };
    (pid > 0 && launched > 0.0).then_some(LaunchTarget { pid, launched })
}

/// Undo only this shell's startup activation; never take focus from a third app.
#[cfg(target_os = "macos")]
pub fn restore_launch_target(target: LaunchTarget) -> bool {
    unsafe extern "C" {
        fn msime_macos_restore_launch_target(pid: i32, launched: f64) -> bool;
    }
    // SAFETY: scalar ABI; native side validates thread, process identity and focus.
    unsafe { msime_macos_restore_launch_target(target.pid, target.launched) }
}

/// Post a keyboard stroke to the application captured before a non-activating
/// panel was shown. The launch time is checked again in native code so a
/// recycled PID can never receive input intended for the old application.
#[cfg(target_os = "macos")]
pub fn send_keyboard_key_to_target(request: &KeyboardInputRequest, target: &LaunchTarget) -> bool {
    let Some(stroke) = keyboard_stroke(request) else {
        return false;
    };
    unsafe extern "C" {
        fn msime_macos_send_keyboard_key_to_target(
            pid: i32,
            launched: f64,
            code: u16,
            flags: u64,
        ) -> bool;
    }
    // SAFETY: scalar ABI; native code validates the target identity, main
    // thread, Accessibility permission and event allocation before posting.
    unsafe {
        msime_macos_send_keyboard_key_to_target(
            target.pid,
            target.launched,
            stroke.code,
            stroke.flags,
        )
    }
}

/// Enumerate input-capable CoreAudio devices using their stable UIDs. The
/// callback runs synchronously on the caller's thread and never opens a
/// device, so this is safe to use from a Tauri blocking task.
#[cfg(target_os = "macos")]
pub fn voice_capture_devices() -> Vec<(String, String)> {
    use std::ffi::{c_char, c_void, CStr};

    extern "C" fn collect(
        uid: *const c_char,
        name: *const c_char,
        _is_default: bool,
        context: *mut c_void,
    ) {
        if uid.is_null() || name.is_null() || context.is_null() {
            return;
        }
        let (uid, name) = unsafe { (CStr::from_ptr(uid), CStr::from_ptr(name)) };
        let (Ok(uid), Ok(name)) = (uid.to_str(), name.to_str()) else {
            return;
        };
        if uid.is_empty()
            || name.is_empty()
            || uid.len() > 512
            || name.len() > 512
            || uid.chars().any(char::is_control)
            || name.chars().any(char::is_control)
        {
            return;
        }
        // SAFETY: the native enumerator invokes this callback synchronously
        // with the exact Vec pointer passed below and never stores it.
        let devices = unsafe { &mut *(context.cast::<Vec<(String, String)>>()) };
        devices.push((uid.to_owned(), name.to_owned()));
    }

    unsafe extern "C" {
        fn msime_macos_list_voice_capture_devices(
            callback: extern "C" fn(*const c_char, *const c_char, bool, *mut c_void),
            context: *mut c_void,
        );
    }

    let mut devices = Vec::new();
    // SAFETY: `collect` has the ABI and lifetime required by the native
    // callback; the context points to a live Vec for the duration of the call.
    unsafe {
        msime_macos_list_voice_capture_devices(
            collect,
            (&mut devices as *mut Vec<(String, String)>).cast::<c_void>(),
        );
    }
    devices
}

#[cfg(target_os = "macos")]
pub fn uninstall_input_source(
    bundle: &std::path::Path,
    user_data: &std::path::Path,
    remove_user_data: bool,
) -> Result<(), &'static str> {
    use std::ffi::CString;
    let home = std::env::var_os("HOME").ok_or("home unavailable")?;
    if !std::path::PathBuf::from(&home).is_absolute()
        || !bundle.is_absolute()
        || !user_data.is_absolute()
    {
        return Err("invalid uninstall path");
    }
    let bundle =
        CString::new(bundle.to_string_lossy().as_bytes()).map_err(|_| "invalid uninstall path")?;
    let user_data = CString::new(user_data.to_string_lossy().as_bytes())
        .map_err(|_| "invalid uninstall path")?;
    let domain = CString::new("app.msime.client.preview.inputmethod").unwrap();
    unsafe extern "C" {
        fn msime_macos_uninstall_input_source(
            bundle: *const std::ffi::c_char,
            user_data: *const std::ffi::c_char,
            preferences_domain: *const std::ffi::c_char,
            remove_user_data: bool,
        ) -> bool;
    }
    let ok = unsafe {
        msime_macos_uninstall_input_source(
            bundle.as_ptr(),
            user_data.as_ptr(),
            domain.as_ptr(),
            remove_user_data,
        )
    };
    ok.then_some(()).ok_or("uninstall failed")
}

/// Ask the separate IMK process to release active dictionary sessions before a
/// settings process takes the exclusive maintenance lock.  The notification
/// carries no input, credentials, or paths.
#[cfg(target_os = "macos")]
pub fn quiesce_input_sessions() {
    unsafe extern "C" {
        fn msime_macos_quiesce_input_sessions();
    }
    // SAFETY: the native function has no arguments and retains no state.
    unsafe { msime_macos_quiesce_input_sessions() };
}

/// Read the account session shared with the Swift backend Keychain store.
#[cfg(target_os = "macos")]
pub fn account_load() -> Result<Option<Vec<u8>>, &'static str> {
    let mut bytes = vec![0_u8; 1024 * 1024];
    let mut length = 0_usize;
    unsafe extern "C" {
        fn msime_macos_account_load(buffer: *mut u8, capacity: usize, length: *mut usize) -> i32;
    }
    let status = unsafe { msime_macos_account_load(bytes.as_mut_ptr(), bytes.len(), &mut length) };
    if status < 0 || length > bytes.len() {
        return Err("account keychain unavailable");
    }
    Ok((status == 1).then(|| {
        bytes.truncate(length);
        bytes
    }))
}

#[cfg(target_os = "macos")]
pub fn account_save(bytes: &[u8]) -> Result<(), &'static str> {
    if bytes.is_empty() || bytes.len() > 1024 * 1024 {
        return Err("account session too large");
    }
    unsafe extern "C" {
        fn msime_macos_account_save(bytes: *const u8, length: usize) -> bool;
    }
    unsafe { msime_macos_account_save(bytes.as_ptr(), bytes.len()) }
        .then_some(())
        .ok_or("account keychain unavailable")
}

#[cfg(target_os = "macos")]
pub fn account_clear() -> Result<(), &'static str> {
    unsafe extern "C" {
        fn msime_macos_account_clear() -> bool;
    }
    unsafe { msime_macos_account_clear() }
        .then_some(())
        .ok_or("account keychain unavailable")
}

#[cfg(not(target_os = "macos"))]
pub fn account_load() -> Result<Option<Vec<u8>>, &'static str> {
    Ok(None)
}

#[cfg(not(target_os = "macos"))]
pub fn account_save(_: &[u8]) -> Result<(), &'static str> {
    Err("account unavailable")
}

#[cfg(not(target_os = "macos"))]
pub fn account_clear() -> Result<(), &'static str> {
    Err("account unavailable")
}

#[cfg(not(target_os = "macos"))]
pub fn quiesce_input_sessions() {}

#[cfg(not(target_os = "macos"))]
pub fn uninstall_input_source(
    _: &std::path::Path,
    _: &std::path::Path,
    _: bool,
) -> Result<(), &'static str> {
    Err("uninstall unavailable")
}

#[cfg(not(target_os = "macos"))]
pub fn voice_capture_devices() -> Vec<(String, String)> {
    Vec::new()
}

#[cfg(target_os = "macos")]
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ClipboardSnapshot {
    pub change_count: i64,
    pub text: Option<String>,
}

#[cfg(target_os = "macos")]
pub fn clipboard_snapshot(include_text: bool) -> Option<ClipboardSnapshot> {
    let mut bytes = vec![0_u8; msime_client_core::clipboard::MAX_TEXT_BYTES];
    let mut length = 0_usize;
    let mut has_text = false;
    let mut change_count = 0_i64;
    unsafe extern "C" {
        fn msime_macos_read_clipboard(
            buffer: *mut u8,
            capacity: usize,
            read_text: bool,
            length: *mut usize,
            has_text: *mut bool,
            change_count: *mut i64,
        ) -> bool;
    }
    // SAFETY: the native function fills only the provided bounded buffer and
    // scalar outputs, and never retains any pointer after returning.
    let available = unsafe {
        msime_macos_read_clipboard(
            bytes.as_mut_ptr(),
            bytes.len(),
            include_text,
            &mut length,
            &mut has_text,
            &mut change_count,
        )
    };
    if !available || length > bytes.len() {
        return None;
    }
    let text = has_text
        .then(|| String::from_utf8(bytes[..length].to_vec()).ok())
        .flatten();
    Some(ClipboardSnapshot { change_count, text })
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyStroke {
    pub code: u16,
    /// CoreGraphics Shift, Control, Option, Command flags.
    pub flags: u64,
}

/// Translate the shared virtual-key contract to macOS ANSI hardware codes.
/// Unknown PC-only keys fail closed instead of accidentally typing another key.
pub fn keyboard_stroke(request: &KeyboardInputRequest) -> Option<KeyStroke> {
    request.validate().ok()?;
    let code = match request.virtual_key {
        0x41 => 0,
        0x53 => 1,
        0x44 => 2,
        0x46 => 3,
        0x48 => 4,
        0x47 => 5,
        0x5a => 6,
        0x58 => 7,
        0x43 => 8,
        0x56 => 9,
        0x42 => 11,
        0x51 => 12,
        0x57 => 13,
        0x45 => 14,
        0x52 => 15,
        0x59 => 16,
        0x54 => 17,
        0x31 => 18,
        0x32 => 19,
        0x33 => 20,
        0x34 => 21,
        0x36 => 22,
        0x35 => 23,
        0xbb => 24,
        0x39 => 25,
        0x37 => 26,
        0xbd => 27,
        0x38 => 28,
        0x30 => 29,
        0xdd => 30,
        0x4f => 31,
        0x55 => 32,
        0xdb => 33,
        0x49 => 34,
        0x50 => 35,
        0x0d => 36,
        0x4c => 37,
        0x4a => 38,
        0xde => 39,
        0x4b => 40,
        0xba => 41,
        0xdc => 42,
        0xbc => 43,
        0xbf => 44,
        0x4e => 45,
        0x4d => 46,
        0xbe => 47,
        0x09 => 48,
        0x20 => 49,
        0xc0 => 50,
        0x08 => 51,
        0x1b => 53,
        0x6e => 65,
        0x6a => 67,
        0x6b => 69,
        0x90 => 71,
        0x6f => 75,
        0x6d => 78,
        0x60 => 82,
        0x61 => 83,
        0x62 => 84,
        0x63 => 85,
        0x64 => 86,
        0x65 => 87,
        0x66 => 88,
        0x67 => 89,
        0x68 => 91,
        0x69 => 92,
        0x74 => 96,
        0x75 => 97,
        0x76 => 98,
        0x72 => 99,
        0x77 => 100,
        0x78 => 101,
        0x7a => 103,
        0x79 => 109,
        0x7b => 111,
        0x24 => 115,
        0x21 => 116,
        0x2e => 117,
        0x73 => 118,
        0x23 => 119,
        0x71 => 120,
        0x22 => 121,
        0x70 => 122,
        0x25 => 123,
        0x27 => 124,
        0x28 => 125,
        0x26 => 126,
        _ => return None,
    };
    let sticky = request.include_sticky_modifiers;
    let flags = (u64::from(sticky && request.shift) << 17)
        | (u64::from(sticky && request.modifiers.ctrl) << 18)
        | (u64::from(sticky && request.modifiers.alt) << 19)
        | (u64::from(sticky && request.modifiers.win) << 20);
    Some(KeyStroke { code, flags })
}

/// Must be called on the AppKit main thread. No permission prompt or focus change.
#[cfg(target_os = "macos")]
pub fn send_keyboard_key(request: &KeyboardInputRequest) -> bool {
    let Some(stroke) = keyboard_stroke(request) else {
        return false;
    };
    unsafe extern "C" {
        fn msime_macos_send_keyboard_key(code: u16, flags: u64) -> bool;
    }
    // SAFETY: scalar-only ABI. Native code checks main thread, permissions,
    // external foreground ownership and event allocation before posting.
    unsafe { msime_macos_send_keyboard_key(stroke.code, stroke.flags) }
}

#[cfg(test)]
mod tests {
    use super::*;
    use msime_client_core::panels::KeyboardModifiers;

    fn request(key: u16) -> KeyboardInputRequest {
        KeyboardInputRequest {
            virtual_key: key,
            shift: true,
            modifiers: KeyboardModifiers {
                ctrl: true,
                alt: true,
                win: true,
            },
            include_sticky_modifiers: true,
        }
    }

    #[test]
    fn ansi_letters_digits_punctuation_and_navigation_are_mapped() {
        for (key, code) in [
            (0x41, 0),
            (0x5a, 6),
            (0x30, 29),
            (0x31, 18),
            (0xba, 41),
            (0xde, 39),
            (0xdc, 42),
            (0x08, 51),
            (0x2e, 117),
            (0x0d, 36),
            (0x09, 48),
            (0x25, 123),
            (0x26, 126),
            (0x70, 122),
            (0x7b, 111),
            (0x90, 71),
            (0x69, 92),
        ] {
            assert_eq!(keyboard_stroke(&request(key)).unwrap().code, code);
        }
        for key in b'A'..=b'Z' {
            assert!(keyboard_stroke(&request(key.into())).is_some());
        }
        for key in 0x60..=0x69 {
            assert!(keyboard_stroke(&request(key)).is_some());
        }
        for key in 0x70..=0x7b {
            assert!(keyboard_stroke(&request(key)).is_some());
        }
    }

    #[test]
    fn modifiers_map_to_command_option_and_commit_keys_drop_sticky_state() {
        let mut key = request(0x41);
        assert_eq!(keyboard_stroke(&key).unwrap().flags, 0x1e0000);
        key.include_sticky_modifiers = false;
        assert_eq!(keyboard_stroke(&key).unwrap().flags, 0);
        key.include_sticky_modifiers = true;
        key.shift = false;
        key.modifiers.ctrl = false;
        key.modifiers.alt = false;
        assert_eq!(keyboard_stroke(&key).unwrap().flags, 1 << 20);
    }

    #[test]
    fn unsupported_pc_keys_and_invalid_contract_values_are_rejected() {
        for key in [0, 0x100, 0xffff, 0x2c, 0x91, 0x13, 0x2d] {
            assert!(keyboard_stroke(&request(key)).is_none());
        }
    }
}
