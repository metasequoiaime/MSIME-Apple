//! macOS platform operations for shared clients; no desktop or Engine dependency.
use msime_client_core::panels::KeyboardInputRequest;
#[cfg(target_os = "macos")]
pub mod panel_session;
#[cfg(target_os = "macos")]
pub mod cloud_clipboard;
#[cfg(target_os = "macos")]
pub mod cloud_dictionary;

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

/// A launch-only identity, never a cached destination for future key strokes.
#[cfg(target_os = "macos")]
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
