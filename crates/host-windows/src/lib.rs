//! Windows host capabilities for the shared panels.
//!
//! The desktop shell hosts the shared React panels and forbids unsafe code, so
//! the Win32 calls those panels need are wrapped here: remembering the window
//! that owned the caret, injecting synthetic input into it, placing a panel on
//! the work area and opening a directory in the shell.
//!
//! Nothing here reads input, credentials or user text; callers pass the text
//! the panel already holds.

#![cfg(windows)]

use std::path::Path;

/// The window that owned the caret before a panel appeared. Panels never take
/// focus, so a click still has to reach this window rather than the panel.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct InputTarget(isize);

/// Longest text a panel may inject in one call, matching the shared contract.
pub const MAX_TEXT_BYTES: usize = 4096;

/// Modifier keys a panel asks to be held while its key is pressed.
#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Modifiers {
    pub shift: bool,
    pub ctrl: bool,
    pub alt: bool,
    pub win: bool,
}

/// Work area in physical pixels, as `(left, top, right, bottom)`.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct WorkArea {
    pub left: f64,
    pub top: f64,
    pub right: f64,
    pub bottom: f64,
}

impl WorkArea {
    /// Bottom-centered placement for a panel of this size, where the native
    /// panels sat. Oversized panels stay pinned to the work area origin.
    pub fn bottom_center(&self, width: f64, height: f64) -> (f64, f64) {
        let available = self.right - self.left;
        let x = self.left + ((available - width) / 2.0).max(0.0);
        let y = (self.bottom - height - 12.0).max(self.top);
        (x, y)
    }
}

/// The foreground window, or `None` when the desktop has no active window.
pub fn foreground_window() -> Option<InputTarget> {
    use windows_sys::Win32::UI::WindowsAndMessaging::GetForegroundWindow;
    // SAFETY: querying the foreground window has no preconditions.
    let window = unsafe { GetForegroundWindow() };
    (!window.is_null()).then_some(InputTarget(window as isize))
}

/// Bring the remembered window forward so synthetic input reaches it. Fails
/// when the window closed while the panel was open.
pub fn focus(target: InputTarget) -> bool {
    use windows_sys::Win32::Foundation::HWND;
    use windows_sys::Win32::UI::WindowsAndMessaging::{IsWindow, SetForegroundWindow};
    let window = target.0 as HWND;
    // SAFETY: both calls validate the handle themselves.
    unsafe { IsWindow(window) != 0 && SetForegroundWindow(window) != 0 }
}

/// Is the foreground window a usable destination for synthetic input?
///
/// The panels are `WS_EX_NOACTIVATE`, so the foreground really is whatever the
/// user last clicked, and the reference deliberately never calls
/// SetForegroundWindow: it just sends to whatever is in front. The only case to
/// refuse is the foreground belonging to this process, which would make the
/// panel type into itself.
pub fn foreground_is_external() -> bool {
    use windows_sys::Win32::System::Threading::GetCurrentProcessId;
    use windows_sys::Win32::UI::WindowsAndMessaging::{
        GetForegroundWindow, GetWindowThreadProcessId,
    };
    // SAFETY: all three calls validate their arguments themselves.
    unsafe {
        let window = GetForegroundWindow();
        if window.is_null() {
            return false;
        }
        let mut process = 0u32;
        GetWindowThreadProcessId(window, &mut process);
        process != 0 && process != GetCurrentProcessId()
    }
}

/// Keys that must carry `KEYEVENTF_EXTENDEDKEY`.
///
/// Without the flag these arrive as their numeric-keypad twins: the arrow
/// cluster becomes 2/4/6/8, Home/End/PgUp/PgDn/Ins/Del become 7/1/9/3/0/., and
/// applications that read scan codes rather than virtual keys see the wrong
/// key entirely. The ported React layout exposes all of them, so this matters
/// more here than it did upstream.
fn extended_key(virtual_key: u16) -> bool {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
        VK_APPS, VK_DELETE, VK_DIVIDE, VK_DOWN, VK_END, VK_HOME, VK_INSERT, VK_LEFT,
        VK_LWIN, VK_NEXT, VK_NUMLOCK, VK_PRIOR, VK_RCONTROL, VK_RIGHT, VK_RMENU,
        VK_RWIN, VK_UP,
    };
    matches!(
        virtual_key,
        VK_DELETE | VK_LWIN | VK_RWIN | VK_RMENU | VK_RCONTROL | VK_INSERT
            | VK_HOME | VK_END | VK_PRIOR | VK_NEXT | VK_LEFT | VK_RIGHT | VK_UP
            | VK_DOWN | VK_NUMLOCK | VK_DIVIDE | VK_APPS
    )
}

fn key_input(
    virtual_key: u16,
    release: bool,
) -> windows_sys::Win32::UI::Input::KeyboardAndMouse::INPUT {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
        MapVirtualKeyW, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT,
        KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, MAPVK_VK_TO_VSC,
    };
    let mut flags = if release { KEYEVENTF_KEYUP } else { 0 };
    if extended_key(virtual_key) {
        flags |= KEYEVENTF_EXTENDEDKEY;
    }
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: virtual_key,
                // Applications that read the scan code instead of the virtual
                // key saw 0 for every synthetic stroke.
                wScan: unsafe { MapVirtualKeyW(virtual_key as u32, MAPVK_VK_TO_VSC) } as u16,
                dwFlags: flags,
                time: 0,
                dwExtraInfo: unsafe {
                    windows_sys::Win32::UI::WindowsAndMessaging::GetMessageExtraInfo() as usize
                },
            },
        },
    }
}

fn unicode_input(
    unit: u16,
    release: bool,
) -> windows_sys::Win32::UI::Input::KeyboardAndMouse::INPUT {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{
        INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYEVENTF_KEYUP, KEYEVENTF_UNICODE,
    };
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT {
                wVk: 0,
                wScan: unit,
                dwFlags: KEYEVENTF_UNICODE | if release { KEYEVENTF_KEYUP } else { 0 },
                time: 0,
                dwExtraInfo: 0,
            },
        },
    }
}

fn send(inputs: &[windows_sys::Win32::UI::Input::KeyboardAndMouse::INPUT]) -> bool {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{SendInput, INPUT};
    if inputs.is_empty() {
        return false;
    }
    // SAFETY: the pointer and length describe the slice above, and the size
    // argument is the structure the API expects.
    let sent = unsafe {
        SendInput(
            inputs.len() as u32,
            inputs.as_ptr(),
            std::mem::size_of::<INPUT>() as i32,
        )
    };
    sent as usize == inputs.len()
}

/// Press and release one key with the requested modifiers held around it.
/// The whole sequence is submitted at once so nothing else interleaves.
pub fn send_key(virtual_key: u16, modifiers: Modifiers) -> bool {
    use windows_sys::Win32::UI::Input::KeyboardAndMouse::{VK_CONTROL, VK_LWIN, VK_MENU, VK_SHIFT};
    if virtual_key == 0 {
        return false;
    }
    let mut held: Vec<u16> = Vec::new();
    if modifiers.ctrl {
        held.push(VK_CONTROL);
    }
    if modifiers.alt {
        held.push(VK_MENU);
    }
    if modifiers.win {
        held.push(VK_LWIN);
    }
    if modifiers.shift {
        held.push(VK_SHIFT);
    }
    let mut inputs = Vec::with_capacity(held.len() * 2 + 2);
    for modifier in &held {
        inputs.push(key_input(*modifier, false));
    }
    inputs.push(key_input(virtual_key, false));
    inputs.push(key_input(virtual_key, true));
    for modifier in held.iter().rev() {
        inputs.push(key_input(*modifier, true));
    }
    send(&inputs)
}

/// Type text the panel already holds. Surrogate pairs are delivered as the two
/// code units the receiving control expects.
pub fn send_text(text: &str) -> bool {
    if text.is_empty() || text.len() > MAX_TEXT_BYTES {
        return false;
    }
    let mut inputs = Vec::new();
    for unit in text.encode_utf16() {
        inputs.push(unicode_input(unit, false));
        inputs.push(unicode_input(unit, true));
    }
    send(&inputs)
}

/// The primary work area, excluding the taskbar.
pub fn work_area() -> Option<WorkArea> {
    use windows_sys::Win32::Foundation::RECT;
    use windows_sys::Win32::UI::WindowsAndMessaging::{SystemParametersInfoW, SPI_GETWORKAREA};
    let mut rect = RECT {
        left: 0,
        top: 0,
        right: 0,
        bottom: 0,
    };
    // SAFETY: the call writes the work area into the caller-owned rectangle.
    let read =
        unsafe { SystemParametersInfoW(SPI_GETWORKAREA, 0, (&mut rect as *mut RECT).cast(), 0) };
    if read == 0 || rect.right <= rect.left || rect.bottom <= rect.top {
        return None;
    }
    Some(WorkArea {
        left: f64::from(rect.left),
        top: f64::from(rect.top),
        right: f64::from(rect.right),
        bottom: f64::from(rect.bottom),
    })
}

/// Reveal an existing directory in the shell. The caller owns the path; a
/// missing or relative path is refused rather than handed to the shell.
pub fn open_directory(path: &Path) -> bool {
    use windows_sys::Win32::System::Com::{
        CoInitializeEx, CoUninitialize, COINIT_APARTMENTTHREADED,
    };
    use windows_sys::Win32::UI::Shell::ShellExecuteW;
    use windows_sys::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
    if !path.is_absolute() || !path.is_dir() {
        return false;
    }
    let mut target: Vec<u16> = path.as_os_str().encode_wide().collect();
    target.push(0);
    let mut operation: Vec<u16> = "open".encode_utf16().collect();
    operation.push(0);
    // SAFETY: the apartment is released below, including on the failure path.
    let entered = unsafe { CoInitializeEx(std::ptr::null(), COINIT_APARTMENTTHREADED as u32) };
    // SAFETY: both strings are NUL terminated and outlive the call.
    let result = unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            operation.as_ptr(),
            target.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            SW_SHOWNORMAL,
        )
    };
    if entered >= 0 {
        // SAFETY: balances the successful initialization above.
        unsafe { CoUninitialize() };
    }
    // ShellExecuteW reports success with a value above the legacy error range.
    result as isize > 32
}

use std::os::windows::ffi::OsStrExt;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn placement_centers_on_the_work_area_and_clamps_oversized_panels() {
        let area = WorkArea {
            left: 0.0,
            top: 0.0,
            right: 1920.0,
            bottom: 1040.0,
        };
        assert_eq!(area.bottom_center(1100.0, 400.0), (410.0, 628.0));
        // A panel taller or wider than the work area stays at its origin.
        assert_eq!(area.bottom_center(3000.0, 2000.0), (0.0, 0.0));
        let offset = WorkArea {
            left: -1920.0,
            top: -100.0,
            right: 0.0,
            bottom: 980.0,
        };
        assert_eq!(offset.bottom_center(1100.0, 400.0), (-1510.0, 568.0));
    }

    #[test]
    fn text_injection_refuses_empty_and_oversized_input() {
        assert!(!send_text(""));
        assert!(!send_text(&"a".repeat(MAX_TEXT_BYTES + 1)));
    }

    #[test]
    fn key_injection_refuses_an_unset_virtual_key() {
        assert!(!send_key(0, Modifiers::default()));
    }

    #[test]
    fn directories_must_be_absolute_and_exist() {
        assert!(!open_directory(Path::new("relative")));
        assert!(!open_directory(Path::new(
            "C:\\definitely-missing-msime-path"
        )));
    }

    #[test]
    fn extended_keys_cover_the_cluster_the_panel_exposes() {
        use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
        // Without KEYEVENTF_EXTENDEDKEY these arrive as their numeric-keypad
        // twins: the arrows become 2/4/6/8 and Home/End/PgUp/PgDn/Ins/Del
        // become 7/1/9/3/0/. - so the panel would type digits.
        for key in [
            VK_LEFT, VK_RIGHT, VK_UP, VK_DOWN, VK_HOME, VK_END, VK_PRIOR,
            VK_NEXT, VK_INSERT, VK_DELETE, VK_APPS, VK_NUMLOCK, VK_DIVIDE,
            VK_LWIN, VK_RWIN, VK_RMENU, VK_RCONTROL,
        ] {
            assert!(extended_key(key), "{key} should be extended");
        }
        // Ordinary keys must not carry the flag, or they would be misread the
        // other way round.
        for key in [
            VK_SPACE, VK_RETURN, VK_BACK, VK_TAB, VK_SHIFT, VK_LCONTROL,
            VK_LMENU, VK_NUMPAD0, VK_NUMPAD9, VK_MULTIPLY, VK_ADD,
            VK_SUBTRACT, VK_DECIMAL, VK_CAPITAL,
        ] {
            assert!(!extended_key(key), "{key} should not be extended");
        }
    }

    #[test]
    fn a_synthetic_stroke_carries_a_scan_code() {
        use windows_sys::Win32::UI::Input::KeyboardAndMouse::*;
        // Applications that read the scan code rather than the virtual key saw
        // zero for every synthetic stroke.
        let down = key_input(VK_SPACE, false);
        let ki = unsafe { down.Anonymous.ki };
        assert_ne!(ki.wScan, 0);
        assert_eq!(ki.wVk, VK_SPACE);
        assert_eq!(ki.dwFlags & KEYEVENTF_KEYUP, 0);
        assert_eq!(ki.dwFlags & KEYEVENTF_EXTENDEDKEY, 0);

        let up = key_input(VK_SPACE, true);
        assert_ne!(unsafe { up.Anonymous.ki }.dwFlags & KEYEVENTF_KEYUP, 0);

        // An extended key carries both the flag and a scan code, and keeps the
        // flag on release - a Win key released without it stays stuck down.
        let left = key_input(VK_LEFT, false);
        let left_ki = unsafe { left.Anonymous.ki };
        assert_ne!(left_ki.dwFlags & KEYEVENTF_EXTENDEDKEY, 0);
        assert_ne!(left_ki.wScan, 0);
        let left_up = unsafe { key_input(VK_LEFT, true).Anonymous.ki };
        assert_ne!(left_up.dwFlags & KEYEVENTF_EXTENDEDKEY, 0);
        assert_ne!(left_up.dwFlags & KEYEVENTF_KEYUP, 0);
    }
}
