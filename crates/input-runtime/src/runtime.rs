//! `Runtime`: the orchestration between keystrokes, the engine, and everything the
//! providers return asynchronously.

use super::*;

pub enum Action {
    ResetCache,
    Character {
        value: u8,
        shift: bool,
    },
    Punctuation(u8),
    /// Finish the highlighted composition and append the literal ASCII mark.
    /// Linux uses this when IBus surrounding text says smart punctuation
    /// should stay ASCII; the Engine's normal punctuation table remains
    /// authoritative for every other punctuation action.
    PunctuationAscii(u8),
    Command(Command),
    SegmentBackspace,
    SegmentMoveLeft,
    SegmentMoveRight,
    Select(CandidateId),
    /// Select any candidate in the current Engine generation. This is reserved
    /// for hosts that explicitly requested [`Runtime::all_candidates`].
    SelectAnyCandidate(CandidateId),
    SelectEdge(CandidateId, CandidateEdge),
    PinCandidate(CandidateId),
    RemoveCandidate(CandidateId),
    FixCandidatePosition(CandidateId, u8),
    ClearCandidatePosition(CandidateId),
    ChooseNineKeySpelling(NineKeySpellingId),
    SelectHighlighted,
    Finish,
    NextPage,
    PreviousPage,
    NextCandidate,
    PreviousCandidate,
    FirstCandidateOnPage,
    LastCandidateOnPage,
}

pub struct Runtime<E: InputEngine = Session> {
    pub(crate) engine: E,
    pub(crate) session: u64,
    pub(crate) generation: u64,
    pub(crate) focused: bool,
    pub(crate) page_size: usize,
    pub(crate) highlighted: usize,
    pub(crate) translations: HashMap<String, String>,
    pub(crate) cached: EngineSnapshot,
    pub(crate) snapshot_valid: bool,
    pub(crate) character_width: CharacterWidth,
    pub(crate) touch_keyboard_layout: TouchKeyboardLayout,
    /// Recently committed text, sent to the AI provider as context.
    ///
    /// The reference sends what the user has just written so a suggestion fits
    /// the sentence in progress. Every host but Linux left this empty, which
    /// made AI suggestions guess from the pinyin alone.
    pub(crate) ai_context: String,
    /// Reorders candidates the pinyin decoder assembled, when a host supplied a model.
    ///
    /// Absent unless a host calls [`Runtime::set_reranker`], and absent is the only state the
    /// hosts that ship no model ever see.
    pub(crate) reranker: Option<Reranker>,
    /// A second, larger model run once the user stops typing, when one is attached.
    ///
    /// Capacity is the most effective lever the model has — the 24M preset beats the 6.8M one by
    /// 49 points of top-1 on the harvested failure set — and it is also the one the keystroke path
    /// cannot afford: the same model measures p95 153ms against a 16ms frame, with the slowest
    /// keystroke at 342ms. Both numbers are real and they do not have to be reconciled, because
    /// they are answers to different questions. While the user is typing, the first row has to be
    /// plausible now; when the user stops to read the candidates, it has to be right. The fast
    /// model owns the first job and this one owns the second.
    pub(crate) settled_reranker: Option<Reranker>,
}

/// `CandidateSource::Generated`: a whole-sentence path the word lattice assembled. The one source
/// whose members really are alternative readings of the same key.
pub(crate) const LATTICE_SOURCE: u8 = 8;

/// Move the flagged elements to the end, keeping both groups in their existing order.
pub(crate) fn move_to_back<T>(items: &mut Vec<T>, moved: &[bool]) {
    let mut flags = moved.iter();
    let mut tail: Vec<T> = Vec::new();
    let mut head: Vec<T> = Vec::with_capacity(items.len());
    for item in items.drain(..) {
        if flags.next().copied().unwrap_or(false) {
            tail.push(item);
        } else {
            head.push(item);
        }
    }
    head.append(&mut tail);
    *items = head;
}

/// Move the element at `index` to the front, keeping everything else in its existing order.
///
/// A rotation rather than a swap, so the rest of the list stays as the engine ranked it: promoting
/// one candidate is the whole change, not a reshuffle.
fn rotate_to_front<T>(items: &mut [T], index: usize) {
    items[..=index].rotate_right(1);
}

impl Runtime<Session> {
    /// A live host mode changes neither composition nor candidate identity.
    pub fn set_chinese_punctuation_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.engine
            .set_chinese_punctuation_enabled(enabled)
            .map_err(|error| RuntimeError::Engine(error.to_string()))
    }

    pub fn online_query(&self) -> Result<Option<OnlineQuery>, RuntimeError> {
        let query = self
            .engine
            .online_query()
            .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        if !query.available {
            return Ok(None);
        }
        Ok(Some(OnlineQuery {
            scheme: query.scheme,
            generation: query.generation,
            identity: query.identity,
            query_text: query.query_text,
            cache_key: query.cache_key,
            pinyin_segments: query.pinyin_segments,
            cloud_eligible: query.cloud_eligible,
            ai_eligible: query.ai_eligible,
            cloud_candidates: true,
            session_id: query.session_id,
            ai_context: self.ai_context.clone(),
            ai_assistant: None,
        }))
    }

    /// Queue the current eligible query for an injected provider. Hosts call
    /// this after dispatching input; the bounded worker performs I/O off-thread.
    pub fn submit_online_query(&self, worker: &OnlineProviderWorker) -> Result<bool, RuntimeError> {
        Ok(self
            .online_query()?
            .is_some_and(|query| worker.submit(query)))
    }

    pub fn apply_online_candidate(
        &mut self,
        query: &OnlineQuery,
        candidate: &str,
        source: u8,
    ) -> Result<bool, RuntimeError> {
        // Provider callbacks are asynchronous and can be malformed even when
        // their query identity is still current. Keep the single-item path
        // subject to the same bounds as the batch path before handing text to
        // Engine; the Windows source rejects empty callback results as well.
        if candidate.is_empty()
            || candidate.len() > 4096
            || candidate.chars().any(char::is_control)
            || source > 1
            // Windows only merges a cloud suggestion into an existing
            // candidate page.  A callback arriving after the local page was
            // cleared must not manufacture a new page from stale provider
            // state.  AI suggestions intentionally do not use this guard:
            // Windows accepts them for an otherwise eligible pinyin query
            // even when the local dictionary returned no rows.
            || (source == 0 && self.cached.candidates.is_empty())
            || (source == 0 && (!query.cloud_candidates || !query.cloud_eligible))
            || (source == 1 && !query.ai_eligible)
        {
            return Ok(false);
        }
        let query = OnlineQuerySnapshot {
            available: true,
            scheme: query.scheme,
            generation: query.generation,
            identity: query.identity.clone(),
            query_text: query.query_text.clone(),
            cache_key: query.cache_key.clone(),
            pinyin_segments: query.pinyin_segments.clone(),
            cloud_eligible: query.cloud_eligible,
            ai_eligible: query.ai_eligible,
            session_id: query.session_id,
        };
        let applied = self
            .engine
            .apply_online_candidate(&query, candidate, source)
            .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        if applied {
            // An asynchronous provider replaces the visible Engine candidate
            // set without going through dispatch(). Advance the host-owned
            // identity just as an input action does, so stale candidate IDs
            // cannot select the pre-provider page and Windows UI mailboxes can
            // recognize the replacement as a new rendered generation.
            self.advance()?;
            self.refresh()
                .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        }
        Ok(applied)
    }
    pub fn apply_online_candidates(
        &mut self,
        query: &OnlineQuery,
        candidates: &[String],
        source: u8,
    ) -> Result<bool, RuntimeError> {
        let limit = if source == 0 {
            1
        } else {
            query
                .ai_assistant
                .as_ref()
                .filter(|ai| ai.enabled)
                .map_or(0, |ai| usize::from(ai.candidate_limit.clamp(1, 10)))
        };
        if candidates.is_empty()
            || candidates.len() > limit
            || candidates.iter().any(|text| {
                text.is_empty() || text.len() > 4096 || text.chars().any(char::is_control)
            })
            || source > 1
            || (source == 0 && self.cached.candidates.is_empty())
            || (source == 0 && (!query.cloud_candidates || !query.cloud_eligible))
            || (source == 1 && !query.ai_eligible)
        {
            return Ok(false);
        }
        let query = OnlineQuerySnapshot {
            available: true,
            scheme: query.scheme,
            generation: query.generation,
            identity: query.identity.clone(),
            query_text: query.query_text.clone(),
            cache_key: query.cache_key.clone(),
            pinyin_segments: query.pinyin_segments.clone(),
            cloud_eligible: query.cloud_eligible,
            ai_eligible: query.ai_eligible,
            session_id: query.session_id,
        };
        let applied = self
            .engine
            .apply_online_candidates(&query, candidates, source)
            .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        if applied {
            self.advance()?;
            self.refresh()
                .map_err(|error| RuntimeError::Engine(error.to_string()))?;
        }
        Ok(applied)
    }
}

impl<E: InputEngine> Runtime<E> {
    pub fn set_paired_punctuation_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.engine.set_paired_punctuation_enabled(enabled)
    }

    pub fn balance_paired_punctuation_after_auto_close(
        &mut self,
        opening: u8,
    ) -> Result<(), RuntimeError> {
        if opening != b'<' {
            return Err(RuntimeError::InvalidPunctuation);
        }
        self.engine
            .balance_paired_punctuation_after_auto_close(opening)
    }

    pub fn set_punctuation_lock(&mut self, lock: u8) -> Result<(), RuntimeError> {
        self.engine.set_punctuation_lock(lock)
    }

    pub fn set_dedicated_english(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.advance()?;
        self.engine.set_dedicated_english(enabled)?;
        self.refresh()
    }

    pub fn new(engine: E, page_size: u8) -> Result<Self, RuntimeError> {
        Self::new_with_touch_layout(engine, page_size, TouchKeyboardLayout::default())
    }

    pub fn new_with_touch_layout(
        engine: E,
        page_size: u8,
        touch_keyboard_layout: TouchKeyboardLayout,
    ) -> Result<Self, RuntimeError> {
        if !(1..=9).contains(&page_size) {
            return Err(RuntimeError::InvalidPageSize);
        }
        let session = NEXT_SESSION
            .fetch_update(Ordering::Relaxed, Ordering::Relaxed, |id| id.checked_add(1))
            .map_err(|_| RuntimeError::IdentityExhausted)?;
        let cached = engine.snapshot()?;
        Ok(Self {
            engine,
            session,
            generation: 0,
            ai_context: String::new(),
            reranker: None,
            settled_reranker: None,
            focused: false,
            page_size: page_size.into(),
            highlighted: 0,
            translations: HashMap::new(),
            cached,
            snapshot_valid: true,
            character_width: CharacterWidth::Halfwidth,
            touch_keyboard_layout,
        })
    }

    /// Attach a candidate reranker. Hosts load the model themselves, because where a model file
    /// lives is a packaging question that differs per platform and the runtime has no business
    /// guessing at it.
    pub fn set_reranker(&mut self, reranker: Option<Reranker>) {
        self.reranker = reranker;
    }

    /// Attach the model that runs after typing settles. Absent leaves the behaviour unchanged.
    pub fn set_settled_reranker(&mut self, reranker: Option<Reranker>) {
        self.settled_reranker = reranker;
    }

    /// Re-rank the current candidates with the settled model, reporting whether the order moved.
    ///
    /// The host decides when this is: it owns the clock and already runs a settle timer for cloud
    /// candidates. The runtime has no timer of its own and should not grow one — a keystroke that
    /// arrives while this is deciding makes the whole answer stale, and only the host knows that
    /// a keystroke arrived.
    ///
    /// Returns false when nothing changed, so a host can skip redrawing the candidate window. A
    /// window that repaints identically on every pause is a flicker the user cannot explain.
    pub fn rerank_settled(&mut self) -> bool {
        if self.settled_reranker.is_none() || self.is_idle() {
            return false;
        }
        let leader = self.cached.candidates.first().cloned();
        std::mem::swap(&mut self.reranker, &mut self.settled_reranker);
        self.rerank();
        std::mem::swap(&mut self.reranker, &mut self.settled_reranker);
        let moved = self.cached.candidates.first() != leader.as_ref();
        if moved {
            self.snapshot_valid = true;
        }
        moved
    }

    pub fn set_character_width(&mut self, width: CharacterWidth) {
        self.character_width = width;
    }

    /// Put text into the committed context without typing it.
    ///
    /// The context a candidate is ranked against is whatever the user just committed, and it is
    /// what lets the model tell 会议 from 回忆. An evaluation harness has to be able to establish
    /// that context: replaying it as keystrokes would make each case depend on how well the
    /// *previous* sentence converted, which is precisely the confound a per-case measurement is
    /// supposed to remove. Bounded and focus-gated exactly as a real commit is, so a seeded
    /// session is indistinguishable from one that typed its way there.
    pub fn seed_context(&mut self, text: &str) {
        self.remember_commit(text);
    }

    /// Switch the Engine's digit interpretation only after the host finishes composition.
    pub fn set_nine_key_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        if enabled && self.cached.scheme != 0 {
            return Err(RuntimeError::InvalidNineKeyScheme);
        }
        if !self.is_idle() {
            return Err(RuntimeError::CompositionActive);
        }
        if self.cached.nine_key == enabled {
            return Ok(());
        }
        self.advance()?;
        self.engine.set_nine_key_enabled(enabled)?;
        self.refresh()
    }

    pub fn view(&self) -> View {
        let page = self.highlighted / self.page_size;
        let start = page * self.page_size;
        View {
            scheme: self.cached.scheme,
            nine_key: self.cached.nine_key,
            nine_key_spellings: self.cached.nine_key_spellings.clone(),
            touch_keyboard_layout: self.touch_keyboard_layout,
            character_width: self.character_width,
            microsoft_shuangpin: self.cached.microsoft_shuangpin,
            shuangpin_profile: self.cached.shuangpin_profile.clone(),
            answered_by_pinyin_fallback: self.cached.answered_by_pinyin_fallback,
            local_mode: self.cached.local_mode.clone(),
            dedicated_english: self.cached.dedicated_english,
            session: self.session,
            generation: self.generation,
            focused: self.focused,
            preedit: self.cached.preedit.clone(),
            reading: self.cached.reading.clone(),
            editing_text: self.cached.editing_text.clone(),
            caret_position: self.cached.caret_position,
            page,
            page_size: self.page_size,
            page_count: self.cached.candidates.len().div_ceil(self.page_size),
            candidates: self
                .cached
                .candidates
                .iter()
                .enumerate()
                .skip(start)
                .take(self.page_size)
                .map(|(index, text)| self.candidate(index, text))
                .collect(),
        }
    }

    /// Copy the complete candidate generation for an explicitly opened panel.
    pub fn all_candidates(&self) -> CandidateSnapshot {
        CandidateSnapshot {
            session: self.session,
            generation: self.generation,
            preedit: self.cached.preedit.clone(),
            reading: self.cached.reading.clone(),
            candidates: self
                .cached
                .candidates
                .iter()
                .enumerate()
                .map(|(index, text)| self.candidate(index, text))
                .collect(),
        }
    }

    fn candidate(&self, index: usize, text: &str) -> Candidate {
        Candidate {
            id: CandidateId {
                session: self.session,
                generation: self.generation,
                index,
            },
            text: text.to_owned(),
            code: self
                .cached
                .candidate_codes
                .get(index)
                .cloned()
                .unwrap_or_default(),
            annotation: self
                .cached
                .candidate_annotations
                .get(index)
                .cloned()
                .unwrap_or_default(),
            source: self
                .cached
                .candidate_sources
                .get(index)
                .copied()
                .unwrap_or_default(),
            corrected: self
                .cached
                .candidate_corrected
                .get(index)
                .copied()
                .unwrap_or(false),
            fixed_position: self
                .cached
                .candidate_positions
                .get(index)
                .copied()
                .unwrap_or_default(),
            highlighted: index == self.highlighted,
            translation: self.translations.get(text).cloned(),
        }
    }

    pub fn is_idle(&self) -> bool {
        self.snapshot_valid
            && self.cached.preedit.is_empty()
            && self.cached.editing_text.is_empty()
            && self.cached.candidates.is_empty()
    }

    /// Apply translations to the current candidate generation. Stale async
    /// responses are ignored so a newer candidate window cannot be polluted.
    pub fn apply_translations(
        &mut self,
        generation: u64,
        translations: impl IntoIterator<Item = (String, String)>,
    ) -> bool {
        if generation != self.generation {
            return false;
        }
        self.translations = translations.into_iter().collect();
        true
    }

    /// Presentation-only resize; a live composition keeps its numeric key map.
    pub fn set_page_size(&mut self, page_size: u8) -> Result<(), RuntimeError> {
        if !(1..=9).contains(&page_size) {
            return Err(RuntimeError::InvalidPageSize);
        }
        if self.page_size == usize::from(page_size) {
            return Ok(());
        }
        if !self.is_idle() {
            return Err(RuntimeError::CompositionActive);
        }
        self.advance()?;
        self.page_size = page_size.into();
        Ok(())
    }

    /// Preserve the host handle/focus while invalidating every old candidate ID.
    /// Validate the replacement before changing any live state.
    pub fn replace_engine(&mut self, engine: E, page_size: u8) -> Result<(), RuntimeError> {
        self.replace_engine_with_touch_layout(engine, page_size, self.touch_keyboard_layout)
    }

    pub fn replace_engine_with_touch_layout(
        &mut self,
        engine: E,
        page_size: u8,
        touch_keyboard_layout: TouchKeyboardLayout,
    ) -> Result<(), RuntimeError> {
        if !(1..=9).contains(&page_size) {
            return Err(RuntimeError::InvalidPageSize);
        }
        if !self.is_idle() {
            return Err(RuntimeError::CompositionActive);
        }
        let cached = engine.snapshot()?;
        self.advance()?;
        self.engine = engine;
        self.cached = cached;
        self.snapshot_valid = true;
        self.page_size = page_size.into();
        self.highlighted = 0;
        self.touch_keyboard_layout = touch_keyboard_layout;
        Ok(())
    }

    /// The Engine caps a single-letter query at twenty-four candidates so the first page is cheap,
    /// and hands over the rest only when asked. Without this, paging stops at that cap and the rest
    /// of the dictionary is unreachable for those queries.
    ///
    /// Expanding when the next page would be the partial last one keeps that page full the first
    /// time it is shown, rather than showing a short page that silently grows.
    ///
    /// Answers whether the arrivals filled the page the caller is already on, in which case paging
    /// has to stay put: advancing would step over the candidates that just showed up.
    fn expand_for_next_page(&mut self) -> Result<bool, RuntimeError> {
        let len = self.cached.candidates.len();
        if len == 0 {
            return Ok(false);
        }
        let page = self.highlighted / self.page_size;
        let last_page = (len - 1) / self.page_size;
        let next_is_partial_last = page + 1 == last_page && !len.is_multiple_of(self.page_size);
        if page != last_page && !next_is_partial_last {
            return Ok(false);
        }
        let page_was_full = (page + 1) * self.page_size <= len;
        if !self.engine.expand_initial_candidates()? {
            return Ok(false);
        }
        self.cached = self.engine.snapshot()?;
        self.rerank();
        self.demote_runner_up_readings();
        Ok(page == last_page && !page_was_full)
    }

    fn advance(&mut self) -> Result<(), RuntimeError> {
        self.generation = self
            .generation
            .checked_add(1)
            .ok_or(RuntimeError::IdentityExhausted)?;
        Ok(())
    }

    /// Keep the tail of what was committed, cut on a character boundary.
    ///
    /// Bounded at 1024 bytes because `query_candidates` refuses anything longer
    /// outright - an over-long context would silently disable the whole query
    /// rather than being trimmed for us.
    pub(crate) fn remember_commit(&mut self, text: &str) {
        if !self.focused {
            self.ai_context.clear();
            return;
        }
        self.ai_context.push_str(text);
        if self.ai_context.len() > 1024 {
            let mut cut = self.ai_context.len() - 1024;
            while cut < self.ai_context.len() && !self.ai_context.is_char_boundary(cut) {
                cut += 1;
            }
            self.ai_context.drain(..cut);
        }
    }

    fn transition(&mut self, result: EngineResult) -> Transition {
        // Every commit passes through here, so this is the one place the AI
        // context has to be fed from.
        if result.has_commit {
            let committed = result.commit.clone();
            self.remember_commit(&committed);
        }
        Transition {
            commit_context: result.has_commit.then(|| OutputContext {
                scheme: self.cached.scheme,
                local_mode: self.cached.local_mode.clone(),
            }),
            handled: result.handled,
            commit: result.has_commit.then_some(result.commit),
            diagnostic: (!result.diagnostic.is_empty()).then_some(result.diagnostic),
            view: self.view(),
        }
    }

    /// Let the model promote a candidate the pinyin decoder assembled, if a host attached one.
    ///
    /// Reordering happens here because this is the one place a candidate list enters the runtime,
    /// so everything downstream — the view, `all_candidates`, the evaluation harness — sees the
    /// same order the user does.
    ///
    /// The candidate arrays run in parallel and every one of them has to move together. Rotating
    /// only the texts would leave each candidate wearing another's code, annotation and source.
    fn rerank(&mut self) {
        let Some(reranker) = self.reranker.as_mut() else {
            return;
        };
        let snapshot = &self.cached;
        let count = snapshot.candidates.len();
        if count < 2
            || snapshot.candidate_sources.len() != count
            || snapshot.candidate_codes.len() != count
            || snapshot.candidate_annotations.len() != count
            || snapshot.candidate_positions.len() != count
            || snapshot.candidate_corrected.len() != count
        {
            return;
        }
        let texts: Vec<&str> = snapshot.candidates.iter().map(String::as_str).collect();
        let Some(promote) = reranker.best(&self.ai_context, &texts, &snapshot.candidate_sources)
        else {
            return;
        };
        let snapshot = &mut self.cached;
        rotate_to_front(&mut snapshot.candidates, promote);
        rotate_to_front(&mut snapshot.candidate_codes, promote);
        rotate_to_front(&mut snapshot.candidate_annotations, promote);
        rotate_to_front(&mut snapshot.candidate_sources, promote);
        rotate_to_front(&mut snapshot.candidate_positions, promote);
        rotate_to_front(&mut snapshot.candidate_corrected, promote);
    }

    /// Move the runner-up sentence readings behind the rest of the list.
    ///
    /// The lattice searches several readings of the whole key so that something can choose between
    /// them. Leaving all of them at the front fills the candidate page with near-duplicate
    /// sentences and pushes the short candidates a user actually wants off it, which is why the
    /// search used to be pinned to a single path.
    ///
    /// They are moved rather than removed. A candidate page needs its *first* row to be the chosen
    /// reading; it does not need the others gone. Deleting them threw away the model's second and
    /// third choices, so a reading the model ranked third was unreachable even when it was right.
    ///
    /// Only lattice readings are touched. An earlier version of this keyed on "any source that is
    /// not a dictionary", which is wrong twice over: a source number says which code produced a
    /// candidate, not that two candidates are spellings of one answer, and most of the other
    /// sources are plural by design — English words, emoji, kaomoji, quick phrases and AI
    /// suggestions all arrive as lists, and that version silently dropped all but one of each.
    fn demote_runner_up_readings(&mut self) {
        // The lattice never runs on fewer than three syllables, so a shorter candidate reached the
        // list some other way and is not a reading of the same sentence. Japanese kana are the case
        // that proves it: あ and ア are both Generated and both one character.
        const SENTENCE_SYLLABLES: usize = 3;

        let snapshot = &self.cached;
        let count = snapshot.candidates.len();
        if count < 2 || snapshot.candidate_sources.len() != count {
            return;
        }
        let Some(width) = snapshot
            .candidates
            .iter()
            .zip(&snapshot.candidate_sources)
            .find(|(_, source)| **source == LATTICE_SOURCE)
            .map(|(text, _)| text.chars().count())
        else {
            return;
        };
        if width < SENTENCE_SYLLABLES {
            return;
        }
        // Everything after the first lattice reading of the full key is a runner-up.
        let mut kept_one = false;
        let mut demote: Vec<bool> = Vec::with_capacity(count);
        for (text, source) in snapshot.candidates.iter().zip(&snapshot.candidate_sources) {
            let reading = *source == LATTICE_SOURCE && text.chars().count() == width;
            demote.push(reading && kept_one);
            kept_one |= reading;
        }
        if !demote.iter().any(|moved| *moved) {
            return;
        }
        let snapshot = &mut self.cached;
        move_to_back(&mut snapshot.candidates, &demote);
        move_to_back(&mut snapshot.candidate_codes, &demote);
        move_to_back(&mut snapshot.candidate_annotations, &demote);
        move_to_back(&mut snapshot.candidate_sources, &demote);
        move_to_back(&mut snapshot.candidate_positions, &demote);
        move_to_back(&mut snapshot.candidate_corrected, &demote);
    }

    pub(crate) fn refresh(&mut self) -> Result<(), RuntimeError> {
        self.snapshot_valid = false;
        self.translations.clear();
        // Drop cached candidate identities even if fetching the replacement fails.
        let previous = std::mem::replace(
            &mut self.cached,
            EngineSnapshot {
                scheme: 255,
                nine_key: false,
                nine_key_spellings: Vec::new(),
                candidate_annotations: Vec::new(),
                candidate_codes: Vec::new(),
                candidate_sources: Vec::new(),
                candidate_positions: Vec::new(),
                candidate_corrected: Vec::new(),
                microsoft_shuangpin: false,
                shuangpin_profile: String::new(),
                answered_by_pinyin_fallback: true,
                local_mode: "unknown".into(),
                dedicated_english: false,
                preedit: String::new(),
                reading: String::new(),
                editing_text: String::new(),
                caret_position: 0,
                segment_raw_boundaries: vec![],
                candidates: Vec::new(),
            },
        );
        let previous_highlight = self.highlighted;
        self.highlighted = 0;
        self.cached = self.engine.snapshot()?;
        self.rerank();
        self.demote_runner_up_readings();
        self.snapshot_valid = true;
        if self.cached.editing_text == previous.editing_text
            && self.cached.scheme == previous.scheme
            && self.cached.local_mode == previous.local_mode
            && self.cached.reading == previous.reading
            && self.cached.dedicated_english == previous.dedicated_english
            && self.cached.candidates == previous.candidates
            && self.cached.candidate_codes == previous.candidate_codes
            && self.cached.candidate_annotations == previous.candidate_annotations
            && self.cached.candidate_sources == previous.candidate_sources
            && self.cached.candidate_positions == previous.candidate_positions
            && self.cached.candidate_corrected == previous.candidate_corrected
        {
            self.highlighted =
                previous_highlight.min(self.cached.candidates.len().saturating_sub(1));
        }
        Ok(())
    }

    pub fn focus(&mut self, focused: bool) -> Result<Transition, RuntimeError> {
        self.advance()?;
        // Invalidate the client before cancellation, including on engine failure.
        self.focused = false;
        let result = self.engine.command(Command::Cancel);
        self.refresh()?;
        let result = result?;
        self.focused = focused;
        // A different client is a different sentence, so context never leaks
        // from one application into another.
        self.ai_context.clear();
        Ok(self.transition(result))
    }

    fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
        // Finish through Engine with the host highlight BEFORE asking it to translate.
        // Calling Engine punctuation on an active composition would choose candidate zero.
        let mut finished = self.engine.finish(self.highlighted)?;
        let punctuation = match self.engine.punctuation(value) {
            Ok(result) => result,
            Err(error) if finished.has_commit => {
                // Completion already changed Engine state: never discard that commit.
                finished.commit.push(char::from(value));
                finished.handled = true;
                finished.diagnostic =
                    format!("{} Punctuation failed: {error}", finished.diagnostic)
                        .trim()
                        .to_owned();
                return Ok(finished);
            }
            Err(error) => return Err(error),
        };
        if !finished.has_commit {
            return Ok(punctuation);
        }
        finished.handled = true;
        if punctuation.has_commit {
            finished.commit.push_str(&punctuation.commit);
        } else if !punctuation.handled {
            // ASCII mode/unsupported symbols still terminate composition in one commit.
            finished.commit.push(char::from(value));
        }
        if !punctuation.diagnostic.is_empty() {
            finished.diagnostic = format!("{} {}", finished.diagnostic, punctuation.diagnostic)
                .trim()
                .to_owned();
        }
        Ok(finished)
    }

    fn punctuation_ascii(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
        // Keep the same highlighted-candidate completion semantics as normal
        // punctuation, but do not ask Engine to translate the trailing mark.
        // The Linux host has already applied its surrounding-text policy.
        let mut finished = self.engine.finish(self.highlighted)?;
        if !finished.has_commit {
            return Ok(finished);
        }
        finished.handled = true;
        finished.commit.push(char::from(value));
        Ok(finished)
    }

    pub fn dispatch(&mut self, action: Action) -> Result<Transition, RuntimeError> {
        if matches!(&action, Action::Punctuation(value) | Action::PunctuationAscii(value) if !value.is_ascii_punctuation())
        {
            return Err(RuntimeError::InvalidPunctuation);
        }
        // Cache maintenance belongs to the session, including while its host
        // has no focus. Ordinary input must still pass through unchanged.
        if !self.focused && !matches!(&action, Action::ResetCache) {
            return Ok(self.transition(empty_result(false)));
        }
        if let Action::SelectAnyCandidate(id) = &action {
            if id.session != self.session
                || id.generation != self.generation
                || id.index >= self.cached.candidates.len()
            {
                return Err(RuntimeError::StaleCandidate);
            }
        }
        if let Action::Select(id)
        | Action::SelectEdge(id, _)
        | Action::PinCandidate(id)
        | Action::RemoveCandidate(id)
        | Action::FixCandidatePosition(id, _)
        | Action::ClearCandidatePosition(id) = &action
        {
            let start = (self.highlighted / self.page_size) * self.page_size;
            if id.session != self.session
                || id.generation != self.generation
                || id.index < start
                || id.index >= (start + self.page_size).min(self.cached.candidates.len())
            {
                return Err(RuntimeError::StaleCandidate);
            }
        }
        if let Action::ChooseNineKeySpelling(id) = &action {
            if id.session != self.session
                || id.generation != self.generation
                || !self.cached.nine_key
                || id.index >= self.cached.nine_key_spellings.len()
            {
                return Err(RuntimeError::StaleNineKeySpelling);
            }
        }
        self.advance()?;
        let filled_current_page =
            matches!(action, Action::NextPage) && self.expand_for_next_page()?;
        let len = self.cached.candidates.len();
        let next_highlight = match &action {
            // Staying keeps the highlight exactly where it was: the page did not change, it only
            // stopped being short.
            Action::NextPage if filled_current_page => Some(self.highlighted),
            Action::NextPage if len > 0 => Some(
                (self.highlighted / self.page_size + 1).min((len - 1) / self.page_size)
                    * self.page_size,
            ),
            Action::PreviousPage if len > 0 => {
                Some((self.highlighted / self.page_size).saturating_sub(1) * self.page_size)
            }
            Action::NextCandidate if len > 0 => Some((self.highlighted + 1).min(len - 1)),
            Action::PreviousCandidate if len > 0 => Some(self.highlighted.saturating_sub(1)),
            Action::FirstCandidateOnPage if len > 0 => {
                Some((self.highlighted / self.page_size) * self.page_size)
            }
            Action::LastCandidateOnPage if len > 0 => Some(
                ((self.highlighted / self.page_size) * self.page_size + self.page_size)
                    .min(len)
                    .saturating_sub(1),
            ),
            _ => None,
        };
        if let Some(index) = next_highlight {
            self.highlighted = index;
            return Ok(self.transition(empty_result(true)));
        }
        let commit_context = OutputContext {
            scheme: self.cached.scheme,
            local_mode: self.cached.local_mode.clone(),
        };
        let result = match action {
            Action::ResetCache => {
                self.engine.reset_cache()?;
                Ok(EngineResult {
                    handled: true,
                    has_commit: false,
                    commit: String::new(),
                    diagnostic: String::new(),
                })
            }
            Action::Punctuation(value) => self.punctuation(value),
            Action::PunctuationAscii(value) => self.punctuation_ascii(value),
            Action::Finish => self.engine.finish(self.highlighted),
            Action::Character { value, shift } => {
                self.engine.character(value, shift).and_then(|result| {
                    // The nine-key separator is a layout action, not Chinese quote punctuation.
                    if !result.handled && self.cached.nine_key && value == b'\'' {
                        return Ok(result);
                    }
                    if !result.handled && value.is_ascii_punctuation() {
                        return self.punctuation(value);
                    }
                    // Let Engine consume numeric input (Unicode mode, nine-key, etc.) first.
                    if result.handled
                        || self.cached.nine_key
                        || !(b'1'..=b'9').contains(&value)
                        || len == 0
                    {
                        return Ok(result);
                    }
                    let page_start = (self.highlighted / self.page_size) * self.page_size;
                    let slot = usize::from(value - b'1');
                    if slot >= self.page_size || page_start + slot >= len {
                        return Ok(empty_result(true));
                    }
                    self.engine.select(page_start + slot)
                })
            }
            Action::Command(command) => self.engine.command(command),
            Action::SegmentBackspace => self.engine.segment_command(SegmentCommand::Backspace),
            Action::SegmentMoveLeft => self.engine.segment_command(SegmentCommand::MoveLeft),
            Action::SegmentMoveRight => self.engine.segment_command(SegmentCommand::MoveRight),
            Action::Select(id) => self.engine.select(id.index),
            Action::SelectAnyCandidate(id) => self.engine.select(id.index),
            Action::SelectEdge(id, edge) => self.engine.select_edge(id.index, edge),
            Action::PinCandidate(id) => self.engine.pin_candidate(id.index),
            Action::RemoveCandidate(id) => self.engine.remove_candidate(id.index),
            Action::FixCandidatePosition(id, position) => {
                if !(1..=5).contains(&position) {
                    return Err(RuntimeError::Engine(
                        "Candidate position must be between 1 and 5".into(),
                    ));
                }
                self.engine.fix_candidate_position(id.index, position)
            }
            Action::ClearCandidatePosition(id) => self.engine.clear_candidate_position(id.index),
            Action::ChooseNineKeySpelling(id) => self.engine.choose_nine_key_spelling(id.index),
            Action::SelectHighlighted if len > 0 => self.engine.select(self.highlighted),
            Action::SelectHighlighted => self.engine.command(Command::CommitCandidate),
            _ => return Ok(self.transition(empty_result(false))),
        };
        let refresh = self.refresh();
        let mut result = result?;
        if let Err(error) = refresh {
            // A successful engine commit must survive a presentation refresh failure.
            result.diagnostic = format!("Candidate refresh failed: {error}");
        }
        let mut transition = self.transition(result);
        if transition.commit.is_some() {
            transition.commit_context = Some(commit_context);
        }
        Ok(transition)
    }
}

pub(crate) fn empty_result(handled: bool) -> EngineResult {
    EngineResult {
        handled,
        has_commit: false,
        commit: String::new(),
        diagnostic: String::new(),
    }
}
