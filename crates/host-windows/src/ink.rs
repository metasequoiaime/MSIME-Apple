//! Windows Ink handwriting recognition.
//!
//! Windows ships a handwriting recognizer for every installed language pack,
//! and the reference panel uses it directly. Without this, Windows had no
//! recognizer at all unless the optional packaged Engine model happened to be
//! installed, so the handwriting panel answered "unavailable" on a stock
//! machine — the one platform where a recognizer is already present.
//!
//! Nothing here reads user text beyond the strokes the panel passes in, and no
//! stroke leaves the machine: `InkRecognizerContainer` resolves locally.

use windows::Foundation::Point;
use windows::UI::Input::Inking::{
    InkPoint, InkRecognitionTarget, InkRecognizerContainer, InkStrokeBuilder, InkStrokeContainer,
};

/// One handwritten stroke: the points the pointer passed through, in order.
pub type Stroke = Vec<(f32, f32)>;

/// Why recognition could not answer. The panel distinguishes these because
/// they need different things from the user.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum InkError {
    /// No Simplified Chinese recognizer is installed. The user has to add the
    /// handwriting feature for the language; nothing we do will substitute.
    NoChineseRecognizer,
    /// Nothing to recognize.
    EmptyInput,
    /// The Ink API itself failed.
    Unavailable,
}

/// Longest run of strokes we will hand to the recognizer, matching the panel's
/// own limit. A caller that ignored its limit must not be able to make us
/// build an unbounded stroke container.
const MAX_STROKES: usize = 128;
/// Longest single stroke. A pointer stream stuck in a loop is bounded here.
const MAX_POINTS: usize = 4096;

/// True when the recognizer's name looks like Simplified Chinese.
///
/// Matching on the name is what the reference does. The recognizer list is
/// localised, so the display name arrives in the user's own UI language and no
/// single spelling covers it — hence several, including the English one.
fn looks_like_chinese(name: &str) -> bool {
    let lowered = name.to_lowercase();
    ["中文", "简体", "chinese", "zh-cn"]
        .iter()
        .any(|needle| lowered.contains(needle))
}

/// True when the text contains a CJK ideograph.
fn contains_cjk(text: &str) -> bool {
    text.chars().any(|ch| {
        matches!(ch as u32, 0x3400..=0x4DBF | 0x4E00..=0x9FFF | 0xF900..=0xFAFF)
    })
}

/// Recognize handwritten strokes, most likely candidate first.
///
/// Chinese candidates are ordered ahead of the rest: the recognizer returns
/// Latin readings of the same strokes too, and a user writing Chinese should
/// not have to scroll past them.
pub fn recognize(strokes: &[Stroke]) -> Result<Vec<String>, InkError> {
    if strokes.is_empty() || strokes.iter().all(|stroke| stroke.len() < 2) {
        return Err(InkError::EmptyInput);
    }
    recognize_inner(strokes).unwrap_or_else(Err)
}

fn recognize_inner(strokes: &[Stroke]) -> Result<Result<Vec<String>, InkError>, InkError> {
    let container = InkRecognizerContainer::new().map_err(|_| InkError::Unavailable)?;
    let recognizers = container.GetRecognizers().map_err(|_| InkError::Unavailable)?;
    let mut chosen = false;
    for recognizer in recognizers {
        let name = recognizer
            .Name()
            .map(|value| value.to_string_lossy())
            .unwrap_or_default();
        if looks_like_chinese(&name) {
            container
                .SetDefaultRecognizer(&recognizer)
                .map_err(|_| InkError::Unavailable)?;
            chosen = true;
            break;
        }
    }
    if !chosen {
        // Not a failure we can retry around: the user has to install the
        // handwriting feature for Chinese.
        return Ok(Err(InkError::NoChineseRecognizer));
    }

    let strokes_container = InkStrokeContainer::new().map_err(|_| InkError::Unavailable)?;
    let builder = InkStrokeBuilder::new().map_err(|_| InkError::Unavailable)?;
    // The identity transform: the panel already sends canvas-relative points.
    let identity = windows_numerics::Matrix3x2 {
        M11: 1.0,
        M12: 0.0,
        M21: 0.0,
        M22: 1.0,
        M31: 0.0,
        M32: 0.0,
    };
    for stroke in strokes.iter().take(MAX_STROKES) {
        // A single point is a dot, not a stroke; the builder rejects it and
        // would fail the whole batch over one stray tap.
        if stroke.len() < 2 {
            continue;
        }
        // The projection's iterable takes the type's default representation,
        // which for a WinRT class is Option<T>.
        let points: Vec<Option<InkPoint>> = stroke
            .iter()
            .take(MAX_POINTS)
            .filter(|(x, y)| x.is_finite() && y.is_finite())
            .map(|&(x, y)| {
                InkPoint::CreateInkPoint(Point { X: x, Y: y }, 0.5).map(Some)
            })
            .collect::<Result<_, _>>()
            .map_err(|_| InkError::Unavailable)?;
        if points.len() < 2 {
            continue;
        }
        let built = builder
            .CreateStrokeFromInkPoints(
                &windows_collections::IIterable::<InkPoint>::from(points),
                identity,
            )
            .map_err(|_| InkError::Unavailable)?;
        strokes_container
            .AddStroke(&built)
            .map_err(|_| InkError::Unavailable)?;
    }

    let results = container
        .RecognizeAsync(&strokes_container, InkRecognitionTarget::All)
        .map_err(|_| InkError::Unavailable)?
        .get()
        .map_err(|_| InkError::Unavailable)?;

    let mut chinese: Vec<String> = Vec::new();
    let mut other: Vec<String> = Vec::new();
    for result in results {
        let Ok(candidates) = result.GetTextCandidates() else {
            continue;
        };
        for candidate in candidates {
            let text = candidate.to_string_lossy();
            if text.is_empty() {
                continue;
            }
            let bucket = if contains_cjk(&text) {
                &mut chinese
            } else {
                &mut other
            };
            // The recognizer repeats candidates across results; a duplicate
            // costs the user a candidate slot for nothing.
            if !bucket.contains(&text) {
                bucket.push(text);
            }
        }
    }
    chinese.retain(|text| !text.is_empty());
    for text in other {
        if !chinese.contains(&text) {
            chinese.push(text);
        }
    }
    Ok(Ok(chinese))
}

#[cfg(test)]
mod tests {
    use super::*;

    // Name matching is the part that decides whether Windows recognises
    // Chinese at all, and the list arrives localised.
    #[test]
    fn recognizer_names_are_matched_in_any_ui_language() {
        assert!(looks_like_chinese("中文(简体，中国)"));
        assert!(looks_like_chinese("简体中文"));
        assert!(looks_like_chinese("Chinese (Simplified, China)"));
        assert!(looks_like_chinese("chinese"));
        assert!(looks_like_chinese("zh-CN"));
        // Case is folded, so an unexpected capitalisation still matches.
        assert!(looks_like_chinese("ZH-CN"));
        assert!(looks_like_chinese("CHINESE (SIMPLIFIED)"));
    }

    // Picking the wrong recognizer is worse than picking none: it would
    // silently return Latin readings of Chinese strokes.
    #[test]
    fn other_languages_are_not_mistaken_for_chinese() {
        assert!(!looks_like_chinese("English (United States)"));
        assert!(!looks_like_chinese("日本語"));
        assert!(!looks_like_chinese("한국어"));
        assert!(!looks_like_chinese("Deutsch"));
        assert!(!looks_like_chinese(""));
    }

    #[test]
    fn cjk_detection_sorts_candidates() {
        assert!(contains_cjk("你好"));
        assert!(contains_cjk("a你"));
        // Extension A and compatibility ideographs count too.
        assert!(contains_cjk("\u{3400}"));
        assert!(contains_cjk("\u{F900}"));
        assert!(!contains_cjk("hello"));
        assert!(!contains_cjk(""));
        // Punctuation and kana are not ideographs.
        assert!(!contains_cjk("，。"));
        assert!(!contains_cjk("ひらがな"));
    }

    // Empty input must be reported as such rather than reaching the Ink API,
    // which would report a generic failure the panel cannot explain.
    #[test]
    fn empty_input_is_rejected_before_calling_windows() {
        assert_eq!(recognize(&[]), Err(InkError::EmptyInput));
        // A single tap is a dot, not a stroke.
        assert_eq!(recognize(&[vec![(1.0, 1.0)]]), Err(InkError::EmptyInput));
        assert_eq!(
            recognize(&[vec![(1.0, 1.0)], vec![(2.0, 2.0)]]),
            Err(InkError::EmptyInput)
        );
    }
}
