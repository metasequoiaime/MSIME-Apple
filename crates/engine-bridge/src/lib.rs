//! Owning CXX bridge to the pinned C++ Session. No Tauri or native UI dependency.
//! Sessions remain thread-confined; no unsafe Send/Sync implementation is provided.

#[cxx::bridge(namespace = "msime")]
mod ffi {
    #[derive(Debug, Clone, Copy, PartialEq, Eq)]
    enum DictionaryKind {
        Pinyin,
        Wubi,
        QuickPhrase,
        English,
    }
    #[derive(Debug, Clone, PartialEq, Eq)]
    struct DictionaryEntry {
        kind: DictionaryKind,
        key: String,
        value: String,
        weight: i64,
    }
    #[derive(Debug)]
    struct DictionaryPage {
        entries: Vec<DictionaryEntry>,
        has_more: bool,
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
        // Same stable codes as EngineOptions, but from the live Engine snapshot.
        pub scheme: u8,
        pub local_mode: String,
        pub microsoft_shuangpin: bool,
        pub preedit: String,
        pub editing_text: String,
        pub caret_position: usize,
        pub candidates: Vec<String>,
    }
    #[derive(Debug)]
    pub struct EngineResult {
        pub handled: bool,
        pub has_commit: bool,
        pub commit: String,
        pub diagnostic: String,
    }
    unsafe extern "C++" {
        include!("bridge.h");
        type EngineSession;
        fn create_session(options: &EngineOptions) -> Result<UniquePtr<EngineSession>>;
        fn dictionary_entries(
            options: &EngineOptions,
            offset: usize,
            limit: usize,
        ) -> Result<DictionaryPage>;
        fn dictionary_edit(
            options: &EngineOptions,
            previous: &[DictionaryEntry],
            replacement: &[DictionaryEntry],
            request_id: &str,
        ) -> Result<()>;
        fn prepare_options(
            resources: &str,
            user_data: &str,
            cache: &str,
            content_id: &str,
        ) -> Result<EngineOptions>;
        fn snapshot(self: &EngineSession) -> Result<EngineSnapshot>;
        fn character(self: Pin<&mut EngineSession>, value: u8, shift: bool)
            -> Result<EngineResult>;
        fn command(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
        fn select(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
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
    }
}

pub use ffi::{DictionaryEntry, DictionaryKind, DictionaryPage};
pub use ffi::{EngineOptions, EngineResult, EngineSnapshot};

/// Read a bounded page of user-inserted entries, not the bundled dictionary.
/// Entries retain Engine's stable kind/key/value ordering. Limits are validated by Engine.
pub fn dictionary_entries(
    options: &EngineOptions,
    offset: usize,
    limit: usize,
) -> Result<DictionaryPage, cxx::Exception> {
    ffi::dictionary_entries(options, offset, limit)
}

/// Atomically add, replace or remove an entry and its replay journal.
///
/// The host must quiesce all sessions using these paths before writing, then recreate
/// them to invalidate caches. This bridge does not coordinate other threads/processes.
/// Previous values are optimistic concurrency guards. Use a stable nonempty request ID
/// for retries across process boundaries; do not log entries or raw Engine errors.
pub fn dictionary_edit(
    options: &EngineOptions,
    previous: Option<&DictionaryEntry>,
    replacement: Option<&DictionaryEntry>,
    request_id: &str,
) -> Result<(), cxx::Exception> {
    ffi::dictionary_edit(
        options,
        previous.map_or(&[], std::slice::from_ref),
        replacement.map_or(&[], std::slice::from_ref),
        request_id,
    )
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
    pub fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().character(value, shift)
    }
    pub fn command(&mut self, command: Command) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().command(command as u8)
    }
    pub fn select(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().select(index)
    }
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
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn dictionary_bridge_rejects_invalid_bounds_and_edits() {
        let dir = tempfile::tempdir().unwrap();
        let options = options(dir.path());
        for (offset, limit) in [(0, 0), (0, 1001), (1_000_001, 1)] {
            assert!(dictionary_entries(&options, offset, limit).is_err());
        }
        assert!(dictionary_edit(&options, None, None, "empty-fixture").is_err());
        let entry = DictionaryEntry {
            kind: DictionaryKind::QuickPhrase,
            key: "!".into(),
            value: "fixture".into(),
            weight: 1,
        };
        assert!(dictionary_edit(&options, None, Some(&entry), "invalid-fixture").is_err());
        assert!(
            ffi::dictionary_edit(&options, &[], &[entry.clone(), entry], "many-fixture").is_err()
        );
    }
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
        assert_eq!(snapshot.scheme, 0);
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
