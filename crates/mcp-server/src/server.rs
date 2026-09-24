//! The tools, and the limits around the ones that write.
//!
//! Every tool reads the runtime-options document afresh, so the server follows the settings page when it moves the data directory or changes the dictionaries without being restarted. Nothing typed, no dictionary content beyond quick phrases and no credential leaves the input method through here; the audit lines on stderr name the tool and the outcome, never what was written.

use crate::config::Config;
use crate::preferences::{self, PreferencesChange, PreferencesView};
use crate::statistics::{self, StatisticsRequest, StatisticsView};
use msime_client_core::dictionary::quiesce::QuiescedHosts;
use msime_host_api::{DictionaryOptions, QuickPhrase, QuickPhraseEdit};
use rmcp::handler::server::router::tool::ToolRouter;
use rmcp::handler::server::wrapper::Parameters;
use rmcp::model::{Implementation, ServerCapabilities, ServerConfig};
use rmcp::schemars::JsonSchema;
use rmcp::{tool, tool_handler, tool_router, Json, ServerHandler};
use serde::{Deserialize, Serialize};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

const DEFAULT_PAGE: usize = 100;
const MAX_PAGE: usize = 1000;
/// The most edits one call may carry. An agent tidying a handful of phrases stays well inside it; one rewriting the whole collection has to show its work across calls.
const MAX_EDITS: usize = 50;
/// The shortest gap between two writing calls, so an agent stuck in a loop cannot rewrite the dictionary or the preferences many times a second.
const WRITE_INTERVAL: Duration = Duration::from_secs(1);

const WRITE_TOOLS: [&str; 2] = ["edit_quick_phrases", "update_preferences"];

const INSTRUCTIONS: &str = "Manages 水杉输入法 (MSIME), a Chinese input method: its quick phrases (a short code the user types that expands to a longer text), a few of its preferences, and aggregate typing statistics. Changes take effect in the input method within a few seconds. Writing tools are only offered when the user started the server with --allow-write.";

#[derive(Clone)]
pub struct MsimeServer {
    config: Arc<Config>,
    last_write: Arc<Mutex<Option<Instant>>>,
    tool_router: ToolRouter<Self>,
}

#[derive(Debug, Default, Deserialize, JsonSchema)]
#[schemars(crate = "rmcp::schemars")]
#[serde(deny_unknown_fields)]
pub struct ListRequest {
    /// Only phrases whose code starts with this. Codes are lowercase.
    pub code_prefix: Option<String>,
    /// How many matching phrases to skip.
    pub offset: Option<usize>,
    /// At most this many phrases, 1 to 1000. Defaults to 100.
    pub limit: Option<usize>,
}

#[derive(Clone, Debug, Deserialize, Serialize, JsonSchema, PartialEq, Eq)]
#[schemars(crate = "rmcp::schemars")]
#[serde(deny_unknown_fields)]
pub struct Phrase {
    /// What the user types, lowercase letters.
    pub code: String,
    /// What it expands to.
    pub text: String,
}

#[derive(Debug, Serialize, JsonSchema)]
#[schemars(crate = "rmcp::schemars")]
pub struct PhrasePage {
    pub phrases: Vec<Phrase>,
    /// More phrases match; ask again with a larger offset.
    pub has_more: bool,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(crate = "rmcp::schemars")]
#[serde(tag = "op", rename_all = "snake_case", deny_unknown_fields)]
pub enum Edit {
    /// Add a phrase. Refused if the same code already expands to the same text.
    Add { code: String, text: String },
    /// Change a phrase, found by its current code and text, keeping its rank.
    Replace {
        previous: Phrase,
        replacement: Phrase,
    },
    /// Remove a phrase, found by its code and text.
    Remove { code: String, text: String },
}

#[derive(Debug, Deserialize, JsonSchema)]
#[schemars(crate = "rmcp::schemars")]
#[serde(deny_unknown_fields)]
pub struct EditRequest {
    /// Applied in order, at most 50. The first that fails stops the rest; those before it stay applied.
    pub edits: Vec<Edit>,
}

#[derive(Debug, Serialize, JsonSchema, PartialEq, Eq)]
#[schemars(crate = "rmcp::schemars")]
pub struct EditOutcome {
    /// How many edits were applied, from the start of the list.
    pub applied: usize,
    /// The index of the edit that failed, when one did.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub failed_index: Option<usize>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
}

impl From<QuickPhrase> for Phrase {
    fn from(value: QuickPhrase) -> Self {
        Self {
            code: value.code,
            text: value.text,
        }
    }
}

impl From<Phrase> for QuickPhrase {
    fn from(value: Phrase) -> Self {
        Self {
            code: value.code,
            text: value.text,
        }
    }
}

impl From<Edit> for QuickPhraseEdit {
    fn from(value: Edit) -> Self {
        match value {
            Edit::Add { code, text } => Self::Add(QuickPhrase { code, text }),
            Edit::Replace {
                previous,
                replacement,
            } => Self::Replace {
                previous: previous.into(),
                replacement: replacement.into(),
            },
            Edit::Remove { code, text } => Self::Remove(QuickPhrase { code, text }),
        }
    }
}

#[tool_router]
impl MsimeServer {
    pub fn new(config: Config) -> Self {
        let mut tool_router = Self::tool_router();
        if !config.allow_write {
            for name in WRITE_TOOLS {
                tool_router.remove_route(name);
            }
        }
        Self {
            config: Arc::new(config),
            last_write: Arc::new(Mutex::new(None)),
            tool_router,
        }
    }

    #[tool(
        name = "list_quick_phrases",
        description = "List the user's own quick phrases: short codes that expand to longer text when typed. Built-in phrases are not included.",
        annotations(read_only_hint = true, open_world_hint = false)
    )]
    async fn list_quick_phrases(
        &self,
        Parameters(request): Parameters<ListRequest>,
    ) -> Result<Json<PhrasePage>, String> {
        let limit = request.limit.unwrap_or(DEFAULT_PAGE);
        if !(1..=MAX_PAGE).contains(&limit) {
            return Err(format!("limit must be between 1 and {MAX_PAGE}"));
        }
        let config = self.config.clone();
        blocking(move || {
            let options = DictionaryOptions::from_host_document(config.read_options()?)?;
            let page = msime_host_api::user_quick_phrases(
                &options,
                request.code_prefix.as_deref().unwrap_or(""),
                request.offset.unwrap_or(0),
                limit,
            )?;
            Ok(Json(PhrasePage {
                phrases: page.phrases.into_iter().map(Phrase::from).collect(),
                has_more: page.has_more,
            }))
        })
        .await
    }

    #[tool(
        name = "edit_quick_phrases",
        description = "Add, replace or remove the user's quick phrases. Each phrase is found by its exact code and text, so list them first. Edits are applied in order and the first failure stops the rest.",
        annotations(
            read_only_hint = false,
            destructive_hint = true,
            idempotent_hint = false,
            open_world_hint = false
        )
    )]
    async fn edit_quick_phrases(
        &self,
        Parameters(request): Parameters<EditRequest>,
    ) -> Result<Json<EditOutcome>, String> {
        if request.edits.is_empty() || request.edits.len() > MAX_EDITS {
            return Err(format!("send between 1 and {MAX_EDITS} edits"));
        }
        self.claim_write()?;
        let config = self.config.clone();
        let edits: Vec<QuickPhraseEdit> = request.edits.into_iter().map(Into::into).collect();
        let outcome = blocking(move || {
            let options = DictionaryOptions::from_host_document(config.read_options()?)?;
            Ok(apply_edits(&options, &edits))
        })
        .await?;
        eprintln!(
            "msime-mcp: edit_quick_phrases applied {}{}",
            outcome.applied,
            if outcome.error.is_some() {
                " then failed"
            } else {
                ""
            }
        );
        Ok(Json(outcome))
    }

    #[tool(
        name = "get_preferences",
        description = "Read the preferences an agent may see: input scheme, shuangpin layout, candidate page size, font size and layout, and a few switches. Pass the returned revision to update_preferences.",
        annotations(read_only_hint = true, open_world_hint = false)
    )]
    async fn get_preferences(&self) -> Result<Json<PreferencesView>, String> {
        let config = self.config.clone();
        blocking(move || {
            let state_dir = config.state_dir(&config.read_options()?)?;
            preferences::load(&state_dir).map(Json)
        })
        .await
    }

    #[tool(
        name = "update_preferences",
        description = "Change some of the preferences get_preferences returns. Only the fields given change. Refused when the preferences changed since expected_revision was read.",
        annotations(
            read_only_hint = false,
            destructive_hint = false,
            idempotent_hint = true,
            open_world_hint = false
        )
    )]
    async fn update_preferences(
        &self,
        Parameters(change): Parameters<PreferencesChange>,
    ) -> Result<Json<PreferencesView>, String> {
        self.claim_write()?;
        let config = self.config.clone();
        let result = blocking(move || {
            let state_dir = config.state_dir(&config.read_options()?)?;
            preferences::update(&state_dir, &config.options, &change).map(Json)
        })
        .await;
        eprintln!(
            "msime-mcp: update_preferences {}",
            if result.is_ok() { "saved" } else { "refused" }
        );
        result
    }

    #[tool(
        name = "get_typing_statistics",
        description = "Read aggregate typing statistics: characters per day, per category and per input scheme, and how often each candidate position is chosen. Counts only; no text is ever recorded.",
        annotations(read_only_hint = true, open_world_hint = false)
    )]
    async fn get_typing_statistics(
        &self,
        Parameters(request): Parameters<StatisticsRequest>,
    ) -> Result<Json<StatisticsView>, String> {
        let config = self.config.clone();
        blocking(move || {
            let state_dir = config.state_dir(&config.read_options()?)?;
            statistics::load(&state_dir, &request).map(Json)
        })
        .await
    }
}

#[tool_handler(router = self.tool_router)]
impl ServerHandler for MsimeServer {
    fn get_info(&self) -> ServerConfig {
        ServerConfig::new(ServerCapabilities::builder().enable_tools().build())
            .with_server_info(Implementation::new("msime", env!("CARGO_PKG_VERSION")))
            .with_instructions(INSTRUCTIONS)
    }
}

impl MsimeServer {
    /// Take the next write slot, or refuse when the previous write was too recent.
    fn claim_write(&self) -> Result<(), String> {
        let mut last = self
            .last_write
            .lock()
            .map_err(|_| "the server is shutting down")?;
        let now = Instant::now();
        if last.is_some_and(|previous| now.duration_since(previous) < WRITE_INTERVAL) {
            return Err("writes are limited to one a second; try again shortly".into());
        }
        *last = Some(now);
        Ok(())
    }
}

/// Apply `edits` in order under one lease, so the input hosts let go of the dictionary once for the whole call rather than once per edit. The lease is removed when this returns. The macOS input method finds it on its one-second timer; the desktop app also tells it at once, which would take the macOS host crate here for a second's difference.
fn apply_edits(options: &DictionaryOptions, edits: &[QuickPhraseEdit]) -> EditOutcome {
    let mut hosts = QuiescedHosts::new(Some(options.user_data()), || {});
    for (index, edit) in edits.iter().enumerate() {
        let request_id = msime_client_core::uuid::Uuid::new_v4().simple().to_string();
        if let Err(error) =
            hosts.run(|| msime_host_api::edit_user_quick_phrase(options, edit, &request_id))
        {
            return EditOutcome {
                applied: index,
                failed_index: Some(index),
                error: Some(error),
            };
        }
    }
    EditOutcome {
        applied: edits.len(),
        failed_index: None,
        error: None,
    }
}

/// Run file and dictionary work off the protocol task, so a slow disk or a busy dictionary does not stall the stdio loop.
async fn blocking<T: Send + 'static>(
    work: impl FnOnce() -> Result<T, String> + Send + 'static,
) -> Result<T, String> {
    tokio::task::spawn_blocking(work)
        .await
        .map_err(|_| "the request was interrupted".to_owned())?
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::path::PathBuf;

    fn server(allow_write: bool) -> MsimeServer {
        MsimeServer::new(Config {
            options: PathBuf::from("/nonexistent/runtime-options.json"),
            state_dir: None,
            allow_write,
        })
    }

    #[test]
    fn write_tools_are_offered_only_when_allowed() {
        let names = |server: &MsimeServer| {
            let mut names: Vec<String> = server
                .tool_router
                .list_all()
                .into_iter()
                .map(|tool| tool.name.to_string())
                .collect();
            names.sort();
            names
        };
        assert_eq!(
            names(&server(false)),
            [
                "get_preferences",
                "get_typing_statistics",
                "list_quick_phrases"
            ]
        );
        assert_eq!(
            names(&server(true)),
            [
                "edit_quick_phrases",
                "get_preferences",
                "get_typing_statistics",
                "list_quick_phrases",
                "update_preferences"
            ]
        );
    }

    #[test]
    fn writes_are_spaced_out() {
        let server = server(true);
        server.claim_write().unwrap();
        assert!(server.claim_write().is_err());
        *server.last_write.lock().unwrap() = Some(Instant::now() - WRITE_INTERVAL);
        server.claim_write().unwrap();
    }

    #[test]
    fn edits_read_as_the_engine_edits() {
        let request: EditRequest = serde_json::from_value(serde_json::json!({ "edits": [
            { "op": "add", "code": "yx", "text": "邮箱" },
            { "op": "replace", "previous": { "code": "yx", "text": "邮箱" }, "replacement": { "code": "yx", "text": "someone@example.com" } },
            { "op": "remove", "code": "yx", "text": "someone@example.com" }
        ]}))
        .unwrap();
        let edits: Vec<QuickPhraseEdit> = request.edits.into_iter().map(Into::into).collect();
        let phrase = |text: &str| QuickPhrase {
            code: "yx".into(),
            text: text.into(),
        };
        assert_eq!(
            edits,
            [
                QuickPhraseEdit::Add(phrase("邮箱")),
                QuickPhraseEdit::Replace {
                    previous: phrase("邮箱"),
                    replacement: phrase("someone@example.com")
                },
                QuickPhraseEdit::Remove(phrase("someone@example.com")),
            ]
        );
        assert!(serde_json::from_value::<EditRequest>(
            serde_json::json!({ "edits": [{ "op": "add", "code": "a", "text": "b", "weight": 1 }] })
        )
        .is_err());
    }
}
