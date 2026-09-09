//! Install trusted, pinned resource sets without replacing active generations.
//! Transport is injected by the host; filenames, lengths and hashes come from a
//! reviewed product lock, never from an untrusted downloaded manifest alone.

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use std::collections::HashSet;
use std::fs::{self, File, OpenOptions};
use std::io::{Read, Write};
use std::path::{Path, PathBuf};

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Artifact {
    pub name: String,
    pub url: String,
    pub sha256: String,
    pub size: u64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ResourceSet {
    /// Actual source of the data, independently of the Engine code revision.
    pub source_commit: String,
    pub artifacts: Vec<Artifact>,
}

#[derive(Debug, thiserror::Error)]
pub enum ResourceError {
    #[error("invalid pinned resource set")]
    InvalidManifest,
    #[error("resource length or digest mismatch")]
    Integrity,
    #[error("existing resource generation has unexpected files")]
    ExistingGeneration,
    #[error("resource storage or transport failed: {0}")]
    Io(#[from] std::io::Error),
}

impl ResourceSet {
    pub fn validate(&self) -> Result<(), ResourceError> {
        let hex = |text: &str, len| {
            text.len() == len
                && text
                    .bytes()
                    .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(&b))
        };
        if !hex(&self.source_commit, 40) || self.artifacts.is_empty() || self.artifacts.len() > 128
        {
            return Err(ResourceError::InvalidManifest);
        }
        let mut names = HashSet::new();
        for artifact in &self.artifacts {
            // A flat, portable resource layout. Reject aliases, traversal and device names.
            let stem = artifact
                .name
                .split('.')
                .next()
                .unwrap_or_default()
                .to_ascii_lowercase();
            let reserved = matches!(stem.as_str(), "con" | "prn" | "aux" | "nul")
                || (stem.len() == 4
                    && (stem.starts_with("com") || stem.starts_with("lpt"))
                    && stem.as_bytes()[3].is_ascii_digit());
            if artifact.name.is_empty()
                || artifact.name.len() > 128
                || artifact.name.starts_with('.')
                || artifact.name.ends_with('.')
                || !artifact
                    .name
                    .bytes()
                    .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b))
                || reserved
                || !names.insert(artifact.name.to_ascii_lowercase())
                || !hex(&artifact.sha256, 64)
                || artifact.size > 2 * 1024 * 1024 * 1024
                || !artifact.url.starts_with("https://")
            {
                return Err(ResourceError::InvalidManifest);
            }
        }
        Ok(())
    }

    pub fn generation(&self) -> Result<String, ResourceError> {
        self.validate()?;
        let encoded = serde_json::to_vec(self).map_err(|_| ResourceError::InvalidManifest)?;
        Ok(format!("{:x}", Sha256::digest(encoded)))
    }
}

pub struct ResourceStore {
    root: PathBuf,
}

impl ResourceStore {
    /// root is an application-owned directory, separate from user learning data.
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn install(
        &self,
        specification: &ResourceSet,
        mut fetch: impl FnMut(&Artifact) -> Result<Box<dyn Read>, std::io::Error>,
    ) -> Result<PathBuf, ResourceError> {
        let generation = specification.generation()?;
        fs::create_dir_all(&self.root)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.root.join("resources.lock"))?;
        lock.lock()?;
        let destination = self.root.join(generation);
        if fs::symlink_metadata(&destination).is_ok() {
            self.verify(&destination, specification)?;
            return Ok(destination);
        }
        let stage = tempfile::Builder::new()
            .prefix("incoming-")
            .tempdir_in(&self.root)?;
        for artifact in &specification.artifacts {
            let mut source = fetch(artifact)?;
            let mut output = File::create(stage.path().join(&artifact.name))?;
            copy_verified(source.as_mut(), &mut output, artifact)?;
            output.sync_all()?;
        }
        // Published directories are complete. Existing generations are never overwritten.
        fs::rename(stage.path(), &destination)?;
        Ok(destination)
    }

    pub fn verify(
        &self,
        directory: &Path,
        specification: &ResourceSet,
    ) -> Result<(), ResourceError> {
        specification.validate()?;
        if !fs::symlink_metadata(directory)?.file_type().is_dir() {
            return Err(ResourceError::ExistingGeneration);
        }
        let expected: HashSet<_> = specification
            .artifacts
            .iter()
            .map(|a| a.name.as_str())
            .collect();
        let mut count = 0;
        for entry in fs::read_dir(directory)? {
            let entry = entry?;
            if !entry.file_type()?.is_file()
                || !expected.contains(
                    entry
                        .file_name()
                        .to_str()
                        .ok_or(ResourceError::ExistingGeneration)?,
                )
            {
                return Err(ResourceError::ExistingGeneration);
            }
            count += 1;
        }
        if count != expected.len() {
            return Err(ResourceError::ExistingGeneration);
        }
        for artifact in &specification.artifacts {
            let mut input = File::open(directory.join(&artifact.name))?;
            copy_verified(&mut input, &mut std::io::sink(), artifact)?;
        }
        Ok(())
    }
}

fn copy_verified(
    input: &mut dyn Read,
    output: &mut dyn Write,
    artifact: &Artifact,
) -> Result<(), ResourceError> {
    let mut hash = Sha256::new();
    let mut remaining = artifact.size;
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let limit = buffer.len().min((remaining + 1) as usize);
        let count = input.read(&mut buffer[..limit])?;
        if count == 0 {
            break;
        }
        if count as u64 > remaining {
            return Err(ResourceError::Integrity);
        }
        remaining -= count as u64;
        hash.update(&buffer[..count]);
        output.write_all(&buffer[..count])?;
    }
    if remaining != 0 || format!("{:x}", hash.finalize()) != artifact.sha256 {
        return Err(ResourceError::Integrity);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;
    fn specification() -> ResourceSet {
        ResourceSet {
            source_commit: "a".repeat(40),
            artifacts: vec![Artifact {
                name: "msime.db".into(),
                url: "https://example.invalid/msime.db".into(),
                sha256: format!("{:x}", Sha256::digest(b"fixture")),
                size: 7,
            }],
        }
    }
    fn source(bytes: &[u8]) -> Box<dyn Read> {
        Box::new(Cursor::new(bytes.to_vec()))
    }
    #[test]
    fn publishes_complete_generation_and_verifies_cached_bytes() {
        let root = tempfile::tempdir().unwrap();
        let store = ResourceStore::new(root.path());
        let spec = specification();
        let path = store.install(&spec, |_| Ok(source(b"fixture"))).unwrap();
        assert_eq!(fs::read(path.join("msime.db")).unwrap(), b"fixture");
        assert_eq!(
            store
                .install(&spec, |_| panic!("must not fetch cached resources"))
                .unwrap(),
            path
        );
        fs::write(path.join("msime.db"), b"damaged").unwrap();
        assert!(matches!(
            store.install(&spec, |_| panic!("must not overwrite active resources")),
            Err(ResourceError::Integrity)
        ));
    }
    #[test]
    fn rejects_truncated_oversized_and_wrong_digest_without_publishing() {
        for bytes in [b"short".as_slice(), b"fixture-extra", b"invalid"] {
            let root = tempfile::tempdir().unwrap();
            let store = ResourceStore::new(root.path());
            let spec = specification();
            assert!(matches!(
                store.install(&spec, |_| Ok(source(bytes))),
                Err(ResourceError::Integrity)
            ));
            assert!(!root.path().join(spec.generation().unwrap()).exists());
            assert_eq!(fs::read_dir(root.path()).unwrap().count(), 1);
        }
    }
    #[test]
    fn failed_upgrade_preserves_previous_generation() {
        let root = tempfile::tempdir().unwrap();
        let store = ResourceStore::new(root.path());
        let mut spec = specification();
        let old = store.install(&spec, |_| Ok(source(b"fixture"))).unwrap();
        spec.source_commit = "b".repeat(40);
        assert!(store
            .install(&spec, |_| Err(std::io::Error::other("offline")))
            .is_err());
        assert_eq!(fs::read(old.join("msime.db")).unwrap(), b"fixture");
    }
    #[test]
    fn rejects_path_aliases_and_duplicate_names() {
        for name in [
            "../secret",
            "a/b",
            "a\\b",
            "CON",
            "nul.db",
            "msime.db.",
            ".hidden",
        ] {
            let mut spec = specification();
            spec.artifacts[0].name = name.into();
            assert!(spec.validate().is_err());
        }
        let mut spec = specification();
        let mut duplicate = spec.artifacts[0].clone();
        duplicate.name = "MSIME.DB".into();
        spec.artifacts.push(duplicate);
        assert!(spec.validate().is_err());
    }
}
