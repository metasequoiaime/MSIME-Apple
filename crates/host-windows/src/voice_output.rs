//! Native output only; voice policy and recognition belong to the caller.

use super::{InputTarget, MAX_TEXT_BYTES};
#[path = "paste_policy.rs"]
mod paste_policy;
use windows_sys::Win32::Foundation::GlobalFree;
use windows_sys::Win32::System::DataExchange::{
    CloseClipboard, EmptyClipboard, GetClipboardSequenceNumber, OpenClipboard, SetClipboardData,
};
use windows_sys::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
use windows_sys::Win32::System::Threading::GetCurrentProcessId;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DestroyWindow, GetForegroundWindow, GetWindowThreadProcessId, HWND_MESSAGE,
};

/// Restore an external editor, never a window owned by this panel process.
pub fn focus_external(target: InputTarget) -> bool {
    let mut process = 0;
    // SAFETY: the API validates the HWND and writes to a live local variable.
    unsafe {
        GetWindowThreadProcessId(target.0 as _, &mut process);
        if process == 0 || process == GetCurrentProcessId() {
            return false;
        }
    }
    // SAFETY: reading the foreground handle has no preconditions.
    super::focus(target) && unsafe { GetForegroundWindow() == target.0 as _ }
}

/// Copy bounded text and paste it into the remembered external editor.
/// Clipboard failure never sends Ctrl+V with unrelated existing contents.
/// History uses its shared UTF-8 byte budget, not the smaller SendInput budget.
pub fn paste_text(target: InputTarget, text: &str) -> bool {
    paste_text_with_limit(target, text, msime_client_core::clipboard::MAX_TEXT_BYTES)
}

fn paste_text_with_limit(target: InputTarget, text: &str, max_bytes: usize) -> bool {
    if !paste_policy::valid_paste_text(text, max_bytes) {
        return false;
    }
    if !focus_external(target) {
        return false;
    }
    let Some(sequence) = write_unicode_clipboard(text) else {
        return false;
    };
    std::thread::sleep(std::time::Duration::from_millis(30));
    // SAFETY: the sequence query has no preconditions. If another writer won,
    // keep the transcript in the UI instead of pasting its unrelated contents.
    if !focus_external(target) || unsafe { GetClipboardSequenceNumber() } != sequence {
        return false;
    }
    super::send_key(
        b'V' as u16,
        super::Modifiers {
            ctrl: true,
            ..Default::default()
        },
    )
}

/// Paste voice output through the same guarded external-editor path.
/// Keep the voice limit independent of the larger clipboard-history budget.
pub fn paste_voice_text(target: InputTarget, text: &str) -> bool {
    paste_text_with_limit(target, text, MAX_TEXT_BYTES)
}

fn write_unicode_clipboard(text: &str) -> Option<u32> {
    let units: Vec<u16> = text.encode_utf16().chain(std::iter::once(0)).collect();
    // SAFETY: STATIC is a system-provided window class. This non-visible owner
    // is created and destroyed on the current thread. A NULL clipboard owner
    // is unsuitable for EmptyClipboard followed by SetClipboardData.
    unsafe {
        let class: Vec<u16> = "STATIC\0".encode_utf16().collect();
        let owner = CreateWindowExW(
            0,
            class.as_ptr(),
            std::ptr::null(),
            0,
            0,
            0,
            0,
            0,
            HWND_MESSAGE,
            std::ptr::null_mut(),
            std::ptr::null_mut(),
            std::ptr::null(),
        );
        if owner.is_null() {
            return None;
        }
        let memory = GlobalAlloc(GMEM_MOVEABLE, units.len() * size_of::<u16>());
        if memory.is_null() {
            DestroyWindow(owner);
            return None;
        }
        let destination = GlobalLock(memory).cast::<u16>();
        if destination.is_null() {
            GlobalFree(memory);
            DestroyWindow(owner);
            return None;
        }
        std::ptr::copy_nonoverlapping(units.as_ptr(), destination, units.len());
        GlobalUnlock(memory);
        let mut opened = false;
        for _ in 0..5 {
            if OpenClipboard(owner) != 0 {
                opened = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        // CF_UNICODETEXT is 13; ownership of GMEM_MOVEABLE memory transfers to
        // Windows only on successful SetClipboardData. Never free it afterward.
        let transferred =
            opened && EmptyClipboard() != 0 && !SetClipboardData(13, memory).is_null();
        let sequence = GetClipboardSequenceNumber();
        if opened {
            CloseClipboard();
        }
        if !transferred {
            GlobalFree(memory);
        }
        DestroyWindow(owner);
        (transferred && sequence != 0).then_some(sequence)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_transcripts_do_not_touch_the_clipboard() {
        let invalid_target = InputTarget(0);
        assert!(!paste_voice_text(invalid_target, ""));
        assert!(!paste_voice_text(invalid_target, "x\0y"));
        assert!(!paste_voice_text(
            invalid_target,
            &"x".repeat(MAX_TEXT_BYTES + 1)
        ));
        assert!(!focus_external(invalid_target));
    }
}
