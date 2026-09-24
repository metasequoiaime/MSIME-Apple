//! Owning CXX bridge to the pinned C++ Session. No Tauri or native UI dependency.
//! Sessions remain thread-confined; no unsafe Send/Sync implementation is provided.

// The workspace denies unsafe code; the cxx bridge declares the pinned C++ Session's methods in an
// `unsafe extern "C++"` block; there is no safe spelling for a foreign vtable.
// The exemption is stated here rather than left implicit by opting out of
// the workspace lint table, which would also silently drop every other lint
// the workspace adds later.
#![allow(unsafe_code)]

mod dictionary_revision;
pub use dictionary_revision::dictionary_state_revision;
use dictionary_revision::DictionaryRevision;
mod dictionary_stage;
use dictionary_stage::DictionaryRecordStream;
pub use dictionary_stage::{stage_dictionary_state, DictionaryStateRecord, SnapshotReadError};

#[cxx::bridge(namespace = "msime")]
mod ffi {
    struct CaptureDevice {
        id: String,
        label: String,
    }
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
    /// A row of the dictionary tables themselves. `user_inserted` rows are the user's own words; every other row shipped with the dictionary (or was learned) and only its weight can change.
    #[derive(Debug, Clone, PartialEq, Eq)]
    struct DictionaryTableEntry {
        entry: DictionaryEntry,
        user_inserted: bool,
    }
    #[derive(Debug)]
    struct DictionaryTablePage {
        entries: Vec<DictionaryTableEntry>,
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
        pub shuangpin_preedit_uses_raw: bool,
        pub learning: bool,
        pub autocorrect_transposition: bool,
        pub autocorrect_neighbor: bool,
        pub fuzzy_pinyin_rules: u32,
        pub wubi_mixed_pinyin: bool,
        pub helpcode: bool,
        pub show_helpcode: bool,
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
        /// Ask the decoder for every whole-sentence reading it found rather than only its best.
        /// The runtime reorders them and crops the list, so a host that sets this must also be the
        /// one deciding what reaches the candidate page.
        pub sentence_alternatives: bool,
    }
    #[derive(Debug)]
    pub struct EngineSnapshot {
        pub local_mode: String,
        pub dedicated_english: bool,
        pub nine_key: bool,
        pub nine_key_spellings: Vec<String>,
        pub microsoft_shuangpin: bool,
        pub shuangpin_profile: String,
        pub preedit: String,
        /// Japanese kana reading shown to the user instead of the romaji editing text.
        pub reading: String,
        pub editing_text: String,
        pub caret_position: usize,
        pub segment_raw_boundaries: Vec<u64>,
        pub candidates: Vec<String>,
        pub candidate_codes: Vec<String>,
        pub scheme: u8,
        pub answered_by_pinyin_fallback: bool,
        pub wubi_unique_four_code: bool,
        pub candidate_annotations: Vec<String>,
        pub candidate_sources: Vec<u8>,
        pub candidate_positions: Vec<u8>,
        pub candidate_corrected: Vec<bool>,
        /// Whether each candidate answers the whole key, rather than a prefix of it or a completion
        /// running past it. The engine decides this to advance the composition, so it is reported
        /// rather than inferred: character count agrees only while a key has one segmentation, and
        /// `xian` reads as both 现 and 西安.
        pub candidate_answers_key: Vec<bool>,
    }
    #[derive(Debug)]
    pub struct EngineResult {
        pub handled: bool,
        pub has_commit: bool,
        pub commit: String,
        pub diagnostic: String,
    }
    pub struct DictionaryReplaySummary {
        pub applied: i32,
        pub skipped: i32,
        pub failed: i32,
        pub error: String,
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
    pub struct EmojiCatalogSlice {
        pub items: Vec<EmojiCatalogItem>,
        pub next_offset: usize,
        pub complete: bool,
    }
    #[derive(Debug)]
    pub struct EmojiSymbolGroup {
        pub parent: String,
        pub title: String,
    }
    /// One letter key of a double-pinyin face and the units it carries, already
    /// formatted for display as `initials / finals`.
    #[derive(Clone, Debug)]
    pub struct ShuangpinKeyHint {
        pub key: String,
        pub hint: String,
    }
    #[derive(Clone, Debug)]
    pub struct CandidateGlossInput {
        pub text: String,
        pub source: u8,
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
        fn reset_learned_data(options: &EngineOptions) -> Result<()>;
        fn hash_dictionary_state(
            options: &EngineOptions,
            sink: &mut DictionaryRevision,
        ) -> Result<()>;
        fn create_session(options: &EngineOptions) -> Result<UniquePtr<EngineSession>>;
        /// Capture bounded mono 16 kHz PCM samples through the Engine's
        /// platform-neutral AudioCapture implementation. An empty result
        /// means the host could not open a capture device.
        fn capture_audio(milliseconds: u32) -> Vec<f32>;
        fn capture_device_names() -> Vec<String>;
        fn capture_devices() -> Vec<CaptureDevice>;
        fn dictionary_entries(
            options: &EngineOptions,
            offset: usize,
            limit: usize,
        ) -> Result<DictionaryPage>;
        fn dictionary_export_entries(
            options: &EngineOptions,
            offset: usize,
            limit: usize,
            include_learned_pinyin: bool,
        ) -> Result<DictionaryPage>;
        fn dictionary_table_entries(
            options: &EngineOptions,
            kind: u8,
            query: &str,
            offset: usize,
            limit: usize,
        ) -> Result<DictionaryTablePage>;
        fn dictionary_edit_bundled(
            options: &EngineOptions,
            previous: &DictionaryEntry,
            weight: &[i64],
            request_id: &str,
        ) -> Result<()>;
        fn english_completions(resources: &str, prefix: &str, limit: usize) -> Result<Vec<String>>;
        fn dictionary_validate(entry: &DictionaryEntry) -> Result<DictionaryEntry>;
        fn dictionary_edit(
            options: &EngineOptions,
            previous: &[DictionaryEntry],
            replacement: &[DictionaryEntry],
            request_id: &str,
        ) -> Result<()>;
        fn replay_user_dictionary(
            user_db_path: &str,
            main_db_path: &str,
            english_db_path: &str,
        ) -> DictionaryReplaySummary;
        fn prepare_options(
            resources: &str,
            user_data: &str,
            cache: &str,
            content_id: &str,
        ) -> Result<EngineOptions>;
        fn hanzi_to_pinyin(options: &EngineOptions, text: &str) -> String;
        fn normalize_full_pinyin(input: &str, expected_syllables: usize) -> String;
        fn shuangpin_key_hints(profile: &str) -> Vec<ShuangpinKeyHint>;
        fn snapshot(self: &EngineSession) -> Result<EngineSnapshot>;
        fn online_query(self: &EngineSession) -> Result<OnlineQuerySnapshot>;
        fn reset_cache(self: Pin<&mut EngineSession>);
        fn apply_online_candidate(
            self: Pin<&mut EngineSession>,
            query: &OnlineQuerySnapshot,
            candidate: &str,
            source: u8,
        ) -> Result<bool>;
        fn apply_online_candidates(
            self: Pin<&mut EngineSession>,
            query: &OnlineQuerySnapshot,
            candidates: &[String],
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
        fn emoji_catalog_slice(
            resources: &str,
            search: &str,
            category: &str,
            group: &str,
            offset: usize,
            limit: u16,
            parent: &str,
        ) -> Result<EmojiCatalogSlice>;
        fn emoji_symbol_groups(resources: &str) -> Result<Vec<EmojiSymbolGroup>>;
        fn handwriting_order_candidates(candidates: &[String]) -> Result<Vec<String>>;
        fn emoji_catalog_groups(resources: &str, category: &str) -> Result<Vec<String>>;
        fn candidate_glosses(
            resources: &str,
            candidates: &[CandidateGlossInput],
        ) -> Result<Vec<String>>;
        fn candidate_glosses_with_user(
            resources: &str,
            user_data: &str,
            candidates: &[CandidateGlossInput],
        ) -> Result<Vec<String>>;
        fn save_candidate_gloss(
            user_data: &str,
            chinese_to_english: bool,
            key: &str,
            gloss: &str,
        ) -> bool;
        #[cfg(not(any(target_os = "android", target_env = "ohos")))]
        fn handwriting_recognize(
            model_path: &str,
            points: &[HandwritingPoint],
            width: f32,
            height: f32,
        ) -> Result<Vec<String>>;
        fn character(self: Pin<&mut EngineSession>, value: u8, shift: bool)
            -> Result<EngineResult>;
        fn expand_initial_candidates(self: Pin<&mut EngineSession>) -> Result<bool>;
        fn set_nine_key_enabled(self: Pin<&mut EngineSession>, enabled: bool) -> Result<()>;
        fn choose_nine_key_spelling(
            self: Pin<&mut EngineSession>,
            index: usize,
        ) -> Result<EngineResult>;
        fn command(self: Pin<&mut EngineSession>, value: u8) -> Result<EngineResult>;
        fn commit_raw_with_policy(self: Pin<&mut EngineSession>) -> Result<EngineResult>;
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
        fn balance_paired_punctuation_after_auto_close(
            self: Pin<&mut EngineSession>,
            opening: u8,
        ) -> Result<()>;
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
    CaptureDevice, DictionaryEntry, DictionaryKind, DictionaryPage, DictionaryTableEntry,
    DictionaryTablePage, EmojiCatalogItem, EngineOptions, EngineResult, EngineSnapshot,
    HandwritingPoint, OnlineQuerySnapshot,
};

/// Read a bounded page of user-inserted entries, excluding the bundled dictionary.
pub fn dictionary_entries(
    options: &EngineOptions,
    offset: usize,
    limit: usize,
) -> Result<DictionaryPage, cxx::Exception> {
    ffi::dictionary_entries(options, offset, limit)
}

/// Read a bounded page of the entries a dictionary export writes: the user-inserted entries, plus, with `include_learned_pinyin`, the pinyin entries whose weight was learned or edited. Single-character pinyin entries are left out in that mode, as the reference's pinyin export does.
pub fn dictionary_export_entries(
    options: &EngineOptions,
    offset: usize,
    limit: usize,
    include_learned_pinyin: bool,
) -> Result<DictionaryPage, cxx::Exception> {
    ffi::dictionary_export_entries(options, offset, limit, include_learned_pinyin)
}

/// Look up the working dictionary tables of one kind by code prefix, read-only, bundled rows included. Pinyin ignores separators and case; an empty query lists every quick phrase and nothing for the other kinds. User-inserted rows come first, then exact matches, then by weight.
pub fn dictionary_table_entries(
    options: &EngineOptions,
    kind: DictionaryKind,
    query: &str,
    offset: usize,
    limit: usize,
) -> Result<DictionaryTablePage, cxx::Exception> {
    let kind = match kind {
        DictionaryKind::Pinyin => 0,
        DictionaryKind::Wubi => 1,
        DictionaryKind::QuickPhrase => 2,
        DictionaryKind::English => 3,
        _ => u8::MAX,
    };
    ffi::dictionary_table_entries(options, kind, query, offset, limit)
}

/// Set the weight of (`Some`) or delete (`None`) a row that is not user-inserted, journaled so it survives replay onto a fresh dictionary. `previous` must carry the row's current weight. The caller must quiesce sessions sharing these paths before editing.
pub fn dictionary_edit_bundled(
    options: &EngineOptions,
    previous: &DictionaryEntry,
    weight: Option<i64>,
    request_id: &str,
) -> Result<(), cxx::Exception> {
    ffi::dictionary_edit_bundled(options, previous, weight.as_slice(), request_id)
}

/// Query the packaged English dictionary without creating or mutating an input session.
pub fn english_completions(
    resources: &str,
    prefix: &str,
    limit: usize,
) -> Result<Vec<String>, cxx::Exception> {
    ffi::english_completions(resources, prefix, limit)
}

/// Validate and normalize one personal-dictionary entry through the Engine.
pub fn dictionary_validate(entry: &DictionaryEntry) -> Result<DictionaryEntry, cxx::Exception> {
    ffi::dictionary_validate(entry)
}

/// Capture bounded mono 16 kHz samples through the pinned Engine audio layer.
/// An empty vector indicates that capture could not be started or produced no
/// samples; the caller owns session cancellation and provider transport.
pub fn capture_audio(milliseconds: u32) -> Vec<f32> {
    ffi::capture_audio(milliseconds)
}

/// Enumerate capture devices without opening one or exposing device handles.
pub fn capture_device_names() -> Vec<String> {
    ffi::capture_device_names()
}

/// Backend-qualified endpoint identities and display labels; never log them.
pub fn capture_devices() -> Vec<ffi::CaptureDevice> {
    ffi::capture_devices()
}

/// Resolve a pure Han phrase to the highest-ranked canonical pinyin in the
/// verified Engine dictionary for native dictionary import tooling.
pub fn hanzi_to_pinyin(options: &EngineOptions, text: &str) -> String {
    ffi::hanzi_to_pinyin(options, text)
}

/// Normalize an unsegmented full-pinyin code using the Engine's canonical
/// syllable table. An expected Han-character count resolves ambiguous cuts.
pub fn normalize_full_pinyin(input: &str, expected_syllables: usize) -> String {
    ffi::normalize_full_pinyin(input, expected_syllables)
}

/// Per-key double-pinyin hint text for one profile, read out of the Engine's own
/// profile tables. A keyboard face that keeps its own copy of the keymap drifts
/// from the scheme the session runs, so hosts ask for this instead. An unknown
/// profile name yields no hints rather than the default profile's.
pub fn shuangpin_key_hints(profile: &str) -> Vec<ffi::ShuangpinKeyHint> {
    ffi::shuangpin_key_hints(profile)
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

/// Replace mutable dictionaries and the Engine journal with fresh copies of
/// the packaged state. The caller must quiesce every session using these paths.
pub fn reset_learned_data(options: &EngineOptions) -> Result<(), cxx::Exception> {
    ffi::reset_learned_data(options)
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

/// Replay the Engine-owned user dictionary journal into the freshly installed
/// dictionaries. The installer calls this only after quiescing the previous
/// Server, so the operation cannot race a live session.
pub fn replay_user_dictionary(
    user_db_path: &str,
    main_db_path: &str,
    english_db_path: &str,
) -> (i32, i32, i32, String) {
    let result = ffi::replay_user_dictionary(user_db_path, main_db_path, english_db_path);
    (result.applied, result.skipped, result.failed, result.error)
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

pub fn emoji_catalog_slice(
    resources: &str,
    search: &str,
    category: &str,
    group: &str,
    offset: usize,
    limit: u16,
    parent: &str,
) -> Result<ffi::EmojiCatalogSlice, cxx::Exception> {
    ffi::emoji_catalog_slice(resources, search, category, group, offset, limit, parent)
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

/// Query the packaged English dictionary without creating or mutating an input session.
/// Look up display-only candidate glosses in the packaged Engine dictionary.
/// The result is parallel to `candidates`; an ineligible candidate has an empty gloss.
pub fn candidate_glosses(
    resources: &str,
    candidates: &[(String, u8)],
) -> Result<Vec<String>, cxx::Exception> {
    candidate_glosses_with_user(resources, "", candidates)
}

pub fn save_candidate_gloss(
    user_data: &str,
    chinese_to_english: bool,
    key: &str,
    gloss: &str,
) -> bool {
    ffi::save_candidate_gloss(user_data, chinese_to_english, key, gloss)
}

pub fn candidate_glosses_with_user(
    resources: &str,
    user_data: &str,
    candidates: &[(String, u8)],
) -> Result<Vec<String>, cxx::Exception> {
    let candidates = candidates
        .iter()
        .map(|(text, source)| ffi::CandidateGlossInput {
            text: text.clone(),
            source: *source,
        })
        .collect::<Vec<_>>();
    if user_data.is_empty() {
        ffi::candidate_glosses(resources, &candidates)
    } else {
        ffi::candidate_glosses_with_user(resources, user_data, &candidates)
    }
}

/// Apply Engine's shared handwriting candidate policy to provider results.
pub fn handwriting_order_candidates(candidates: &[String]) -> Result<Vec<String>, cxx::Exception> {
    ffi::handwriting_order_candidates(candidates)
}

/// Run the Engine's optional offline handwriting recognizer on copied strokes.
/// Points are flattened with their zero-based stroke index for the CXX ABI.
/// Absent on the mobile hosts, which inject their own recognizer: the build turns
/// MSIME_ENGINE_BRIDGE_HANDWRITING off there, so the symbol does not exist to link.
#[cfg(not(any(target_os = "android", target_env = "ohos")))]
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
    CycleKanaVariant,
    CommitReading,
    /// Commit the letters as typed without learning them as an English word. Windows learns an entered word only on Enter (`event_listener.cpp`, `ShouldLearnEnteredEnglishWord`); a mode switch commits the keystroke buffer and learns nothing (`KeyHandler.cpp`, `_HandleToogleIMEMode`).
    CommitRawWithoutLearning,
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
    pub fn reset_cache(&mut self) {
        self.inner.pin_mut().reset_cache()
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
    pub fn apply_online_candidates(
        &mut self,
        query: &OnlineQuerySnapshot,
        candidates: &[String],
        source: u8,
    ) -> Result<bool, cxx::Exception> {
        self.inner
            .pin_mut()
            .apply_online_candidates(query, candidates, source)
    }
    pub fn character(&mut self, value: u8, shift: bool) -> Result<EngineResult, cxx::Exception> {
        self.inner.pin_mut().character(value, shift)
    }
    /// Ask the Engine for the candidates it withheld from a single-letter query. It caps those at
    /// twenty-four so the first page is cheap; everything below that cap is unreachable until
    /// someone asks. Answers whether the candidate list actually grew.
    pub fn expand_initial_candidates(&mut self) -> Result<bool, cxx::Exception> {
        self.inner.pin_mut().expand_initial_candidates()
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
        if matches!(command, Command::CommitRaw) {
            self.inner.pin_mut().commit_raw_with_policy()
        } else {
            self.inner.pin_mut().command(command as u8)
        }
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
    pub fn balance_paired_punctuation_after_auto_close(
        &mut self,
        opening: u8,
    ) -> Result<(), cxx::Exception> {
        self.inner
            .pin_mut()
            .balance_paired_punctuation_after_auto_close(opening)
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

    #[test]
    fn normalizes_full_pinyin_using_the_expected_word_length() {
        assert_eq!(normalize_full_pinyin("xian", 1), "xian");
        assert_eq!(normalize_full_pinyin("xian", 2), "xi'an");
        assert_eq!(
            normalize_full_pinyin("a'ba'la'ti'ya'yun'hai", 7),
            "a'ba'la'ti'ya'yun'hai"
        );
        assert_eq!(normalize_full_pinyin("xian", 3), "");
        assert_eq!(normalize_full_pinyin("ni'hao'", 2), "");
    }

    #[test]
    fn validates_and_normalizes_personal_dictionary_entries() {
        let normalized = dictionary_validate(&DictionaryEntry {
            kind: DictionaryKind::Pinyin,
            key: "NI HAO".into(),
            value: "拟好".into(),
            weight: 100_000,
        })
        .unwrap();
        assert_eq!(normalized.key, "ni'hao");
        let english = dictionary_validate(&DictionaryEntry {
            kind: DictionaryKind::English,
            key: "dont".into(),
            value: "don't".into(),
            weight: 100_000,
        })
        .unwrap();
        assert_eq!(english.key, "dont");
        assert_eq!(english.value, "don't");
        assert!(dictionary_validate(&DictionaryEntry {
            kind: DictionaryKind::English,
            key: "wrong_code".into(),
            value: "Word".into(),
            weight: 100_000,
        })
        .is_err());
    }

    #[test]
    fn learned_glosses_survive_unavailable_packaged_dictionary() {
        let resources = tempfile::tempdir().unwrap();
        let user = tempfile::tempdir().unwrap();
        let resources_path = resources.path().to_str().unwrap();
        let user_path = user.path().to_str().unwrap();
        let candidates = vec![
            ("测试".into(), 0),
            ("Synthetic".into(), 4),
            ("Missing".into(), 4),
        ];
        assert!(candidate_glosses_with_user(resources_path, user_path, &candidates).is_err());
        assert!(save_candidate_gloss(
            user_path,
            true,
            "测试",
            "synthetic gloss"
        ));
        assert!(save_candidate_gloss(
            user_path,
            false,
            "synthetic",
            "合成释义"
        ));
        let expected = vec![
            "synthetic gloss".to_owned(),
            "合成释义".to_owned(),
            String::new(),
        ];
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            expected
        );
        let packaged = resources.path().join("english.db");
        std::fs::write(&packaged, "synthetic damaged database").unwrap();
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            expected
        );
        assert!(candidate_glosses(resources_path, &candidates).is_err());
        std::fs::remove_file(&packaged).unwrap();
        let db = rusqlite::Connection::open(&packaged).unwrap();
        db.execute_batch(
            "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);
            CREATE TABLE en_zh_glosses(english TEXT PRIMARY KEY,chinese_gloss TEXT);
            CREATE TABLE zh_en_glosses(chinese TEXT PRIMARY KEY,english_gloss TEXT);
            INSERT INTO en_zh_glosses VALUES('missing','发布释义');
            INSERT INTO zh_en_glosses VALUES('测试','packaged gloss');",
        )
        .unwrap();
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            vec!["synthetic gloss", "合成释义", "发布释义"]
        );
        std::fs::write(
            user.path().join("translation-glosses.db"),
            "synthetic damaged database",
        )
        .unwrap();
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            vec!["packaged gloss", "", "发布释义"]
        );
    }

    #[test]
    fn hand_written_glosses_outrank_learned_and_packaged_ones() {
        // The user's own file wins, and nothing was pinning that. It arrives by a route worth writing
        // down: translation-glosses.db sits in the user directory the settings page writes
        // custom_translations.txt to, and EnglishDictionary opened without an explicit translations path
        // reads its sidecar from beside the database - so the learned store carries the hand-written
        // entries too, and query_*_gloss answers from them before touching anything else.
        //
        // That makes the precedence an emergent property of where two files happen to live. Moving either
        // one, or giving the learned store an explicit translations path, would silently drop the user's
        // glosses to the bottom. This test is what would notice.
        let resources = tempfile::tempdir().unwrap();
        let user = tempfile::tempdir().unwrap();
        let database = rusqlite::Connection::open(resources.path().join("english.db")).unwrap();
        database
            .execute_batch(
                "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);
                 CREATE TABLE en_zh_glosses(english TEXT PRIMARY KEY,chinese_gloss TEXT);
                 CREATE TABLE zh_en_glosses(chinese TEXT PRIMARY KEY,english_gloss TEXT);
                 INSERT INTO zh_en_glosses VALUES('测试','packaged gloss');",
            )
            .unwrap();
        let resources_path = resources.path().to_str().unwrap();
        let user_path = user.path().to_str().unwrap();
        let candidates = vec![("测试".into(), 0)];

        // Packaged only, to begin with.
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            vec!["packaged gloss"]
        );

        // A gloss learned from the network outranks the packaged one, which this already guaranteed.
        assert!(save_candidate_gloss(
            user_path,
            true,
            "测试",
            "learned gloss"
        ));
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            vec!["learned gloss"]
        );

        // What the user wrote outranks both. Anything else means an automatic answer silently replacing
        // the one they asked for by hand.
        std::fs::write(
            user.path().join("custom_translations.txt"),
            "测试\thand written gloss\n",
        )
        .unwrap();
        assert_eq!(
            candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
            vec!["hand written gloss"]
        );
    }

    #[test]
    fn unsafe_learned_glosses_fall_back_to_packaged_values() {
        let resources = tempfile::tempdir().unwrap();
        let user = tempfile::tempdir().unwrap();
        let database = rusqlite::Connection::open(resources.path().join("english.db")).unwrap();
        database
            .execute_batch(
                "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);
                 CREATE TABLE en_zh_glosses(english TEXT PRIMARY KEY,chinese_gloss TEXT);
                 CREATE TABLE zh_en_glosses(chinese TEXT PRIMARY KEY,english_gloss TEXT);
                 INSERT INTO zh_en_glosses VALUES('测试','packaged gloss');",
            )
            .unwrap();
        let resources_path = resources.path().to_str().unwrap();
        let user_path = user.path().to_str().unwrap();
        let candidates = vec![("测试".into(), 0)];

        for codepoint in (1..=0x1f).chain(0x7f..=0x9f) {
            let control = char::from_u32(codepoint).unwrap();
            if matches!(control, '\t' | '\n' | '\r') {
                continue;
            }
            assert!(save_candidate_gloss(
                user_path,
                true,
                "测试",
                &format!("before{control}after"),
            ));
            assert_eq!(
                candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
                vec!["packaged gloss"]
            );
        }
        for whitespace in ['\t', '\n', '\r'] {
            assert!(save_candidate_gloss(
                user_path,
                true,
                "测试",
                &format!("learned{whitespace}gloss"),
            ));
            assert_eq!(
                candidate_glosses_with_user(resources_path, user_path, &candidates).unwrap(),
                vec!["learned gloss"]
            );
        }
    }

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
            shuangpin_preedit_uses_raw: true,
            learning: false,
            autocorrect_transposition: true,
            autocorrect_neighbor: true,
            fuzzy_pinyin_rules: 0,
            wubi_mixed_pinyin: false,
            helpcode: false,
            show_helpcode: true,
            helpcode_schema: "ziranma".into(),
            chinese_punctuation: true,
            paired_punctuation: true,
            punctuation_lock: 0,
            frequency_mode: "promote".into(),
            frequency_trigger_count: 1,
            frequency_linear_step: 1,
            mixed_english: true,
            english_minimum_prefix: 5,
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
            sentence_alternatives: true,
        }
    }

    #[test]
    fn reset_learned_data_restores_packaged_dictionaries_and_clears_journal() {
        // Both an ASCII root and one carrying Chinese characters. On Windows a
        // narrow conversion of the second either mangles it or throws, and the
        // reset derives temporary, backup and SQLite sidecar names from these
        // paths - a throw would abort it after it had already published files.
        for component in ["ascii", "陆傲天"] {
            reset_learned_data_under_root(component);
        }
    }

    fn reset_learned_data_under_root(component: &str) {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().join(component);
        std::fs::create_dir_all(&root).unwrap();
        let root = root.as_path();
        let value = options(root);
        let resources = std::path::Path::new(&value.resources);
        let dictionaries = std::path::Path::new(&value.dictionaries);
        let main_fixture = "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER);\
                            INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',100);\
                            CREATE TABLE wubi86(key TEXT,value TEXT,weight INTEGER);\
                            CREATE TABLE quick_parases(key TEXT,value TEXT,weight INTEGER);";
        rusqlite::Connection::open(resources.join("msime.db"))
            .unwrap()
            .execute_batch(main_fixture)
            .unwrap();
        rusqlite::Connection::open(resources.join("english.db"))
            .unwrap()
            .execute_batch(
                "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);\
                 CREATE TABLE en_zh_glosses(english TEXT PRIMARY KEY,chinese_gloss TEXT);\
                 CREATE TABLE zh_en_glosses(chinese TEXT PRIMARY KEY,english TEXT);\
                 INSERT INTO english_words VALUES('word','word',100);",
            )
            .unwrap();
        std::fs::copy(resources.join("msime.db"), dictionaries.join("msime.db")).unwrap();
        std::fs::copy(
            resources.join("english.db"),
            dictionaries.join("english.db"),
        )
        .unwrap();
        let journal = std::path::Path::new(&value.user_data).join("msime_user.db");
        rusqlite::Connection::open(&journal)
            .unwrap()
            .execute_batch(
                "CREATE TABLE user_dictionary_operations(dictionary TEXT,key TEXT,value TEXT,operation TEXT,weight INTEGER,display TEXT,user_inserted INTEGER);\
                 CREATE TABLE personal_dictionary_receipts(request_id TEXT PRIMARY KEY,payload TEXT);\
                 CREATE TABLE candidate_selection_state(context_key TEXT,entry_key TEXT,value TEXT,selection_count INTEGER);\
                 CREATE TABLE fixed_candidate_positions(context_key TEXT,entry_key TEXT,value TEXT,position INTEGER);\
                 INSERT INTO user_dictionary_operations VALUES('pinyin','ni''hao','你好','upsert',1,'',1);\
                 INSERT INTO candidate_selection_state VALUES('ni''hao','ni''hao','你好',7);",
            )
            .unwrap();
        rusqlite::Connection::open(dictionaries.join("msime.db"))
            .unwrap()
            .execute("UPDATE tbl_2_n SET weight=1", [])
            .unwrap();

        reset_learned_data(&value).unwrap();

        let database = rusqlite::Connection::open(dictionaries.join("msime.db")).unwrap();
        let weight: i64 = database
            .query_row(
                "SELECT weight FROM tbl_2_n WHERE key='ni''hao'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(weight, 100);
        let journal = rusqlite::Connection::open(journal).unwrap();
        let operations: i64 = journal
            .query_row(
                "SELECT count(*) FROM user_dictionary_operations",
                [],
                |row| row.get(0),
            )
            .unwrap();
        let selections: i64 = journal
            .query_row(
                "SELECT count(*) FROM candidate_selection_state",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(operations, 0);
        assert_eq!(selections, 0);
    }

    #[test]
    fn prepared_options_disable_quanpin_autocorrect_by_default() {
        let root = tempfile::tempdir().unwrap();
        let resources = root.path().join("resources");
        std::fs::create_dir_all(&resources).unwrap();
        for name in ["msime.db", "english.db"] {
            rusqlite::Connection::open(resources.join(name)).unwrap();
        }
        let prepared = super::prepare_options(
            resources.to_str().unwrap(),
            root.path().join("user").to_str().unwrap(),
            root.path().join("cache").to_str().unwrap(),
            "synthetic-defaults",
        )
        .unwrap();
        assert!(!prepared.autocorrect_transposition);
        assert!(!prepared.autocorrect_neighbor);
        assert_eq!(prepared.english_minimum_prefix, 5);
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
        for schema in [
            "lantian",
            "ziranma",
            "shouyou2_0",
            "shouyouplus",
            "xiaohe",
            "jiajia",
        ] {
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

    /// The jiajia table this repository carries is in the shape the Engine parses.
    ///
    /// Five helpcode tables arrive inside the locked Engine archive and cannot rot independently of
    /// it. This one does not: it lives in `resources/helpcodes/` and is injected by an overlay, so
    /// it is the one that can go missing, be truncated by a bad merge, or be saved in an encoding
    /// the Engine reads as nothing. The test above would not notice any of that - it points
    /// `resources` at an empty directory, so it shows the scheme is registered and accepted and
    /// would pass with no table at all.
    ///
    /// What it checks is the Engine's own parse rule from `HelpcodeUtils::load_helpcode_keymap`:
    /// split at the first `=`, take two characters after it, keep the entry only when both are
    /// `a`-`z`. An entry this rejects is silently absent at runtime rather than an error, which is
    /// why counting them here is worth doing.
    ///
    /// Reading the codes the Engine would read is as far as this level goes: filtering candidates
    /// needs a real dictionary, and these tests run against empty directories.
    #[test]
    fn the_carried_jiajia_table_parses_the_way_the_engine_reads_it() {
        let table = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../resources/helpcodes/jiajia_helpcode.txt");
        let text = std::fs::read_to_string(&table)
            .unwrap_or_else(|error| panic!("{}: {error}", table.display()));

        let mut keymap = std::collections::BTreeMap::new();
        let mut rejected = Vec::new();
        for line in text.lines() {
            let Some(position) = line.find('=') else {
                rejected.push(line);
                continue;
            };
            let (character, code) = line.split_at(position);
            let code: String = code[1..].chars().take(2).collect();
            if position == 0
                || code.len() != 2
                || !code.bytes().all(|byte| byte.is_ascii_lowercase())
            {
                rejected.push(line);
                continue;
            }
            keymap.insert(character.to_owned(), code);
        }

        assert!(
            rejected.is_empty(),
            "the Engine drops these silently: {:?}",
            &rejected[..rejected.len().min(5)]
        );
        // Codes quoted in resources/helpcodes/NOTICE.md as coming from the alignment.
        for (character, code) in [("好", "nz"), ("你", "de"), ("中", "ks"), ("国", "ky")] {
            assert_eq!(keymap.get(character).map(String::as_str), Some(code));
        }
        // The notice records 7968 entries; a table that lost a chunk still parses.
        assert_eq!(keymap.len(), 7968);
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
    fn microsoft_profile_keeps_trailing_semicolon_in_segment_boundaries() {
        let dir = tempfile::tempdir().unwrap();
        for (input, expected) in [
            ("nihkb;", vec![0, 2, 4, 6]),
            // `cb` is a valid Microsoft shuangpin pair and must win over
            // pairing the final `b` with the trailing semicolon.
            ("nihcb;", vec![0, 2, 3, 5, 6]),
        ] {
            let mut options = options(dir.path());
            options.scheme = 1;
            options.shuangpin_profile = 3;
            let mut session = Session::new(&options).unwrap();
            for character in input.bytes() {
                session.character(character, false).unwrap();
            }
            assert_eq!(session.snapshot().unwrap().segment_raw_boundaries, expected);
        }
    }

    /// A keyboard face labels its letter keys with the units they carry. The hints
    /// have to come from the profile the session is running, which is why this asks
    /// the session for its profile name instead of assuming the option index and the
    /// name agree.
    #[test]
    fn shuangpin_key_hints_describe_the_profile_the_session_runs() {
        let dir = tempfile::tempdir().unwrap();
        let mut seen: Vec<(String, Vec<(String, String)>)> = Vec::new();
        for profile in 0..4 {
            let mut options = options(dir.path());
            options.scheme = 1;
            options.shuangpin_profile = profile;
            let session = Session::new(&options).unwrap();
            let name = session.snapshot().unwrap().shuangpin_profile;
            let hints: Vec<(String, String)> = shuangpin_key_hints(&name)
                .into_iter()
                .map(|entry| (entry.key, entry.hint))
                .collect();
            assert!(
                hints.len() >= 26,
                "{name} labelled only {} keys",
                hints.len()
            );
            for (key, hint) in &hints {
                assert!(
                    key.len() == 1 && ("A"..="Z").contains(&key.as_str()) || key == ";",
                    "{name} produced a hint for {key:?}, which is not a letter key"
                );
                assert!(!hint.is_empty(), "{name} key {key} carries an empty hint");
                // " / " separates initials from finals, so it appears at most once; units
                // on the same side are separated by a space.
                assert!(
                    hint.matches(" / ").count() <= 1,
                    "{name} key {key} hint {hint:?} reads as more than two sides"
                );
            }
            seen.push((name, hints));
        }
        for (index, (name, hints)) in seen.iter().enumerate() {
            for (other_name, other_hints) in seen.iter().skip(index + 1) {
                assert_ne!(
                    hints, other_hints,
                    "{name} and {other_name} produced the same key face"
                );
            }
        }
    }

    /// Xiaohe keeps two finals on K, and a host-side copy of the keymap listed only
    /// one of them, so the key that types `guai` carried no sign of it. The hints are
    /// read out of the Engine now; this holds that specific key to both units.
    #[test]
    fn shuangpin_key_hints_keep_every_unit_a_key_carries() {
        let hints: std::collections::HashMap<String, String> = shuangpin_key_hints("xiaohe")
            .into_iter()
            .map(|entry| (entry.key, entry.hint))
            .collect();
        assert_eq!(hints.get("K").map(String::as_str), Some("ing uai"));
        assert_eq!(hints.get("V").map(String::as_str), Some("zh / ui ü"));
    }

    /// Labelling the keys with a scheme the session is not running is worse than
    /// labelling nothing, so an unrecognised name yields no hints at all instead of
    /// falling back to the default profile the Engine's own lookup returns.
    #[test]
    fn shuangpin_key_hints_reject_an_unknown_profile() {
        assert!(shuangpin_key_hints("").is_empty());
        assert!(shuangpin_key_hints("xiaohe-v2").is_empty());
        assert!(shuangpin_key_hints("quanpin").is_empty());
    }

    #[test]
    fn all_shuangpin_profiles_accept_yo_as_one_syllable() {
        let dir = tempfile::tempdir().unwrap();
        for profile in 0..4 {
            let mut options = options(dir.path());
            options.scheme = 1;
            options.shuangpin_profile = profile;
            let mut session = Session::new(&options).unwrap();
            session.character(b'y', false).unwrap();
            session.character(b'o', false).unwrap();
            let snapshot = session.snapshot().unwrap();
            assert_eq!(snapshot.editing_text, "yo");
            assert_eq!(snapshot.preedit, "yo", "yo was split: {snapshot:?}");
        }
    }

    #[test]
    fn cloud_query_preserves_manual_quanpin_segmentation() {
        let dir = tempfile::tempdir().unwrap();
        let mut session = Session::new(&options(dir.path())).unwrap();
        for character in b"qi'e'huan" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        let query = session.online_query().unwrap();
        assert!(query.available);
        assert_eq!(query.query_text, "qi'e'huan");
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

    #[test]
    fn real_engine_cycles_the_last_japanese_kana_variant() {
        let dir = tempfile::tempdir().unwrap();
        let mut value = options(dir.path());
        value.scheme = 3;
        let mut session = Session::new(&value).unwrap();
        for character in b"ka" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        assert_eq!(session.snapshot().unwrap().reading, "か");
        assert!(session.command(Command::CycleKanaVariant).unwrap().handled);
        assert_eq!(session.snapshot().unwrap().reading, "が");
        assert!(session.command(Command::CycleKanaVariant).unwrap().handled);
        assert_eq!(session.snapshot().unwrap().reading, "か");
    }

    #[test]
    fn commit_raw_applies_windows_english_learning_policy() {
        let dir = tempfile::tempdir().unwrap();
        let value = options(dir.path());
        let mut session = Session::new(&value).unwrap();
        session.set_dedicated_english(true).unwrap();
        for character in b"hello" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        assert_eq!(session.command(Command::CommitRaw).unwrap().commit, "hello");
        let database = rusqlite::Connection::open(
            std::path::Path::new(&value.dictionaries).join("english.db"),
        )
        .unwrap();
        let learned: String = database
            .query_row(
                "SELECT display FROM english_words WHERE word='hello'",
                [],
                |row| row.get(0),
            )
            .unwrap();
        assert_eq!(learned, "hello");
    }

    #[test]
    fn raw_commit_without_learning_leaves_the_english_dictionary_alone() {
        for dedicated in [true, false] {
            raw_commit_without_learning_case(dedicated);
        }
    }

    fn raw_commit_without_learning_case(dedicated: bool) {
        let dir = tempfile::tempdir().unwrap();
        let value = options(dir.path());
        let mut session = Session::new(&value).unwrap();
        session.set_dedicated_english(dedicated).unwrap();
        for character in b"hello" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        assert_eq!(
            session
                .command(Command::CommitRawWithoutLearning)
                .unwrap()
                .commit,
            "hello"
        );
        let database = std::path::Path::new(&value.dictionaries).join("english.db");
        if database.exists() {
            let database = rusqlite::Connection::open(database).unwrap();
            let learned: i64 = database
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='english_words'",
                    [],
                    |row| row.get(0),
                )
                .unwrap();
            let learned = if learned == 0 {
                0
            } else {
                database
                    .query_row(
                        "SELECT COUNT(*) FROM english_words WHERE word='hello'",
                        [],
                        |row| row.get(0),
                    )
                    .unwrap()
            };
            assert_eq!(learned, 0);
        }
    }

    #[test]
    fn complete_pinyin_raw_commit_does_not_learn_as_english() {
        let dir = tempfile::tempdir().unwrap();
        let value = options(dir.path());
        let mut session = Session::new(&value).unwrap();
        for character in b"ni" {
            assert!(session.character(*character, false).unwrap().handled);
        }
        assert_eq!(session.command(Command::CommitRaw).unwrap().commit, "ni");
        let database = std::path::Path::new(&value.dictionaries).join("english.db");
        if database.exists() {
            let database = rusqlite::Connection::open(database).unwrap();
            let count: i64 = database
                .query_row(
                    "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='english_words'",
                    [],
                    |row| row.get(0),
                )
                .unwrap();
            assert_eq!(count, 0);
        }
    }
}
