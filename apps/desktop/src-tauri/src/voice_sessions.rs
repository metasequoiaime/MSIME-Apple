use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

#[derive(Clone)]
pub(crate) struct VoiceSession {
    pub request_id: String,
    pub generation: u64,
    pub path: PathBuf,
    pub cancelled: Arc<AtomicBool>,
}

#[derive(Default)]
struct State {
    generation: u64,
    active: Option<VoiceSession>,
}

#[derive(Default)]
pub(crate) struct VoiceSessions(Mutex<State>);

impl VoiceSessions {
    pub fn begin(&self, request_id: String, path: PathBuf) -> Option<VoiceSession> {
        let mut state = self.0.lock().ok()?;
        if state.active.is_some() {
            return None;
        }
        state.generation = state.generation.checked_add(1)?;
        let session = VoiceSession {
            request_id,
            generation: state.generation,
            path,
            cancelled: Arc::new(AtomicBool::new(false)),
        };
        state.active = Some(session.clone());
        Some(session)
    }

    pub fn finish(&self, generation: u64) {
        if let Ok(mut state) = self.0.lock() {
            if state
                .active
                .as_ref()
                .is_some_and(|s| s.generation == generation)
            {
                state.active = None;
            }
        }
    }

    pub fn cancel(&self, request_id: Option<&str>) -> Option<VoiceSession> {
        let mut state = self.0.lock().ok()?;
        let active = state.active.as_ref()?;
        if request_id.is_some_and(|id| id != active.request_id) {
            return None;
        }
        active.cancelled.store(true, Ordering::Relaxed);
        state.active.take()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancel_preserves_the_original_endpoint_and_generation() {
        let state = VoiceSessions::default();
        let first = state
            .begin("first".into(), "/fixture/old.sock".into())
            .unwrap();
        assert!(state
            .begin("overlap".into(), "/fixture/new.sock".into())
            .is_none());
        let cancelled = state.cancel(Some("first")).unwrap();
        assert_eq!(cancelled.path, PathBuf::from("/fixture/old.sock"));
        assert_eq!(cancelled.generation, first.generation);
        assert!(first.cancelled.load(Ordering::Relaxed));
        let second = state
            .begin("second".into(), "/fixture/new.sock".into())
            .unwrap();
        assert!(second.generation > first.generation);
        state.finish(first.generation);
        assert!(state.cancel(Some("first")).is_none());
        assert!(!second.cancelled.load(Ordering::Relaxed));
        assert_eq!(
            state.cancel(Some("second")).unwrap().generation,
            second.generation
        );
    }

    #[test]
    fn completed_sessions_and_repeated_cancel_do_not_affect_later_recordings() {
        let state = VoiceSessions::default();
        let first = state
            .begin("first".into(), "/fixture/provider.sock".into())
            .unwrap();
        state.finish(first.generation);
        assert!(state.cancel(None).is_none());
        let second = state.begin("second".into(), first.path).unwrap();
        assert_eq!(state.cancel(None).unwrap().generation, second.generation);
        assert!(state.cancel(None).is_none());
    }
}
