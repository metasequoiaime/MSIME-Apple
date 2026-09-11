//! Host independent voice input contracts.
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Clone, Debug, Error, Eq, PartialEq)]
pub enum VoiceError {
    #[error("invalid language")]
    InvalidLanguage,
    #[error("audio is empty")]
    EmptyAudio,
    #[error("audio is too large")]
    AudioTooLarge,
    #[error("recognized text is too large")]
    TextTooLarge,
    #[error("invalid confidence")]
    InvalidConfidence,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum VoiceProvider {
    LocalWhisper,
    Cloud,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct VoicePreferences {
    pub enabled: bool,
    pub provider: VoiceProvider,
    pub language: String,
}

impl Default for VoicePreferences {
    fn default() -> Self {
        Self {
            enabled: true,
            provider: VoiceProvider::LocalWhisper,
            language: "zh-CN".into(),
        }
    }
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct VoiceRecognitionRequest {
    pub provider: VoiceProvider,
    pub language: String,
    pub audio: Vec<u8>,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize, Deserialize)]
pub struct VoiceRecognitionResult {
    pub text: String,
    pub confidence: Option<u16>,
}

pub trait VoiceRecognizer {
    fn recognize(
        &self,
        request: &VoiceRecognitionRequest,
    ) -> Result<VoiceRecognitionResult, VoiceError>;
}

pub fn recognize<R: VoiceRecognizer>(
    recognizer: &R,
    request: &VoiceRecognitionRequest,
) -> Result<VoiceRecognitionResult, VoiceError> {
    request.validate()?;
    let result = recognizer.recognize(request)?;
    result.validate()?;
    Ok(result)
}

impl VoiceRecognitionResult {
    pub fn validate(&self) -> Result<(), VoiceError> {
        if self.text.len() > 16 * 1024 {
            return Err(VoiceError::TextTooLarge);
        }
        if self.confidence.is_some_and(|v| v > 1000) {
            return Err(VoiceError::InvalidConfidence);
        }
        Ok(())
    }
}

impl VoiceRecognitionRequest {
    pub fn validate(&self) -> Result<(), VoiceError> {
        if self.language.is_empty() || self.language.len() > 32 {
            return Err(VoiceError::InvalidLanguage);
        }
        if self.audio.is_empty() {
            return Err(VoiceError::EmptyAudio);
        }
        if self.audio.len() > 25 * 1024 * 1024 {
            return Err(VoiceError::AudioTooLarge);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn validates_bounds() {
        let request = VoiceRecognitionRequest {
            provider: VoiceProvider::LocalWhisper,
            language: "zh-CN".into(),
            audio: vec![1],
        };
        assert!(request.validate().is_ok());
        let mut empty = request.clone();
        empty.audio.clear();
        assert!(empty.validate().is_err());
    }

    struct Stub;
    impl VoiceRecognizer for Stub {
        fn recognize(
            &self,
            _: &VoiceRecognitionRequest,
        ) -> Result<VoiceRecognitionResult, VoiceError> {
            Ok(VoiceRecognitionResult {
                text: "你好".into(),
                confidence: Some(900),
            })
        }
    }
    #[test]
    fn dispatch_validates_request_and_result() {
        let r = VoiceRecognitionRequest {
            provider: VoiceProvider::Cloud,
            language: "zh-CN".into(),
            audio: vec![1],
        };
        assert_eq!(recognize(&Stub, &r).unwrap().text, "你好");
    }
}
