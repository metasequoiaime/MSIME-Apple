//! Host-independent voice session lifecycle. Audio and ASR transports are injected.

/// Platform-injected streaming voice transport.
pub trait VoiceTransport {
    type Error;
    fn start(&mut self, generation: u64) -> Result<(), Self::Error>;
    fn send_audio(&mut self, generation: u64, pcm16_mono_16khz: &[u8]) -> Result<(), Self::Error>;
    fn finish(&mut self, generation: u64) -> Result<(), Self::Error>;
    fn cancel(&mut self, generation: u64) -> Result<(), Self::Error>;
}


#[derive(Debug, Default)]
pub struct VoiceSessionState {
    generation: u64,
    active: bool,
}

impl VoiceSessionState {
    pub fn start(&mut self) -> u64 {
        self.generation = self.generation.wrapping_add(1);
        self.active = true;
        self.generation
    }

    pub fn cancel(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        self.active = false;
    }

    pub fn apply(&mut self, generation: u64, text: &str) -> Option<String> {
        if !self.active || generation != self.generation || text.is_empty() {
            return None;
        }
        self.active = false;
        Some(text.to_owned())
    }

    pub fn is_active(&self) -> bool {
        self.active
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn stale_voice_results_are_rejected() {
        let mut state = VoiceSessionState::default();
        let old = state.start();
        state.cancel();
        let current = state.start();
        assert!(state.apply(old, "旧结果").is_none());
        assert_eq!(state.apply(current, "新结果"), Some("新结果".into()));
        assert!(!state.is_active());
    }
}
