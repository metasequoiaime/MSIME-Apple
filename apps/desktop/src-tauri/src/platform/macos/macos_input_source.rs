//! Install the packaged macOS InputMethodKit bundle without making the
//! settings application own input-method state.
//!
//! The settings app is the public UI for this action, but the input source
//! remains a separate bundle with its existing IMK process boundary.  Copying
//! is deliberately staged and atomic so a failed update never removes a
//! working input source.

use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub(crate) const INPUT_SOURCE_BUNDLE_ID: &str = "app.msime.client.preview.inputmethod";
pub(crate) const INPUT_SOURCE_BUNDLE_NAME: &str = "水杉输入法（预览）.app";
const INPUT_SOURCE_EXECUTABLE: &str = "水杉输入法（预览）";

#[derive(Debug)]
pub(crate) enum InstallError {
    SourceUnavailable,
    InvalidBundle,
    HomeUnavailable,
    Io,
    Registration,
}

fn is_symlink(path: &Path) -> io::Result<bool> {
    Ok(fs::symlink_metadata(path)?.file_type().is_symlink())
}

fn validate_bundle(source: &Path) -> Result<(), InstallError> {
    let metadata = fs::symlink_metadata(source).map_err(|_| InstallError::SourceUnavailable)?;
    if !metadata.is_dir() || metadata.file_type().is_symlink() {
        return Err(InstallError::InvalidBundle);
    }
    let info = source.join("Contents/Info.plist");
    let executable = source.join("Contents/MacOS").join(INPUT_SOURCE_EXECUTABLE);
    if is_symlink(&info).map_err(|_| InstallError::InvalidBundle)?
        || is_symlink(&executable).map_err(|_| InstallError::InvalidBundle)?
        || !info.is_file()
        || !executable.is_file()
    {
        return Err(InstallError::InvalidBundle);
    }
    let plist = fs::read(info).map_err(|_| InstallError::InvalidBundle)?;
    if !String::from_utf8_lossy(&plist).contains(INPUT_SOURCE_BUNDLE_ID) {
        return Err(InstallError::InvalidBundle);
    }
    Ok(())
}

fn copy_tree(source: &Path, destination: &Path) -> Result<(), InstallError> {
    let metadata = fs::symlink_metadata(source).map_err(|_| InstallError::Io)?;
    if metadata.file_type().is_symlink() {
        return Err(InstallError::InvalidBundle);
    }
    if metadata.is_dir() {
        fs::create_dir(destination).map_err(|_| InstallError::Io)?;
        for entry in fs::read_dir(source).map_err(|_| InstallError::Io)? {
            let entry = entry.map_err(|_| InstallError::Io)?;
            copy_tree(&entry.path(), &destination.join(entry.file_name()))?;
        }
        fs::set_permissions(destination, metadata.permissions()).map_err(|_| InstallError::Io)?;
        return Ok(());
    }
    if !metadata.is_file() {
        return Err(InstallError::InvalidBundle);
    }
    fs::copy(source, destination).map_err(|_| InstallError::Io)?;
    fs::set_permissions(destination, metadata.permissions()).map_err(|_| InstallError::Io)
}

fn remove_staging(path: &Path) -> Result<(), InstallError> {
    if !path.exists() {
        return Ok(());
    }
    if is_symlink(path).map_err(|_| InstallError::Io)? {
        return Err(InstallError::InvalidBundle);
    }
    fs::remove_dir_all(path).map_err(|_| InstallError::Io)
}

/// Install a validated bundle below `input_methods`, replacing an existing
/// directory only after the complete copy has succeeded and registration has
/// accepted the staged replacement. A failed registration restores the old
/// bundle before returning the error.
fn install_bundle_at_with_registration<F>(
    source: &Path,
    input_methods: &Path,
    register: F,
) -> Result<PathBuf, InstallError>
where
    F: FnOnce(&Path) -> Result<(), InstallError>,
{
    validate_bundle(source)?;
    fs::create_dir_all(input_methods).map_err(|_| InstallError::Io)?;
    let target = input_methods.join(INPUT_SOURCE_BUNDLE_NAME);
    if target.exists() && is_symlink(&target).map_err(|_| InstallError::Io)? {
        return Err(InstallError::InvalidBundle);
    }
    let pid = std::process::id();
    let staging = input_methods.join(format!(".{INPUT_SOURCE_BUNDLE_NAME}.installing-{pid}"));
    let backup = input_methods.join(format!(".{INPUT_SOURCE_BUNDLE_NAME}.previous-{pid}"));
    remove_staging(&staging)?;
    if backup.exists() {
        return Err(InstallError::Io);
    }
    copy_tree(source, &staging)?;

    let had_previous = target.exists();
    if had_previous {
        fs::rename(&target, &backup).map_err(|_| {
            let _ = remove_staging(&staging);
            InstallError::Io
        })?;
    }
    if fs::rename(&staging, &target).is_err() {
        let _ = remove_staging(&staging);
        if had_previous {
            let _ = fs::rename(&backup, &target);
        }
        return Err(InstallError::Io);
    }
    if let Err(error) = register(&target) {
        if fs::remove_dir_all(&target).is_err() {
            return Err(InstallError::Io);
        }
        if had_previous && fs::rename(&backup, &target).is_err() {
            return Err(InstallError::Io);
        }
        return Err(error);
    }
    if had_previous {
        fs::remove_dir_all(&backup).map_err(|_| InstallError::Io)?;
    }
    Ok(target)
}

/// Install a validated bundle below `input_methods`, replacing an existing
/// directory only after the complete copy has succeeded.
pub(crate) fn install_bundle_at(
    source: &Path,
    input_methods: &Path,
) -> Result<PathBuf, InstallError> {
    install_bundle_at_with_registration(source, input_methods, |_| Ok(()))
}

fn source_candidates(resource_directory: Option<&Path>, current_directory: &Path) -> Vec<PathBuf> {
    let manifest_root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let repository_root = manifest_root.join("../../..");
    let mut candidates = Vec::new();
    if let Some(resource_directory) = resource_directory {
        candidates.push(resource_directory.join(INPUT_SOURCE_BUNDLE_NAME));
    }
    candidates.push(
        current_directory
            .join("target/macos")
            .join(INPUT_SOURCE_BUNDLE_NAME),
    );
    candidates.push(
        repository_root
            .join("target/macos")
            .join(INPUT_SOURCE_BUNDLE_NAME),
    );
    candidates
}

fn find_source(
    resource_directory: Option<&Path>,
    current_directory: &Path,
) -> Result<PathBuf, InstallError> {
    source_candidates(resource_directory, current_directory)
        .into_iter()
        .find(|candidate| validate_bundle(candidate).is_ok())
        .ok_or(InstallError::SourceUnavailable)
}

fn home_input_methods() -> Result<PathBuf, InstallError> {
    let home = std::env::var_os("HOME").ok_or(InstallError::HomeUnavailable)?;
    let home = PathBuf::from(home);
    if !home.is_absolute() {
        return Err(InstallError::HomeUnavailable);
    }
    Ok(home.join("Library/Input Methods"))
}

pub(crate) fn installed_bundle_path() -> Result<PathBuf, InstallError> {
    Ok(home_input_methods()?.join(INPUT_SOURCE_BUNDLE_NAME))
}

fn register_installed_bundle(bundle: &Path) -> Result<(), InstallError> {
    let executable = bundle.join("Contents/MacOS").join(INPUT_SOURCE_EXECUTABLE);
    let status = std::process::Command::new(executable)
        .arg("--register-input-source")
        .status()
        .map_err(|_| InstallError::Registration)?;
    if status.success() {
        Ok(())
    } else {
        Err(InstallError::Registration)
    }
}

pub(crate) fn install(resource_directory: Option<&Path>) -> Result<(), InstallError> {
    let source = find_source(
        resource_directory,
        &std::env::current_dir().map_err(|_| InstallError::SourceUnavailable)?,
    )?;
    let input_methods = home_input_methods()?;
    install_bundle_at_with_registration(&source, &input_methods, register_installed_bundle)
        .map(|_| ())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    use tempfile::tempdir;

    fn fixture(root: &Path, id: &str, executable_contents: &[u8]) -> PathBuf {
        let bundle = root.join("fixture.app");
        fs::create_dir_all(bundle.join("Contents/MacOS")).unwrap();
        fs::write(
            bundle.join("Contents/Info.plist"),
            format!("CFBundleIdentifier={id}"),
        )
        .unwrap();
        let executable = bundle.join(format!("Contents/MacOS/{INPUT_SOURCE_EXECUTABLE}"));
        fs::write(&executable, executable_contents).unwrap();
        fs::set_permissions(&executable, fs::Permissions::from_mode(0o755)).unwrap();
        bundle
    }

    #[test]
    fn installs_atomically_and_preserves_executable_mode() {
        let root = tempdir().unwrap();
        let source = fixture(root.path(), INPUT_SOURCE_BUNDLE_ID, b"new");
        let destination = root.path().join("Library/Input Methods");
        let installed = install_bundle_at(&source, &destination).unwrap();
        assert_eq!(
            fs::read(installed.join(format!("Contents/MacOS/{INPUT_SOURCE_EXECUTABLE}"))).unwrap(),
            b"new"
        );
        assert_eq!(
            fs::metadata(installed.join(format!("Contents/MacOS/{INPUT_SOURCE_EXECUTABLE}")))
                .unwrap()
                .permissions()
                .mode()
                & 0o111,
            0o111
        );

        let replacement = fixture(root.path(), INPUT_SOURCE_BUNDLE_ID, b"replacement");
        install_bundle_at(&replacement, &destination).unwrap();
        assert_eq!(
            fs::read(
                destination
                    .join(INPUT_SOURCE_BUNDLE_NAME)
                    .join(format!("Contents/MacOS/{INPUT_SOURCE_EXECUTABLE}"))
            )
            .unwrap(),
            b"replacement"
        );
        assert!(!destination
            .join(format!(
                ".{INPUT_SOURCE_BUNDLE_NAME}.installing-{}",
                std::process::id()
            ))
            .exists());
    }

    #[test]
    fn rejects_wrong_bundle_without_touching_existing_install() {
        let root = tempdir().unwrap();
        let destination = root.path().join("Library/Input Methods");
        let existing = fixture(root.path(), INPUT_SOURCE_BUNDLE_ID, b"existing");
        install_bundle_at(&existing, &destination).unwrap();
        let wrong = fixture(root.path(), "org.example.other", b"wrong");
        assert!(matches!(
            install_bundle_at(&wrong, &destination),
            Err(InstallError::InvalidBundle)
        ));
        assert_eq!(
            fs::read(
                destination
                    .join(INPUT_SOURCE_BUNDLE_NAME)
                    .join(format!("Contents/MacOS/{INPUT_SOURCE_EXECUTABLE}"))
            )
            .unwrap(),
            b"existing"
        );
    }

    #[test]
    fn rejects_symlinked_bundle_contents() {
        let root = tempdir().unwrap();
        let source = fixture(root.path(), INPUT_SOURCE_BUNDLE_ID, b"new");
        let link = source.join("Contents/Info.plist.link-target");
        fs::write(&link, b"outside").unwrap();
        fs::remove_file(source.join("Contents/Info.plist")).unwrap();
        std::os::unix::fs::symlink(&link, source.join("Contents/Info.plist")).unwrap();
        assert!(matches!(
            validate_bundle(&source),
            Err(InstallError::InvalidBundle)
        ));
    }

    #[test]
    fn registration_failure_restores_previous_install() {
        let old_root = tempdir().unwrap();
        let new_root = tempdir().unwrap();
        let destination_root = tempdir().unwrap();
        let old_source = fixture(old_root.path(), INPUT_SOURCE_BUNDLE_ID, b"old");
        let new_source = fixture(new_root.path(), INPUT_SOURCE_BUNDLE_ID, b"new");
        let destination = destination_root.path().join("Library/Input Methods");
        install_bundle_at(&old_source, &destination).unwrap();

        let result = install_bundle_at_with_registration(&new_source, &destination, |_| {
            Err(InstallError::Registration)
        });
        assert!(matches!(result, Err(InstallError::Registration)));
        assert_eq!(
            fs::read(
                destination
                    .join(INPUT_SOURCE_BUNDLE_NAME)
                    .join(format!("Contents/MacOS/{INPUT_SOURCE_EXECUTABLE}"))
            )
            .unwrap(),
            b"old"
        );
        assert!(!destination
            .join(format!(
                ".{INPUT_SOURCE_BUNDLE_NAME}.previous-{}",
                std::process::id()
            ))
            .exists());
    }
}
