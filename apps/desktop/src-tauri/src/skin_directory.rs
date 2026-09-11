use std::path::{Path, PathBuf};

/// Create only the host-selected skin directory and pass its absolute path to
/// the platform opener. Neither a webview path nor a shell command is accepted.
fn prepare_and_open(
    root: &Path,
    launch: impl FnOnce(&Path) -> std::io::Result<()>,
) -> std::io::Result<PathBuf> {
    std::fs::create_dir_all(root)?;
    // Do not canonicalize: Windows canonicalization adds a verbatim path prefix
    // which is intended for filesystem APIs, not shell directory navigation.
    let directory = std::path::absolute(root)?;
    launch(&directory)?;
    Ok(directory)
}

pub fn open(root: &Path) -> Result<(), &'static str> {
    prepare_and_open(root, launch_directory)
        .map(|_| ())
        .map_err(|_| "storage")
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn launch_directory(directory: &Path) -> std::io::Result<()> {
    #[cfg(target_os = "macos")]
    let program = "open";
    #[cfg(target_os = "linux")]
    let program = "xdg-open";
    let status = std::process::Command::new(program)
        .arg(directory)
        .stdin(std::process::Stdio::null())
        .stdout(std::process::Stdio::null())
        .stderr(std::process::Stdio::null())
        .status()?;
    if status.success() {
        Ok(())
    } else {
        Err(std::io::Error::other("directory opener failed"))
    }
}

#[cfg(target_os = "windows")]
fn launch_directory(directory: &Path) -> std::io::Result<()> {
    let directory = directory.to_path_buf();
    // A dedicated thread avoids inheriting a runtime worker's COM apartment.
    std::thread::spawn(move || launch_windows_directory(&directory))
        .join()
        .map_err(|_| std::io::Error::other("directory opener failed"))?
}

#[cfg(target_os = "windows")]
fn launch_windows_directory(directory: &Path) -> std::io::Result<()> {
    use std::os::windows::ffi::OsStrExt;
    #[link(name = "ole32")]
    unsafe extern "system" {
        fn CoInitializeEx(reserved: *mut std::ffi::c_void, flags: u32) -> i32;
        fn CoUninitialize();
    }
    #[link(name = "shell32")]
    unsafe extern "system" {
        fn ShellExecuteW(
            window: *mut std::ffi::c_void,
            operation: *const u16,
            file: *const u16,
            parameters: *const u16,
            directory: *const u16,
            show: i32,
        ) -> *mut std::ffi::c_void;
    }
    let path: Vec<u16> = directory.as_os_str().encode_wide().chain(Some(0)).collect();
    let operation: Vec<u16> = "open".encode_utf16().chain(Some(0)).collect();
    // SAFETY: this fresh thread has no COM apartment; reserved is null.
    // COINIT_APARTMENTTHREADED | COINIT_DISABLE_OLE1DDE, per ShellExecuteW.
    let initialized = unsafe { CoInitializeEx(std::ptr::null_mut(), 0x2 | 0x4) };
    if initialized < 0 {
        return Err(std::io::Error::other("directory opener failed"));
    }
    // SAFETY: both strings are NUL terminated and live through the call; all
    // optional pointers are null. ShellExecuteW does not retain these buffers.
    let result = unsafe {
        ShellExecuteW(
            std::ptr::null_mut(),
            operation.as_ptr(),
            path.as_ptr(),
            std::ptr::null(),
            std::ptr::null(),
            1,
        )
    };
    // SAFETY: balance the successful initialization on the same thread.
    unsafe { CoUninitialize() };
    if result as isize > 32 {
        Ok(())
    } else {
        Err(std::io::Error::other("directory opener failed"))
    }
}

#[cfg(not(any(target_os = "macos", target_os = "linux", target_os = "windows")))]
fn launch_directory(_: &Path) -> std::io::Result<()> {
    Err(std::io::Error::other("unsupported platform"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn creates_host_directory_before_launch_and_preserves_existing_files() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("synthetic state & spaces").join("skins");
        let opened = prepare_and_open(&root, |path| {
            assert!(path.is_absolute());
            assert!(path.is_dir());
            assert_eq!(path, std::path::absolute(&root).unwrap());
            Ok(())
        })
        .unwrap();
        std::fs::write(opened.join("marker"), b"synthetic").unwrap();
        prepare_and_open(&root, |_| Ok(())).unwrap();
        assert_eq!(std::fs::read(opened.join("marker")).unwrap(), b"synthetic");
    }

    #[test]
    fn file_collision_never_launches_or_overwrites() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        std::fs::write(&root, b"synthetic").unwrap();
        assert!(prepare_and_open(&root, |_| panic!("must not launch")).is_err());
        assert_eq!(std::fs::read(root).unwrap(), b"synthetic");
    }

    #[test]
    fn launch_failure_is_reported_without_removing_directory() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        assert!(prepare_and_open(&root, |_| Err(std::io::Error::other("synthetic"))).is_err());
        assert!(root.is_dir());
    }
}
