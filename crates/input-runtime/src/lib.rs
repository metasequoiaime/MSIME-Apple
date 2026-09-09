//! Shared host orchestration; the Engine remains the owner of composition state.
//! Views are cached values. UI selection carries both session and view identity.

use msime_engine_bridge::{Command, EngineResult, EngineSnapshot, Session};
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
    #[error("engine action failed: {0}")]
    Engine(String),
}

pub trait InputEngine {
    fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError>;
    fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, RuntimeError>;
    fn command(&mut self, command: Command) -> Result<EngineResult, RuntimeError>;
    fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError>;
    fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError>;
}

impl InputEngine for Session {
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

#[derive(Clone, Debug, Serialize)]
pub struct View {
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
    Command(Command),
    Select(CandidateId),
    SelectHighlighted,
    Finish,
    NextPage,
    PreviousPage,
    NextCandidate,
    PreviousCandidate,
}

pub struct Runtime<E: InputEngine = Session> {
    engine: E,
    session: u64,
    generation: u64,
    focused: bool,
    page_size: usize,
    highlighted: usize,
    cached: EngineSnapshot,
}

impl<E: InputEngine> Runtime<E> {
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
        })
    }

    pub fn view(&self) -> View {
        let page = self.highlighted / self.page_size;
        let start = page * self.page_size;
        View {
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
        // Drop cached candidate identities even if fetching the replacement fails.
        let previous = std::mem::replace(
            &mut self.cached,
            EngineSnapshot {
                preedit: String::new(),
                editing_text: String::new(),
                caret_position: 0,
                candidates: Vec::new(),
            },
        );
        let previous_highlight = self.highlighted;
        self.highlighted = 0;
        self.cached = self.engine.snapshot()?;
        if self.cached.editing_text == previous.editing_text
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

    pub fn dispatch(&mut self, action: Action) -> Result<Transition, RuntimeError> {
        if !self.focused {
            return Ok(self.transition(empty_result(false)));
        }
        if let Action::Select(id) = &action {
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
            _ => None,
        };
        if let Some(index) = next_highlight {
            self.highlighted = index;
            return Ok(self.transition(empty_result(true)));
        }
        let result = match action {
            Action::Finish => self.engine.finish(self.highlighted),
            Action::Character { value, shift } => {
                self.engine.character(value, shift).and_then(|result| {
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
        words: Vec<String>,
        text: String,
    }
    impl InputEngine for Fixture {
        fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
            let mut result = self.select(index)?;
            result.commit.push_str("-remaining-segments");
            Ok(result)
        }
        fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError> {
            Ok(EngineSnapshot {
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
            if value.is_ascii_digit() {
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
    }
    fn runtime() -> Runtime<Fixture> {
        Runtime::new(
            Fixture {
                words: (0..12).map(|n| format!("candidate-{n}")).collect(),
                text: String::new(),
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
}
