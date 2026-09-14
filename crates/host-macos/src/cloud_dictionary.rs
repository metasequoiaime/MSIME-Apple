//! Read only the native account owner's private dictionary export, never a path
//! supplied by a webview. Keep directory/file handles pinned across validation.
use super::cloud_clipboard::CloudClipboardError;
use std::ffi::CString;
use std::fs::{File, OpenOptions};
use std::io::Read;
use std::os::fd::{AsRawFd, FromRawFd};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt};
use std::path::Path;

pub fn read_export(
    path: &Path,
    expected_name: &str,
    expected_bytes: u64,
) -> Result<String, CloudClipboardError> {
    let unavailable = || CloudClipboardError::Unavailable;
    if !path.is_absolute()
        || expected_bytes > 384 * 1024 * 1024
        || ![
            "dictionary-pinyin.tsv",
            "dictionary-wubi.tsv",
            "dictionary-quick.tsv",
            "dictionary-english.tsv",
        ]
        .contains(&expected_name)
        || path.file_name().and_then(|name| name.to_str()) != Some(expected_name)
    {
        return Err(CloudClipboardError::Invalid);
    }
    let root = path.parent().ok_or_else(unavailable)?;
    let name = root
        .file_name()
        .and_then(|name| name.to_str())
        .ok_or_else(unavailable)?;
    let suffix = name.strip_prefix("msime-export-").ok_or_else(unavailable)?;
    if suffix.len() != 36
        || !suffix
            .bytes()
            .all(|byte| byte.is_ascii_hexdigit() || byte == b'-')
    {
        return Err(CloudClipboardError::Invalid);
    }
    // Darwin flags: O_NOFOLLOW, O_DIRECTORY, O_CLOEXEC. This module is macOS-only.
    let directory = OpenOptions::new()
        .read(true)
        .custom_flags(0x100 | 0x100000 | 0x1000000)
        .open(root)
        .map_err(|_| unavailable())?;
    unsafe extern "C" {
        fn getuid() -> u32;
        fn openat(directory: i32, path: *const std::ffi::c_char, flags: i32, ...) -> i32;
    }
    // SAFETY: getuid takes no pointers and has no side effects.
    let uid = unsafe { getuid() };
    let metadata = directory.metadata().map_err(|_| unavailable())?;
    if !metadata.is_dir() || metadata.uid() != uid || metadata.mode() & 0o777 != 0o700 {
        return Err(unavailable());
    }
    let name = CString::new(expected_name).map_err(|_| unavailable())?;
    // SAFETY: live directory FD and NUL-terminated fixed filename; no creation.
    // O_NONBLOCK also prevents a substituted FIFO from hanging before fstat.
    let descriptor = unsafe {
        openat(
            directory.as_raw_fd(),
            name.as_ptr(),
            0x4 | 0x100 | 0x1000000,
        )
    };
    if descriptor < 0 {
        return Err(unavailable());
    }
    // SAFETY: openat returned a new owned descriptor exactly once.
    let file = unsafe { File::from_raw_fd(descriptor) };
    let metadata = file.metadata().map_err(|_| unavailable())?;
    if !metadata.is_file()
        || metadata.uid() != uid
        || metadata.mode() & 0o777 != 0o600
        || metadata.nlink() != 1
        || metadata.len() != expected_bytes
    {
        return Err(unavailable());
    }
    let mut text = String::new();
    file.take(expected_bytes + 1)
        .read_to_string(&mut text)
        .map_err(|_| unavailable())?;
    if text.len() as u64 != expected_bytes || text.contains('\0') {
        return Err(unavailable());
    }
    Ok(text)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::{symlink, PermissionsExt};
    #[test]
    fn private_export_preserves_large_utf8_and_rejects_links_and_wrong_metadata() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary
            .path()
            .join("msime-export-00000000-0000-0000-0000-000000000000");
        std::fs::create_dir(&root).unwrap();
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
        let file = root.join("dictionary-pinyin.tsv");
        let text = "synthetic\t合成\t100\n".repeat(150_000);
        std::fs::write(&file, &text).unwrap();
        std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert_eq!(
            read_export(&file, "dictionary-pinyin.tsv", text.len() as u64).unwrap(),
            text
        );
        assert!(read_export(&file, "dictionary-pinyin.tsv", 1).is_err());
        assert!(read_export(&file, "dictionary-english.tsv", text.len() as u64).is_err());
        let link = root.join("dictionary-wubi.tsv");
        symlink(&file, &link).unwrap();
        assert!(read_export(&link, "dictionary-wubi.tsv", text.len() as u64).is_err());
        let fifo = root.join("dictionary-quick.tsv");
        let fifo_name = CString::new(fifo.as_os_str().as_encoded_bytes()).unwrap();
        unsafe extern "C" {
            fn mkfifo(path: *const std::ffi::c_char, mode: u16) -> i32;
        }
        // SAFETY: a NUL-terminated path inside this test's owned temporary directory.
        assert_eq!(unsafe { mkfifo(fifo_name.as_ptr(), 0o600) }, 0);
        assert!(read_export(&fifo, "dictionary-quick.tsv", 0).is_err());
        std::fs::set_permissions(&file, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(read_export(&file, "dictionary-pinyin.tsv", text.len() as u64).is_err());
    }
}
