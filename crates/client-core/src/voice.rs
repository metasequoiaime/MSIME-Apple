//! Host independent voice input contracts.
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoiceProvider { LocalWhisper, Cloud }

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct VoiceRecognitionRequest { pub provider: VoiceProvider, pub language: String, pub audio: Vec<u8> }

impl VoiceRecognitionRequest {
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.language.is_empty() || self.language.len() > 32 { return Err("invalid language"); }
        if self.audio.is_empty() { return Err("empty audio"); }
        if self.audio.len() > 25 * 1024 * 1024 { return Err("audio too large"); }
        Ok(())
    }
}

#[cfg(test)]
mod tests { use super::*; #[test] fn validates_bounds() { let r=VoiceRecognitionRequest{provider:VoiceProvider::LocalWhisper,language:"zh-CN".into(),audio:vec![1]}; assert!(r.validate().is_ok()); let mut e=r.clone(); e.audio.clear(); assert!(e.validate().is_err()); } }
