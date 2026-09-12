//! Owning CXX bridge to the pinned C++ Session. No Tauri or native UI dependency.
//! Sessions remain thread-confined; no unsafe Send/Sync implementation is provided.

mod dictionary_revision;
pub use dictionary_revision::dictionary_state_revision;
use dictionary_revision::DictionaryRevision;
mod dictionary_stage;
use dictionary_stage::DictionaryRecordStream;
pub use dictionary_stage::{stage_dictionary_state, DictionaryStateRecord, SnapshotReadError};

#[cxx::bridge(namespace = "msime")]
mod ffi {
    extern "Rust" {
        type DictionaryRevision;
        fn text(self: &mut DictionaryRevision, value: &str);
        fn integer(self: &mut DictionaryRevision, value: u64);
        type DictionaryRecordStream;
        fn next(self: &mut DictionaryRecordStream) -> Result<DictionaryStateWire>;
    }
    struct DictionaryStateWire {
        record_type: u8,
        kind: DictionaryKind,
        context: String,
        key: String,
        value: String,
        number: i64,
        display: String,
        deleted: bool,
        user_inserted: bool,
    }
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
        pub autocorrect_transposition: bool,
        pub autocorrect_neighbor: bool,
        pub helpcode: bool,
        pub helpcode_schema: String,
        pub chinese_punctuation: bool,
        pub paired_punctuation: bool,
        pub punctuation_lock: u8,
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
        pub nine_key: bool,
        pub nine_key_spellings: Vec<String>,
        pub microsoft_shuangpin: bool,
        pub shuangpin_profile: String,
        pub preedit: String,
        pub editing_text: String,
        pub caret_position: usize,
        pub candidates: Vec<String>,
        pub scheme: u8,
        pub answered_by_pinyin_fallback: bool,
        pub candidate_annotations: Vec<String>,
        pub candidate_sources: Vec<u8>,
        pub candidate_positions: Vec<u8>,
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
    #[derive(Debug)]
    pub struct EmojiCatalogItem {
        pub text: String,
        pub annotation: String,
        pub group: String,
    }
    #[derive(Debug)]
    pub struct EmojiSymbolGroup {
        pub parent: String,
        pub title: String,
    }
    #[derive(Clone, Debug)]
    pub struct HandwritingPoint {
        pub stroke: u32,
        pub x: f32,
        pub y: f32,
    }
    unsafe extern "C++" {
        include!("bridge.h");
        type EngineSession;
        fn stage_dictionary_state(
            options: &EngineOptions,
            generation: &str,
            content_id: &str,
            maximum_records: usize,
            stream: &mut DictionaryRecordStream,
        ) -> Result<EngineOptions>;
        fn hash_dictionary_state(
            options: &EngineOptions,
            sink: &mut DictionaryRevision,
        ) -> Result<()>;
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
        fn online_query(self: &EngineSession) -> Result<OnlineQuerySnapshot>;
        fn apply_online_candidate(
            self: Pin<&mut EngineSession>,
            query: &OnlineQuerySnapshot,
            candidate: &str,
            source: u8,
        ) -> Result<bool>;
        fn emoji_catalog(
            resources: &str,
            search: &str,
            category: &str,
            limit: u8,
        ) -> Result<Vec<EmojiCatalogItem>>;
        fn emoji_catalog_page(
            resources: &str,
            search: &str,
            category: &str,
            offset: usize,
            limit: u16,
        ) -> Result<Vec<EmojiCatalogItem>>;
        fn emoji_catalog_filtered_page(
            resources: &str,
            search: &str,
            category: &str,
            group: &str,
            offset: usize,
            limit: u16,
            parent: &str,
        ) -> Result<Vec<EmojiCatalogItem>>;
        fn emoji_symbol_groups(resources: &str) -> Result<Vec<EmojiSymbolGroup>>;
        fn emoji_catalog_groups(resources: &str, category: &str) -> Result<Vec<String>>;
        fn handwriting_recognize(
            model_path: &str,
            points: &[HandwritingPoint],
            width: f32,
            height: f32,
        ) -> Result<Vec<String>>;
        fn character(self: Pin<&mut EngineSession>, value: u8, shift: bool)
            -> Result<EngineResult>;
        fn set_nine_key_enabled(self: Pin<&mut EngineSession>, enabled: bool) -> Result<()>;
        fn choose_nine_key_spelling(
            self: Pin<&mut EngineSession>,
            index: usize,
        ) -> Result<EngineResult>;
        fn command(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
        fn select(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn pin_candidate(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn remove_candidate(self: Pin<&mut EngineSession>, index: usize) -> Result<EngineResult>;
        fn fix_candidate_position(
            self: Pin<&mut EngineSession>,
            index: usize,
            position: u8,
        ) -> Result<EngineResult>;
        fn clear_candidate_position(
            self: Pin<&mut EngineSession>,
            index: usize,
        ) -> Result<EngineResult>;
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
        fn set_punctuation_lock(self: Pin<&mut EngineSession>, lock: u8) -> Result<()>;
        fn set_paired_punctuation_enabled(
            self: Pin<&mut EngineSession>,
            enabled: bool,
        ) -> Result<()>;
        fn set_dedicated_english(self: Pin<&mut EngineSession>, enabled: bool) -> Result<()>;
    }
}

pub use ffi::{
    DictionaryEntry, DictionaryKind, DictionaryPage, EmojiCatalogItem, EngineOptions, EngineResult,
    EngineSnapshot, HandwritingPoint, OnlineQuerySnapshot,
};

/// Read a bounded page of user-inserted entries, excluding the bundled dictionary.
pub fn dictionary_entries(
    options: &EngineOptions,
    offset: usize,
    limit: usize,
) -> Result<DictionaryPage, cxx::Exception> {
    ffi::dictionary_entries(options, offset, limit)
}

/// Atomically add, replace, or remove one personal-dictionary entry.
/// The caller must quiesce sessions sharing these paths before editing.
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

pub fn emoji_catalog(
    resources: &str,
    search: &str,
    category: &str,
    limit: u8,
) -> Result<Vec<EmojiCatalogItem>, cxx::Exception> {
    ffi::emoji_catalog(resources, search, category, limit)
}

pub fn emoji_catalog_page(
    resources: &str,
    search: &str,
    category: &str,
    offset: usize,
    limit: u16,
) -> Result<Vec<EmojiCatalogItem>, cxx::Exception> {
    ffi::emoji_catalog_page(resources, search, category, offset, limit)
}

pub fn emoji_catalog_filtered_page(
    resources: &str,
    search: &str,
    category: &str,
    group: &str,
    offset: usize,
    limit: u16,
) -> Result<Vec<EmojiCatalogItem>, cxx::Exception> {
    ffi::emoji_catalog_filtered_page(resources, search, category, group, offset, limit, "")
}

pub fn emoji_catalog_parent_page(
    resources: &str,
    search: &str,
    category: &str,
    group: &str,
    offset: usize,
    limit: u16,
    parent: &str,
) -> Result<Vec<EmojiCatalogItem>, cxx::Exception> {
    ffi::emoji_catalog_filtered_page(resources, search, category, group, offset, limit, parent)
}

pub fn emoji_symbol_groups(resources: &str) -> Result<Vec<ffi::EmojiSymbolGroup>, cxx::Exception> {
    ffi::emoji_symbol_groups(resources)
}

pub fn emoji_catalog_groups(
    resources: &str,
    category: &str,
) -> Result<Vec<String>, cxx::Exception> {
    ffi::emoji_catalog_groups(resources, category)
}

/// Run the Engine's optional offline handwriting recognizer on copied strokes.
/// Points are flattened with their zero-based stroke index for the CXX ABI.
pub fn handwriting_recognize(
    model_path: &str,
    strokes: &[Vec<(f32, f32)>],
    width: f32,
    height: f32,
) -> Result<Vec<String>, cxx::Exception> {
    let points: Vec<HandwritingPoint> = strokes
        .iter()
        .enumerate()
        .flat_map(|(stroke, points)| {
            points.iter().map(move |&(x, y)| HandwritingPoint {
                stroke: stroke as u32,
                x,
                y,
            })
        })
        .collect();
    ffi::handwriting_recognize(model_path, &points, width, height)
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
    pub fn set_nine_key_enabled(&mut self, enabled: bool) -> Result<(), cxx::Exception> {
        self.inner.pin_mut().set_nine_key_enabled(enabled)
    }
    pub fn choose_nine_key_spelling(
        &mut self,
        index: usize,
    ) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().choose_nine_key_spelling(index)
    }
    pub fn command(&mut self, command: Command) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().command(command as u8)
    }
    pub fn select(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().select(index)
    }
    pub fn pin_candidate(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().pin_candidate(index)
    }
    pub fn remove_candidate(&mut self, index: usize) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().remove_candidate(index)
    }
    pub fn fix_candidate_position(
        &mut self,
        index: usize,
        position: u8,
    ) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().fix_candidate_position(index, position)
    }
    pub fn clear_candidate_position(
        &mut self,
        index: usize,
    ) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().clear_candidate_position(index)
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
    pub fn set_punctuation_lock(&mut self, lock: u8) -> Result<(), cxx::Exception> {
        self.inner.pin_mut().set_punctuation_lock(lock)
    }
    pub fn set_paired_punctuation_enabled(&mut self, enabled: bool) -> Result<(), cxx::Exception> {
        self.inner.pin_mut().set_paired_punctuation_enabled(enabled)
    }
    pub fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), cxx::Exception> {
        self.inner.pin_mut().set_dedicated_english(enabled)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    pub(super) fn options(root: &std::path::Path) -> EngineOptions {
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
            autocorrect_transposition: true,
            autocorrect_neighbor: true,
            helpcode: false,
            helpcode_schema: "ziranma".into(),
            chinese_punctuation: true,
            paired_punctuation: true,
            punctuation_lock: 0,
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
    fn dictionary_revision_uses_real_journal_and_rejects_corruption() {
        let dir = tempfile::tempdir().unwrap();
        let value = options(dir.path());
        let before = super::dictionary_state_revision(&value).unwrap();
        assert_eq!(before.len(), 64);
        assert_eq!(before, super::dictionary_state_revision(&value).unwrap());
        let journal = std::path::Path::new(&value.user_data).join("msime_user.db");
        assert!(!journal.exists());
        std::fs::write(&journal, b"synthetic invalid database").unwrap();
        assert!(super::dictionary_state_revision(&value).is_err());
        assert_eq!(
            std::fs::read(&journal).unwrap(),
            b"synthetic invalid database"
        );
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

    #[test]
    fn real_engine_exposes_nine_key_mode_and_spelling_choices() {
        let dir = tempfile::tempdir().unwrap();
        let mut session = Session::new(&options(dir.path())).unwrap();
        assert!(!session.snapshot().unwrap().nine_key);
        assert!(!session.character(b'6', false).unwrap().handled);
        session.set_nine_key_enabled(true).unwrap();
        assert!(session.snapshot().unwrap().nine_key);
        assert!(session.character(b'6', false).unwrap().handled);
        let snapshot = session.snapshot().unwrap();
        assert!(!snapshot.nine_key_spellings.is_empty());
        assert!(
            !session
                .choose_nine_key_spelling(snapshot.nine_key_spellings.len())
                .unwrap()
                .handled
        );
        assert!(session.choose_nine_key_spelling(0).unwrap().handled);
        session.command(Command::Cancel).unwrap();
        session.set_nine_key_enabled(false).unwrap();
        assert!(!session.snapshot().unwrap().nine_key);
    }
}
