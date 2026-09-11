//! Host independent voice input contracts.
use serde::{Deserialize, Serialize};

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoiceProvider { LocalWhisper, Cloud }

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct VoiceRecognitionRequest { pub provider: VoiceProvider, pub language: String, pub audio: Vec<u8> }

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct VoiceRecognitionResult { pub text: String, pub confidence: Option<u16> }

impl VoiceRecognitionResult { pub fn validate(&self) -> Result<(), &'static str> { if self.text.len() > 16 * 1024 { return Err("text too large"); } if self.confidence.is_some_and(|v| v > 1000) { return Err("invalid confidence"); } Ok(()) } }

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
