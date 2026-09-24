//! Typing statistics as an agent may see them: counts per day and per category, never text.
//!
//! The document already holds nothing typed (`msime_client_core::typing_statistics` classifies commits in memory and keeps counts only). Hourly buckets, active time and the last commit instant are left out as well: together they describe when someone sits at the keyboard, which an agent has no use for when answering how much and what kind of text was typed.

use msime_client_core::typing_statistics::{TypingStatistics, TypingStatisticsStore};
use rmcp::schemars::JsonSchema;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::path::Path;

pub const DEFAULT_DAYS: u32 = 7;
pub const MAX_DAYS: u32 = 90;

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[schemars(crate = "rmcp::schemars")]
#[serde(deny_unknown_fields)]
pub struct StatisticsRequest {
    /// How many of the most recent days with recorded typing to cover, 1 to 90. Defaults to 7.
    pub days: Option<u32>,
}

#[derive(Debug, Serialize, JsonSchema, PartialEq, Eq)]
#[schemars(crate = "rmcp::schemars")]
pub struct StatisticsView {
    /// Whether the user has turned statistics on. Nothing is recorded while it is off.
    pub enabled: bool,
    /// Characters committed over the whole retained history.
    pub total: u64,
    /// The covered days, oldest first. A day is the user's local date as the input method recorded it.
    pub days: Vec<DayCount>,
    /// Characters over the covered days by category (han, number, punctuation, symbol and so on) and by source, the input scheme or feature that produced them (quanpin, wubi, voice, ai and so on).
    pub breakdown: Breakdown,
    /// How often each candidate position was chosen, over the whole history: `ranks[0]` is the first candidate.
    pub selections: Selections,
}

#[derive(Debug, Serialize, JsonSchema, PartialEq, Eq)]
#[schemars(crate = "rmcp::schemars")]
pub struct DayCount {
    pub day: String,
    pub characters: u64,
}

#[derive(Debug, Serialize, JsonSchema, PartialEq, Eq)]
#[schemars(crate = "rmcp::schemars")]
pub struct Breakdown {
    pub characters: BTreeMap<String, u64>,
    pub sources: BTreeMap<String, u64>,
}

#[derive(Debug, Serialize, JsonSchema, PartialEq, Eq)]
#[schemars(crate = "rmcp::schemars")]
pub struct Selections {
    pub ranks: Vec<u64>,
    /// Choices from beyond the first page.
    pub beyond: u64,
}

pub fn load(state_dir: &Path, request: &StatisticsRequest) -> Result<StatisticsView, String> {
    let days = request.days.unwrap_or(DEFAULT_DAYS);
    if !(1..=MAX_DAYS).contains(&days) {
        return Err(format!("days must be between 1 and {MAX_DAYS}"));
    }
    let statistics = TypingStatisticsStore::new(state_dir)
        .load()
        .map_err(|error| error.to_string())?;
    Ok(view(&statistics, days as usize))
}

/// The most recent `days` recorded days rather than a calendar window: only the host knows the user's timezone, so the server does not guess which day today is.
fn view(statistics: &TypingStatistics, days: usize) -> StatisticsView {
    let recent: Vec<String> = statistics
        .days
        .keys()
        .rev()
        .take(days)
        .rev()
        .cloned()
        .collect();
    let breakdown = statistics.breakdown(Some(&recent));
    StatisticsView {
        enabled: statistics.enabled,
        total: statistics.total,
        days: recent
            .iter()
            .map(|day| DayCount {
                day: day.clone(),
                characters: statistics.days[day],
            })
            .collect(),
        breakdown: Breakdown {
            characters: breakdown.characters,
            sources: breakdown.sources,
        },
        selections: Selections {
            ranks: statistics.selections.ranks.clone(),
            beyond: statistics.selections.beyond,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use msime_client_core::typing_statistics::TypingBreakdown;

    #[test]
    fn only_the_most_recent_days_are_covered_and_timing_stays_out() {
        let mut statistics = TypingStatistics {
            enabled: true,
            total: 60,
            ..TypingStatistics::default()
        };
        for (day, count) in [("2026-09-20", 10), ("2026-09-21", 20), ("2026-09-22", 30)] {
            statistics.days.insert(day.into(), count);
            statistics.daily_details.insert(
                day.into(),
                TypingBreakdown {
                    characters: [("han".to_owned(), count)].into(),
                    sources: [("wubi".to_owned(), count)].into(),
                },
            );
            statistics.daily_hours.insert(day.into(), vec![count; 24]);
            statistics.daily_active_ms.insert(day.into(), 1000);
        }
        statistics.selections.ranks = vec![5, 1];
        statistics.last_commit_ms = 1;

        let view = view(&statistics, 2);
        assert_eq!(
            view.days,
            vec![
                DayCount {
                    day: "2026-09-21".into(),
                    characters: 20
                },
                DayCount {
                    day: "2026-09-22".into(),
                    characters: 30
                },
            ]
        );
        assert_eq!(view.breakdown.characters["han"], 50);
        assert_eq!(view.breakdown.sources["wubi"], 50);
        assert_eq!(view.selections.ranks, vec![5, 1]);
        let json = serde_json::to_string(&view).unwrap();
        for absent in ["hours", "active", "last_commit", "lastCommit"] {
            assert!(!json.contains(absent), "{absent} leaked into {json}");
        }
    }

    #[test]
    fn the_day_count_is_bounded() {
        let directory = tempfile::tempdir().unwrap();
        for days in [0, MAX_DAYS + 1] {
            assert!(load(directory.path(), &StatisticsRequest { days: Some(days) }).is_err());
        }
        let empty = load(directory.path(), &StatisticsRequest::default()).unwrap();
        assert!(empty.days.is_empty());
        assert!(!empty.enabled);
    }
}
