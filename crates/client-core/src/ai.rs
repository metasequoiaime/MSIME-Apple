//! Host independent contract for asynchronous AI candidate suggestions.
use serde::{Deserialize, Serialize};
use thiserror::Error;

#[derive(Debug, Clone, Error, Eq, PartialEq)]
pub enum AiError {
    #[error("segmented pinyin is empty or too large")]
    InvalidSegments,
    #[error("context is too large")]
    ContextTooLarge,
    #[error("candidate limit is invalid")]
    InvalidLimit,
    #[error("candidate text is empty or too large")]
    InvalidCandidate,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSuggestionRequest {
    pub segmented_pinyin: Vec<String>,
    pub context: String,
    pub candidate_limit: u8,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSuggestion {
    pub text: String,
}

#[derive(Debug, Clone, Eq, PartialEq, Serialize, Deserialize)]
pub struct AiSuggestionResponse {
    pub candidates: Vec<AiSuggestion>,
}

pub trait AiSuggestor {
    fn suggest(&self, request: &AiSuggestionRequest) -> Result<AiSuggestionResponse, AiError>;
}

pub fn suggest<S: AiSuggestor>(
    suggestor: &S,
    request: &AiSuggestionRequest,
) -> Result<AiSuggestionResponse, AiError> {
    request.validate()?;
    let response = suggestor.suggest(request)?;
    response.validate(request.candidate_limit)?;
    Ok(response)
}

impl AiSuggestionRequest {
    pub fn validate(&self) -> Result<(), AiError> {
        if self.segmented_pinyin.is_empty()
            || self.segmented_pinyin.len() > 128
            || self
                .segmented_pinyin
                .iter()
                .any(|part| part.is_empty() || part.len() > 32)
        {
            return Err(AiError::InvalidSegments);
        }
        if self.context.len() > 16 * 1024 {
            return Err(AiError::ContextTooLarge);
        }
        if !(1..=10).contains(&self.candidate_limit) {
            return Err(AiError::InvalidLimit);
        }
        Ok(())
    }
}

impl AiSuggestionResponse {
    pub fn validate(&self, limit: u8) -> Result<(), AiError> {
        if self.candidates.len() > limit as usize {
            return Err(AiError::InvalidLimit);
        }
        if self
            .candidates
            .iter()
            .any(|candidate| candidate.text.is_empty() || candidate.text.len() > 4096)
        {
            return Err(AiError::InvalidCandidate);
        }
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    struct Stub;
    impl AiSuggestor for Stub {
        fn suggest(&self, _: &AiSuggestionRequest) -> Result<AiSuggestionResponse, AiError> {
            Ok(AiSuggestionResponse {
                candidates: vec![AiSuggestion {
                    text: "你好".into(),
                }],
            })
        }
    }
    #[test]
    fn validates_and_dispatches_suggestions() {
        let request = AiSuggestionRequest {
            segmented_pinyin: vec!["ni".into(), "hao".into()],
            context: String::new(),
            candidate_limit: 3,
        };
        assert_eq!(suggest(&Stub, &request).unwrap().candidates[0].text, "你好");
    }
    #[test]
    fn rejects_invalid_bounds() {
        let mut request = AiSuggestionRequest {
            segmented_pinyin: vec!["ni".into()],
            context: String::new(),
            candidate_limit: 0,
        };
        assert_eq!(request.validate(), Err(AiError::InvalidLimit));
        request.candidate_limit = 1;
        request.segmented_pinyin[0] = String::new();
        assert_eq!(request.validate(), Err(AiError::InvalidSegments));
    }
}
