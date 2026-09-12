//! Shared host orchestration; the Engine remains the owner of composition state.
//! Views are cached values. UI selection carries both session and view identity.

/// Character width conversion used by host-specific mode selectors.
/// Converts printable ASCII to Unicode fullwidth forms and back.
pub mod character_width {
    pub fn to_fullwidth(input: &str) -> String {
        input
            .chars()
            .map(|c| {
                if c == ' ' {
                    '\u{3000}'
                } else if ('!'..='~').contains(&c) {
                    char::from_u32(c as u32 + 0xfee0).unwrap()
                } else {
                    c
                }
            })
            .collect()
    }
    pub fn to_halfwidth(input: &str) -> String {
        input
            .chars()
            .map(|c| {
                if c == '\u{3000}' {
                    ' '
                } else if ('！'..='～').contains(&c) {
                    char::from_u32(c as u32 - 0xfee0).unwrap()
                } else {
                    c
                }
            })
            .collect()
    }
}

use msime_client_core::preferences::TouchKeyboardLayout;
use msime_engine_bridge::{
    CandidateEdge, Command, EngineResult, EngineSnapshot, OnlineQuerySnapshot, Session,
};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::sync::atomic::{AtomicU64, Ordering};
// The Unix socket providers below are the only consumers of these imports.
#[cfg(unix)]
use serde_json::{json, Value};
#[cfg(unix)]
use std::io::{BufRead, BufReader, Read, Write};
#[cfg(unix)]
use std::os::unix::net::UnixStream;
#[cfg(unix)]
use std::path::PathBuf;
#[cfg(unix)]
use std::sync::atomic::AtomicBool;
use std::sync::mpsc;
use std::thread::{self, JoinHandle};

static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);

/// Windows cloud-candidate settle delay, matching the native Server behavior.
pub const WINDOWS_CLOUD_DEBOUNCE: std::time::Duration = std::time::Duration::from_millis(500);

#[derive(Debug, thiserror::Error)]
pub enum RuntimeError {
    #[error("candidate page size must be between 1 and 9")]
    InvalidPageSize,
    #[error("candidate belongs to an expired view or another session")]
    StaleCandidate,
    #[error("nine-key spelling belongs to an expired view or another session")]
    StaleNineKeySpelling,
    #[error("session identity exhausted")]
    IdentityExhausted,
    #[error("cannot replace an engine while composition is active")]
    CompositionActive,
    #[error("nine-key mode requires the quanpin scheme")]
    InvalidNineKeyScheme,
    #[error("punctuation action requires an ASCII punctuation character")]
    InvalidPunctuation,
    #[error("engine action failed: {0}")]
    Engine(String),
}

pub trait InputEngine {
    fn set_paired_punctuation_enabled(&mut self, _enabled: bool) -> Result<(), RuntimeError> {
        Ok(())
    }
    fn set_punctuation_lock(&mut self, _lock: u8) -> Result<(), RuntimeError> {
        Ok(())
    }
    fn set_dedicated_english(&mut self, _enabled: bool) -> Result<(), RuntimeError> {
        Ok(())
    }
    fn set_nine_key_enabled(&mut self, _enabled: bool) -> Result<(), RuntimeError> {
        Err(RuntimeError::Engine("Nine-key mode is unsupported".into()))
    }
    fn choose_nine_key_spelling(&mut self, _index: usize) -> Result<EngineResult, RuntimeError> {
        Err(RuntimeError::Engine(
            "Nine-key spelling selection is unsupported".into(),
        ))
    }
    fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError>;
    fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, RuntimeError>;
    fn command(&mut self, command: Command) -> Result<EngineResult, RuntimeError>;
    fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError>;
    fn pin_candidate(&mut self, _index: usize) -> Result<EngineResult, RuntimeError> {
        Err(RuntimeError::Engine(
            "Candidate pinning is unsupported".into(),
        ))
    }
    fn remove_candidate(&mut self, _index: usize) -> Result<EngineResult, RuntimeError> {
        Err(RuntimeError::Engine(
            "Candidate removal is unsupported".into(),
        ))
    }
    fn fix_candidate_position(
        &mut self,
        _index: usize,
        _position: u8,
    ) -> Result<EngineResult, RuntimeError> {
        Err(RuntimeError::Engine(
            "Candidate position fixing is unsupported".into(),
        ))
    }
    fn clear_candidate_position(&mut self, _index: usize) -> Result<EngineResult, RuntimeError> {
        Err(RuntimeError::Engine(
            "Candidate position clearing is unsupported".into(),
        ))
    }
    fn select_edge(
        &mut self,
        index: usize,
        edge: CandidateEdge,
    ) -> Result<EngineResult, RuntimeError>;
    fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError>;
    fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError>;
}

impl InputEngine for Session {
    fn set_paired_punctuation_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        Session::set_paired_punctuation_enabled(self, enabled)
            .map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn set_punctuation_lock(&mut self, lock: u8) -> Result<(), RuntimeError> {
        Session::set_punctuation_lock(self, lock).map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        Session::set_dedicated_english(self, enabled)
            .map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn set_nine_key_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        Session::set_nine_key_enabled(self, enabled)
            .map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn choose_nine_key_spelling(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        Session::choose_nine_key_spelling(self, index)
            .map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
        Session::punctuation(self, value).map_err(|error| RuntimeError::Engine(error.to_string()))
    }
    fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError> {
        Session::snapshot(self).map_err(|error| RuntimeError::Engine(error.to_string()))
    }
    fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, RuntimeError> {
        Session::character(self, value, shift)
            .map_err(|error| RuntimeError::Engine(error.to_string()))
    }
    fn command(&mut self, command: Command) -> Result<EngineResult, RuntimeError> {
        Session::command(self, command).map_err(|error| RuntimeError::Engine(error.to_string()))
    }
    fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        Session::select(self, index).map_err(|error| RuntimeError::Engine(error.to_string()))
    }
    fn pin_candidate(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        Session::pin_candidate(self, index).map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn remove_candidate(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        Session::remove_candidate(self, index).map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn fix_candidate_position(
        &mut self,
        index: usize,
        position: u8,
    ) -> Result<EngineResult, RuntimeError> {
        Session::fix_candidate_position(self, index, position)
            .map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn clear_candidate_position(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        Session::clear_candidate_position(self, index)
            .map_err(|e| RuntimeError::Engine(e.to_string()))
    }
    fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        Session::finish(self, index).map_err(|error| RuntimeError::Engine(error.to_string()))
    }
    fn select_edge(
        &mut self,
        index: usize,
        edge: CandidateEdge,
    ) -> Result<EngineResult, RuntimeError> {
        Session::select_edge(self, index, edge)
            .map_err(|error| RuntimeError::Engine(error.to_string()))
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct CandidateId {
    pub session: u64,
    pub generation: u64,
    pub index: usize,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub struct NineKeySpellingId {
    pub session: u64,
    pub generation: u64,
    pub index: usize,
}

#[derive(Clone, Debug, Serialize)]
pub struct Candidate {
    pub id: CandidateId,
    pub text: String,
    /// Engine-derived display suffix, never part of selection or committed text.
    pub annotation: String,
    /// Engine candidate source, stable for the lifetime of this view.
    pub source: u8,
    /// Engine fixed-position slot, or zero when dynamically ranked.
    pub fixed_position: u8,
    pub highlighted: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub translation: Option<String>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum CharacterWidth {
    Fullwidth,
    Halfwidth,
}

#[derive(Clone, Debug, Serialize)]
pub struct View {
    pub scheme: u8,
    /// Engine-owned mobile layout mode. Digits are input, never candidate shortcuts, while active.
    pub nine_key: bool,
    pub nine_key_spellings: Vec<String>,
    /// Applied touch presentation, independent of Engine-owned Chinese nine-key digit handling.
    pub touch_keyboard_layout: TouchKeyboardLayout,
    /// Applied Engine configuration, not a newer deferred preference snapshot.
    pub character_width: CharacterWidth,
    pub microsoft_shuangpin: bool,
    pub shuangpin_profile: String,
    pub answered_by_pinyin_fallback: bool,
    /// Authoritative Engine mode, never inferred from displayed text.
    pub local_mode: String,
    pub session: u64,
    pub generation: u64,
    pub focused: bool,
    pub preedit: String,
    pub editing_text: String,
    /// Byte offset in Engine's ASCII editing_text, not an OS UTF-16 offset.
    pub caret_position: usize,
    pub page: usize,
    pub page_size: usize,
    pub page_count: usize,
    pub candidates: Vec<Candidate>,
}

#[derive(Debug, Serialize)]
pub struct OutputContext {
    pub scheme: u8,
    pub local_mode: String,
}

#[derive(Debug, Serialize)]
pub struct Transition {
    pub handled: bool,
    pub commit: Option<String>,
    /// Mode before dispatch; committing may clear a local mode or apply deferred settings.
    pub commit_context: Option<OutputContext>,
    pub diagnostic: Option<String>,
    pub view: View,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct AiAssistantProviderConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub provider: String,
    #[serde(default)]
    pub model: String,
    #[serde(default)]
    pub endpoint: String,
    #[serde(default = "default_ai_candidate_limit")]
    pub candidate_limit: u8,
    #[serde(default)]
    pub prompt_id: String,
    #[serde(default)]
    pub prompt: String,
    #[serde(default)]
    pub prompt_custom_1: String,
    #[serde(default)]
    pub prompt_custom_2: String,
    #[serde(default)]
    pub prompt_custom_3: String,
}

fn default_ai_candidate_limit() -> u8 {
    3
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct OnlineQuery {
    pub scheme: u8,
    pub generation: u64,
    pub identity: String,
    pub query_text: String,
    pub cache_key: String,
    pub pinyin_segments: Vec<String>,
    pub cloud_eligible: bool,
    pub ai_eligible: bool,
    /// Host preference controlling whether a provider may return cloud suggestions.
    #[serde(default = "default_cloud_candidates")]
    pub cloud_candidates: bool,
    pub session_id: u64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ai_assistant: Option<AiAssistantProviderConfig>,
}

fn default_cloud_candidates() -> bool {
    true
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct TranslationProviderConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub endpoint: String,
    #[serde(default)]
    pub api_key: String,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct TranslationQuery {
    pub generation: u64,
    #[serde(default = "default_translation_target_language")]
    pub target_language: String,
    pub candidates: Vec<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub custom_translation: Option<TranslationProviderConfig>,
}

fn default_translation_target_language() -> String {
    "en".into()
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct TranslationResult {
    pub text: String,
    pub translation: String,
}

/// A bounded stroke payload sent by a Linux handwriting panel to its
/// user-owned recognizer service. Coordinates are normalized panel pixels;
/// the recognizer decides how to map them to a platform model.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct HandwritingPoint {
    pub x: f32,
    pub y: f32,
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq)]
pub struct HandwritingQuery {
    #[serde(default)]
    pub language: String,
    pub strokes: Vec<Vec<HandwritingPoint>>,
}

/// Search request for a standalone Linux emoji panel. The panel owns its
/// category/search UI while the provider supplies the catalog and annotations.
#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct EmojiPanelQuery {
    #[serde(default)]
    pub search: String,
    #[serde(default)]
    pub category: String,
    #[serde(default = "default_emoji_panel_limit")]
    pub limit: u8,
}

fn default_emoji_panel_limit() -> u8 {
    48
}

#[derive(Clone, Debug, Deserialize, Serialize, PartialEq, Eq)]
pub struct EmojiPanelItem {
    pub text: String,
    #[serde(default)]
    pub annotation: String,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct OnlineCandidate {
    pub query: OnlineQuery,
    pub text: String,
    /// 0 = cloud suggestion, 1 = AI suggestion.
    pub source: u8,
}

/// Build the default cloud request for an eligible online query. Hosts perform
/// the actual network I/O through their injected transport and then submit the
/// result to `Runtime::apply_online_candidate`.
pub fn cloud_request_url(query: &OnlineQuery) -> Option<String> {
    if !query.cloud_eligible || !query.cloud_candidates {
        return None;
    }
    msime_client_core::cloud::build_google_url(&query.query_text, query.scheme == 3)
}

/// Convert a host-fetched Google response into a bounded online result.
pub fn cloud_candidate_from_response(
    query: OnlineQuery,
    response: &[u8],
) -> Option<OnlineCandidate> {
    if !query.cloud_eligible || !query.cloud_candidates {
        return None;
    }
    let text = msime_client_core::cloud::parse_google_response(response)?;
    Some(OnlineCandidate {
        query,
        text,
        source: 0,
    })
}

/// Linux adapter for a user-owned provider over a local Unix socket.
/// Credentials and network policy remain in the socket service; only a
/// copied, bounded query crosses this boundary.
#[cfg(unix)]
#[derive(Clone, Debug)]
pub struct UnixSocketProvider {
    path: PathBuf,
}

#[cfg(unix)]
impl UnixSocketProvider {
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    pub fn query(&self, query: OnlineQuery) -> Option<(String, u8)> {
        if query.query_text.len() > 4096 || query.identity.len() > 4096 {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(std::time::Duration::from_millis(500)))
            .ok()?;
        let request = json!({"version": 1, "kind": "online", "query": query}).to_string();
        if request.len() > 16384
            || stream.write_all(request.as_bytes()).is_err()
            || stream.write_all(b"\n").is_err()
        {
            return None;
        }
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).ok()?;
        #[derive(Deserialize)]
        struct Reply {
            text: String,
            source: u8,
        }
        let reply: Reply = serde_json::from_str(&line).ok()?;
        if reply.text.is_empty()
            || reply.text.len() > 4096
            || reply.source > 1
            || (!query.cloud_candidates && reply.source == 0)
        {
            return None;
        }
        Some((reply.text, reply.source))
    }

    pub fn translate(&self, query: TranslationQuery) -> Option<Vec<TranslationResult>> {
        if query.candidates.is_empty()
            || query.candidates.len() > 9
            || query.candidates.iter().any(|text| text.len() > 4096)
        {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(std::time::Duration::from_millis(500)))
            .ok()?;
        let request = json!({"version": 1, "kind": "translation", "query": query}).to_string();
        if request.len() > 16384
            || stream.write_all(request.as_bytes()).is_err()
            || stream.write_all(b"\n").is_err()
        {
            return None;
        }
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).ok()?;
        #[derive(Deserialize)]
        struct Reply {
            translations: Vec<TranslationResult>,
        }
        let reply: Reply = serde_json::from_str(&line).ok()?;
        if reply.translations.len() > 9
            || reply
                .translations
                .iter()
                .any(|item| item.text.len() > 4096 || item.translation.len() > 4096)
        {
            return None;
        }
        Some(reply.translations)
    }

    /// Ask the user-owned handwriting recognizer for up to twelve candidates.
    /// The Linux panel owns ink capture and presentation; this service owns
    /// model selection and any platform-specific recognizer integration.
    pub fn handwriting(&self, query: HandwritingQuery) -> Option<Vec<String>> {
        if query.language.len() > 64
            || query.strokes.is_empty()
            || query.strokes.len() > 32
            || query
                .strokes
                .iter()
                .any(|stroke| stroke.is_empty() || stroke.len() > 512)
        {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(std::time::Duration::from_millis(500)))
            .ok()?;
        let request = json!({"version": 1, "kind": "handwriting", "query": query}).to_string();
        if request.len() > 262_144
            || stream.write_all(request.as_bytes()).is_err()
            || stream.write_all(b"\n").is_err()
        {
            return None;
        }
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).ok()?;
        #[derive(Deserialize)]
        struct Reply {
            candidates: Vec<String>,
        }
        let reply: Reply = serde_json::from_str(&line).ok()?;
        if reply.candidates.len() > 12
            || reply
                .candidates
                .iter()
                .any(|candidate| candidate.is_empty() || candidate.len() > 4096)
        {
            return None;
        }
        Some(reply.candidates)
    }

    /// Search the user-owned emoji catalog. Results stay outside the IBus
    /// session and can be rendered by any desktop panel toolkit.
    pub fn emoji(&self, query: EmojiPanelQuery) -> Option<Vec<EmojiPanelItem>> {
        if query.search.len() > 256
            || query.category.len() > 128
            || !(1..=96).contains(&query.limit)
        {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(std::time::Duration::from_millis(500)))
            .ok()?;
        let request = json!({"version": 1, "kind": "emoji", "query": query}).to_string();
        if request.len() > 16_384
            || stream.write_all(request.as_bytes()).is_err()
            || stream.write_all(b"\n").is_err()
        {
            return None;
        }
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).ok()?;
        #[derive(Deserialize)]
        struct Reply {
            items: Vec<EmojiPanelItem>,
        }
        let reply: Reply = serde_json::from_str(&line).ok()?;
        if reply.items.len() > 96
            || reply.items.iter().any(|item| {
                item.text.is_empty() || item.text.len() > 64 || item.annotation.len() > 256
            })
        {
            return None;
        }
        Some(reply.items)
    }

    /// Run one bounded voice capture/ASR request through the user-owned
    /// service. The service owns PipeWire/ALSA access, credentials and the
    /// recognizer; the input host only receives bounded UTF-8 text.
    pub fn voice(&self, language: &str, generation: u64) -> Option<String> {
        self.voice_with_options(language, generation, &Value::Null)
    }

    /// Run a voice request with non-sensitive behavior options. Credentials
    /// are deliberately not accepted here; the provider owns authentication
    /// and may ignore options it does not understand.
    pub fn voice_with_options(
        &self,
        language: &str,
        generation: u64,
        options: &Value,
    ) -> Option<String> {
        self.voice_with_options_cancelled(language, generation, options, None)
    }

    /// Cancellable variant used by the IBus worker. The provider may still
    /// take up to the socket read timeout to answer, but cancellation never
    /// waits for the full thirty-second voice request deadline.
    pub fn voice_with_options_cancelled(
        &self,
        language: &str,
        generation: u64,
        options: &Value,
        cancelled: Option<&AtomicBool>,
    ) -> Option<String> {
        if language.len() > 64 {
            return None;
        }
        if cancelled.is_some_and(|value| value.load(Ordering::Relaxed)) {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(match cancelled {
                Some(_) => std::time::Duration::from_millis(100),
                None => std::time::Duration::from_secs(30),
            }))
            .ok()?;
        let mut request = json!({
            "version": 1,
            "kind": "voice",
            "query": {"language": language, "generation": generation}
        });
        if let Some(query) = request.get_mut("query").and_then(Value::as_object_mut) {
            if options.is_object() && !options.as_object().is_some_and(|value| value.is_empty()) {
                query.insert("options".to_owned(), options.clone());
            }
        }
        let request = request.to_string();
        if request.len() > 4096
            || stream.write_all(request.as_bytes()).is_err()
            || stream.write_all(b"\n").is_err()
        {
            return None;
        }
        let mut line = Vec::new();
        let mut reader = BufReader::new(stream);
        loop {
            if cancelled.is_some_and(|value| value.load(Ordering::Relaxed)) {
                return None;
            }
            let mut byte = [0u8; 512];
            match reader.read(&mut byte) {
                Ok(0) => break,
                Ok(length) => {
                    line.extend_from_slice(&byte[..length]);
                    if line.contains(&b'\n') {
                        if let Some(end) = line.iter().position(|value| *value == b'\n') {
                            line.truncate(end);
                        }
                        break;
                    }
                    if line.len() > 8192 {
                        return None;
                    }
                }
                Err(error)
                    if matches!(
                        error.kind(),
                        std::io::ErrorKind::WouldBlock | std::io::ErrorKind::TimedOut
                    ) =>
                {
                    continue
                }
                Err(_) => return None,
            }
        }
        let line = String::from_utf8(line).ok()?;
        #[derive(Deserialize)]
        struct Reply {
            text: String,
        }
        let reply: Reply = serde_json::from_str(&line).ok()?;
        if reply.text.is_empty() || reply.text.len() > 4096 {
            return None;
        }
        Some(reply.text)
    }

    /// Forward one validated account-backed dictionary operation to the
    /// user-owned service. The provider owns authentication, synchronization,
    /// and network policy; this adapter only carries bounded JSON.
    pub fn cloud_dictionary(&self, request: Value) -> Option<Value> {
        let encoded = json!({
            "version": 1,
            "kind": "cloud_dictionary",
            "request": request,
        })
        .to_string();
        if encoded.len() > 65_536 {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(30)))
            .ok()?;
        if stream.write_all(encoded.as_bytes()).is_err() || stream.write_all(b"\n").is_err() {
            return None;
        }
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).ok()?;
        if line.len() > 65_536 {
            return None;
        }
        let response = serde_json::from_str::<Value>(&line).ok()?;
        response.is_object().then_some(response)
    }

    /// Forward one account-backed cloud clipboard operation to the
    /// user-owned service. The provider owns authentication and retention.
    pub fn cloud_clipboard(&self, request: Value) -> Option<Value> {
        let encoded = json!({
            "version": 1,
            "kind": "cloud_clipboard",
            "request": request,
        })
        .to_string();
        if encoded.len() > 65_536 {
            return None;
        }
        let mut stream = UnixStream::connect(&self.path).ok()?;
        stream
            .set_read_timeout(Some(std::time::Duration::from_secs(30)))
            .ok()?;
        if stream.write_all(encoded.as_bytes()).is_err() || stream.write_all(b"\n").is_err() {
            return None;
        }
        let mut line = String::new();
        BufReader::new(stream).read_line(&mut line).ok()?;
        if line.len() > 65_536 {
            return None;
        }
        let response = serde_json::from_str::<Value>(&line).ok()?;
        response.is_object().then_some(response)
    }
}

/// Bounded provider worker. Provider code runs off the host/IBus thread and
/// receives only copied query data. Results remain inert until the owner
/// applies them through Runtime::apply_online_candidate, which revalidates
/// session identity and Engine generation.
pub struct OnlineProviderWorker {
    requests: Option<mpsc::SyncSender<OnlineQuery>>,
    results: mpsc::Receiver<OnlineCandidate>,
    join: Option<JoinHandle<()>>,
}

impl OnlineProviderWorker {
    pub fn spawn<F>(capacity: usize, provider: F) -> Result<Self, &'static str>
    where
        F: Fn(OnlineQuery) -> Option<(String, u8)> + Send + 'static,
    {
        Self::spawn_with_debounce(capacity, std::time::Duration::ZERO, provider)
    }

    pub fn spawn_with_debounce<F>(
        capacity: usize,
        debounce: std::time::Duration,
        provider: F,
    ) -> Result<Self, &'static str>
    where
        F: Fn(OnlineQuery) -> Option<(String, u8)> + Send + 'static,
    {
        if capacity == 0 {
            return Err("provider queue capacity must be positive");
        }
        let (requests, incoming) = mpsc::sync_channel::<OnlineQuery>(capacity);
        let (outgoing, results) = mpsc::channel();
        let join = thread::Builder::new()
            .name("msime-online-provider".into())
            .spawn(move || {
                while let Ok(mut query) = incoming.recv() {
                    // Coalesce bursts from one composition: Windows waits for
                    // input to settle instead of querying every intermediate text.
                    while let Ok(newest) = incoming.try_recv() {
                        query = newest;
                    }
                    if !debounce.is_zero() {
                        let deadline = std::time::Instant::now() + debounce;
                        loop {
                            let remaining =
                                deadline.saturating_duration_since(std::time::Instant::now());
                            if remaining.is_zero() {
                                break;
                            }
                            match incoming.recv_timeout(remaining) {
                                Ok(newest) => query = newest,
                                Err(mpsc::RecvTimeoutError::Timeout) => break,
                                Err(mpsc::RecvTimeoutError::Disconnected) => return,
                            }
                        }
                    }
                    if let Some((text, source)) = provider(query.clone()) {
                        if text.is_empty() || source > 1 {
                            continue;
                        }
                        if outgoing
                            .send(OnlineCandidate {
                                query,
                                text,
                                source,
                            })
                            .is_err()
                        {
                            break;
                        }
                    }
                }
            })
            .map_err(|_| "could not spawn provider worker")?;
        Ok(Self {
            requests: Some(requests),
            results,
            join: Some(join),
        })
    }

    pub fn submit(&self, query: OnlineQuery) -> bool {
        self.requests
            .as_ref()
            .is_some_and(|requests| requests.try_send(query).is_ok())
    }

    pub fn try_recv(&self) -> Option<OnlineCandidate> {
        self.results.try_recv().ok()
    }

    pub fn shutdown(mut self) {
        self.requests.take();
        if let Some(join) = self.join.take() {
            let _ = join.join();
        }
    }
}

pub enum Action {
    Character { value: u8, shift: bool },
    Punctuation(u8),
    /// Finish the highlighted composition and append the literal ASCII mark.
    /// Linux uses this when IBus surrounding text says smart punctuation
    /// should stay ASCII; the Engine's normal punctuation table remains
    /// authoritative for every other punctuation action.
    PunctuationAscii(u8),
    Command(Command),
    Select(CandidateId),
    SelectEdge(CandidateId, CandidateEdge),
    PinCandidate(CandidateId),
    RemoveCandidate(CandidateId),
    FixCandidatePosition(CandidateId, u8),
    ClearCandidatePosition(CandidateId),
    ChooseNineKeySpelling(NineKeySpellingId),
    SelectHighlighted,
    Finish,
    NextPage,
    PreviousPage,
    NextCandidate,
    PreviousCandidate,
    FirstCandidateOnPage,
    LastCandidateOnPage,
}

pub struct Runtime<E: InputEngine = Session> {
    engine: E,
    session: u64,
    generation: u64,
    focused: bool,
    page_size: usize,
    highlighted: usize,
    translations: HashMap<String, String>,
    cached: EngineSnapshot,
    snapshot_valid: bool,
    character_width: CharacterWidth,
    touch_keyboard_layout: TouchKeyboardLayout,
}

impl Runtime<Session> {
    /// A live host mode changes neither composition nor candidate identity.
    pub fn set_chinese_punctuation_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.engine
            .set_chinese_punctuation_enabled(enabled)
            .map_err(|error| RuntimeError::Engine(error.to_string()))
    }

    pub fn online_query(&self) -> Result<Option<OnlineQuery>, RuntimeError> {
        let query = self
            .engine
            .online_query()
            .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        if !query.available {
            return Ok(None);
        }
        Ok(Some(OnlineQuery {
            scheme: query.scheme,
            generation: query.generation,
            identity: query.identity,
            query_text: query.query_text,
            cache_key: query.cache_key,
            pinyin_segments: query.pinyin_segments,
            cloud_eligible: query.cloud_eligible,
            ai_eligible: query.ai_eligible,
            cloud_candidates: true,
            session_id: query.session_id,
            ai_assistant: None,
        }))
    }

    /// Queue the current eligible query for an injected provider. Hosts call
    /// this after dispatching input; the bounded worker performs I/O off-thread.
    pub fn submit_online_query(&self, worker: &OnlineProviderWorker) -> Result<bool, RuntimeError> {
        Ok(self
            .online_query()?
            .is_some_and(|query| worker.submit(query)))
    }

    pub fn apply_online_candidate(
        &mut self,
        query: &OnlineQuery,
        candidate: &str,
        source: u8,
    ) -> Result<bool, RuntimeError> {
        if source > 1
            || (source == 0 && (!query.cloud_candidates || !query.cloud_eligible))
            || (source == 1 && !query.ai_eligible)
        {
            return Ok(false);
        }
        let query = OnlineQuerySnapshot {
            available: true,
            scheme: query.scheme,
            generation: query.generation,
            identity: query.identity.clone(),
            query_text: query.query_text.clone(),
            cache_key: query.cache_key.clone(),
            pinyin_segments: query.pinyin_segments.clone(),
            cloud_eligible: query.cloud_eligible,
            ai_eligible: query.ai_eligible,
            session_id: query.session_id,
        };
        let applied = self
            .engine
            .apply_online_candidate(&query, candidate, source)
            .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        if applied {
            self.refresh()
                .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        }
        Ok(applied)
    }
}

impl<E: InputEngine> Runtime<E> {
    pub fn set_paired_punctuation_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.engine.set_paired_punctuation_enabled(enabled)
    }

    pub fn set_punctuation_lock(&mut self, lock: u8) -> Result<(), RuntimeError> {
        self.engine.set_punctuation_lock(lock)
    }

    pub fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.advance()?;
        self.engine.set_dedicated_english(enabled)?;
        self.refresh()
    }

    pub fn new(engine: E, page_size: u8) -> Result<Self, RuntimeError> {
        Self::new_with_touch_layout(engine, page_size, TouchKeyboardLayout::default())
    }

    pub fn new_with_touch_layout(
        engine: E,
        page_size: u8,
        touch_keyboard_layout: TouchKeyboardLayout,
    ) -> Result<Self, RuntimeError> {
        if !(1..=9).contains(&page_size) {
            return Err(RuntimeError::InvalidPageSize);
        }
        let session = NEXT_SESSION
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
            .map_err(|_| RuntimeError::IdentityExhausted)?;
        let cached = engine.snapshot()?;
        Ok(Self {
            engine,
            session,
            generation: 0,
            focused: false,
            page_size: page_size.into(),
            highlighted: 0,
            translations: HashMap::new(),
            cached,
            snapshot_valid: true,
            character_width: CharacterWidth::Halfwidth,
            touch_keyboard_layout,
        })
    }

    pub fn set_character_width(&mut self, width: CharacterWidth) {
        self.character_width = width;
    }

    /// Switch the Engine's digit interpretation only after the host finishes composition.
    pub fn set_nine_key_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        if enabled && self.cached.scheme != 0 {
            return Err(RuntimeError::InvalidNineKeyScheme);
        }
        if !self.is_idle() {
            return Err(RuntimeError::CompositionActive);
        }
        if self.cached.nine_key == enabled {
            return Ok(());
        }
        self.advance()?;
        self.engine.set_nine_key_enabled(enabled)?;
        self.refresh()
    }

    pub fn view(&self) -> View {
        let page = self.highlighted / self.page_size;
        let start = page * self.page_size;
        View {
            scheme: self.cached.scheme,
            nine_key: self.cached.nine_key,
            nine_key_spellings: self.cached.nine_key_spellings.clone(),
            touch_keyboard_layout: self.touch_keyboard_layout,
            character_width: self.character_width,
            microsoft_shuangpin: self.cached.microsoft_shuangpin,
            shuangpin_profile: self.cached.shuangpin_profile.clone(),
            answered_by_pinyin_fallback: self.cached.answered_by_pinyin_fallback,
            local_mode: self.cached.local_mode.clone(),
            session: self.session,
            generation: self.generation,
            focused: self.focused,
            preedit: self.cached.preedit.clone(),
            editing_text: self.cached.editing_text.clone(),
            caret_position: self.cached.caret_position,
            page,
            page_size: self.page_size,
            page_count: self.cached.candidates.len().div_ceil(self.page_size),
            candidates: self
                .cached
                .candidates
                .iter()
                .enumerate()
                .skip(start)
                .take(self.page_size)
                .map(|(index, text)| Candidate {
                    id: CandidateId {
                        session: self.session,
                        generation: self.generation,
                        index,
                    },
                    text: text.clone(),
                    annotation: self
                        .cached
                        .candidate_annotations
                        .get(index)
                        .cloned()
                        .unwrap_or_default(),
                    source: self
                        .cached
                        .candidate_sources
                        .get(index)
                        .copied()
                        .unwrap_or_default(),
                    fixed_position: self
                        .cached
                        .candidate_positions
                        .get(index)
                        .copied()
                        .unwrap_or_default(),
                    highlighted: index == self.highlighted,
                    translation: self.translations.get(text).cloned(),
                })
                .collect(),
        }
    }

    pub fn is_idle(&self) -> bool {
        self.snapshot_valid
            && self.cached.preedit.is_empty()
            && self.cached.editing_text.is_empty()
            && self.cached.candidates.is_empty()
    }

    /// Apply translations to the current candidate generation. Stale async
    /// responses are ignored so a newer candidate window cannot be polluted.
    pub fn apply_translations(
        &mut self,
        generation: u64,
        translations: impl IntoIterator<Item = (String, String)>,
    ) -> bool {
        if generation != self.generation {
            return false;
        }
        self.translations = translations.into_iter().collect();
        true
    }

    /// Presentation-only resize; a live composition keeps its numeric key map.
    pub fn set_page_size(&mut self, page_size: u8) -> Result<(), RuntimeError> {
        if !(1..=9).contains(&page_size) {
            return Err(RuntimeError::InvalidPageSize);
        }
        if self.page_size == usize::from(page_size) {
            return Ok(());
        }
        if !self.is_idle() {
            return Err(RuntimeError::CompositionActive);
        }
        self.advance()?;
        self.page_size = page_size.into();
        Ok(())
    }

    /// Preserve the host handle/focus while invalidating every old candidate ID.
    /// Validate the replacement before changing any live state.
    pub fn replace_engine(&mut self, engine: E, page_size: u8) -> Result<(), RuntimeError> {
        self.replace_engine_with_touch_layout(engine, page_size, self.touch_keyboard_layout)
    }

    pub fn replace_engine_with_touch_layout(
        &mut self,
        engine: E,
        page_size: u8,
        touch_keyboard_layout: TouchKeyboardLayout,
    ) -> Result<(), RuntimeError> {
        if !(1..=9).contains(&page_size) {
            return Err(RuntimeError::InvalidPageSize);
        }
        if !self.is_idle() {
            return Err(RuntimeError::CompositionActive);
        }
        let cached = engine.snapshot()?;
        self.advance()?;
        self.engine = engine;
        self.cached = cached;
        self.snapshot_valid = true;
        self.page_size = page_size.into();
        self.highlighted = 0;
        self.touch_keyboard_layout = touch_keyboard_layout;
        Ok(())
    }

    fn advance(&mut self) -> Result<(), RuntimeError> {
        self.generation = self
            .generation
            .checked_add(1)
            .ok_or(RuntimeError::IdentityExhausted)?;
        Ok(())
    }

    fn transition(&self, result: EngineResult) -> Transition {
        Transition {
            commit_context: result.has_commit.then(|| OutputContext {
                scheme: self.cached.scheme,
                local_mode: self.cached.local_mode.clone(),
            }),
            handled: result.handled,
            commit: result.has_commit.then_some(result.commit),
            diagnostic: (!result.diagnostic.is_empty()).then_some(result.diagnostic),
            view: self.view(),
        }
    }

    fn refresh(&mut self) -> Result<(), RuntimeError> {
        self.snapshot_valid = false;
        self.translations.clear();
        // Drop cached candidate identities even if fetching the replacement fails.
        let previous = std::mem::replace(
            &mut self.cached,
            EngineSnapshot {
                scheme: 255,
                nine_key: false,
                nine_key_spellings: Vec::new(),
                candidate_annotations: Vec::new(),
                candidate_sources: Vec::new(),
                candidate_positions: Vec::new(),
                microsoft_shuangpin: false,
                shuangpin_profile: String::new(),
                answered_by_pinyin_fallback: true,
                local_mode: "unknown".into(),
                preedit: String::new(),
                editing_text: String::new(),
                caret_position: 0,
                candidates: Vec::new(),
            },
        );
        let previous_highlight = self.highlighted;
        self.highlighted = 0;
        self.cached = self.engine.snapshot()?;
        self.snapshot_valid = true;
        if self.cached.editing_text == previous.editing_text
            && self.cached.scheme == previous.scheme
            && self.cached.local_mode == previous.local_mode
            && self.cached.candidates == previous.candidates
            && self.cached.candidate_annotations == previous.candidate_annotations
            && self.cached.candidate_sources == previous.candidate_sources
            && self.cached.candidate_positions == previous.candidate_positions
        {
            self.highlighted =
                previous_highlight.min(self.cached.candidates.len().saturating_sub(1));
        }
        Ok(())
    }

    pub fn focus(&mut self, focused: bool) -> Result<Transition, RuntimeError> {
        self.advance()?;
        // Invalidate the client before cancellation, including on engine failure.
        self.focused = false;
        let result = self.engine.command(Command::Cancel);
        self.refresh()?;
        let result = result?;
        self.focused = focused;
        Ok(self.transition(result))
    }

    fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
        // Finish through Engine with the host highlight BEFORE asking it to translate.
        // Calling Engine punctuation on an active composition would choose candidate zero.
        let mut finished = self.engine.finish(self.highlighted)?;
        let punctuation = match self.engine.punctuation(value) {
            Ok(result) => result,
            Err(error) if finished.has_commit => {
                // Completion already changed Engine state: never discard that commit.
                finished.commit.push(char::from(value));
                finished.handled = true;
                finished.diagnostic =
                    format!("{} Punctuation failed: {error}", finished.diagnostic)
                        .trim()
                        .to_owned();
                return Ok(finished);
            }
            Err(error) => return Err(error),
        };
        if !finished.has_commit {
            return Ok(punctuation);
        }
        finished.handled = true;
        if punctuation.has_commit {
            finished.commit.push_str(&punctuation.commit);
        } else if !punctuation.handled {
            // ASCII mode/unsupported symbols still terminate composition in one commit.
            finished.commit.push(char::from(value));
        }
        if !punctuation.diagnostic.is_empty() {
            finished.diagnostic = format!("{} {}", finished.diagnostic, punctuation.diagnostic)
                .trim()
                .to_owned();
        }
        Ok(finished)
    }

    fn punctuation_ascii(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
        // Keep the same highlighted-candidate completion semantics as normal
        // punctuation, but do not ask Engine to translate the trailing mark.
        // The Linux host has already applied its surrounding-text policy.
        let mut finished = self.engine.finish(self.highlighted)?;
        if !finished.has_commit {
            return Ok(finished);
        }
        finished.handled = true;
        finished.commit.push(char::from(value));
        Ok(finished)
    }

    pub fn dispatch(&mut self, action: Action) -> Result<Transition, RuntimeError> {
        if matches!(&action, Action::Punctuation(value) | Action::PunctuationAscii(value) if !value.is_ascii_punctuation()) {
            return Err(RuntimeError::InvalidPunctuation);
        }
        if !self.focused {
            return Ok(self.transition(empty_result(false)));
        }
        if let Action::Select(id)
        | Action::SelectEdge(id, _)
        | Action::PinCandidate(id)
        | Action::RemoveCandidate(id)
        | Action::FixCandidatePosition(id, _)
        | Action::ClearCandidatePosition(id) = &action
        {
            let start = (self.highlighted / self.page_size) * self.page_size;
            if id.session != self.session
                || id.generation != self.generation
                || id.index < start
                || id.index >= (start + self.page_size).min(self.cached.candidates.len())
            {
                return Err(RuntimeError::StaleCandidate);
            }
        }
        if let Action::ChooseNineKeySpelling(id) = &action {
            if id.session != self.session
                || id.generation != self.generation
                || !self.cached.nine_key
                || id.index >= self.cached.nine_key_spellings.len()
            {
                return Err(RuntimeError::StaleNineKeySpelling);
            }
        }
        self.advance()?;
        let len = self.cached.candidates.len();
        let next_highlight = match &action {
            Action::NextPage if len > 0 => Some(
                (self.highlighted / self.page_size + 1).min((len - 1) / self.page_size)
                    * self.page_size,
            ),
            Action::PreviousPage if len > 0 => {
                Some((self.highlighted / self.page_size).saturating_sub(1) * self.page_size)
            }
            Action::NextCandidate if len > 0 => Some((self.highlighted + 1).min(len - 1)),
            Action::PreviousCandidate if len > 0 => Some(self.highlighted.saturating_sub(1)),
            Action::FirstCandidateOnPage if len > 0 => {
                Some((self.highlighted / self.page_size) * self.page_size)
            }
            Action::LastCandidateOnPage if len > 0 => Some(
                ((self.highlighted / self.page_size) * self.page_size + self.page_size)
                    .min(len)
                    .saturating_sub(1),
            ),
            _ => None,
        };
        if let Some(index) = next_highlight {
            self.highlighted = index;
            return Ok(self.transition(empty_result(true)));
        }
        let commit_context = OutputContext {
            scheme: self.cached.scheme,
            local_mode: self.cached.local_mode.clone(),
        };
        let result = match action {
            Action::Punctuation(value) => self.punctuation(value),
            Action::PunctuationAscii(value) => self.punctuation_ascii(value),
            Action::Finish => self.engine.finish(self.highlighted),
            Action::Character { value, shift } => {
                self.engine.character(value, shift).and_then(|result| {
                    // The nine-key separator is a layout action, not Chinese quote punctuation.
                    if !result.handled && self.cached.nine_key && value == b'\'' {
                        return Ok(result);
                    }
                    if !result.handled && value.is_ascii_punctuation() {
                        return self.punctuation(value);
                    }
                    // Let Engine consume numeric input (Unicode mode, nine-key, etc.) first.
                    if result.handled
                        || self.cached.nine_key
                        || !(b'1'..=b'9').contains(&value)
                        || len == 0
                    {
                        return Ok(result);
                    }
                    let page_start = (self.highlighted / self.page_size) * self.page_size;
                    let slot = usize::from(value - b'1');
                    if slot >= self.page_size || page_start + slot >= len {
                        return Ok(empty_result(true));
                    }
                    self.engine.select(page_start + slot)
                })
            }
            Action::Command(command) => self.engine.command(command),
            Action::Select(id) => self.engine.select(id.index),
            Action::SelectEdge(id, edge) => self.engine.select_edge(id.index, edge),
            Action::PinCandidate(id) => self.engine.pin_candidate(id.index),
            Action::RemoveCandidate(id) => self.engine.remove_candidate(id.index),
            Action::FixCandidatePosition(id, position) => {
                if !(1..=5).contains(&position) {
                    return Err(RuntimeError::Engine(
                        "Candidate position must be between 1 and 5".into(),
                    ));
                }
                self.engine.fix_candidate_position(id.index, position)
            }
            Action::ClearCandidatePosition(id) => self.engine.clear_candidate_position(id.index),
            Action::ChooseNineKeySpelling(id) => self.engine.choose_nine_key_spelling(id.index),
            Action::SelectHighlighted if len > 0 => self.engine.select(self.highlighted),
            Action::SelectHighlighted => self.engine.command(Command::CommitCandidate),
            _ => return Ok(self.transition(empty_result(false))),
        };
        let refresh = self.refresh();
        let mut result = result?;
        if let Err(error) = refresh {
            // A successful engine commit must survive a presentation refresh failure.
            result.diagnostic = format!("Candidate refresh failed: {error}");
        }
        let mut transition = self.transition(result);
        if transition.commit.is_some() {
            transition.commit_context = Some(commit_context);
        }
        Ok(transition)
    }
}

fn empty_result(handled: bool) -> EngineResult {
    EngineResult {
        handled,
        has_commit: false,
        commit: String::new(),
        diagnostic: String::new(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[cfg(unix)]
    use std::os::unix::net::UnixListener;
    use std::time::Duration;
    struct Fixture {
        scheme: u8,
        nine_key: bool,
        nine_key_spellings: Vec<String>,
        local_mode: String,
        words: Vec<String>,
        text: String,
        snapshot_fails: bool,
    }

    #[cfg(unix)]
    #[test]
    fn cloud_dictionary_provider_forwards_bounded_request() {
        let directory = tempfile::tempdir().unwrap();
        let socket = directory.path().join("cloud-dictionary.sock");
        let listener = UnixListener::bind(&socket).unwrap();
        let server = std::thread::spawn(move || {
            let (stream, _) = listener.accept().unwrap();
            let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
            let mut line = String::new();
            std::io::BufRead::read_line(&mut reader, &mut line).unwrap();
            let request: Value = serde_json::from_str(&line).unwrap();
            assert_eq!(request["version"], 1);
            assert_eq!(request["kind"], "cloud_dictionary");
            assert_eq!(request["request"]["operation"], "changes");
            let mut stream = stream;
            std::io::Write::write_all(&mut stream, br#"{"changes":[],"next":0}"#).unwrap();
            std::io::Write::write_all(&mut stream, b"\n").unwrap();
        });
        let request = json!({"operation":"changes","after":0,"limit":1});
        let response = UnixSocketProvider::new(socket)
            .cloud_dictionary(request)
            .unwrap();
        assert_eq!(response["next"], 0);
        server.join().unwrap();
    }
    impl InputEngine for Fixture {
        fn set_nine_key_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
            self.nine_key = enabled;
            self.nine_key_spellings.clear();
            Ok(())
        }
        fn choose_nine_key_spelling(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
            if !self.nine_key || index >= self.nine_key_spellings.len() {
                return Ok(empty_result(false));
            }
            self.text = self.nine_key_spellings[index].clone();
            self.nine_key_spellings = vec![self.text.clone()];
            Ok(empty_result(true))
        }
        fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
            if value == b'!' {
                return Err(RuntimeError::Engine("injected punctuation failure".into()));
            }
            if value != b',' {
                return Ok(empty_result(false));
            }
            Ok(EngineResult {
                handled: true,
                has_commit: true,
                commit: "，".into(),
                diagnostic: String::new(),
            })
        }
        fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
            if self.text.is_empty() {
                return Ok(empty_result(false));
            }
            let mut result = self.select(index)?;
            result.commit.push_str("-remaining-segments");
            Ok(result)
        }
        fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError> {
            if self.snapshot_fails {
                return Err(RuntimeError::Engine("injected snapshot failure".into()));
            }
            Ok(EngineSnapshot {
                scheme: self.scheme,
                nine_key: self.nine_key,
                nine_key_spellings: self.nine_key_spellings.clone(),
                candidate_annotations: self
                    .words
                    .iter()
                    .enumerate()
                    .map(|(index, _)| format!("({index})"))
                    .collect(),
                candidate_sources: vec![0; self.words.len()],
                candidate_positions: vec![0; self.words.len()],
                microsoft_shuangpin: false,
                shuangpin_profile: "xiaohe".into(),
                answered_by_pinyin_fallback: false,
                local_mode: self.local_mode.clone(),
                preedit: self.text.clone(),
                editing_text: self.text.clone(),
                caret_position: self.text.len(),
                candidates: if self.text.is_empty() {
                    vec![]
                } else {
                    self.words.clone()
                },
            })
        }
        fn character(&mut self, value: u8, _shift: bool) -> Result<EngineResult, RuntimeError> {
            if self.nine_key && (b'2'..=b'9').contains(&value) {
                self.text.push(value as char);
                self.nine_key_spellings = vec!["ni".into(), "mi".into()];
                return Ok(empty_result(true));
            }
            if value.is_ascii_digit() || value.is_ascii_punctuation() {
                return Ok(empty_result(false));
            }
            self.text.push(value as char);
            Ok(empty_result(true))
        }
        fn command(&mut self, _command: Command) -> Result<EngineResult, RuntimeError> {
            self.text.clear();
            self.nine_key_spellings.clear();
            Ok(empty_result(true))
        }
        fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
            self.text.clear();
            self.nine_key_spellings.clear();
            self.local_mode = "none".into();
            Ok(EngineResult {
                handled: true,
                has_commit: true,
                commit: self.words[index].clone(),
                diagnostic: String::new(),
            })
        }
        fn select_edge(
            &mut self,
            index: usize,
            edge: CandidateEdge,
        ) -> Result<EngineResult, RuntimeError> {
            let mut result = self.select(index)?;
            result.commit.push_str(match edge {
                CandidateEdge::FirstHan => "-first",
                CandidateEdge::LastHan => "-last",
            });
            Ok(result)
        }
    }
    fn runtime() -> Runtime<Fixture> {
        Runtime::new(
            Fixture {
                scheme: 0,
                nine_key: false,
                nine_key_spellings: Vec::new(),
                local_mode: "none".into(),
                words: (0..12).map(|n| format!("candidate-{n}")).collect(),
                text: String::new(),
                snapshot_fails: false,
            },
            5,
        )
        .unwrap()
    }
    fn type_key(runtime: &mut Runtime<Fixture>) -> Transition {
        runtime
            .dispatch(Action::Character {
                value: b'a',
                shift: false,
            })
            .unwrap()
    }

    #[test]
    fn online_provider_worker_is_bounded_and_filters_invalid_results() {
        let query = OnlineQuery {
            scheme: 0,
            generation: 4,
            identity: "identity".into(),
            query_text: "nihao".into(),
            cache_key: "cache".into(),
            pinyin_segments: vec!["ni".into(), "hao".into()],
            cloud_eligible: true,
            ai_eligible: true,
            cloud_candidates: true,
            session_id: 9,
            ai_assistant: None,
        };
        let worker = OnlineProviderWorker::spawn(1, |query| {
            if query.query_text == "nihao" {
                Some(("你好".into(), 0))
            } else {
                Some((String::new(), 7))
            }
        })
        .unwrap();
        assert!(worker.submit(query.clone()));
        let mut result = None;
        for _ in 0..100 {
            result = worker.try_recv();
            if result.is_some() {
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
        let result = result.expect("provider result");
        assert_eq!(result.query, query);
        assert_eq!(result.text, "你好");
        assert_eq!(result.source, 0);
        worker.shutdown();
    }

    #[test]
    fn cloud_request_requires_eligible_query() {
        assert_eq!(
            WINDOWS_CLOUD_DEBOUNCE,
            std::time::Duration::from_millis(500)
        );
        let mut query = OnlineQuery {
            scheme: 0,
            generation: 1,
            identity: "x".into(),
            query_text: "ni".into(),
            cache_key: "x".into(),
            pinyin_segments: vec![],
            cloud_eligible: false,
            ai_eligible: false,
            cloud_candidates: true,
            session_id: 1,
            ai_assistant: None,
        };
        assert!(cloud_request_url(&query).is_none());
        query.cloud_eligible = true;
        assert!(cloud_request_url(&query)
            .unwrap()
            .contains("inputtools.google.com"));
        let response = serde_json::json!(["SUCCESS", [["ni", ["你"]]]]).to_string();
        let result = cloud_candidate_from_response(query, response.as_bytes()).unwrap();
        assert_eq!(result.text, "你");
        assert_eq!(result.source, 0);
    }

    #[test]
    fn online_provider_worker_rejects_zero_capacity_and_shutdowns_idle() {
        assert!(OnlineProviderWorker::spawn(0, |_| None).is_err());
        let worker = OnlineProviderWorker::spawn(1, |_| None).unwrap();
        worker.shutdown();
    }
    #[test]
    fn replacement_requires_verified_idle_and_preserves_session_focus() {
        let mut active = runtime();
        active.focus(true).unwrap();
        let old = type_key(&mut active).view;
        assert!(matches!(
            active.replace_engine(runtime().engine, 2),
            Err(RuntimeError::CompositionActive)
        ));
        assert_eq!(active.view().editing_text, old.editing_text);
        active.dispatch(Action::Command(Command::Cancel)).unwrap();
        active.replace_engine(runtime().engine, 2).unwrap();
        let updated = type_key(&mut active).view;
        assert_eq!(updated.session, old.session);
        assert!(updated.focused && updated.generation > old.generation);
        assert_eq!(updated.candidates.len(), 2);
        assert!(matches!(
            active.dispatch(Action::Select(old.candidates[0].id)),
            Err(RuntimeError::StaleCandidate)
        ));
        active.engine.snapshot_fails = true;
        assert!(active.refresh().is_err());
        assert!(active.view().editing_text.is_empty());
        assert!(
            !active.is_idle(),
            "missing snapshot is not proof of idle Engine"
        );
        assert!(matches!(
            active.replace_engine(runtime().engine, 2),
            Err(RuntimeError::CompositionActive)
        ));
    }

    #[test]
    fn touch_layout_changes_atomically_with_engine_replacement() {
        let mut active = runtime();
        assert_eq!(
            active.view().touch_keyboard_layout,
            TouchKeyboardLayout::TwentySixKey
        );
        active.focus(true).unwrap();
        type_key(&mut active);
        assert!(matches!(
            active.replace_engine_with_touch_layout(
                runtime().engine,
                2,
                TouchKeyboardLayout::NineKey
            ),
            Err(RuntimeError::CompositionActive)
        ));
        assert_eq!(
            active.view().touch_keyboard_layout,
            TouchKeyboardLayout::TwentySixKey
        );
        active.dispatch(Action::Command(Command::Cancel)).unwrap();
        active
            .replace_engine_with_touch_layout(runtime().engine, 2, TouchKeyboardLayout::NineKey)
            .unwrap();
        assert_eq!(
            active.view().touch_keyboard_layout,
            TouchKeyboardLayout::NineKey
        );
        active
            .replace_engine_with_touch_layout(runtime().engine, 2, TouchKeyboardLayout::Handwriting)
            .unwrap();
        assert_eq!(
            active.view().touch_keyboard_layout,
            TouchKeyboardLayout::Handwriting
        );
    }

    #[test]
    fn translations_are_generation_scoped_and_exposed_on_candidates() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        let view = type_key(&mut runtime).view;
        assert!(!runtime
            .apply_translations(view.generation - 1, [("candidate-0".into(), "old".into())]));
        assert!(runtime.apply_translations(
            view.generation,
            [("candidate-0".into(), "translated".into())]
        ));
        assert_eq!(
            runtime.view().candidates[0].translation.as_deref(),
            Some("translated")
        );
        runtime.dispatch(Action::Command(Command::Cancel)).unwrap();
        assert!(runtime
            .view()
            .candidates
            .iter()
            .all(|candidate| candidate.translation.is_none()));
    }

    #[test]
    fn replacement_snapshot_failure_keeps_the_original_engine() {
        let mut active = runtime();
        active.focus(true).unwrap();
        let generation = active.view().generation;
        let mut replacement = runtime().engine;
        replacement.snapshot_fails = true;
        assert!(active.replace_engine(replacement, 2).is_err());
        assert_eq!(active.view().generation, generation);
        assert_eq!(type_key(&mut active).view.candidates.len(), 5);
    }

    #[test]
    fn paging_and_selection_use_global_engine_indices() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        let page = runtime.dispatch(Action::NextPage).unwrap().view;
        assert_eq!(page.page, 1);
        assert_eq!(page.page_count, 3);
        assert_eq!(page.candidates[0].annotation, "(5)");
        assert_eq!(page.candidates[0].text, "candidate-5");
        let result = runtime
            .dispatch(Action::Select(page.candidates[2].id))
            .unwrap();
        assert_eq!(result.commit.as_deref(), Some("candidate-7"));
        assert!(result.view.candidates.is_empty());
    }

    #[test]
    fn candidate_page_edges_stay_within_the_active_page() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        let first = runtime.dispatch(Action::FirstCandidateOnPage).unwrap().view;
        assert_eq!(
            first
                .candidates
                .iter()
                .find(|c| c.highlighted)
                .unwrap()
                .text,
            "candidate-0"
        );
        let last = runtime.dispatch(Action::LastCandidateOnPage).unwrap().view;
        assert_eq!(
            last.candidates.iter().find(|c| c.highlighted).unwrap().text,
            "candidate-4"
        );
        runtime.dispatch(Action::NextPage).unwrap();
        let page_last = runtime.dispatch(Action::LastCandidateOnPage).unwrap().view;
        assert_eq!(
            page_last
                .candidates
                .iter()
                .find(|c| c.highlighted)
                .unwrap()
                .text,
            "candidate-9"
        );
        let page_first = runtime.dispatch(Action::FirstCandidateOnPage).unwrap().view;
        assert_eq!(
            page_first
                .candidates
                .iter()
                .find(|c| c.highlighted)
                .unwrap()
                .text,
            "candidate-5"
        );
    }

    #[test]
    fn edge_selection_checks_identity_and_routes_global_index() {
        for edge in [CandidateEdge::FirstHan, CandidateEdge::LastHan] {
            let mut active = runtime();
            active.focus(true).unwrap();
            let first = type_key(&mut active).view.candidates[0].id;
            let page = active.dispatch(Action::NextPage).unwrap().view;
            let id = page.candidates[1].id;
            assert_eq!(id.index, 6);
            let generation = active.view().generation;
            for invalid in [
                first,
                CandidateId {
                    session: id.session + 1,
                    ..id
                },
                CandidateId { index: 0, ..id },
                CandidateId { index: 10, ..id },
            ] {
                assert!(matches!(
                    active.dispatch(Action::SelectEdge(invalid, edge)),
                    Err(RuntimeError::StaleCandidate)
                ));
                assert_eq!(active.view().generation, generation);
            }
            let selected = active.dispatch(Action::SelectEdge(id, edge)).unwrap();
            assert_eq!(
                selected.commit.as_deref(),
                Some(match edge {
                    CandidateEdge::FirstHan => "candidate-6-first",
                    CandidateEdge::LastHan => "candidate-6-last",
                })
            );
            assert!(selected.view.editing_text.is_empty());
        }
    }

    #[test]
    fn punctuation_finishes_highlighted_candidate_and_remaining_segments() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        runtime.dispatch(Action::NextPage).unwrap();
        let result = runtime
            .dispatch(Action::Character {
                value: b',',
                shift: false,
            })
            .unwrap();
        assert_eq!(
            result.commit.as_deref(),
            Some("candidate-5-remaining-segments，")
        );
        assert!(result.handled && result.view.editing_text.is_empty());
    }

    #[test]
    fn unsupported_punctuation_is_appended_only_after_a_composition() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        let idle = runtime
            .dispatch(Action::Character {
                value: b'@',
                shift: false,
            })
            .unwrap();
        assert!(!idle.handled && idle.commit.is_none());
        type_key(&mut runtime);
        let result = runtime
            .dispatch(Action::Character {
                value: b'@',
                shift: false,
            })
            .unwrap();
        assert_eq!(
            result.commit.as_deref(),
            Some("candidate-0-remaining-segments@")
        );
    }

    #[test]
    fn punctuation_failure_does_not_lose_an_already_finished_commit() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        let result = runtime
            .dispatch(Action::Character {
                value: b'!',
                shift: false,
            })
            .unwrap();
        assert_eq!(
            result.commit.as_deref(),
            Some("candidate-0-remaining-segments!")
        );
        assert!(result
            .diagnostic
            .unwrap()
            .contains("injected punctuation failure"));
    }

    #[test]
    fn number_keys_select_the_visible_page_and_pass_through_when_idle() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        assert!(
            !runtime
                .dispatch(Action::Character {
                    value: b'2',
                    shift: false
                })
                .unwrap()
                .handled
        );
        type_key(&mut runtime);
        runtime.dispatch(Action::NextPage).unwrap();
        let result = runtime
            .dispatch(Action::Character {
                value: b'2',
                shift: false,
            })
            .unwrap();
        assert_eq!(result.commit.as_deref(), Some("candidate-6"));
    }

    #[test]
    fn nine_key_mode_owns_digits_and_spelling_choices_are_generation_scoped() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        let original_generation = runtime.view().generation;
        runtime.set_nine_key_enabled(true).unwrap();
        assert!(runtime.view().nine_key && runtime.view().generation > original_generation);
        let typed = runtime
            .dispatch(Action::Character {
                value: b'6',
                shift: false,
            })
            .unwrap();
        assert!(typed.handled && typed.commit.is_none());
        assert_eq!(
            typed.view.nine_key_spellings,
            vec!["ni".to_owned(), "mi".to_owned()]
        );
        let invalid_digit = runtime
            .dispatch(Action::Character {
                value: b'1',
                shift: false,
            })
            .unwrap();
        assert!(!invalid_digit.handled && invalid_digit.commit.is_none());
        let separator = runtime
            .dispatch(Action::Character {
                value: b'\'',
                shift: false,
            })
            .unwrap();
        assert!(!separator.handled && separator.commit.is_none());
        let generation = separator.view.generation;
        let stale = NineKeySpellingId {
            session: separator.view.session,
            generation: generation - 1,
            index: 0,
        };
        assert!(matches!(
            runtime.dispatch(Action::ChooseNineKeySpelling(stale)),
            Err(RuntimeError::StaleNineKeySpelling)
        ));
        let invalid = NineKeySpellingId {
            session: separator.view.session,
            generation,
            index: 2,
        };
        assert!(matches!(
            runtime.dispatch(Action::ChooseNineKeySpelling(invalid)),
            Err(RuntimeError::StaleNineKeySpelling)
        ));
        let selected = runtime
            .dispatch(Action::ChooseNineKeySpelling(NineKeySpellingId {
                session: separator.view.session,
                generation,
                index: 1,
            }))
            .unwrap();
        assert!(selected.handled && selected.view.editing_text == "mi");
        assert!(matches!(
            runtime.set_nine_key_enabled(false),
            Err(RuntimeError::CompositionActive)
        ));
        runtime.dispatch(Action::Command(Command::Cancel)).unwrap();
        runtime.set_nine_key_enabled(false).unwrap();
        assert!(!runtime.view().nine_key);
        runtime.engine.scheme = 1;
        runtime.refresh().unwrap();
        assert!(matches!(
            runtime.set_nine_key_enabled(true),
            Err(RuntimeError::InvalidNineKeyScheme)
        ));
    }

    #[test]
    fn unavailable_numeric_slot_does_not_jump_back_to_first_page() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        runtime.dispatch(Action::NextPage).unwrap();
        runtime.dispatch(Action::NextPage).unwrap();
        let result = runtime
            .dispatch(Action::Character {
                value: b'9',
                shift: false,
            })
            .unwrap();
        assert!(result.handled && result.commit.is_none());
        assert_eq!(result.view.page, 2);
    }

    #[test]
    fn engine_mode_is_authoritative_and_resets_old_highlight() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        runtime.dispatch(Action::NextPage).unwrap();
        runtime.engine.local_mode = "unicode".into();
        let result = runtime
            .dispatch(Action::Character {
                value: b'0',
                shift: false,
            })
            .unwrap();
        assert_eq!(result.view.local_mode, "unicode");
        assert_eq!(result.view.page, 0);
        assert!(!result.view.editing_text.starts_with('U'));
    }

    #[test]
    fn commit_context_precedes_mode_reset_for_every_selection_route() {
        for route in 0..5 {
            let mut runtime = runtime();
            runtime.focus(true).unwrap();
            runtime.engine.local_mode = "unicode".into();
            let view = type_key(&mut runtime).view;
            let id = view.candidates[0].id;
            let action = match route {
                0 => Action::Select(id),
                1 => Action::SelectEdge(id, CandidateEdge::FirstHan),
                2 => Action::SelectHighlighted,
                3 => Action::Finish,
                _ => Action::Character {
                    value: b'1',
                    shift: false,
                },
            };
            let committed = runtime.dispatch(action).unwrap();
            assert!(committed.commit.is_some());
            assert_eq!(committed.commit_context.unwrap().local_mode, "unicode");
            assert_eq!(committed.view.local_mode, "none");
        }
    }

    #[test]
    fn finish_preserves_engine_completion_of_remaining_segments() {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        runtime.dispatch(Action::NextPage).unwrap();
        let result = runtime.dispatch(Action::Finish).unwrap();
        assert_eq!(
            result.commit.as_deref(),
            Some("candidate-5-remaining-segments")
        );
        assert!(result.view.preedit.is_empty());
    }
    #[test]
    fn stale_views_and_other_sessions_cannot_select() {
        let mut a = runtime();
        let mut b = runtime();
        a.focus(true).unwrap();
        b.focus(true).unwrap();
        let id = type_key(&mut a).view.candidates[0].id;
        type_key(&mut b);
        assert!(matches!(
            b.dispatch(Action::Select(id)),
            Err(RuntimeError::StaleCandidate)
        ));
        a.dispatch(Action::NextCandidate).unwrap();
        assert!(matches!(
            a.dispatch(Action::Select(id)),
            Err(RuntimeError::StaleCandidate)
        ));
    }
    #[test]
    fn unfocused_keys_pass_through_and_blur_cancels_composition() {
        let mut runtime = runtime();
        assert!(!type_key(&mut runtime).handled);
        runtime.focus(true).unwrap();
        let id = type_key(&mut runtime).view.candidates[0].id;
        assert!(runtime.focus(false).unwrap().view.preedit.is_empty());
        assert!(!type_key(&mut runtime).handled);
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        assert!(matches!(
            runtime.dispatch(Action::Select(id)),
            Err(RuntimeError::StaleCandidate)
        ));
    }
    #[test]
    fn character_width_conversion_preserves_non_ascii_and_roundtrips_ascii() {
        let full = crate::character_width::to_fullwidth("A 1!");
        assert_eq!(full, "Ａ　１！");
        assert_eq!(crate::character_width::to_halfwidth(&full), "A 1!");
        assert_eq!(crate::character_width::to_fullwidth("中文"), "中文");
    }
}
