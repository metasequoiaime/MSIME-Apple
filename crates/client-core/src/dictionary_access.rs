//! Cooperative cross-process access to prepared dictionaries and their user journal.
//! Keep the stable lock files: unlinking them would split the lock domain.
use std::fs::{File, OpenOptions};
use std::io;
use std::path::Path;

/// The guard must outlive every Engine/session using these paths.
/// This coordinates participating clients, not legacy hosts or external editors.
pub struct DictionaryAccess {
    _files: Vec<File>,
}

impl DictionaryAccess {
    /// None is busy. Absolute, existing prepared directories are required.
    pub fn try_session(user: &Path, dictionaries: &Path) -> io::Result<Option<Self>> {
        Self::acquire(user, dictionaries, false)
    }

    /// None is busy; never waits for sessions or another writer.
    pub fn try_maintenance(user: &Path, dictionaries: &Path) -> io::Result<Option<Self>> {
        Self::acquire(user, dictionaries, true)
    }

    fn acquire(user: &Path, dictionaries: &Path, exclusive: bool) -> io::Result<Option<Self>> {
        if !user.is_absolute() || !dictionaries.is_absolute() {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "absolute dictionary paths required",
            ));
        }
        let mut roots = vec![user.canonicalize()?, dictionaries.canonicalize()?];
        roots.sort();
        roots.dedup();
        let mut files = Vec::new();
        for root in roots {
            let mut options = OpenOptions::new();
            options.read(true).write(true).create(true).truncate(false);
            #[cfg(unix)]
            {
                use std::os::unix::fs::OpenOptionsExt;
                options.mode(0o600);
            }
            let file = options.open(root.join(".msime-dictionary-access.lock"))?;
            let acquired = if exclusive {
                crate::file_lock::try_exclusive(&file)?
            } else {
                crate::file_lock::try_shared(&file)?
            };
            if !acquired {
                return Ok(None);
            }
            files.push(file);
        }
        Ok(Some(Self { _files: files }))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn process_probe() {
        let Some(root) = std::env::var_os("MSIME_ACCESS_TEST_ROOT") else {
            return;
        };
        let root = std::path::PathBuf::from(root);
        let access = if std::env::var_os("MSIME_ACCESS_TEST_READER").is_some() {
            DictionaryAccess::try_session(&root, &root)
        } else {
            DictionaryAccess::try_maintenance(&root, &root)
        };
        assert!(access.unwrap().is_none());
    }

    #[test]
    fn readers_exclude_another_process_writer() {
        let root = tempfile::tempdir().unwrap();
        let reader = DictionaryAccess::try_session(root.path(), root.path())
            .unwrap()
            .unwrap();
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "dictionary_access::tests::process_probe"])
            .env("MSIME_ACCESS_TEST_ROOT", root.path())
            .status()
            .unwrap();
        assert!(status.success());
        drop(reader);
        let _writer = DictionaryAccess::try_maintenance(root.path(), root.path())
            .unwrap()
            .unwrap();
        let status = std::process::Command::new(std::env::current_exe().unwrap())
            .args(["--exact", "dictionary_access::tests::process_probe"])
            .env("MSIME_ACCESS_TEST_ROOT", root.path())
            .env("MSIME_ACCESS_TEST_READER", "1")
            .status()
            .unwrap();
        assert!(status.success());
    }
    #[test]
    fn readers_share_and_writers_exclude_both_roots() {
        let user = tempfile::tempdir().unwrap();
        let dictionaries = tempfile::tempdir().unwrap();
        let other = tempfile::tempdir().unwrap();
        let first = DictionaryAccess::try_session(user.path(), dictionaries.path())
            .unwrap()
            .unwrap();
        let second = DictionaryAccess::try_session(user.path(), dictionaries.path())
            .unwrap()
            .unwrap();
        assert!(
            DictionaryAccess::try_maintenance(other.path(), dictionaries.path())
                .unwrap()
                .is_none()
        );
        assert!(DictionaryAccess::try_maintenance(user.path(), other.path())
            .unwrap()
            .is_none());
        drop(first);
        assert!(
            DictionaryAccess::try_maintenance(user.path(), dictionaries.path())
                .unwrap()
                .is_none()
        );
        drop(second);
        let writer = DictionaryAccess::try_maintenance(user.path(), dictionaries.path())
            .unwrap()
            .unwrap();
        assert!(
            DictionaryAccess::try_session(user.path(), dictionaries.path())
                .unwrap()
                .is_none()
        );
        assert!(
            DictionaryAccess::try_maintenance(user.path(), dictionaries.path())
                .unwrap()
                .is_none()
        );
        drop(writer);
        assert!(
            DictionaryAccess::try_session(user.path(), dictionaries.path())
                .unwrap()
                .is_some()
        );
    }
}
