//! Cooperative cross-process access to prepared dictionaries and their user journal.
//! Lock files are stable coordination objects and must not be removed.

use std::fs::{File, OpenOptions};
use std::io;
use std::path::Path;

/// A guard held for the lifetime of every Engine/session using the paths.
pub struct DictionaryAccess {
    _files: Vec<File>,
}

impl DictionaryAccess {
    /// Acquire shared access without waiting. `None` means maintenance is active.
    pub fn try_session(user: &Path, dictionaries: &Path) -> io::Result<Option<Self>> {
        Self::acquire(user, dictionaries, false)
    }

    /// Acquire exclusive maintenance access without waiting. `None` means sessions/writers are active.
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
    fn shared_access_excludes_maintenance_and_releases_cleanly() {
        let user = tempfile::tempdir().unwrap();
        let dictionaries = tempfile::tempdir().unwrap();
        let first = DictionaryAccess::try_session(user.path(), dictionaries.path())
            .unwrap()
            .unwrap();
        let second = DictionaryAccess::try_session(user.path(), dictionaries.path())
            .unwrap()
            .unwrap();
        assert!(
            DictionaryAccess::try_maintenance(user.path(), dictionaries.path())
                .unwrap()
                .is_none()
        );
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
        drop(writer);
        assert!(
            DictionaryAccess::try_session(user.path(), dictionaries.path())
                .unwrap()
                .is_some()
        );
    }
}
