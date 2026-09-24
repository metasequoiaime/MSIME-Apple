//! Private aggregate typing statistics shared by native hosts and settings UI.
//! Committed text is classified in memory and is never serialized.

use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs::{self, File, OpenOptions};
use std::io::Write;
use std::path::{Path, PathBuf};
use std::time::SystemTime;
use unicode_general_category::{get_general_category, GeneralCategory};
use unicode_segmentation::UnicodeSegmentation;

const MAX_RETAINED_DAYS: usize = 366;

/// Only a guard against loading a hostile or garbage file, not a retention limit. It must stay far above anything `Forever` can produce, because a document over it cannot be read at all and the whole history is lost with it; a day costs a few hundred bytes, so 64 MiB covers centuries.
const MAX_DOCUMENT_BYTES: u64 = 64 * 1_048_576;
const MAX_COMMIT_BYTES: usize = 40_000;
const MAX_COMMIT_SCALARS: usize = 10_000;
const MAX_COUNT: u64 = 9_000_000_000_000_000;
/// Buckets in a day, one per local hour.
pub const HOURS: usize = 24;
/// A day cannot hold more active time than it has milliseconds.
const MAX_ACTIVE_MS_PER_DAY: u64 = 24 * 60 * 60 * 1000;
/// A pause of at most this much between two consecutive commits counts as active typing time.
///
/// Taken from the Windows baseline, which calibrated it on real input: at five seconds ordinary
/// thinking pauses were counted as typing and the speed reading came out too low. It is the one
/// number here that decides what "active" means, so it is a constant with a reason rather than a
/// literal in the middle of `record`.
const ACTIVE_GAP_LIMIT_MS: u64 = 10_000;

/// Statistics are off until the user turns them on.
///
/// The Windows baseline ships them disabled and says so in its own feature list, and it is the
/// right way round for something that counts what a person types: a feature like this should be
/// asked for rather than opted out of. A document written before this field existed keeps
/// whatever it says; only a fresh profile gets the default.
fn enabled_by_default() -> bool {
    false
}

/// How long recorded days are kept.
///
/// Copied from the Windows baseline's `[statistics] retention`, including that an unrecognised
/// value is read as `Forever`: a preference this side does not understand must not be taken as
/// permission to delete anything.
#[derive(Clone, Copy, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum StatisticsRetention {
    #[default]
    #[serde(rename = "forever")]
    Forever,
    #[serde(rename = "30d")]
    Days30,
    #[serde(rename = "90d")]
    Days90,
    #[serde(rename = "180d")]
    Days180,
    #[serde(rename = "365d")]
    Days365,
}

impl StatisticsRetention {
    /// The window in days, or `None` for "keep everything".
    pub fn days(self) -> Option<u32> {
        match self {
            Self::Forever => None,
            Self::Days30 => Some(30),
            Self::Days90 => Some(90),
            Self::Days180 => Some(180),
            Self::Days365 => Some(365),
        }
    }

    /// Parse the stored spelling. Anything else is `Forever`, never a shorter window.
    pub fn parse(value: &str) -> Self {
        match value {
            "30d" => Self::Days30,
            "90d" => Self::Days90,
            "180d" => Self::Days180,
            "365d" => Self::Days365,
            _ => Self::Forever,
        }
    }
}

/// An unknown retention value is `Forever` rather than a parse failure: a damaged or newer
/// preference must not make the whole document unreadable, and must never delete more.
fn retention_or_forever<'de, D>(deserializer: D) -> Result<StatisticsRetention, D::Error>
where
    D: serde::Deserializer<'de>,
{
    let value = String::deserialize(deserializer).unwrap_or_default();
    Ok(StatisticsRetention::parse(&value))
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

/// Where in the candidate list a commit came from, counted and nothing else.
///
/// This is the field counterpart of the evaluation sets' top-1: `ranks[0]` over the total is how
/// often the first candidate was the one wanted, measured on what the user actually types rather
/// than on 60 hand-written sentences. No text, no pinyin and no context are involved, which is
/// what makes it safe to keep — the same rule the rest of this module follows.
///
/// A candidate page holds nine, so ranks past that are counted together: beyond the first page the
/// distinction between the eleventh and the twelfth says nothing anyone would act on.
#[derive(Clone, Debug, Default, Deserialize, Eq, PartialEq, Serialize)]
pub struct SelectionCounts {
    /// Commits from positions 1 through `RANKS`, `ranks[0]` being the first candidate.
    #[serde(default)]
    pub ranks: Vec<u64>,
    /// Commits from further down the list than `RANKS`.
    #[serde(default)]
    pub beyond: u64,
}

/// One candidate page. Positions past this are counted in `beyond`.
pub const RANKS: usize = 9;

impl SelectionCounts {
    fn add(&mut self, position: usize) -> Result<(), TypingStatisticsError> {
        if position == 0 {
            return Err(TypingStatisticsError::InvalidPosition);
        }
        if position > RANKS {
            self.beyond = self
                .beyond
                .checked_add(1)
                .filter(|count| *count <= MAX_COUNT)
                .ok_or(TypingStatisticsError::CountExhausted)?;
            return Ok(());
        }
        if self.ranks.len() < RANKS {
            self.ranks.resize(RANKS, 0);
        }
        let slot = &mut self.ranks[position - 1];
        *slot = slot
            .checked_add(1)
            .filter(|count| *count <= MAX_COUNT)
            .ok_or(TypingStatisticsError::CountExhausted)?;
        Ok(())
    }

    /// Commits counted here, which is the denominator for any rate drawn from `ranks`.
    pub fn total(&self) -> u64 {
        self.ranks
            .iter()
            .fold(self.beyond, |sum, count| sum.saturating_add(*count))
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
    /// Absent from files written before this existed, which `default` turns into an empty
    /// histogram rather than a parse failure.
    ///
    /// Aggregate only, with no per-day axis, and that is a decision rather than an omission. A
    /// day here would have to be the user's day to sit beside `daily_details`, and the host is
    /// the only thing that knows which day that is — `record` takes one as an argument for
    /// exactly that reason. Candidate selection reaches this crate through a call that carries no
    /// day and would need six platform signatures changed to carry one, and a UTC day quietly
    /// disagreeing with the local day next to it is worse than no axis at all. The rate this
    /// exists to give — how often the first candidate was the right one — does not need one.
    #[serde(default)]
    pub selections: SelectionCounts,
    /// Active typing time per day, in milliseconds.
    ///
    /// Active means the gap to the previous commit was positive and no longer than
    /// [`ACTIVE_GAP_LIMIT_MS`]; anything longer is a break and contributes nothing. It exists to
    /// be a denominator: characters alone say how much was typed, not how fast, and wall-clock
    /// time between the first and last commit of a day would divide by the whole working day.
    ///
    /// A day absent here has no measured active time, which is not the same as zero characters —
    /// documents written before this existed have counts for their days and no entry here, and
    /// every metric derived from it has to treat that as "unknown" rather than "instant".
    #[serde(default)]
    pub daily_active_ms: BTreeMap<String, u64>,
    /// Characters per local hour, [`HOURS`] buckets per day.
    ///
    /// The hour comes from the host for the same reason the day does: only the host knows which
    /// timezone the user is in, and an hour axis quietly disagreeing with the day beside it would
    /// be worse than no axis. A host that does not send one still records characters; its days
    /// simply have no hourly breakdown.
    #[serde(default)]
    pub daily_hours: BTreeMap<String, Vec<u64>>,
    /// Milliseconds since the Unix epoch of the last counted commit.
    ///
    /// State, not history: every commit overwrites it, so it says when typing last happened and
    /// nothing about what was typed or when anything before it was. It has to be in the file
    /// because the store is constructed per call and has nowhere else to keep the previous
    /// commit's instant, which is the only thing the gap can be measured against.
    #[serde(default)]
    pub last_commit_ms: u64,
    /// How long recorded days are kept.
    #[serde(default, deserialize_with = "retention_or_forever")]
    pub retention: StatisticsRetention,
    /// The last day the retention window was applied.
    ///
    /// The baseline prunes on the first write of each day rather than on every write, so this is
    /// what "first" is measured against. It is a day key, not a clock reading.
    #[serde(default)]
    pub last_pruned_day: String,
}

impl Default for TypingStatistics {
    fn default() -> Self {
        Self {
            // Same answer as the serde default, and it has to be: this is what a missing file
            // returns, which is exactly the fresh profile the default is about.
            enabled: enabled_by_default(),
            total: 0,
            days: BTreeMap::new(),
            detail: TypingBreakdown::default(),
            daily_details: BTreeMap::new(),
            selections: SelectionCounts::default(),
            daily_active_ms: BTreeMap::new(),
            daily_hours: BTreeMap::new(),
            last_commit_ms: 0,
            retention: StatisticsRetention::Forever,
            last_pruned_day: String::new(),
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
        // No cap on the number of days: `Forever` keeps every day, as the baseline's stats_daily does, and the document size limit in `read_locked` is what bounds a file.
        if self.total > MAX_COUNT {
            return Err(TypingStatisticsError::InvalidDocument);
        }
        validate_counts(&self.detail, self.total)?;
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
        for (day, active_ms) in &self.daily_active_ms {
            // A day that has active time but no characters is not a document this code can
            // produce, and letting it through would put a day on the calendar that nobody typed
            // on.
            if !self.days.contains_key(day) || *active_ms > MAX_ACTIVE_MS_PER_DAY {
                return Err(TypingStatisticsError::InvalidDocument);
            }
        }
        for (day, hours) in &self.daily_hours {
            let Some(total) = self.days.get(day) else {
                return Err(TypingStatisticsError::InvalidDocument);
            };
            // Not equality: days recorded before hosts sent an hour have characters and no
            // buckets, so the buckets can only ever be a subset of the day.
            if hours.len() != HOURS
                || hours
                    .iter()
                    .try_fold(0_u64, |sum, count| sum.checked_add(*count))
                    .is_none_or(|sum| sum > *total)
            {
                return Err(TypingStatisticsError::InvalidDocument);
            }
        }
        Ok(())
    }

    /// Drop every recorded day outside the retention window, counting back from `today`.
    ///
    /// The comparison is on the day key, which sorts as a date because it is `YYYY-MM-DD`; no
    /// calendar arithmetic is needed beyond producing the boundary. `Forever` removes nothing,
    /// and a day in the future - a clock that was wrong when it was recorded - is kept rather
    /// than silently deleted, because the alternative is losing real typing to a bad clock.
    pub fn apply_retention(&mut self, today: &str) {
        let Some(days) = self.retention.days() else {
            return;
        };
        let Some(boundary) = day_before(today, days) else {
            return;
        };
        // Like the baseline's ClearThrough, which deletes the stats_daily rows its overview sums, a cleanup takes the pruned days out of the running totals too, so "累计", the category split and the daily average cover the retained window. A legacy day without a breakdown only lowers `total`; `breakdown(None)` reports the rest as unclassified.
        for (_, count) in self.days.range(..boundary.clone()) {
            self.total = self.total.saturating_sub(*count);
        }
        for (_, detail) in self.daily_details.range(..boundary.clone()) {
            for (key, count) in &detail.characters {
                if let Some(value) = self.detail.characters.get_mut(key) {
                    *value = value.saturating_sub(*count);
                }
            }
            for (key, count) in &detail.sources {
                if let Some(value) = self.detail.sources.get_mut(key) {
                    *value = value.saturating_sub(*count);
                }
            }
        }
        self.days.retain(|day, _| *day >= boundary);
        self.daily_details.retain(|day, _| *day >= boundary);
        self.daily_active_ms.retain(|day, _| *day >= boundary);
        self.daily_hours.retain(|day, _| *day >= boundary);
        // Subtraction keeps whatever `total` and `detail` hold beyond the per-day records, which a document written by an older build can have. Where that leaves the counters out of step with each other - `total` below the retained days, or a category sum above `total` - validate() would reject the document this write produces, so fall back to what the retained days themselves say.
        let retained = self
            .days
            .values()
            .fold(0_u64, |sum, count| sum.saturating_add(*count));
        self.total = self.total.max(retained);
        let sum = |values: &BTreeMap<String, u64>| {
            values
                .values()
                .fold(0_u64, |sum, count| sum.saturating_add(*count))
        };
        if sum(&self.detail.characters) > self.total || sum(&self.detail.sources) > self.total {
            let mut rebuilt = TypingBreakdown::default();
            for detail in self.daily_details.values() {
                let _ = rebuilt.merge(detail);
            }
            self.detail = rebuilt;
        }
    }

    /// Active milliseconds recorded for `day`, or `None` when that day predates the measurement.
    pub fn active_ms(&self, day: &str) -> Option<u64> {
        self.daily_active_ms.get(day).copied()
    }

    /// The day's per-hour character counts, or `None` when the host sent no hour for it.
    pub fn hours(&self, day: &str) -> Option<&[u64]> {
        self.daily_hours.get(day).map(Vec::as_slice)
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
    #[error("candidate position is not one-based")]
    InvalidPosition,
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

    /// Where the statistics file lives, for hosts that offer to reveal it in a file manager.
    pub fn directory(&self) -> &Path {
        &self.directory
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

    /// Moves a valid legacy statistics document into this store without
    /// replacing a document already created by the shared host.
    pub fn migrate_from(
        &self,
        legacy_directory: impl AsRef<Path>,
    ) -> Result<bool, TypingStatisticsError> {
        let legacy_directory = legacy_directory.as_ref();
        if legacy_directory == self.directory {
            return Ok(false);
        }
        let _destination_lock = self.lock()?;
        if self.path().try_exists()? {
            return Ok(false);
        }

        let legacy = Self::new(legacy_directory);
        let _legacy_lock = legacy.lock()?;
        if self.path().try_exists()? || !legacy.path().try_exists()? {
            return Ok(false);
        }
        let _ = legacy.read_locked()?;
        fs::rename(legacy.path(), self.path())?;
        Ok(true)
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

    /// Count one commit's characters against `day`, and the gap since the previous commit as
    /// active time.
    ///
    /// `hour` is the local hour the commit happened in. `None` records the characters without an
    /// hourly breakdown, which is what a host that cannot resolve a local hour should send rather
    /// than guessing one.
    pub fn record(
        &self,
        text: &str,
        source: TypingSource,
        day: &str,
        hour: Option<u8>,
    ) -> Result<u64, TypingStatisticsError> {
        self.record_at(text, source, day, hour, epoch_millis(SystemTime::now()))
    }

    /// `record` with the instant supplied, so the active-time rules can be tested without
    /// sleeping. Production always passes the current time.
    pub fn record_at(
        &self,
        text: &str,
        source: TypingSource,
        day: &str,
        hour: Option<u8>,
        now_ms: u64,
    ) -> Result<u64, TypingStatisticsError> {
        validate_day(day)?;
        if text.len() > MAX_COMMIT_BYTES || text.chars().count() > MAX_COMMIT_SCALARS {
            return Err(TypingStatisticsError::CommitTooLarge);
        }
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        if !value.enabled {
            return Ok(0);
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

        // Attribute the gap to the day and hour of *this* commit, the way the Windows baseline
        // does: the pause belongs to the typing it precedes, and a session that crosses midnight
        // therefore leaves its last pause on the new day rather than extending the old one.
        let active_ms = active_gap_ms(value.last_commit_ms, now_ms);
        if active_ms > 0 {
            let day_active = value.daily_active_ms.entry(day.to_owned()).or_default();
            *day_active = day_active
                .saturating_add(active_ms)
                .min(MAX_ACTIVE_MS_PER_DAY);
        }
        // Never moves backwards. A clock set back would otherwise make every later commit look
        // like it followed a huge pause, and the first one after the correction would be counted
        // as a fresh session instead of the continuation it is.
        if now_ms > value.last_commit_ms {
            value.last_commit_ms = now_ms;
        }

        if let Some(hour) = hour.filter(|hour| usize::from(*hour) < HOURS) {
            let buckets = value
                .daily_hours
                .entry(day.to_owned())
                .or_insert_with(|| vec![0; HOURS]);
            // A file edited by hand could carry a short vector; resize rather than panic on the
            // index, because a malformed bucket list must not cost the user the count itself.
            if buckets.len() != HOURS {
                buckets.resize(HOURS, 0);
            }
            let bucket = &mut buckets[usize::from(hour)];
            *bucket = bucket
                .checked_add(count)
                .filter(|count| *count <= MAX_COUNT)
                .ok_or(TypingStatisticsError::CountExhausted)?;
        }

        // Keep the hard safety cap independent of the optional retention preference. A document
        // can be written by an older host (or with `forever`) and must still never grow without
        // bound. Prune before applying the calendar window so all four per-day maps stay aligned.
        while value.days.len() > MAX_RETAINED_DAYS {
            let oldest = value.days.keys().next().cloned().expect("nonempty days");
            value.days.remove(&oldest);
            value.daily_details.remove(&oldest);
            value.daily_active_ms.remove(&oldest);
            value.daily_hours.remove(&oldest);
        }
        // The retention setting is the only thing that deletes days beyond this safety cap,
        // matching the baseline's RetentionCutoff/ClearThrough. It runs on the first write of
        // each day; doing it on every write would read the whole history on every commit.
        if value.last_pruned_day != day {
            value.apply_retention(day);
            value.last_pruned_day = day.to_owned();
        }
        self.write_locked(&value)?;
        Ok(count)
    }

    /// Count one commit by the one-based position it was chosen from.
    ///
    /// Separate from `record` because the two count different things: `record` counts characters,
    /// this counts commits, and dividing one by the other would mean nothing. The enable flag and
    /// the lock are shared, so turning statistics off turns this off with them and no second
    /// switch appears in settings for a user to misread.
    pub fn record_selection(&self, position: usize) -> Result<(), TypingStatisticsError> {
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        if !value.enabled {
            return Ok(());
        }
        value.selections.add(position)?;
        self.write_locked(&value)?;
        Ok(())
    }

    pub fn set_enabled(&self, enabled: bool) -> Result<TypingStatistics, TypingStatisticsError> {
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        value.enabled = enabled;
        self.write_locked(&value)?;
        Ok(value)
    }

    /// Choose how long recorded days are kept.
    ///
    /// `today` is the caller's local day, for the same reason `record` takes one. A window that
    /// has just been narrowed applies immediately rather than at the next day boundary: the user
    /// asked for those days to be gone, and waiting would leave them visible on the page they
    /// asked from.
    pub fn set_retention(
        &self,
        retention: StatisticsRetention,
        today: &str,
    ) -> Result<TypingStatistics, TypingStatisticsError> {
        validate_day(today)?;
        let _lock = self.lock()?;
        let mut value = self.read_locked()?;
        value.retention = retention;
        value.apply_retention(today);
        value.last_pruned_day = today.to_owned();
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
        // Reset means reset. Leaving the selection histogram behind would keep counting after a
        // user asked for it to stop existing, which is the one thing this module must not do.
        value.selections = SelectionCounts::default();
        value.daily_active_ms.clear();
        value.daily_hours.clear();
        // Including when typing last happened: it is the only field that survives a reset by
        // saying anything about the user at all.
        value.last_commit_ms = 0;
        self.write_locked(&value)?;
        Ok(value)
    }
}

/// Milliseconds since the Unix epoch, saturating at zero for clocks set before 1970.
fn epoch_millis(time: SystemTime) -> u64 {
    time.duration_since(SystemTime::UNIX_EPOCH)
        .map(|elapsed| u64::try_from(elapsed.as_millis()).unwrap_or(u64::MAX))
        .unwrap_or(0)
}

/// How much of the gap between two commits counts as active typing.
///
/// Zero for the first commit ever (`previous` is 0), for a gap longer than the limit, and for any
/// non-positive gap — which covers both a clock set backwards and two commits landing in the same
/// millisecond.
fn active_gap_ms(previous_ms: u64, now_ms: u64) -> u64 {
    if previous_ms == 0 || now_ms <= previous_ms {
        return 0;
    }
    let gap = now_ms - previous_ms;
    if gap > ACTIVE_GAP_LIMIT_MS {
        return 0;
    }
    gap
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

/// The day key `days` days before `day`, or `None` when `day` is not a date.
fn day_before(day: &str, days: u32) -> Option<String> {
    crate::calendar::shift_day(day, -i64::from(days))
}

fn validate_day(day: &str) -> Result<(), TypingStatisticsError> {
    crate::calendar::is_valid_day(day)
        .then_some(())
        .ok_or(TypingStatisticsError::InvalidDay)
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
mod selection_tests {
    use super::*;

    fn store() -> (tempfile::TempDir, TypingStatisticsStore) {
        let directory = tempfile::tempdir().expect("tempdir");
        let store = TypingStatisticsStore::new(directory.path());
        // These tests are about counting, not about the default. Statistics ship off.
        store.set_enabled(true).expect("enable");
        (directory, store)
    }

    #[test]
    fn counts_by_position_and_folds_the_tail() {
        let (_directory, store) = store();
        for position in [1, 1, 1, 2, 9, 10, 40] {
            store.record_selection(position).expect("record");
        }
        let value = store.load().expect("load");
        assert_eq!(value.selections.ranks[0], 3);
        assert_eq!(value.selections.ranks[1], 1);
        assert_eq!(value.selections.ranks[8], 1);
        // Tenth and fortieth are both past a page and are not told apart.
        assert_eq!(value.selections.beyond, 2);
        assert_eq!(value.selections.total(), 7);
    }

    #[test]
    fn rejects_a_zero_position() {
        let (_directory, store) = store();
        assert!(matches!(
            store.record_selection(0),
            Err(TypingStatisticsError::InvalidPosition)
        ));
    }

    #[test]
    fn the_shared_switch_and_reset_cover_it() {
        let (_directory, store) = store();
        store.record_selection(1).expect("record");
        store.set_enabled(false).expect("disable");
        store.record_selection(1).expect("record while off");
        assert_eq!(store.load().expect("load").selections.total(), 1);

        store.set_enabled(true).expect("enable");
        store.record_selection(3).expect("record");
        let value = store.reset().expect("reset");
        assert_eq!(value.selections.total(), 0);
    }

    #[test]
    fn a_file_written_before_this_existed_still_loads() {
        let (directory, store) = store();
        std::fs::write(
            directory.path().join("typing-statistics.json"),
            br#"{"enabled":true,"total":5,"days":{},"detail":{},"dailyDetails":{}}"#,
        )
        .expect("write");
        let value = store.load().expect("load");
        assert_eq!(value.total, 5);
        assert_eq!(value.selections.total(), 0);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::Arc;

    #[test]
    fn records_graphemes_categories_and_sources_without_text() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        store.set_enabled(true).unwrap();
        assert_eq!(
            store
                .record(
                    "汉𠮷Aée\u{301}９1，!👨‍👩‍👧‍👦1️⃣あЖ+ \n",
                    TypingSource::NineKey,
                    "2026-09-07",
                    Some(9),
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
                .record("ignored", TypingSource::English, "2026-09-07", Some(9))
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
    fn moves_a_valid_legacy_store_without_replacing_shared_statistics() {
        let root = tempfile::tempdir().unwrap();
        let legacy = TypingStatisticsStore::new(root.path());
        legacy.set_enabled(true).unwrap();
        legacy
            .record("old", TypingSource::English, "2026-09-07", Some(9))
            .unwrap();
        let shared_directory = root.path().join("MSIME");
        let shared = TypingStatisticsStore::new(&shared_directory);

        assert!(shared.migrate_from(root.path()).unwrap());
        assert!(!root.path().join("typing-statistics.json").exists());
        assert_eq!(shared.load().unwrap().total, 3);

        // Its document was moved away, so as far as the store is concerned this is a fresh
        // profile again - and a fresh profile has statistics off.
        legacy.set_enabled(true).unwrap();
        legacy
            .record("legacy", TypingSource::English, "2026-09-08", Some(9))
            .unwrap();
        assert!(!shared.migrate_from(root.path()).unwrap());
        assert_eq!(shared.load().unwrap().total, 3);
        assert_eq!(legacy.load().unwrap().total, 6);
    }

    #[test]
    fn serializes_writers_and_keeps_every_day_under_forever() {
        let directory = tempfile::tempdir().unwrap();
        let store = Arc::new(TypingStatisticsStore::new(directory.path()));
        store.set_enabled(true).unwrap();
        let writers = (0..50)
            .map(|_| {
                let store = Arc::clone(&store);
                std::thread::spawn(move || {
                    store
                        .record("字", TypingSource::Quanpin, "2026-01-01", Some(9))
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
                    Some(9),
                )
                .unwrap();
        }
        let value = store.load().unwrap();
        // Forever is the default and deletes nothing: the 2026-01-01 the writers shared plus the 370 later days.
        assert_eq!(value.retention, StatisticsRetention::Forever);
        assert_eq!(value.days.len(), 371);
        assert_eq!(value.daily_details.len(), 371);
        assert_eq!(value.total, 420);
        assert_eq!(value.detail.characters["han"], 420);
    }

    #[test]
    fn rejects_invalid_dates_and_documents_without_overwriting() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        assert!(matches!(
            store.record("x", TypingSource::English, "2026-13-01", Some(9)),
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

    #[test]
    fn active_time_counts_only_the_gaps_that_are_still_typing() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        store.set_enabled(true).unwrap();
        let day = "2026-09-21";
        // The first commit has nothing to measure against, so it contributes no active time -
        // otherwise the epoch itself would be counted as one enormous pause.
        store
            .record_at("a", TypingSource::Quanpin, day, Some(9), 1_000)
            .unwrap();
        assert_eq!(store.load().unwrap().active_ms(day), None);

        store
            .record_at("b", TypingSource::Quanpin, day, Some(9), 4_000)
            .unwrap();
        assert_eq!(store.load().unwrap().active_ms(day), Some(3_000));

        // Exactly at the limit still counts; one millisecond past it is a break.
        store
            .record_at(
                "c",
                TypingSource::Quanpin,
                day,
                Some(9),
                4_000 + ACTIVE_GAP_LIMIT_MS,
            )
            .unwrap();
        assert_eq!(
            store.load().unwrap().active_ms(day),
            Some(3_000 + ACTIVE_GAP_LIMIT_MS)
        );
        let after_break = 4_000 + ACTIVE_GAP_LIMIT_MS + ACTIVE_GAP_LIMIT_MS + 1;
        store
            .record_at("d", TypingSource::Quanpin, day, Some(9), after_break)
            .unwrap();
        assert_eq!(
            store.load().unwrap().active_ms(day),
            Some(3_000 + ACTIVE_GAP_LIMIT_MS)
        );

        // A clock set backwards adds nothing and does not move the mark backwards; the next
        // commit at a sane instant must not be measured against the rolled-back one.
        store
            .record_at("e", TypingSource::Quanpin, day, Some(9), 500)
            .unwrap();
        let rolled_back = store.load().unwrap();
        assert_eq!(
            rolled_back.active_ms(day),
            Some(3_000 + ACTIVE_GAP_LIMIT_MS)
        );
        assert_eq!(rolled_back.last_commit_ms, after_break);

        // Two commits in the same millisecond are not a gap.
        store
            .record_at("f", TypingSource::Quanpin, day, Some(9), after_break)
            .unwrap();
        assert_eq!(
            store.load().unwrap().active_ms(day),
            Some(3_000 + ACTIVE_GAP_LIMIT_MS)
        );
    }

    #[test]
    fn hourly_buckets_come_from_the_host_and_are_optional() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        store.set_enabled(true).unwrap();
        let day = "2026-09-21";
        store
            .record_at("ab", TypingSource::Quanpin, day, Some(0), 1_000)
            .unwrap();
        store
            .record_at("c", TypingSource::Quanpin, day, Some(23), 2_000)
            .unwrap();
        // No hour: the characters still count, the day simply has no breakdown for them. The
        // buckets are therefore a subset of the day's total, never equal to it in general.
        store
            .record_at("de", TypingSource::Quanpin, day, None, 3_000)
            .unwrap();
        // Out of range is dropped rather than folded into a neighbouring hour, which would put
        // typing on the chart at a time it did not happen.
        store
            .record_at("f", TypingSource::Quanpin, day, Some(24), 4_000)
            .unwrap();

        let value = store.load().unwrap();
        let hours = value.hours(day).unwrap();
        assert_eq!(hours.len(), HOURS);
        assert_eq!(hours[0], 2);
        assert_eq!(hours[23], 1);
        assert_eq!(hours.iter().sum::<u64>(), 3);
        assert_eq!(value.days[day], 6);
        assert_eq!(value.hours("2026-09-20"), None);
    }

    #[test]
    fn retention_and_reset_take_the_activity_axes_with_them() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        store.set_enabled(true).unwrap();
        // 28-day months and 12-month years, so the synthetic calendar stays valid past a year of recorded days without pulling in a date library.
        let recorded = 367;
        let mut last_day = String::new();
        for offset in 0..recorded {
            last_day = synthetic_day(offset);
            store
                .record_at(
                    "字",
                    TypingSource::Quanpin,
                    &last_day,
                    Some(9),
                    1_000 + offset as u64 * 500,
                )
                .unwrap();
        }
        let value = store.load().unwrap();
        // Forever keeps every day on every axis.
        assert_eq!(value.days.len(), recorded);
        assert_eq!(value.daily_details.len(), recorded);
        assert_eq!(value.daily_hours.len(), recorded);
        // The first commit has no gap to measure, so it is the one day without active time.
        assert_eq!(value.daily_active_ms.len(), recorded - 1);

        let boundary = day_before(&last_day, 365).unwrap();
        let narrowed = store
            .set_retention(StatisticsRetention::Days365, &last_day)
            .unwrap();
        assert!(narrowed.days.len() < recorded);
        assert!(!narrowed.days.is_empty());
        // Pruning a day has to drop every axis keyed by it, or validate() rejects the document it just wrote and the user loses the whole history to a stale entry.
        assert!(narrowed.days.keys().all(|day| *day >= boundary));
        assert!(narrowed.daily_details.keys().all(|day| *day >= boundary));
        assert!(narrowed.daily_active_ms.keys().all(|day| *day >= boundary));
        assert!(narrowed.daily_hours.keys().all(|day| *day >= boundary));
        assert!(narrowed
            .daily_details
            .keys()
            .all(|day| narrowed.days.contains_key(day)));
        assert!(narrowed
            .daily_active_ms
            .keys()
            .all(|day| narrowed.days.contains_key(day)));
        assert!(narrowed
            .daily_hours
            .keys()
            .all(|day| narrowed.days.contains_key(day)));
        // One character a day, so the running total is the number of retained days.
        assert_eq!(narrowed.total, narrowed.days.len() as u64);
        assert_eq!(narrowed.detail.characters["han"], narrowed.total);
        assert!(store.load().is_ok());

        let reset = store.reset().unwrap();
        assert!(reset.daily_active_ms.is_empty());
        assert!(reset.daily_hours.is_empty());
        // Reset means reset: when typing last happened is the one field that would otherwise
        // survive and still say something about the user.
        assert_eq!(reset.last_commit_ms, 0);
    }

    /// A valid `YYYY-MM-DD` for `offset` on a calendar of 28-day months and 12-month years.
    fn synthetic_day(offset: usize) -> String {
        format!(
            "{:04}-{:02}-{:02}",
            2026 + offset / 336,
            (offset % 336) / 28 + 1,
            offset % 28 + 1
        )
    }

    #[test]
    fn forever_never_prunes_even_across_many_first_writes_of_a_day() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        store.set_enabled(true).unwrap();
        // Every day is a new day, so every write runs the first-write-of-a-day retention pass.
        let recorded = 800;
        for offset in 0..recorded {
            store
                .record_at(
                    "字",
                    TypingSource::Quanpin,
                    &synthetic_day(offset),
                    Some(9),
                    1_000 + offset as u64 * 500,
                )
                .unwrap();
        }
        let value = store.load().unwrap();
        assert_eq!(value.retention, StatisticsRetention::Forever);
        assert_eq!(value.days.len(), recorded);
        assert_eq!(value.daily_details.len(), recorded);
        assert_eq!(value.daily_hours.len(), recorded);
        assert_eq!(value.last_pruned_day, synthetic_day(recorded - 1));
    }

    #[test]
    fn a_document_with_more_than_a_year_of_days_loads() {
        let directory = tempfile::tempdir().unwrap();
        let days = (0..500)
            .map(|offset| format!("\"{}\":1", synthetic_day(offset)))
            .collect::<Vec<_>>()
            .join(",");
        fs::write(
            directory.path().join("typing-statistics.json"),
            format!(r#"{{"enabled":true,"total":500,"days":{{{days}}}}}"#),
        )
        .unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        let value = store.load().unwrap();
        assert_eq!(value.days.len(), 500);
        assert_eq!(value.total, 500);
    }

    #[test]
    fn the_retention_boundary_is_calendar_arithmetic() {
        // Across a month, a year and a leap day, which is what a subtraction on the day number
        // alone would get wrong.
        assert_eq!(day_before("2026-09-21", 0).as_deref(), Some("2026-09-21"));
        assert_eq!(day_before("2026-09-21", 30).as_deref(), Some("2026-08-22"));
        assert_eq!(day_before("2026-01-05", 30).as_deref(), Some("2025-12-06"));
        // 2028 is a leap year: 2028-03-01 minus one day is the 29th.
        assert_eq!(day_before("2028-03-01", 1).as_deref(), Some("2028-02-29"));
        assert_eq!(day_before("2026-03-01", 1).as_deref(), Some("2026-02-28"));
        assert_eq!(day_before("2027-01-01", 365).as_deref(), Some("2026-01-01"));
        // Not a date at all.
        assert_eq!(day_before("not-a-day", 30), None);
    }

    #[test]
    fn an_unknown_retention_keeps_everything() {
        // A preference this build does not understand must never be read as permission to delete.
        assert_eq!(
            StatisticsRetention::parse("30d"),
            StatisticsRetention::Days30
        );
        assert_eq!(
            StatisticsRetention::parse("365d"),
            StatisticsRetention::Days365
        );
        assert_eq!(
            StatisticsRetention::parse("7d"),
            StatisticsRetention::Forever
        );
        assert_eq!(StatisticsRetention::parse(""), StatisticsRetention::Forever);
        assert_eq!(StatisticsRetention::Forever.days(), None);
        assert_eq!(StatisticsRetention::Days90.days(), Some(90));
        // And the same through the document, where a damaged value must not make the whole file
        // unreadable either.
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("typing-statistics.json");
        fs::write(
            &path,
            r#"{"enabled":true,"total":1,"days":{"2026-09-21":1},"retention":"7d"}"#,
        )
        .unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        assert_eq!(
            store.load().unwrap().retention,
            StatisticsRetention::Forever
        );
    }

    #[test]
    fn retention_drops_days_outside_the_window_on_the_first_write_of_a_day() {
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        store.set_enabled(true).unwrap();
        for day in ["2026-06-01", "2026-08-25", "2026-09-20"] {
            store
                .record_at("字", TypingSource::Quanpin, day, Some(9), 1_000)
                .unwrap();
        }
        assert_eq!(store.load().unwrap().days.len(), 3);

        // Choosing a window applies it at once: the user asked for those days to be gone, and
        // waiting for the next day boundary would leave them on the page they asked from.
        let narrowed = store
            .set_retention(StatisticsRetention::Days30, "2026-09-21")
            .unwrap();
        assert_eq!(
            narrowed.days.keys().collect::<Vec<_>>(),
            ["2026-08-25", "2026-09-20"]
        );
        assert!(!narrowed.daily_details.contains_key("2026-06-01"));
        assert!(!narrowed.daily_hours.contains_key("2026-06-01"));
        // As with the baseline's ClearThrough, the pruned day leaves the running totals as well, so "累计" and its categories cover the retained window.
        assert_eq!(narrowed.total, 2);
        let mut retained = TypingBreakdown::default();
        for detail in narrowed.daily_details.values() {
            retained.merge(detail).unwrap();
        }
        assert_eq!(narrowed.detail, retained);
        assert_eq!(narrowed.detail.characters["han"], 2);
        assert_eq!(narrowed.detail.sources["quanpin"], 2);

        // A later day carries the window with it: 2026-08-25 falls out once "today" moves past
        // thirty days from it.
        store
            .record_at("字", TypingSource::Quanpin, "2026-09-25", Some(9), 2_000)
            .unwrap();
        let moved = store.load().unwrap();
        assert!(!moved.days.contains_key("2026-08-25"));
        assert!(moved.days.contains_key("2026-09-20"));
        assert_eq!(moved.total, 2);
        assert_eq!(moved.detail.characters["han"], 2);

        // The mark that says the window has been applied for this day.
        //
        // That pruning happens on the *first* write of a day rather than on every write is a
        // cost property, not an observable one: the boundary only depends on the day, so running
        // it on every commit would reach the same result by doing more work. This asserts the
        // mark is kept; nothing here can tell the two apart, and an assertion claiming to would
        // be pinning nothing.
        assert_eq!(moved.last_pruned_day, "2026-09-25");

        // Forever removes nothing.
        let kept = store
            .set_retention(StatisticsRetention::Forever, "2027-12-31")
            .unwrap();
        assert_eq!(kept.days.len(), 2);
    }

    #[test]
    fn pruning_a_day_without_a_breakdown_only_lowers_the_total() {
        let directory = tempfile::tempdir().unwrap();
        fs::write(
            directory.path().join("typing-statistics.json"),
            r#"{"enabled":true,"total":5,"days":{"2026-06-01":3,"2026-09-20":2},"detail":{"characters":{"han":2},"sources":{"quanpin":2}},"dailyDetails":{"2026-09-20":{"characters":{"han":2},"sources":{"quanpin":2}}}}"#,
        )
        .unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        let narrowed = store
            .set_retention(StatisticsRetention::Days30, "2026-09-21")
            .unwrap();
        assert_eq!(narrowed.days.keys().collect::<Vec<_>>(), ["2026-09-20"]);
        assert_eq!(narrowed.total, 2);
        assert_eq!(narrowed.detail.characters["han"], 2);
        assert_eq!(narrowed.detail.sources["quanpin"], 2);
        assert!(store.load().is_ok());
    }

    #[test]
    fn pruning_rebuilds_categories_that_would_exceed_the_new_total() {
        // An older build could keep categories for days it had already dropped. Subtracting only the pruned day's own records would then leave a category sum above the lowered total, which validate() rejects.
        let directory = tempfile::tempdir().unwrap();
        fs::write(
            directory.path().join("typing-statistics.json"),
            r#"{"enabled":true,"total":10,"days":{"2026-06-01":3,"2026-09-20":2},"detail":{"characters":{"han":9},"sources":{"quanpin":9}},"dailyDetails":{"2026-09-20":{"characters":{"han":2},"sources":{"quanpin":2}}}}"#,
        )
        .unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        let narrowed = store
            .set_retention(StatisticsRetention::Days30, "2026-09-21")
            .unwrap();
        assert_eq!(narrowed.total, 7);
        assert_eq!(narrowed.detail.characters["han"], 2);
        assert_eq!(narrowed.detail.sources["quanpin"], 2);
        assert!(store.load().is_ok());
    }

    #[test]
    fn statistics_are_off_until_they_are_asked_for() {
        // The baseline ships them disabled and says so in its feature list. A fresh profile must
        // not start counting what someone types before they have said yes.
        let directory = tempfile::tempdir().unwrap();
        let store = TypingStatisticsStore::new(directory.path());
        assert!(!store.load().unwrap().enabled);
        assert_eq!(
            store
                .record("字", TypingSource::Quanpin, "2026-09-21", Some(9))
                .unwrap(),
            0
        );
        assert_eq!(store.load().unwrap().total, 0);
        // A document written before this field existed keeps what it says.
        fs::write(
            directory.path().join("typing-statistics.json"),
            r#"{"enabled":true,"total":5,"days":{"2026-09-21":5}}"#,
        )
        .unwrap();
        assert!(store.load().unwrap().enabled);
    }

    #[test]
    fn rejects_activity_axes_that_do_not_match_the_days() {
        let directory = tempfile::tempdir().unwrap();
        let path = directory.path().join("typing-statistics.json");
        let store = TypingStatisticsStore::new(directory.path());
        let cases = [
            // Active time on a day with no characters.
            r#"{"enabled":true,"total":1,"days":{"2026-09-21":1},"dailyActiveMs":{"2026-09-20":5}}"#,
            // More active time than a day contains.
            r#"{"enabled":true,"total":1,"days":{"2026-09-21":1},"dailyActiveMs":{"2026-09-21":86400001}}"#,
            // Buckets that do not describe a day of 24 hours.
            r#"{"enabled":true,"total":1,"days":{"2026-09-21":1},"dailyHours":{"2026-09-21":[1,0,0]}}"#,
            // Buckets claiming more characters than the day has.
            r#"{"enabled":true,"total":1,"days":{"2026-09-21":1},"dailyHours":{"2026-09-21":[2,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]}}"#,
        ];
        for document in cases {
            fs::write(&path, document).unwrap();
            assert!(
                matches!(store.load(), Err(TypingStatisticsError::InvalidDocument)),
                "accepted {document}"
            );
        }
        // A day with characters and no activity axes is not malformed: that is every day
        // recorded before these axes existed.
        fs::write(
            &path,
            r#"{"enabled":true,"total":1,"days":{"2026-09-21":1}}"#,
        )
        .unwrap();
        assert_eq!(store.load().unwrap().total, 1);
    }
}
