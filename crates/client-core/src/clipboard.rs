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
                    .filter(|v| valid(v))
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
        let bytes = serde_json::to_vec(&self.entries).expect("clipboard entries are serializable");
        let temp = self.path.with_extension("json.tmp");
        fs::write(&temp, bytes)?;
        fs::rename(temp, &self.path)
    }
}

fn valid(text: &str) -> bool {
    !text.is_empty() && text.len() <= MAX_TEXT_BYTES && !text.chars().any(char::is_control)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn persists_deduplicates_and_clears() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("clipboard_history.json");
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
}
