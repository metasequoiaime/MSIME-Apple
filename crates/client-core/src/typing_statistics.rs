//! Private aggregate typing statistics shared by native hosts and settings UI.
//! Committed text is classified in memory and is never serialized.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::PathBuf;
use std::time::SystemTime;
use unicode_general_category::{get_general_category, GeneralCategory};
use unicode_segmentation::UnicodeSegmentation;

const MAX_RETAINED_DAYS: usize = 366;
const MAX_DOCUMENT_BYTES: u64 = 1_048_576;
const MAX_COMMIT_BYTES: usize = 40_000;
const MAX_COMMIT_SCALARS: usize = 10_000;
const MAX_COUNT: u64 = 9_000_000_000_000_000;

fn enabled_by_default() -> bool {
    true
}

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum TypingSource {
    Quanpin,
    NineKey,
    Shuangpin,
    Ziranma,
    Microsoft,
    Shoudao,
    Wubi,
    Japanese,
    Handwriting,
    English,
    Local,
    Ai,
    Reply,
    Voice,
    Unknown,
}

impl TypingSource {
    fn id(self) -> &'static str {
        match self {
            Self::Quanpin => "quanpin",
            Self::NineKey => "nineKey",
            Self::Shuangpin => "shuangpin",
            Self::Ziranma => "ziranma",
            Self::Microsoft => "microsoft",
            Self::Shoudao => "shoudao",
            Self::Wubi => "wubi",
            Self::Japanese => "japanese",
            Self::Handwriting => "handwriting",
            Self::English => "english",
            Self::Local => "local",
            Self::Ai => "ai",
            Self::Reply => "reply",
            Self::Voice => "voice",
            Self::Unknown => "unknown",
        }
    }
}

#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct TypingBreakdown {
    #[serde(default)]
    pub characters: BTreeMap<String, u64>,
    #[serde(default)]
    pub sources: BTreeMap<String, u64>,
}

impl TypingBreakdown {
    fn add(&mut self, character: &str, source: TypingSource) -> Result<(), TypingStatisticsError> {
        checked_increment(&mut self.characters, character, 1)?;
        checked_increment(&mut self.sources, source.id(), 1)
    }

    fn merge(&mut self, other: &Self) -> Result<(), TypingStatisticsError> {
        for (key, count) in &other.characters {
            checked_increment(&mut self.characters, key, *count)?;
        }
        for (key, count) in &other.sources {
            checked_increment(&mut self.sources, key, *count)?;
        }
        Ok(())
    }

    pub fn including_unclassified(&self, total: u64) -> Self {
        let mut value = self.clone();
        let character_total = value
            .characters
            .values()
            .fold(0_u64, |sum, count| sum.saturating_add(*count));
        let source_total = value
            .sources
            .values()
            .fold(0_u64, |sum, count| sum.saturating_add(*count));
        *value.characters.entry("unknown".to_owned()).or_default() +=
            total.saturating_sub(character_total);
        *value.sources.entry("unknown".to_owned()).or_default() +=
            total.saturating_sub(source_total);
        value
    }
}

#[derive(Clone, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct TypingStatistics {
    #[serde(default = "enabled_by_default")]
    pub enabled: bool,
    #[serde(default)]
    pub total: u64,
    #[serde(default)]
    pub days: BTreeMap<String, u64>,
    #[serde(default)]
    pub detail: TypingBreakdown,
    #[serde(default)]
    pub daily_details: BTreeMap<String, TypingBreakdown>,
}

impl Default for TypingStatistics {
    fn default() -> Self {
        Self {
            enabled: true,
            total: 0,
            days: BTreeMap::new(),
            detail: TypingBreakdown::default(),
            daily_details: BTreeMap::new(),
        }
    }
}

impl TypingStatistics {
    pub fn breakdown(&self, days: Option<&[String]>) -> TypingBreakdown {
        let Some(days) = days else {
            return self.detail.including_unclassified(self.total);
        };
        let mut result = TypingBreakdown::default();
        let mut total = 0_u64;
        for day in days {
            total = total.saturating_add(self.days.get(day).copied().unwrap_or(0));
            if let Some(detail) = self.daily_details.get(day) {
                let _ = result.merge(detail);
            }
        }
        result.including_unclassified(total)
    }

    fn validate(&self) -> Result<(), TypingStatisticsError> {
        if self.total > MAX_COUNT || self.days.len() > MAX_RETAINED_DAYS {
            return Err(TypingStatisticsError::InvalidDocument);
        }
        validate_counts(&self.detail, self.total)?;
        if self.daily_details.len() > MAX_RETAINED_DAYS {
            return Err(TypingStatisticsError::InvalidDocument);
        }
        for (day, count) in &self.days {
            validate_day(day)?;
            if *count > self.total {
                return Err(TypingStatisticsError::InvalidDocument);
            }
            if let Some(detail) = self.daily_details.get(day) {
                validate_counts(detail, *count)?;
            }
        }
        if self
            .daily_details
            .keys()
            .any(|day| !self.days.contains_key(day))
        {
            return Err(TypingStatisticsError::InvalidDocument);
        }
        Ok(())
    }
}

#[derive(Debug, thiserror::Error)]
pub enum TypingStatisticsError {
    #[error("typing statistics storage failed: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid typing statistics document: {0}")]
    Json(#[from] serde_json::Error),
    #[error("invalid typing statistics day")]
    InvalidDay,
    #[error("typing statistics commit is too large")]
    CommitTooLarge,
    #[error("typing statistics document is invalid")]
    InvalidDocument,
    #[error("typing statistics count exhausted")]
    CountExhausted,
}

#[derive(Clone, Debug)]
pub struct TypingStatisticsStore {
    directory: PathBuf,
}

impl TypingStatisticsStore {
    pub fn new(directory: impl Into<PathBuf>) -> Self {
        Self {
            directory: directory.into(),
        }
    }

    fn path(&self) -> PathBuf {
        self.directory.join("typing-statistics.json")
    }

    fn lock(&self) -> Result<File, TypingStatisticsError> {
        fs::create_dir_all(&self.directory)?;
        let lock = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(self.directory.join("typing-statistics.lock"))?;
        crate::file_lock::exclusive(&lock)?;
        Ok(lock)
    }

    fn read_locked(&self) -> Result<TypingStatistics, TypingStatisticsError> {
        let path = self.path();
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {
                return Ok(TypingStatistics::default());
            }
            Err(error) => return Err(error.into()),
        };
        if bytes.len() as u64 > MAX_DOCUMENT_BYTES {
            return Err(TypingStatisticsError::InvalidDocument);
        }
        let value: TypingStatistics = serde_json::from_slice(&bytes)?;
        value.validate()?;
        Ok(value)
    }

    fn write_locked(&self, value: &TypingStatistics) -> Result<(), TypingStatisticsError> {
        value.validate()?;
        let bytes = serde_json::to_vec(value)?;
        let mut temporary = tempfile::NamedTempFile::new_in(&self.directory)?;
        temporary.write_all(&bytes)?;
        temporary.as_file().sync_all()?;
        temporary
            .persist(self.path())
            .map(|_| ())
            .map_err(|error| TypingStatisticsError::Io(error.error))
    }

    pub fn load(&self) -> Result<TypingStatistics, TypingStatisticsError> {
        let _lock = self.lock()?;
        self.read_locked()
    }

    pub fn last_written(&self) -> Result<Option<SystemTime>, TypingStatisticsError> {
        match fs::metadata(self.path()) {
            Ok(metadata) => Ok(metadata.modified().ok()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(None),
            Err(error) => Err(error.into()),
        }
    }

    pub fn record(
        &self,
        text: &str,
        source: TypingSource,
        day: &str,
    ) -> Result<u64, TypingStatisticsError> {
        validate_day(day)?;
        if text.len() > MAX_COMMIT_BYTES || text.chars().count() > MAX_COMMIT_SCALARS {
            return Err(TypingStatisticsError::CommitTooLarge);
        }
        let mut addition = TypingBreakdown::default();
        let mut count = 0_u64;
        for grapheme in text.graphemes(true) {
            if grapheme.chars().all(char::is_whitespace) {
                continue;
            }
            addition.add(classify(grapheme), source)?;
            count += 1;
        }
        if count == 0 {
            return Ok(0);
        }
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        if !value.enabled {
            return Ok(0);
        }
        value.total = value
            .total
            .checked_add(count)
            .filter(|total| *total <= MAX_COUNT)
            .ok_or(TypingStatisticsError::CountExhausted)?;
        checked_increment(&mut value.days, day, count)?;
        value.detail.merge(&addition)?;
        value
            .daily_details
            .entry(day.to_owned())
            .or_default()
            .merge(&addition)?;
        while value.days.len() > MAX_RETAINED_DAYS {
            let oldest = value.days.keys().next().cloned().expect("nonempty days");
            value.days.remove(&oldest);
            value.daily_details.remove(&oldest);
        }
        self.write_locked(&value)?;
        Ok(count)
    }

    pub fn set_enabled(&self, enabled: bool) -> Result<TypingStatistics, TypingStatisticsError> {
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        value.enabled = enabled;
        self.write_locked(&value)?;
        Ok(value)
    }

    pub fn reset(&self) -> Result<TypingStatistics, TypingStatisticsError> {
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        value.total = 0;
        value.days.clear();
        value.detail = TypingBreakdown::default();
        value.daily_details.clear();
        self.write_locked(&value)?;
        Ok(value)
    }
}

fn checked_increment(
    values: &mut BTreeMap<String, u64>,
    key: &str,
    amount: u64,
) -> Result<(), TypingStatisticsError> {
    let value = values.entry(key.to_owned()).or_default();
    *value = value
        .checked_add(amount)
        .filter(|count| *count <= MAX_COUNT)
        .ok_or(TypingStatisticsError::CountExhausted)?;
    Ok(())
}

fn validate_counts(value: &TypingBreakdown, total: u64) -> Result<(), TypingStatisticsError> {
    for values in [&value.characters, &value.sources] {
        if values.len() > 64
            || values.keys().any(|key| {
                key.is_empty()
                    || key.len() > 32
                    || !key
                        .bytes()
                        .all(|byte| byte.is_ascii_alphanumeric() || byte == b'_')
            })
            || values.values().any(|count| *count > total)
            || values
                .values()
                .try_fold(0_u64, |sum, count| sum.checked_add(*count))
                .is_none_or(|sum| sum > total)
        {
            return Err(TypingStatisticsError::InvalidDocument);
        }
    }
    Ok(())
}

fn validate_day(day: &str) -> Result<(), TypingStatisticsError> {
    let bytes = day.as_bytes();
    let valid = bytes.len() == 10
        && bytes[4] == b'-'
        && bytes[7] == b'-'
        && bytes
            .iter()
            .enumerate()
            .all(|(index, byte)| index == 4 || index == 7 || byte.is_ascii_digit())
        && day[5..7]
            .parse::<u8>()
            .is_ok_and(|month| (1..=12).contains(&month))
        && day[8..10]
            .parse::<u8>()
            .is_ok_and(|date| (1..=31).contains(&date));
    valid.then_some(()).ok_or(TypingStatisticsError::InvalidDay)
}

fn classify(grapheme: &str) -> &'static str {
    let mut scalars = grapheme.chars();
    let Some(first) = scalars.next() else {
        return "symbol";
    };
    let code = first as u32;
    if is_han(code) {
        return "han";
    }
    if is_emoji(grapheme) {
        return "emoji";
    }
    match get_general_category(first) {
        GeneralCategory::DecimalNumber => "number",
        GeneralCategory::UppercaseLetter
        | GeneralCategory::LowercaseLetter
        | GeneralCategory::TitlecaseLetter
        | GeneralCategory::ModifierLetter
        | GeneralCategory::OtherLetter => {
            if is_latin(code) {
                "latin"
            } else {
                "otherLetter"
            }
        }
        GeneralCategory::ConnectorPunctuation
        | GeneralCategory::DashPunctuation
        | GeneralCategory::OpenPunctuation
        | GeneralCategory::ClosePunctuation
        | GeneralCategory::InitialPunctuation
        | GeneralCategory::FinalPunctuation
        | GeneralCategory::OtherPunctuation => "punctuation",
        _ => "symbol",
    }
}

fn is_han(code: u32) -> bool {
    (0x3400..=0x4dbf).contains(&code)
        || (0x4e00..=0x9fff).contains(&code)
        || (0xf900..=0xfaff).contains(&code)
        || (0x20000..=0x323af).contains(&code)
}

fn is_latin(code: u32) -> bool {
    (0x41..=0x5a).contains(&code)
        || (0x61..=0x7a).contains(&code)
        || (0xc0..=0x24f).contains(&code)
        || (0x1e00..=0x1eff).contains(&code)
        || (0xab30..=0xab6f).contains(&code)
        || (0xff21..=0xff3a).contains(&code)
        || (0xff41..=0xff5a).contains(&code)
}

fn is_emoji(grapheme: &str) -> bool {
    grapheme.chars().any(|scalar| {
        let code = scalar as u32;
        (0x1f000..=0x1faff).contains(&code)
            || (0x2600..=0x27bf).contains(&code)
            || code == 0x20e3
            || code == 0xfe0f
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn records_graphemes_categories_and_sources_without_text() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        assert_eq!(
            store
                .record(
                    "汉𠮷Aée\u{301}９1，!👨‍👩‍👧‍👦1️⃣あЖ+ \n",
                    TypingSource::NineKey,
                    "2026-09-07",
                )
                .unwrap(),
            14
        );
        let value = store.load().unwrap();
        assert_eq!(value.total, 14);
        assert_eq!(value.detail.characters["han"], 2);
        assert_eq!(value.detail.characters["latin"], 3);
        assert_eq!(value.detail.characters["number"], 2);
        assert_eq!(value.detail.characters["punctuation"], 2);
        assert_eq!(value.detail.characters["emoji"], 2);
        assert_eq!(value.detail.characters["otherLetter"], 2);
        assert_eq!(value.detail.characters["symbol"], 1);
        assert_eq!(value.detail.sources["nineKey"], 14);
        let persisted =
            fs::read_to_string(directory.path().join("typing-statistics.json")).unwrap();
        assert!(!persisted.contains('汉'));
        assert!(persisted.contains("nineKey\":14"));
    }

    #[test]
    fn migrates_legacy_totals_and_preserves_pause_on_reset() {
        let directory = tempfile::tempdir().unwrap();
        fs::write(
            directory.path().join("typing-statistics.json"),
            r#"{"enabled":true,"total":12,"days":{"2026-09-07":12}}"#,
        )
        .unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        let legacy = store.load().unwrap();
        assert_eq!(legacy.breakdown(None).characters["unknown"], 12);
        store.set_enabled(false).unwrap();
        assert_eq!(
            store
                .record("ignored", TypingSource::English, "2026-09-07")
                .unwrap(),
            0
        );
        assert_eq!(store.load().unwrap().total, 12);
        let reset = store.reset().unwrap();
        assert!(!reset.enabled);
        assert_eq!(reset.total, 0);
        assert!(reset.days.is_empty());
    }

    #[test]
    fn serializes_writers_and_bounds_daily_history() {
        let directory = tempfile::tempdir().unwrap();
        let store = Arc::new(TypingStatisticsStore::new(directory.path()));
        let writers = (0..50)
            .map(|_| {
                let store = Arc::clone(&store);
                std::thread::spawn(move || {
                    store
                        .record("字", TypingSource::Quanpin, "2026-01-01")
                        .unwrap();
                })
            })
            .collect::<Vec<_>>();
        for writer in writers {
            writer.join().unwrap();
        }
        for offset in 1..=370 {
            let year = 2026 + (offset / 336);
            let day_of_year = offset % 336;
            let month = day_of_year / 28 + 1;
            let day = day_of_year % 28 + 1;
            store
                .record(
                    "字",
                    TypingSource::Quanpin,
                    &format!("{year:04}-{month:02}-{day:02}"),
                )
                .unwrap();
        }
        let value = store.load().unwrap();
        assert_eq!(value.days.len(), MAX_RETAINED_DAYS);
        assert_eq!(value.daily_details.len(), MAX_RETAINED_DAYS);
        assert_eq!(value.total, 420);
        assert_eq!(value.detail.characters["han"], 420);
    }

    #[test]
    fn rejects_invalid_dates_and_documents_without_overwriting() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        assert!(matches!(
            store.record("x", TypingSource::English, "2026-13-01"),
            Err(TypingStatisticsError::InvalidDay)
        ));
        let path = directory.path().join("typing-statistics.json");
        fs::write(&path, r#"{"enabled":true,"total":1,"days":{},"detail":{"characters":{"latin":2},"sources":{}},"dailyDetails":{}}"#).unwrap();
        assert!(matches!(
            store.load(),
            Err(TypingStatisticsError::InvalidDocument)
        ));
        assert!(fs::read_to_string(path).unwrap().contains("\"latin\":2"));
    }
}
