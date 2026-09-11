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

use msime_engine_bridge::{CandidateEdge, Command, EngineResult, EngineSnapshot, Session};
use serde::Serialize;
use std::sync::atomic::{AtomicU64, Ordering};

static NEXT_SESSION: AtomicU64 = AtomicU64::new(1);

#[derive(Debug, thiserror::Error)]
pub enum RuntimeError {
    #[error("candidate page size must be between 1 and 9")]
    InvalidPageSize,
    #[error("candidate belongs to an expired view or another session")]
    StaleCandidate,
    #[error("session identity exhausted")]
    IdentityExhausted,
    #[error("cannot replace an engine while composition is active")]
    CompositionActive,
    #[error("punctuation action requires an ASCII punctuation character")]
    InvalidPunctuation,
    #[error("engine action failed: {0}")]
    Engine(String),
}

pub trait InputEngine {
    fn set_dedicated_english(&mut self, _enabled: bool) -> Result<(), RuntimeError> {
        Ok(())
    }
    fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError>;
    fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, RuntimeError>;
    fn command(&mut self, command: Command) -> Result<EngineResult, RuntimeError>;
    fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError>;
    fn select_edge(
        &mut self,
        index: usize,
        edge: CandidateEdge,
    ) -> Result<EngineResult, RuntimeError>;
    fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError>;
    fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError>;
}

impl InputEngine for Session {
    fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        Session::set_dedicated_english(self, enabled)
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

#[derive(Clone, Debug, Serialize)]
pub struct Candidate {
    pub id: CandidateId,
    pub text: String,
    pub highlighted: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize)]
pub enum CharacterWidth {
    Fullwidth,
    Halfwidth,
}

#[derive(Clone, Debug, Serialize)]
pub struct View {
    /// Applied Engine configuration, not a newer deferred preference snapshot.
    pub character_width: CharacterWidth,
    pub microsoft_shuangpin: bool,
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
    pub page_count: usize,
    pub candidates: Vec<Candidate>,
}

#[derive(Debug, Serialize)]
pub struct Transition {
    pub handled: bool,
    pub commit: Option<String>,
    pub diagnostic: Option<String>,
    pub view: View,
}

pub enum Action {
    Character { value: u8, shift: bool },
    Punctuation(u8),
    Command(Command),
    Select(CandidateId),
    SelectEdge(CandidateId, CandidateEdge),
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
    cached: EngineSnapshot,
    snapshot_valid: bool,
    character_width: CharacterWidth,
}

impl Runtime<Session> {
    /// A live host mode changes neither composition nor candidate identity.
    pub fn set_chinese_punctuation_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.engine
            .set_chinese_punctuation_enabled(enabled)
            .map_err(|error| RuntimeError::Engine(error.to_string()))
    }
}

impl<E: InputEngine> Runtime<E> {
    pub fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.engine.set_dedicated_english(enabled)
    }

    pub fn new(engine: E, page_size: u8) -> Result<Self, RuntimeError> {
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
            cached,
            snapshot_valid: true,
            character_width: CharacterWidth::Halfwidth,
        })
    }

    pub fn set_character_width(&mut self, width: CharacterWidth) {
        self.character_width = width;
    }

    pub fn view(&self) -> View {
        let page = self.highlighted / self.page_size;
        let start = page * self.page_size;
        View {
            character_width: self.character_width,
            microsoft_shuangpin: self.cached.microsoft_shuangpin,
            local_mode: self.cached.local_mode.clone(),
            session: self.session,
            generation: self.generation,
            focused: self.focused,
            preedit: self.cached.preedit.clone(),
            editing_text: self.cached.editing_text.clone(),
            caret_position: self.cached.caret_position,
            page,
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
                    highlighted: index == self.highlighted,
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

    /// Preserve the host handle/focus while invalidating every old candidate ID.
    /// Validate the replacement before changing any live state.
    pub fn replace_engine(&mut self, engine: E, page_size: u8) -> Result<(), RuntimeError> {
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
            handled: result.handled,
            commit: result.has_commit.then_some(result.commit),
            diagnostic: (!result.diagnostic.is_empty()).then_some(result.diagnostic),
            view: self.view(),
        }
    }

    fn refresh(&mut self) -> Result<(), RuntimeError> {
        self.snapshot_valid = false;
        // Drop cached candidate identities even if fetching the replacement fails.
        let previous = std::mem::replace(
            &mut self.cached,
            EngineSnapshot {
                microsoft_shuangpin: false,
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
            && self.cached.local_mode == previous.local_mode
            && self.cached.candidates == previous.candidates
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

    pub fn dispatch(&mut self, action: Action) -> Result<Transition, RuntimeError> {
        if matches!(&action, Action::Punctuation(value) if !value.is_ascii_punctuation()) {
            return Err(RuntimeError::InvalidPunctuation);
        }
        if !self.focused {
            return Ok(self.transition(empty_result(false)));
        }
        if let Action::Select(id) | Action::SelectEdge(id, _) = &action {
            let start = (self.highlighted / self.page_size) * self.page_size;
            if id.session != self.session
                || id.generation != self.generation
                || id.index < start
                || id.index >= (start + self.page_size).min(self.cached.candidates.len())
            {
                return Err(RuntimeError::StaleCandidate);
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
        let result = match action {
            Action::Punctuation(value) => self.punctuation(value),
            Action::Finish => self.engine.finish(self.highlighted),
            Action::Character { value, shift } => {
                self.engine.character(value, shift).and_then(|result| {
                    if !result.handled && value.is_ascii_punctuation() {
                        return self.punctuation(value);
                    }
                    // Let Engine consume numeric input (Unicode mode, nine-key, etc.) first.
                    if result.handled || !(b'1'..=b'9').contains(&value) || len == 0 {
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
        Ok(self.transition(result))
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
    struct Fixture {
        local_mode: String,
        words: Vec<String>,
        text: String,
        snapshot_fails: bool,
    }
    impl InputEngine for Fixture {
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
                microsoft_shuangpin: false,
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
            if value.is_ascii_digit() || value.is_ascii_punctuation() {
                return Ok(empty_result(false));
            }
            self.text.push(value as char);
            Ok(empty_result(true))
        }
        fn command(&mut self, _command: Command) -> Result<EngineResult, RuntimeError> {
            self.text.clear();
            Ok(empty_result(true))
        }
        fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
            self.text.clear();
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
