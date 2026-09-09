//! Versioned local preferences. Hosts supply a private application data directory.
//! All writers coordinate through the stable lock file, not the replaced data file.

use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum InputScheme {
    #[default]
    Quanpin,
    Shuangpin,
    Wubi,
    Japanese,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Preferences {
    pub scheme: InputScheme,
    pub candidate_page_size: u8,
    pub learning: bool,
    pub chinese_punctuation: bool,
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            scheme: InputScheme::default(),
            candidate_page_size: 5,
            learning: true,
            chinese_punctuation: true,
        }
    }
}

impl Preferences {
    pub fn validate(&self) -> Result<(), PreferencesError> {
        if !(1..=9).contains(&self.candidate_page_size) {
            return Err(PreferencesError::InvalidPageSize);
        }
        Ok(())
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct PreferencesSnapshot {
    pub format_version: u32,
    pub revision: u64,
    pub preferences: Preferences,
}

impl Default for PreferencesSnapshot {
    fn default() -> Self {
        Self {
            format_version: 1,
            revision: 0,
            preferences: Preferences::default(),
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum PreferencesError {
    #[error("candidate page size must be between 1 and 9")]
    InvalidPageSize,
    #[error("preferences changed; reload before saving")]
    Conflict,
    #[error("unsupported preferences format")]
    UnsupportedFormat,
    #[error("preferences revision exhausted")]
    RevisionExhausted,
    #[error("preferences storage failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid preferences document: {0}")]
    Json(#[from] serde_json::Error),
}

pub struct PreferencesStore {
    directory: PathBuf,
}

impl PreferencesStore {
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        Self {
            directory: directory.into(),
        }
    }

    fn lock(&self) -> Result<File, PreferencesError> {
        fs::create_dir_all(&self.directory)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.directory.join("preferences.lock"))?;
        lock.lock()?;
        Ok(lock)
    }

    fn path(&self) -> PathBuf {
        self.directory.join("preferences.json")
    }

    fn read_locked(&self) -> Result<PreferencesSnapshot, PreferencesError> {
        let bytes = match fs::read(self.path()) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(PreferencesSnapshot::default())
            }
            Err(error) => return Err(error.into()),
        };
        let snapshot: PreferencesSnapshot = serde_json::from_slice(&bytes)?;
        if snapshot.format_version != 1 {
            return Err(PreferencesError::UnsupportedFormat);
        }
        snapshot.preferences.validate()?;
        Ok(snapshot)
    }

    pub fn load(&self) -> Result<PreferencesSnapshot, PreferencesError> {
        let _lock = self.lock()?;
        self.read_locked()
    }

    /// Compare-and-swap prevents stale settings windows or IME hosts losing updates.
    /// Corrupt or future-format files are never silently replaced with defaults.
    pub fn save(
        &self,
        expected_revision: u64,
        preferences: Preferences,
    ) -> Result<PreferencesSnapshot, PreferencesError> {
        preferences.validate()?;
        let _lock = self.lock()?;
        let current = self.read_locked()?;
        if current.revision != expected_revision {
            return Err(PreferencesError::Conflict);
        }
        let snapshot = PreferencesSnapshot {
            format_version: 1,
            revision: current
                .revision
                .checked_add(1)
                .ok_or(PreferencesError::RevisionExhausted)?,
            preferences,
        };
        atomic_write(
            &self.directory,
            &self.path(),
            &serde_json::to_vec_pretty(&snapshot)?,
        )?;
        Ok(snapshot)
    }
}

fn atomic_write(directory: &Path, path: &Path, contents: &[u8]) -> Result<(), PreferencesError> {
    let mut temporary = tempfile::NamedTempFile::new_in(directory)?;
    temporary.write_all(contents)?;
    temporary.as_file().sync_all()?;
    temporary.persist(path).map_err(|error| error.error)?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persists_across_instances_and_rejects_stale_save() {
        let dir = tempfile::tempdir().unwrap();
        let first = PreferencesStore::new(dir.path());
        let second = PreferencesStore::new(dir.path());
        let preferences = Preferences {
            learning: false,
            ..Preferences::default()
        };
        let saved = first.save(0, preferences).unwrap();
        assert_eq!(saved.revision, 1);
        assert_eq!(second.load().unwrap(), saved);
        assert!(matches!(
            second.save(0, Preferences::default()),
            Err(PreferencesError::Conflict)
        ));
        assert_eq!(first.load().unwrap(), saved);
    }

    #[test]
    fn invalid_values_do_not_change_disk() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let initial = store.save(0, Preferences::default()).unwrap();
        for size in [0, 10, 255] {
            assert!(matches!(
                store.save(
                    1,
                    Preferences {
                        candidate_page_size: size,
                        ..Preferences::default()
                    }
                ),
                Err(PreferencesError::InvalidPageSize)
            ));
        }
        assert_eq!(store.load().unwrap(), initial);
    }

    #[test]
    fn malformed_future_and_unknown_documents_are_preserved() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        for bytes in ["broken".to_owned(), serde_json::to_string(&PreferencesSnapshot { format_version: 2, ..PreferencesSnapshot::default() }).unwrap(),
            r#"{"format_version":1,"revision":0,"preferences":{"scheme":"quanpin","candidate_page_size":5,"learning":true,"chinese_punctuation":true,"future_option":true}}"#.to_owned()] {
            fs::write(store.path(), &bytes).unwrap();
            assert!(store.save(0, Preferences::default()).is_err());
            assert_eq!(fs::read_to_string(store.path()).unwrap(), bytes);
        }
    }

    #[test]
    fn concurrent_stores_have_exactly_one_winner() {
        let dir = tempfile::tempdir().unwrap();
        let barrier = std::sync::Arc::new(std::sync::Barrier::new(8));
        let handles: Vec<_> = (0..8)
            .map(|_| {
                let barrier = barrier.clone();
                let store = PreferencesStore::new(dir.path());
                std::thread::spawn(move || {
                    barrier.wait();
                    store.save(0, Preferences::default())
                })
            })
            .collect();
        let results: Vec<_> = handles.into_iter().map(|h| h.join().unwrap()).collect();
        assert_eq!(results.iter().filter(|r| r.is_ok()).count(), 1);
        assert_eq!(
            results
                .iter()
                .filter(|r| matches!(r, Err(PreferencesError::Conflict)))
                .count(),
            7
        );
    }
}
