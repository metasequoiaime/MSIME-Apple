//! Bounded persistent clipboard history. Hosts decide which clipboard events to observe.

use std::fs;
use std::path::PathBuf;

const MAX_ENTRIES: usize = 50;
const MAX_TEXT_BYTES: usize = 4096;

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
        match fs::read(&self.path) {
            Ok(bytes) => {
                let values: Vec<String> = serde_json::from_slice(&bytes).unwrap_or_default();
                self.entries = values
                    .into_iter()
                    .filter(|value| valid(value))
                    .take(MAX_ENTRIES)
                    .collect();
                Ok(())
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
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
        self.entries.retain(|item| item != &text);
        self.entries.insert(0, text);
        self.entries.truncate(MAX_ENTRIES);
        self.persist()?;
        Ok(true)
    }

    pub fn clear(&mut self) -> std::io::Result<()> {
        self.entries.clear();
        match fs::remove_file(&self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(error),
        }
    }

    fn persist(&self) -> std::io::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)?;
        }
        let bytes = serde_json::to_vec(&self.entries).expect("clipboard entries are serializable");
        let temp = self.path.with_extension("json.tmp");
        fs::write(&temp, bytes)?;
        match fs::rename(&temp, &self.path) {
            Ok(()) => Ok(()),
            Err(error) if error.kind() == std::io::ErrorKind::AlreadyExists => {
                // Windows does not replace an existing destination with rename(). The history
                // is disposable state, so replace it only after the complete temp file exists.
                fs::remove_file(&self.path)?;
                fs::rename(temp, &self.path)
            }
            Err(error) => Err(error),
        }
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
}
