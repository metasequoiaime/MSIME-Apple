//! Owning CXX bridge to the pinned C++ Session. No Tauri or native UI dependency.
//! Sessions remain thread-confined; no unsafe Send/Sync implementation is provided.

#[cxx::bridge(namespace = "msime")]
mod ffi {
    #[derive(Clone)]
    pub struct DictionaryStateRecord {
        pub kind: u8,
        pub context: String,
        pub key: String,
        pub value: String,
        pub weight: i64,
        pub display: String,
        pub deleted: bool,
        pub user_inserted: bool,
        pub position: i32,
        pub count: i32,
    }
    #[derive(Clone)]
    pub struct EngineOptions {
        pub resources: String,
        pub user_data: String,
        pub cache: String,
        pub dictionaries: String,
        pub scheme: u8,
        pub shuangpin_profile: u8,
        pub learning: bool,
        pub autocorrect: bool,
        pub helpcode: bool,
        pub helpcode_schema: String,
        pub chinese_punctuation: bool,
        pub frequency_mode: String,
        pub frequency_trigger_count: u8,
        pub frequency_linear_step: u8,
        pub mixed_english: bool,
        pub english_minimum_prefix: u8,
        pub mixed_emoji: bool,
        pub mixed_kaomoji: bool,
        pub local_unicode: bool,
        pub local_date_time: bool,
        pub local_quick_phrase: bool,
        pub local_emoji: bool,
        pub local_kaomoji: bool,
        pub local_super_jianpin: bool,
        pub local_temporary_english: bool,
        pub local_temporary_japanese: bool,
    }
    #[derive(Debug)]
    pub struct EngineSnapshot {
        pub local_mode: String,
        pub microsoft_shuangpin: bool,
        pub shuangpin_profile: String,
        pub preedit: String,
        pub editing_text: String,
        pub caret_position: usize,
        pub candidates: Vec<String>,
        pub scheme: u8,
        pub answered_by_pinyin_fallback: bool,
        pub candidate_annotations: Vec<String>,
    }
    #[derive(Debug)]
    pub struct EngineResult {
        pub handled: bool,
        pub has_commit: bool,
        pub commit: String,
        pub diagnostic: String,
    }
    #[derive(Debug)]
    pub struct OnlineQuerySnapshot {
        pub available: bool,
        pub scheme: u8,
        pub generation: u64,
        pub identity: String,
        pub query_text: String,
        pub cache_key: String,
        pub pinyin_segments: Vec<String>,
        pub cloud_eligible: bool,
        pub ai_eligible: bool,
        pub session_id: u64,
    }
    unsafe extern "C++" {
        include!("bridge.h");
        type EngineSession;
        fn create_session(options: &EngineOptions) -> Result<UniquePtr<EngineSession>>;
        fn validate_personal_dictionary(kind: u8, key: &str, value: &str) -> String;
        fn prepare_options(
            resources: &str,
            user_data: &str,
            cache: &str,
            content_id: &str,
        ) -> Result<EngineOptions>;
        fn stage_dictionary_state(resources: &str, generation: &str, content_id: &str,
            records: &Vec<DictionaryStateRecord>) -> Result<EngineOptions>;
        fn snapshot(self: &EngineSession) -> Result<EngineSnapshot>;
        fn online_query(self: &EngineSession) -> Result<OnlineQuerySnapshot>;
        fn apply_online_candidate(
            self: Pin<&mut EngineSession>,
            query: &OnlineQuerySnapshot,
            candidate: &str,
            source: u8,
        ) -> Result<bool>;
        fn character(self: Pin<&mut EngineSession>, value: u8, shift: bool)
            -> Result<EngineResult>;
        fn command(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
        fn select(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn pin_candidate(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn remove_candidate(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn select_edge(
            self: Pin<&mut EngineSession>,
            index: usize,
            edge: u8,
        ) -> Result<EngineResult>;
        fn finish(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn punctuation(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
        fn set_chinese_punctuation_enabled(
            self: Pin<&mut EngineSession>,
            enabled: bool,
        ) -> Result<()>;
        fn set_paired_punctuation_enabled(
            self: Pin<&mut EngineSession>,
            enabled: bool,
        ) -> Result<()>;
        fn set_punctuation_lock(self: Pin<&mut EngineSession>, lock: u8) -> Result<()>;
        fn set_dedicated_english(self: Pin<&mut EngineSession>, enabled: bool) -> Result<()>;
    }
}

pub use ffi::{
    DictionaryStateRecord, EngineOptions, EngineResult, EngineSnapshot, OnlineQuerySnapshot,
};

/// Validate a personal dictionary entry using the pinned Engine contract.
pub fn validate_personal_dictionary(kind: u8, key: &str, value: &str) -> String {
    ffi::validate_personal_dictionary(kind, key, value)
}

/// Delegate working-dictionary preparation and learning replay to the Engine.
/// Caller verifies resources first and quiesces all users of these data paths.
pub fn prepare_options(
    resources: &str,
    user_data: &str,
    cache: &str,
    content_id: &str,
) -> Result<EngineOptions, cxx::Exception> {
    ffi::prepare_options(resources, user_data, cache, content_id)
}
pub fn stage_dictionary_state(resources: &str, generation: &str, content_id: &str,
                              records: &Vec<DictionaryStateRecord>) -> Result<EngineOptions, cxx::Exception> {
    ffi::stage_dictionary_state(resources, generation, content_id, records)
}

#[derive(Clone, Copy)]
#[repr(u8)]
pub enum Command {
    Backspace,
    CommitCandidate,
    CommitRaw,
    Cancel,
    MoveLeft,
    MoveRight,
    MoveHome,
    MoveEnd,
    DeleteForward,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum CandidateEdge {
    FirstHan = 0,
    LastHan = 1,
}

pub struct Session {
    inner: cxx::UniquePtr<ffi::EngineSession>,
    _thread_confined: std::marker::PhantomData<std::rc::Rc<()>>,
}

impl Session {
    pub fn new(options: &EngineOptions) -> Result<Self, cxx::Exception> {
        Ok(Self {
            inner: ffi::create_session(options)?,
            _thread_confined: std::marker::PhantomData,
        })
    }
    pub fn snapshot(&self) -> Result<EngineSnapshot, cxx::Exception> {
        self.inner.snapshot()
    }
    pub fn online_query(&self) -> Result<OnlineQuerySnapshot, cxx::Exception> {
        self.inner.online_query()
    }
    pub fn apply_online_candidate(
        &mut self,
        query: &OnlineQuerySnapshot,
        candidate: &str,
        source: u8,
    ) -> Result<bool, cxx::Exception> {
        self.inner
            .pin_mut()
            .apply_online_candidate(query, candidate, source)
    }
    pub fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().character(value, shift)
    }
    pub fn command(&mut self, command: Command) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().command(command as u8)
    }
    pub fn select(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().select(index)
    }
    pub fn pin_candidate(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> { self.inner.pin_mut().pin_candidate(index) }
    pub fn remove_candidate(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> { self.inner.pin_mut().remove_candidate(index) }
    pub fn select_edge(
        &mut self,
        index: usize,
        edge: CandidateEdge,
    ) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().select_edge(index, edge as u8)
    }
    pub fn finish(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().finish(index)
    }
    pub fn punctuation(&mut self, value: u8) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().punctuation(value)
    }
    pub fn set_chinese_punctuation_enabled(&mut self, enabled: bool) -> Result<(), cxx::Exception> {
        self.inner
            .pin_mut()
            .set_chinese_punctuation_enabled(enabled)
    }
    pub fn set_paired_punctuation_enabled(&mut self, enabled: bool) -> Result<(), cxx::Exception> {
        self.inner
            .pin_mut()
            .set_paired_punctuation_enabled(enabled)
    }
    pub fn set_punctuation_lock(&mut self, lock: u8) -> Result<(), cxx::Exception> {
        self.inner.pin_mut().set_punctuation_lock(lock)
    }
    pub fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), cxx::Exception> {
        self.inner.pin_mut().set_dedicated_english(enabled)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn options(root: &std::path::Path) -> EngineOptions {
        let path = |name| {
            let path = root.join(name);
            std::fs::create_dir_all(&path).unwrap();
            path.to_str().unwrap().to_owned()
        };
        EngineOptions {
            resources: path("resources"),
            user_data: path("user"),
            cache: path("cache"),
            dictionaries: path("dictionaries"),
            scheme: 0,
            shuangpin_profile: 0,
            learning: false,
            autocorrect: true,
            helpcode: false,
            helpcode_schema: "ziranma".into(),
            chinese_punctuation: true,
            frequency_mode: "promote".into(),
            frequency_trigger_count: 1,
            frequency_linear_step: 1,
            mixed_english: true,
            english_minimum_prefix: 2,
            mixed_emoji: false,
            mixed_kaomoji: false,
            local_unicode: true,
            local_date_time: true,
            local_quick_phrase: true,
            local_emoji: true,
            local_kaomoji: true,
            local_super_jianpin: true,
            local_temporary_english: true,
            local_temporary_japanese: true,
        }
    }
    #[test]
    fn helpcode_settings_reach_the_real_engine() {
        let dir = tempfile::tempdir().unwrap();
        let mut value = options(dir.path());
        for schema in ["lantian", "ziranma", "shouyou2_0", "shouyouplus", "xiaohe"] {
            value.helpcode_schema = schema.into();
            for enabled in [false, true] {
                value.helpcode = enabled;
                let mut session = Session::new(&value).unwrap();
                session.character(b'n', false).unwrap();
                session.character(b'i', false).unwrap();
                assert_eq!(session.character(b'H', true).unwrap().handled, enabled);
            }
        }
        value.helpcode_schema = "unknown".into();
        assert!(Session::new(&value).is_err());
    }

    #[test]
    fn invalid_options_return_errors_instead_of_unwinding_into_rust() {
        let dir = tempfile::tempdir().unwrap();
        let mut value = options(dir.path());
        value.scheme = 255;
        assert!(Session::new(&value).is_err());
        value.scheme = 0;
        value.shuangpin_profile = 255;
        assert!(Session::new(&value).is_err());
        value.shuangpin_profile = 0;
        value.resources = "relative".into();
        assert!(Session::new(&value).is_err());
    }
    #[test]
    fn microsoft_profile_accepts_semicolon_as_an_ing_final() {
        let dir = tempfile::tempdir().unwrap();
        for profile in 0..4 {
            let mut options = options(dir.path());
            options.scheme = 1;
            options.shuangpin_profile = profile;
            let mut session = Session::new(&options).unwrap();
            session.character(b'b', false).unwrap();
            session.character(b';', false).unwrap();
            assert_eq!(
                session.snapshot().unwrap().editing_text,
                if profile == 3 { "b;" } else { "b" }
            );
        }
    }
    #[test]
    fn real_engine_handles_unicode_mode_without_a_dictionary_bundle() {
        let dir = tempfile::tempdir().unwrap();
        let mut session = Session::new(&options(dir.path())).unwrap();
        assert!(session.character(b'U', true).unwrap().handled);
        for character in b"4e2d" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        let snapshot = session.snapshot().unwrap();
        assert_eq!(snapshot.local_mode, "unicode");
        assert!(snapshot
            .candidates
            .iter()
            .any(|candidate| candidate == "中"));
        let result = session.select(0).unwrap();
        assert!(result.has_commit);
        assert_eq!(result.commit, "中");
        assert!(session.snapshot().unwrap().preedit.is_empty());
        assert_eq!(session.snapshot().unwrap().local_mode, "none");
    }
}
