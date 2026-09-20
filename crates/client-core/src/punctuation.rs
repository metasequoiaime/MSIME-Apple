//! Host-context punctuation decisions shared by native clients.

use crate::preferences::PunctuationLock;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PunctuationRoute {
    Engine,
    Ascii,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PunctuationContext {
    pub character: u8,
    pub preceding: Option<char>,
    pub host_context_available: bool,
    pub has_composition: bool,
    pub chinese_punctuation: bool,
    pub smart_punctuation: bool,
    /// Keep `,` `.` `:` as ASCII after a digit, and after a letter. Two
    /// switches rather than one, because a version number and an English
    /// sentence want different answers - and both are off on the Windows
    /// baseline, so a host that ignored them was converting for users who had
    /// asked for neither.
    pub direct_digit: bool,
    pub direct_letter: bool,
    pub lock: PunctuationLock,
}

/// Select the explicit ASCII route only when a host document decision is safe.
/// Engine remains authoritative for composition, local/Japanese/English modes,
/// and all punctuation not covered by the shared smart-punctuation contract.
pub fn route(context: PunctuationContext) -> PunctuationRoute {
    if context.has_composition || !context.host_context_available {
        return PunctuationRoute::Engine;
    }
    match context.lock {
        PunctuationLock::Chinese => return PunctuationRoute::Engine,
        PunctuationLock::English => return PunctuationRoute::Ascii,
        PunctuationLock::Follow => {}
    }
    let direct = context.preceding.is_some_and(|value| {
        (value.is_ascii_digit() && context.direct_digit)
            || (value.is_ascii_alphabetic() && context.direct_letter)
    });
    if context.chinese_punctuation
        && context.smart_punctuation
        && matches!(context.character, b',' | b'.' | b':')
        && direct
    {
        PunctuationRoute::Ascii
    } else {
        PunctuationRoute::Engine
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn context(character: u8, preceding: Option<char>) -> PunctuationContext {
        PunctuationContext {
            character,
            preceding,
            host_context_available: true,
            has_composition: false,
            chinese_punctuation: true,
            smart_punctuation: true,
            direct_digit: true,
            direct_letter: true,
            lock: PunctuationLock::Follow,
        }
    }

    #[test]
    fn ascii_alphanumeric_context_uses_ascii_for_supported_marks() {
        for preceding in ['0', '9', 'a', 'z', 'A', 'Z'] {
            for character in *b",.:" {
                assert_eq!(
                    route(context(character, Some(preceding))),
                    PunctuationRoute::Ascii
                );
            }
        }
    }

    #[test]
    fn unsupported_or_non_ascii_context_stays_with_engine() {
        for preceding in [None, Some('中'), Some(' '), Some('_')] {
            assert_eq!(route(context(b',', preceding)), PunctuationRoute::Engine);
        }
        assert_eq!(route(context(b'?', Some('a'))), PunctuationRoute::Engine);
    }

    #[test]
    fn lock_and_composition_take_precedence() {
        let mut value = context(b',', Some('a'));
        value.lock = PunctuationLock::Chinese;
        assert_eq!(route(value), PunctuationRoute::Engine);
        value.lock = PunctuationLock::English;
        assert_eq!(route(value), PunctuationRoute::Ascii);
        value.has_composition = true;
        assert_eq!(route(value), PunctuationRoute::Engine);
    }

    #[test]
    fn each_direct_switch_only_answers_for_its_own_kind_of_neighbour() {
        // Off is the Windows baseline and the shipped default, so a host that reads neither switch was
        // converting punctuation for every user who had asked for none of it.
        let mut value = context(b'.', Some('7'));
        value.direct_digit = false;
        value.direct_letter = true;
        assert_eq!(route(value), PunctuationRoute::Engine);

        let mut value = context(b'.', Some('a'));
        value.direct_digit = true;
        value.direct_letter = false;
        assert_eq!(route(value), PunctuationRoute::Engine);

        // A version number and an English sentence are the two cases the pair exists to separate.
        let mut value = context(b'.', Some('7'));
        value.direct_letter = false;
        assert_eq!(route(value), PunctuationRoute::Ascii);
        let mut value = context(b',', Some('z'));
        value.direct_digit = false;
        assert_eq!(route(value), PunctuationRoute::Ascii);

        for preceding in ['7', 'a'] {
            let mut value = context(b':', Some(preceding));
            value.direct_digit = false;
            value.direct_letter = false;
            assert_eq!(route(value), PunctuationRoute::Engine);
        }
    }

    #[test]
    fn disabled_or_unavailable_host_context_stays_with_engine() {
        let mut value = context(b'.', Some('7'));
        value.smart_punctuation = false;
        assert_eq!(route(value), PunctuationRoute::Engine);
        value.smart_punctuation = true;
        value.chinese_punctuation = false;
        assert_eq!(route(value), PunctuationRoute::Engine);
        value.chinese_punctuation = true;
        value.host_context_available = false;
        assert_eq!(route(value), PunctuationRoute::Engine);
    }
}
