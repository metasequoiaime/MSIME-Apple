//! Bounded persistent clipboard history. Hosts decide which clipboard events to observe.

use std::fs;
use std::io::{Read, Write};
use std::path::PathBuf;

const MAX_ENTRIES: usize = 50;
const MAX_TEXT_BYTES: usize = 4096;
// JSON may escape every input byte as six ASCII bytes.
const MAX_HISTORY_BYTES: u64 = (MAX_ENTRIES * (MAX_TEXT_BYTES * 6 + 3) + 2) as u64;

#[derive(Debug, Clone)]
pub struct ClipboardHistoryStore {
    path: PathBuf,
    entries: Vec<String>,
}

impl ClipboardHistoryStore {
    pub fn open(path: impl Into<PathBuf>) -> Self {
        Self {
            path: path.into(),
            entries: Vec::new(),
        }
    }

    pub fn load(&mut self) -> std::io::Result<()> {
        match fs::File::open(&self.path) {
            Ok(file) => {
                let mut bytes = Vec::new();
                file.take(MAX_HISTORY_BYTES + 1).read_to_end(&mut bytes)?;
                if bytes.len() as u64 > MAX_HISTORY_BYTES {
                    return Err(std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        "clipboard history exceeds size limit",
                    ));
                }
                let values: Vec<String> = serde_json::from_slice(&bytes).map_err(|_| {
                    std::io::Error::new(
                        std::io::ErrorKind::InvalidData,
                        "invalid clipboard history document",
                    )
                })?;
                let mut entries = Vec::new();
                for value in values {
                    if valid(&value) && !entries.contains(&value) {
                        entries.push(value);
                        if entries.len() == MAX_ENTRIES {
                            break;
                        }
                    }
                }
                self.entries = entries;
                Ok(())
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                self.entries.clear();
                Ok(())
            }
            Err(error) => Err(error),
        }
    }

    pub fn entries(&self) -> &[String] {
        &self.entries
    }

    pub fn push(&mut self, text: String) -> std::io::Result<bool> {
        if !valid(&text) {
            return Ok(false);
        }
        let mut next = self.entries.clone();
        next.retain(|item| item != &text);
        next.insert(0, text);
        next.truncate(MAX_ENTRIES);
        self.persist(&next)?;
        self.entries = next;
        Ok(true)
    }

    pub fn clear(&mut self) -> std::io::Result<()> {
        match fs::remove_file(&self.path) {
            Ok(()) => {
                self.entries.clear();
                Ok(())
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                self.entries.clear();
                Ok(())
            }
            Err(error) => Err(error),
        }
    }

    fn persist(&self, entries: &[String]) -> std::io::Result<()> {
        let parent = self
            .path
            .parent()
            .filter(|p| !p.as_os_str().is_empty())
            .unwrap_or_else(|| std::path::Path::new("."));
        fs::create_dir_all(parent)?;
        let bytes = serde_json::to_vec(entries).expect("clipboard entries are serializable");
        // Unique temporary file (0600 on Unix); never remove the old file before replacement.
        let mut temp = tempfile::NamedTempFile::new_in(parent)?;
        temp.write_all(&bytes)?;
        temp.as_file().sync_all()?;
        temp.persist(&self.path).map_err(|error| error.error)?;
        Ok(())
    }
}

fn valid(text: &str) -> bool {
    !text.is_empty()
        && text.len() <= MAX_TEXT_BYTES
        && !text.chars().any(|character| {
            character == '\0'
                || (character.is_control() && !matches!(character, '\n' | '\r' | '\t'))
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn persists_deduplicates_and_clears() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("clipboard_history.json");
        let mut store = ClipboardHistoryStore::open(&path);
        assert!(store.push("second".into()).unwrap());
        assert!(store.push("first".into()).unwrap());
        assert!(store.push("second".into()).unwrap());
        let mut loaded = ClipboardHistoryStore::open(&path);
        loaded.load().unwrap();
        assert_eq!(loaded.entries(), &["second", "first"]);
        loaded.clear().unwrap();
        assert!(!path.exists());
    }

    #[test]
    fn preserves_multiline_text_and_rejects_unsafe_control_data() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("clipboard_history.json");
        let mut store = ClipboardHistoryStore::open(&path);
        assert!(store.push("line\nfeed\tvalue".into()).unwrap());
        assert!(!store.push("line\0feed".into()).unwrap());
        assert!(!store.push("line\u{0007}feed".into()).unwrap());
        assert!(!store.push("x".repeat(MAX_TEXT_BYTES + 1)).unwrap());
        assert_eq!(store.entries(), &["line\nfeed\tvalue"]);
        assert!(path.exists());
    }

    #[test]
    fn load_is_bounded_and_preserves_state_on_corrupt_documents() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.json");
        let mut store = ClipboardHistoryStore::open(&path);
        store.push("synthetic-kept".into()).unwrap();
        fs::write(&path, b"invalid synthetic document").unwrap();
        assert_eq!(
            store.load().unwrap_err().kind(),
            std::io::ErrorKind::InvalidData
        );
        assert_eq!(store.entries(), &["synthetic-kept"]);
        fs::File::create(&path)
            .unwrap()
            .set_len(MAX_HISTORY_BYTES + 1)
            .unwrap();
        assert_eq!(
            store.load().unwrap_err().kind(),
            std::io::ErrorKind::InvalidData
        );
        assert_eq!(store.entries(), &["synthetic-kept"]);
        fs::remove_file(&path).unwrap();
        store.load().unwrap();
        assert!(store.entries().is_empty());
    }

    #[test]
    fn load_deduplicates_before_applying_entry_limit() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.json");
        let mut values = vec!["synthetic-first".to_string(); 55];
        values.extend((0..60).map(|i| format!("synthetic-{i}")));
        fs::write(&path, serde_json::to_vec(&values).unwrap()).unwrap();
        let mut store = ClipboardHistoryStore::open(&path);
        store.load().unwrap();
        assert_eq!(store.entries().len(), MAX_ENTRIES);
        assert_eq!(store.entries()[0], "synthetic-first");
        assert_eq!(store.entries()[49], "synthetic-48");
    }

    #[test]
    fn failed_save_and_clear_keep_in_memory_history() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.json");
        let backup = directory.path().join("backup.json");
        let mut store = ClipboardHistoryStore::open(&path);
        store.push("synthetic-kept".into()).unwrap();
        fs::rename(&path, &backup).unwrap();
        fs::create_dir(&path).unwrap();
        assert!(store.push("synthetic-rejected".into()).is_err());
        assert_eq!(store.entries(), &["synthetic-kept"]);
        assert!(store.clear().is_err());
        assert_eq!(store.entries(), &["synthetic-kept"]);
        assert_eq!(fs::read(&backup).unwrap(), br#"["synthetic-kept"]"#);
        assert_eq!(fs::read_dir(directory.path()).unwrap().count(), 2);
    }

    #[test]
    #[cfg(unix)]
    fn replacement_history_is_owner_only() {
        use std::os::unix::fs::PermissionsExt;
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("history.json");
        fs::write(&path, b"[]").unwrap();
        fs::set_permissions(&path, fs::Permissions::from_mode(0o644)).unwrap();
        let mut store = ClipboardHistoryStore::open(&path);
        store.push("synthetic-private".into()).unwrap();
        assert_eq!(
            fs::metadata(&path).unwrap().permissions().mode() & 0o777,
            0o600
        );
    }
}
