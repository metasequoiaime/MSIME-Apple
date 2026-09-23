use std::path::{Path, PathBuf};

/// Create only the host-selected directory and pass its absolute path to
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

/// Copy a skin folder the user picked into `root`, under the folder's own name, and return that name.
///
/// This is how a skin arrives on a host whose skin folder sits inside the application sandbox. The name and the manifest are checked first, by the rule the catalog lists skins by, so nothing is copied that the page would then report as unusable. An existing skin of that name is replaced whole rather than merged, since a half-overwritten skin draws a stylesheet from one version with assets from another. Symbolic links are left behind: the catalog refuses anything that resolves outside the skin folder anyway.
#[cfg_attr(not(target_os = "ios"), allow(dead_code))]
pub fn import(source: &Path, root: &Path) -> Result<String, &'static str> {
    let name = source
        .file_name()
        .and_then(|name| name.to_str())
        .filter(|name| msime_client_core::skin::catalog::is_external_id(name))
        .ok_or("skin_name")?
        .to_owned();
    if !source.join("skin.toml").is_file() {
        return Err("skin_manifest");
    }
    std::fs::create_dir_all(root).map_err(|_| "storage")?;
    // The leading dot keeps both helpers out of the catalog, which lists only names starting with a letter or digit.
    let staging = root.join(format!(".import-{name}"));
    let replaced = root.join(format!(".replaced-{name}"));
    for leftover in [&staging, &replaced] {
        if leftover.exists() {
            std::fs::remove_dir_all(leftover).map_err(|_| "storage")?;
        }
    }
    let mut budget = ImportBudget::default();
    if copy_tree(source, &staging, 0, &mut budget).is_err() {
        let _ = std::fs::remove_dir_all(&staging);
        return Err("storage");
    }
    let target = root.join(&name);
    let had_previous = target.exists();
    if had_previous && std::fs::rename(&target, &replaced).is_err() {
        let _ = std::fs::remove_dir_all(&staging);
        return Err("storage");
    }
    if std::fs::rename(&staging, &target).is_err() {
        if had_previous {
            let _ = std::fs::rename(&replaced, &target);
        }
        let _ = std::fs::remove_dir_all(&staging);
        return Err("storage");
    }
    if had_previous {
        let _ = std::fs::remove_dir_all(&replaced);
    }
    Ok(name)
}

/// Bounds on one import, so a mistakenly picked folder (a photo library, a whole drive) fails instead of filling the device.
struct ImportBudget {
    entries: usize,
    bytes: u64,
}

impl Default for ImportBudget {
    fn default() -> Self {
        Self {
            entries: 4096,
            bytes: 256 * 1024 * 1024,
        }
    }
}

const MAX_IMPORT_DEPTH: usize = 16;

fn copy_tree(
    source: &Path,
    destination: &Path,
    depth: usize,
    budget: &mut ImportBudget,
) -> std::io::Result<()> {
    if depth > MAX_IMPORT_DEPTH {
        return Err(std::io::Error::other("skin folder too deep"));
    }
    std::fs::create_dir(destination)?;
    for entry in std::fs::read_dir(source)? {
        let entry = entry?;
        budget.entries = budget
            .entries
            .checked_sub(1)
            .ok_or_else(|| std::io::Error::other("skin folder too large"))?;
        let kind = entry.file_type()?;
        let target = destination.join(entry.file_name());
        if kind.is_dir() {
            copy_tree(&entry.path(), &target, depth + 1, budget)?;
        } else if kind.is_file() {
            budget.bytes = budget
                .bytes
                .checked_sub(entry.metadata()?.len())
                .ok_or_else(|| std::io::Error::other("skin folder too large"))?;
            std::fs::copy(entry.path(), target)?;
        }
    }
    Ok(())
}

#[cfg(any(target_os = "macos", target_os = "linux"))]
fn launch_directory(directory: &Path) -> std::io::Result<()> {
    #[cfg(target_os = "linux")]
    {
        return if crate::linux_process::run_status_path(
            "xdg-open",
            directory,
            std::time::Duration::from_secs(3),
        ) {
            Ok(())
        } else {
            Err(std::io::Error::other("directory opener failed"))
        };
    }

    #[cfg(target_os = "macos")]
    {
        let status = std::process::Command::new("open")
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
}

#[cfg(target_os = "windows")]
fn launch_directory(directory: &Path) -> std::io::Result<()> {
    let directory = directory.to_path_buf();
    // A dedicated thread avoids inheriting a runtime worker's COM apartment;
    // the shell call itself lives in the Windows host layer.
    std::thread::spawn(move || {
        msime_host_windows::open_directory(&directory)
            .then_some(())
            .ok_or_else(|| std::io::Error::other("directory opener failed"))
    })
    .join()
    .map_err(|_| std::io::Error::other("directory opener failed"))?
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

    fn picked(parent: &Path, name: &str) -> PathBuf {
        let skin = parent.join(name);
        std::fs::create_dir_all(skin.join("images")).unwrap();
        std::fs::write(skin.join("skin.toml"), b"id = 'synthetic'").unwrap();
        std::fs::write(skin.join("images").join("bg.png"), b"new").unwrap();
        skin
    }

    #[test]
    fn import_copies_the_picked_folder_under_its_own_name() {
        let files = tempfile::tempdir().unwrap();
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        let source = picked(files.path(), "sakura");
        assert_eq!(import(&source, &root).unwrap(), "sakura");
        assert_eq!(
            std::fs::read(root.join("sakura").join("images").join("bg.png")).unwrap(),
            b"new"
        );
        assert!(source.join("skin.toml").is_file());
        let names: Vec<_> = std::fs::read_dir(&root)
            .unwrap()
            .map(|entry| entry.unwrap().file_name())
            .collect();
        assert_eq!(names, ["sakura"]);
    }

    #[test]
    fn import_replaces_an_existing_skin_whole() {
        let files = tempfile::tempdir().unwrap();
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        std::fs::create_dir_all(root.join("sakura")).unwrap();
        std::fs::write(root.join("sakura").join("stale.css"), b"old").unwrap();
        import(&picked(files.path(), "sakura"), &root).unwrap();
        assert!(!root.join("sakura").join("stale.css").exists());
        assert!(root.join("sakura").join("skin.toml").is_file());
        assert!(!root.join(".replaced-sakura").exists());
    }

    #[test]
    fn import_refuses_what_the_catalog_would_not_list() {
        let files = tempfile::tempdir().unwrap();
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        for name in ["Sakura", "willow_green", "樱花"] {
            assert_eq!(import(&picked(files.path(), name), &root), Err("skin_name"));
        }
        let bare = files.path().join("bare");
        std::fs::create_dir_all(&bare).unwrap();
        assert_eq!(import(&bare, &root), Err("skin_manifest"));
        assert!(!root.exists());
    }

    #[test]
    fn import_that_runs_over_budget_leaves_the_previous_skin() {
        let files = tempfile::tempdir().unwrap();
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        std::fs::create_dir_all(root.join("sakura")).unwrap();
        std::fs::write(root.join("sakura").join("skin.toml"), b"old").unwrap();
        let source = picked(files.path(), "sakura");
        let mut deep = source.clone();
        for _ in 0..=MAX_IMPORT_DEPTH {
            deep = deep.join("d");
        }
        std::fs::create_dir_all(&deep).unwrap();
        assert_eq!(import(&source, &root), Err("storage"));
        assert_eq!(
            std::fs::read(root.join("sakura").join("skin.toml")).unwrap(),
            b"old"
        );
        assert!(!root.join(".import-sakura").exists());
    }

    #[cfg(unix)]
    #[test]
    fn import_leaves_symbolic_links_behind() {
        let files = tempfile::tempdir().unwrap();
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        let source = picked(files.path(), "sakura");
        std::os::unix::fs::symlink("/etc", source.join("escape")).unwrap();
        import(&source, &root).unwrap();
        assert!(std::fs::symlink_metadata(root.join("sakura").join("escape")).is_err());
    }

    #[test]
    fn launch_failure_is_reported_without_removing_directory() {
        let state = tempfile::tempdir().unwrap();
        let root = state.path().join("skins");
        assert!(prepare_and_open(&root, |_| Err(std::io::Error::other("synthetic"))).is_err());
        assert!(root.is_dir());
    }
}
