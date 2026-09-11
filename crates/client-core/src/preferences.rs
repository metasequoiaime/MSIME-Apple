//! Versioned local preferences. Hosts supply a private application data directory.
//! All writers coordinate through the stable lock file, not the replaced data file.

use serde::{Deserialize, Serialize};
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use crate::voice::VoicePreferences;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum InputScheme {
    #[default]
    Quanpin,
    Shuangpin,
    Wubi,
    Japanese,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChineseScheme {
    Quanpin,
    Shuangpin,
    Wubi,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum PunctuationLock {
    #[default]
    Follow,
    Chinese,
    English,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum CandidateOrientation {
    Horizontal,
    #[default]
    Vertical,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct Preferences {
    pub scheme: InputScheme,
    /// Retained when the active scheme is Japanese. Absent in legacy documents.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_chinese_scheme: Option<ChineseScheme>,
    #[serde(default)]
    pub shuangpin_profile: ShuangpinProfile,
    pub candidate_page_size: u8,
    #[serde(default = "default_candidate_font_size")]
    pub candidate_font_size: u8,
    #[serde(default)]
    pub candidate_orientation: CandidateOrientation,
    #[serde(default = "default_candidate_skin")]
    pub candidate_skin: String,
    pub learning: bool,
    #[serde(default = "enabled_by_default")]
    pub autocorrect: bool,
    #[serde(default)]
    pub quanpin_helpcode: HelpcodePreferences,
    #[serde(default)]
    pub shuangpin_helpcode: HelpcodePreferences,
    pub chinese_punctuation: bool,
    #[serde(default = "enabled_by_default")]
    pub paired_punctuation: bool,
    #[serde(default)]
    pub punctuation_lock: PunctuationLock,
    #[serde(default)]
    pub navigation: NavigationPreferences,
    #[serde(default)]
    pub word_character: WordCharacterPreferences,
    #[serde(default)]
    pub frequency: FrequencyPreferences,
    #[serde(default)]
    pub mixed_input: MixedInputPreferences,
    #[serde(default)]
    pub local_modes: LocalModePreferences,
    /// Records copied text only when the host explicitly observes clipboard events.
    #[serde(default)]
    pub clipboard_history: bool,
    #[serde(default)]
    pub floating_toolbar: FloatingToolbarPreferences,
    #[serde(default)]
    pub voice: VoicePreferences,
}

/// Settings for the optional host-provided floating toolbar.
///
/// `scale` is stored as a percentage so the preferences remain exactly
/// comparable and portable across hosts. A value of 100 means 100%.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FloatingToolbarPreferences {
    pub enabled: bool,
    pub fullwidth: bool,
    pub punctuation: bool,
    pub character_set: bool,
    pub emoji: bool,
    pub screen_keyboard: bool,
    pub settings: bool,
    pub scale: u16,
    pub font_size: u8,
}

impl Default for FloatingToolbarPreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            fullwidth: true,
            punctuation: true,
            character_set: true,
            emoji: true,
            screen_keyboard: false,
            settings: true,
            scale: 100,
            font_size: 24,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct LocalModePreferences {
    pub unicode: bool,
    pub date_time: bool,
    pub quick_phrase: bool,
    pub emoji: bool,
    pub kaomoji: bool,
    pub super_jianpin: bool,
    pub temporary_english: bool,
    pub temporary_japanese: bool,
}

impl Default for LocalModePreferences {
    fn default() -> Self {
        Self {
            unicode: true,
            date_time: true,
            quick_phrase: true,
            emoji: true,
            kaomoji: true,
            super_jianpin: true,
            temporary_english: true,
            temporary_japanese: true,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct MixedInputPreferences {
    pub english: bool,
    pub minimum_prefix: u8,
    pub emoji: bool,
    pub kaomoji: bool,
}

impl Default for MixedInputPreferences {
    fn default() -> Self {
        Self {
            english: true,
            minimum_prefix: 2,
            emoji: false,
            kaomoji: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum FrequencyMode {
    Disabled,
    Pin,
    Halve,
    Linear,
    #[default]
    Promote,
}

impl FrequencyMode {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Disabled => "disabled",
            Self::Pin => "pin",
            Self::Halve => "halve",
            Self::Linear => "linear",
            Self::Promote => "promote",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct FrequencyPreferences {
    pub mode: FrequencyMode,
    pub trigger_count: u8,
    pub linear_step: u8,
}

impl Default for FrequencyPreferences {
    fn default() -> Self {
        Self {
            mode: FrequencyMode::Promote,
            trigger_count: 1,
            linear_step: 1,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum WordCharacterKeys {
    #[default]
    Brackets,
    MinusEqual,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(deny_unknown_fields)]
pub struct WordCharacterPreferences {
    pub enabled: bool,
    pub keys: WordCharacterKeys,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct NavigationPreferences {
    pub minus_equal: bool,
    pub comma_period: bool,
    pub brackets: bool,
    pub tab: bool,
    pub page_up_down: bool,
    pub arrows: bool,
}

impl Default for NavigationPreferences {
    fn default() -> Self {
        Self {
            minus_equal: true,
            comma_period: true,
            brackets: false,
            tab: true,
            page_up_down: true,
            arrows: true,
        }
    }
}

fn enabled_by_default() -> bool {
    true
}

fn default_candidate_font_size() -> u8 {
    18
}

fn default_candidate_skin() -> String {
    "fluent".to_owned()
}

impl Default for Preferences {
    fn default() -> Self {
        Self {
            scheme: InputScheme::default(),
            last_chinese_scheme: None,
            shuangpin_profile: ShuangpinProfile::default(),
            candidate_page_size: 5,
            candidate_font_size: default_candidate_font_size(),
            candidate_orientation: CandidateOrientation::default(),
            candidate_skin: default_candidate_skin(),
            learning: true,
            autocorrect: true,
            quanpin_helpcode: HelpcodePreferences::default(),
            shuangpin_helpcode: HelpcodePreferences::default(),
            chinese_punctuation: true,
            paired_punctuation: true,
            punctuation_lock: PunctuationLock::Follow,
            navigation: NavigationPreferences::default(),
            word_character: WordCharacterPreferences::default(),
            frequency: FrequencyPreferences::default(),
            mixed_input: MixedInputPreferences::default(),
            local_modes: LocalModePreferences::default(),
            clipboard_history: false,
            floating_toolbar: FloatingToolbarPreferences::default(),
            voice: VoicePreferences::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum ShuangpinProfile {
    #[default]
    Xiaohe,
    Ziranma,
    Shoudao,
    Microsoft,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case")]
pub enum HelpcodeSchema {
    Lantian,
    #[default]
    Ziranma,
    #[serde(rename = "shouyou2_0")]
    Shouyou2,
    Shouyouplus,
    Xiaohe,
}

impl HelpcodeSchema {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Lantian => "lantian",
            Self::Ziranma => "ziranma",
            Self::Shouyou2 => "shouyou2_0",
            Self::Shouyouplus => "shouyouplus",
            Self::Xiaohe => "xiaohe",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct HelpcodePreferences {
    pub enabled: bool,
    pub schema: HelpcodeSchema,
}

impl Default for HelpcodePreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            schema: HelpcodeSchema::default(),
        }
    }
}

impl Preferences {
    pub fn active_helpcode(&self) -> HelpcodePreferences {
        match self.scheme {
            InputScheme::Shuangpin => self.shuangpin_helpcode,
            InputScheme::Quanpin => self.quanpin_helpcode,
            _ => HelpcodePreferences {
                enabled: false,
                ..HelpcodePreferences::default()
            },
        }
    }

    pub fn validate(&self) -> Result<(), PreferencesError> {
        if !(1..=8).contains(&self.mixed_input.minimum_prefix) {
            return Err(PreferencesError::InvalidMixedInput);
        }
        if !(1..=10).contains(&self.frequency.trigger_count)
            || !(1..=10).contains(&self.frequency.linear_step)
        {
            return Err(PreferencesError::InvalidFrequency);
        }
        if !(1..=9).contains(&self.candidate_page_size) {
            return Err(PreferencesError::InvalidPageSize);
        }
        if !matches!(self.candidate_font_size, 16 | 18 | 20) {
            return Err(PreferencesError::InvalidCandidateFontSize);
        }
        if !matches!(self.floating_toolbar.scale, 75 | 100 | 125 | 150)
            || !matches!(
                self.floating_toolbar.font_size,
                16 | 18 | 20 | 22 | 24 | 26 | 28
            )
        {
            return Err(PreferencesError::InvalidFloatingToolbar);
        }
        if self.candidate_skin.is_empty()
            || self.candidate_skin.len() > 64
            || !self.candidate_skin.is_ascii()
            || !self
                .candidate_skin
                .bytes()
                .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'_' | b'-' | b'.'))
            || !self
                .candidate_skin
                .as_bytes()
                .first()
                .is_some_and(|byte| byte.is_ascii_alphanumeric())
        {
            return Err(PreferencesError::InvalidCandidateSkin);
        }
        let paging = match self.word_character.keys {
            WordCharacterKeys::Brackets => self.navigation.brackets,
            WordCharacterKeys::MinusEqual => self.navigation.minus_equal,
        };
        if self.word_character.enabled && paging {
            return Err(PreferencesError::ConflictingKeyBindings);
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
    #[error("candidate font size must be 16, 18, or 20")]
    InvalidCandidateFontSize,
    #[error("floating toolbar scale or font size is invalid")]
    InvalidFloatingToolbar,
    #[error("candidate skin identifier is invalid")]
    InvalidCandidateSkin,
    #[error("word-to-character and paging cannot use the same keys")]
    ConflictingKeyBindings,
    #[error("frequency trigger count and linear step must be between 1 and 10")]
    InvalidFrequency,
    #[error("mixed English minimum prefix must be between 1 and 8")]
    InvalidMixedInput,
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

    fn open_lock(&self) -> Result<File, PreferencesError> {
        fs::create_dir_all(&self.directory)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.directory.join("preferences.lock"))?;
        Ok(lock)
    }

    fn lock(&self) -> Result<File, PreferencesError> {
        let lock = self.open_lock()?;
        crate::file_lock::exclusive(&lock)?;
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

    /// None means the writer lock is busy; retry later without using defaults.
    /// File operations may still block on storage. Validation matches load().
    pub fn try_load(&self) -> Result<Option<PreferencesSnapshot>, PreferencesError> {
        let lock = self.open_lock()?;
        if !crate::file_lock::try_exclusive(&lock)? {
            return Ok(None);
        }
        self.read_locked().map(Some)
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
    fn local_mode_defaults_and_each_switch_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("local_modes");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.local_modes,
            LocalModePreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, key) in [
            "unicode",
            "date_time",
            "quick_phrase",
            "emoji",
            "kaomoji",
            "super_jianpin",
            "temporary_english",
            "temporary_japanese",
        ]
        .iter()
        .enumerate()
        {
            let mut value = serde_json::to_value(Preferences::default()).unwrap();
            value["local_modes"][*key] = false.into();
            let saved = store
                .save(revision as u64, serde_json::from_value(value).unwrap())
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn floating_toolbar_legacy_defaults_and_values_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("floating_toolbar");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.floating_toolbar,
            FloatingToolbarPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);

        let preferences = Preferences {
            floating_toolbar: FloatingToolbarPreferences {
                enabled: false,
                fullwidth: false,
                punctuation: true,
                character_set: false,
                emoji: false,
                screen_keyboard: true,
                settings: false,
                scale: 125,
                font_size: 28,
            },
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        assert_eq!(store.load().unwrap(), saved);

        for (scale, font_size) in [(74, 24), (151, 24), (100, 15), (100, 29)] {
            let mut invalid = saved.preferences.clone();
            invalid.floating_toolbar.scale = scale;
            invalid.floating_toolbar.font_size = font_size;
            assert!(matches!(
                store.save(saved.revision, invalid),
                Err(PreferencesError::InvalidFloatingToolbar)
            ));
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn mixed_input_legacy_roundtrip_and_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("mixed_input");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.mixed_input,
            MixedInputPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for mask in 0..8 {
            let preferences = Preferences {
                mixed_input: MixedInputPreferences {
                    english: mask & 1 != 0,
                    emoji: mask & 2 != 0,
                    kaomoji: mask & 4 != 0,
                    minimum_prefix: mask + 1,
                },
                ..Preferences::default()
            };
            let saved = store.save(u64::from(mask), preferences).unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let saved = store.load().unwrap();
        for value in [0, 9, 255] {
            let mut invalid = saved.preferences.clone();
            invalid.mixed_input.minimum_prefix = value;
            assert!(matches!(
                store.save(saved.revision, invalid),
                Err(PreferencesError::InvalidMixedInput)
            ));
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn frequency_legacy_defaults_modes_and_bounds() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("frequency");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.frequency,
            FrequencyPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, mode) in [
            FrequencyMode::Disabled,
            FrequencyMode::Pin,
            FrequencyMode::Halve,
            FrequencyMode::Linear,
            FrequencyMode::Promote,
        ]
        .into_iter()
        .enumerate()
        {
            let saved = store
                .save(
                    revision as u64,
                    Preferences {
                        frequency: FrequencyPreferences {
                            mode,
                            trigger_count: 10,
                            linear_step: 10,
                        },
                        ..Preferences::default()
                    },
                )
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let saved = store.load().unwrap();
        for value in [0, 11, 255] {
            for trigger in [true, false] {
                let mut preferences = Preferences::default();
                if trigger {
                    preferences.frequency.trigger_count = value;
                } else {
                    preferences.frequency.linear_step = value;
                }
                assert!(matches!(
                    store.save(saved.revision, preferences),
                    Err(PreferencesError::InvalidFrequency)
                ));
                assert_eq!(store.load().unwrap(), saved);
            }
        }
    }

    #[test]
    fn word_character_legacy_roundtrip_and_conflict_protection() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("word_character");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.word_character,
            WordCharacterPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, keys) in [WordCharacterKeys::Brackets, WordCharacterKeys::MinusEqual]
            .into_iter()
            .enumerate()
        {
            let mut preferences = Preferences {
                word_character: WordCharacterPreferences {
                    enabled: true,
                    keys,
                },
                ..Preferences::default()
            };
            preferences.navigation.brackets = false;
            preferences.navigation.minus_equal = false;
            let saved = store.save(revision as u64, preferences.clone()).unwrap();
            assert_eq!(store.load().unwrap(), saved);
            match keys {
                WordCharacterKeys::Brackets => preferences.navigation.brackets = true,
                WordCharacterKeys::MinusEqual => preferences.navigation.minus_equal = true,
            }
            assert!(matches!(
                store.save(saved.revision, preferences),
                Err(PreferencesError::ConflictingKeyBindings)
            ));
            assert_eq!(store.load().unwrap(), saved);
        }
    }

    #[test]
    fn navigation_defaults_and_independent_flags_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("navigation");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.navigation,
            NavigationPreferences::default()
        );
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        let preferences = Preferences {
            navigation: NavigationPreferences {
                minus_equal: false,
                comma_period: false,
                brackets: true,
                tab: false,
                page_up_down: false,
                arrows: false,
            },
            ..Preferences::default()
        };
        let saved = store.save(0, preferences).unwrap();
        assert_eq!(store.load().unwrap(), saved);
        let mut invalid = serde_json::to_value(saved).unwrap();
        invalid["preferences"]["navigation"]["tab"] = "invalid".into();
        let bytes = serde_json::to_vec(&invalid).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.save(1, Preferences::default()).is_err());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
    }

    #[test]
    fn remembered_chinese_scheme_roundtrips_without_changing_legacy_files() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let legacy = serde_json::to_vec(&PreferencesSnapshot::default()).unwrap();
        fs::write(store.path(), &legacy).unwrap();
        assert_eq!(store.load().unwrap().preferences.last_chinese_scheme, None);
        assert_eq!(fs::read(store.path()).unwrap(), legacy);
        for (revision, scheme) in [
            ChineseScheme::Quanpin,
            ChineseScheme::Shuangpin,
            ChineseScheme::Wubi,
        ]
        .into_iter()
        .enumerate()
        {
            let saved = store
                .save(
                    revision as u64,
                    Preferences {
                        scheme: InputScheme::Japanese,
                        last_chinese_scheme: Some(scheme),
                        ..Preferences::default()
                    },
                )
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
        }
        let mut invalid = serde_json::to_value(store.load().unwrap()).unwrap();
        invalid["preferences"]["last_chinese_scheme"] = "japanese".into();
        let bytes = serde_json::to_vec(&invalid).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.save(3, Preferences::default()).is_err());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
    }

    #[test]
    fn helpcode_legacy_defaults_and_independent_schemes_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        for key in ["quanpin_helpcode", "shuangpin_helpcode"] {
            legacy["preferences"].as_object_mut().unwrap().remove(key);
        }
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert_eq!(store.load().unwrap(), PreferencesSnapshot::default());
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        for (revision, schema) in [
            HelpcodeSchema::Lantian,
            HelpcodeSchema::Ziranma,
            HelpcodeSchema::Shouyou2,
            HelpcodeSchema::Shouyouplus,
            HelpcodeSchema::Xiaohe,
        ]
        .into_iter()
        .enumerate()
        {
            let preferences = Preferences {
                quanpin_helpcode: HelpcodePreferences {
                    enabled: false,
                    schema,
                },
                ..Preferences::default()
            };
            let saved = store.save(revision as u64, preferences).unwrap();
            assert_eq!(store.load().unwrap(), saved);
            assert_eq!(
                saved.preferences.shuangpin_helpcode,
                HelpcodePreferences::default()
            );
        }
        let unknown = fs::read_to_string(store.path())
            .unwrap()
            .replace("xiaohe", "unknown");
        fs::write(store.path(), &unknown).unwrap();
        assert!(store.save(5, Preferences::default()).is_err());
        assert_eq!(fs::read_to_string(store.path()).unwrap(), unknown);
    }

    #[test]
    fn autocorrect_legacy_default_and_disabled_roundtrip() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let mut legacy = serde_json::to_value(PreferencesSnapshot::default()).unwrap();
        legacy["preferences"]
            .as_object_mut()
            .unwrap()
            .remove("autocorrect");
        let bytes = serde_json::to_vec(&legacy).unwrap();
        fs::write(store.path(), &bytes).unwrap();
        assert!(store.load().unwrap().preferences.autocorrect);
        assert_eq!(fs::read(store.path()).unwrap(), bytes);
        let preferences = Preferences {
            autocorrect: false,
            ..Preferences::default()
        };
        store.save(0, preferences).unwrap();
        assert!(!store.load().unwrap().preferences.autocorrect);
    }

    #[test]
    fn shuangpin_profiles_preserve_legacy_files_and_reject_unknown_values() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        let legacy = r#"{"format_version":1,"revision":7,"preferences":{"scheme":"shuangpin","candidate_page_size":5,"learning":false,"chinese_punctuation":true}}"#;
        fs::write(store.path(), legacy).unwrap();
        assert_eq!(
            store.load().unwrap().preferences.shuangpin_profile,
            ShuangpinProfile::Xiaohe
        );
        assert_eq!(store.load().unwrap().preferences.candidate_font_size, 18);
        assert_eq!(store.load().unwrap().preferences.candidate_skin, "fluent");
        assert_eq!(
            store.load().unwrap().preferences.candidate_orientation,
            CandidateOrientation::Vertical
        );
        assert_eq!(fs::read_to_string(store.path()).unwrap(), legacy);
        let mut revision = 7;
        for profile in [
            ShuangpinProfile::Xiaohe,
            ShuangpinProfile::Ziranma,
            ShuangpinProfile::Shoudao,
            ShuangpinProfile::Microsoft,
        ] {
            let saved = store
                .save(
                    revision,
                    Preferences {
                        scheme: InputScheme::Shuangpin,
                        shuangpin_profile: profile,
                        ..Preferences::default()
                    },
                )
                .unwrap();
            assert_eq!(store.load().unwrap(), saved);
            revision = saved.revision;
        }
        let unknown = fs::read_to_string(store.path())
            .unwrap()
            .replace("microsoft", "future_profile");
        fs::write(store.path(), &unknown).unwrap();
        assert!(store.load().is_err());
        assert!(store.save(revision, Preferences::default()).is_err());
        assert_eq!(fs::read_to_string(store.path()).unwrap(), unknown);
    }

    #[test]
    fn try_load_distinguishes_busy_missing_and_corrupt() {
        let dir = tempfile::tempdir().unwrap();
        let store = PreferencesStore::new(dir.path());
        assert_eq!(
            store.try_load().unwrap(),
            Some(PreferencesSnapshot::default())
        );
        let lock = store.lock().unwrap();
        assert_eq!(store.try_load().unwrap(), None);
        drop(lock);
        let saved = store.save(0, Preferences::default()).unwrap();
        assert_eq!(store.try_load().unwrap(), Some(saved));
        fs::write(store.path(), "broken").unwrap();
        assert!(store.try_load().is_err());
        assert_eq!(fs::read_to_string(store.path()).unwrap(), "broken");
    }

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
        for size in [0, 15, 21, 255] {
            assert!(matches!(
                store.save(
                    1,
                    Preferences {
                        candidate_font_size: size,
                        ..Preferences::default()
                    }
                ),
                Err(PreferencesError::InvalidCandidateFontSize)
            ));
        }
        for skin in ["", "../escape", "-unsafe", "含中文"] {
            assert!(matches!(
                store.save(
                    1,
                    Preferences {
                        candidate_skin: skin.to_owned(),
                        ..Preferences::default()
                    }
                ),
                Err(PreferencesError::InvalidCandidateSkin)
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
