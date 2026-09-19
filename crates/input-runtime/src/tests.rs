//! Unit tests for the parent module, in their own file because the module
//! is large enough that mixing them with the implementation obscured both.
//! Same `mod tests` as before, so `use super::*` still names the parent.

use super::runtime::empty_result;
use super::*;

#[cfg(unix)]
use std::os::unix::fs::PermissionsExt;
#[cfg(unix)]
use std::os::unix::net::UnixListener;
use std::time::Duration;
struct Fixture {
    scheme: u8,
    dedicated_english: bool,
    nine_key: bool,
    nine_key_spellings: Vec<String>,
    local_mode: String,
    words: Vec<String>,
    codes: Vec<String>,
    text: String,
    snapshot_fails: bool,
    balanced_openings: Vec<u8>,
    cache_resets: usize,
}

#[cfg(unix)]
fn private_tempdir() -> tempfile::TempDir {
    let directory = tempfile::tempdir().unwrap();
    std::fs::set_permissions(directory.path(), std::fs::Permissions::from_mode(0o700)).unwrap();
    directory
}

#[cfg(unix)]
#[test]
fn provider_connect_rejects_untrusted_filesystem_endpoints() {
    let root = private_tempdir();
    let socket = root.path().join("provider.sock");
    std::fs::write(&socket, b"synthetic").unwrap();
    assert!(UnixSocketProvider::new(&socket).connect().is_none());
    std::fs::remove_file(&socket).unwrap();

    let target = root.path().join("target.sock");
    let listener = UnixListener::bind(&target).unwrap();
    let alias = root.path().join("alias.sock");
    std::os::unix::fs::symlink(&target, &alias).unwrap();
    assert!(UnixSocketProvider::new(&alias).connect().is_none());
    drop(listener);

    let socket = root.path().join("private.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    std::fs::set_permissions(root.path(), std::fs::Permissions::from_mode(0o755)).unwrap();
    assert!(UnixSocketProvider::new(&socket).connect().is_none());
    drop(listener);
}

#[cfg(unix)]
#[test]
fn cloud_dictionary_provider_forwards_bounded_request() {
    let directory = private_tempdir();
    let socket = directory.path().join("cloud-dictionary.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
        let mut line = String::new();
        std::io::BufRead::read_line(&mut reader, &mut line).unwrap();
        let request: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(request["version"], 1);
        assert_eq!(request["kind"], "cloud_dictionary");
        assert_eq!(request["request"]["operation"], "changes");
        let mut stream = stream;
        std::io::Write::write_all(&mut stream, br#"{"changes":[],"next":0}"#).unwrap();
        std::io::Write::write_all(&mut stream, b"\n").unwrap();
    });
    let request = json!({"operation":"changes","after":0,"limit":1});
    let response = UnixSocketProvider::new(socket)
        .cloud_dictionary(request)
        .unwrap();
    assert_eq!(response["next"], 0);
    server.join().unwrap();
}

#[cfg(unix)]
#[test]
fn credential_test_provider_keeps_request_and_response_bounded() {
    let directory = private_tempdir();
    let socket = directory.path().join("online.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = std::thread::spawn(move || {
        let (stream, _) = listener.accept().unwrap();
        let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
        let mut line = String::new();
        std::io::BufRead::read_line(&mut reader, &mut line).unwrap();
        let request: Value = serde_json::from_str(&line).unwrap();
        assert_eq!(request["version"], 1);
        assert_eq!(request["kind"], "credential_test");
        assert_eq!(request["query"]["service"], "ai.assistant");
        assert_eq!(request["query"]["config"]["provider"], "deepseek");
        let mut stream = stream;
        std::io::Write::write_all(
            &mut stream,
            br#"{"ok":true,"message":"configuration accepted"}"#,
        )
        .unwrap();
        std::io::Write::write_all(&mut stream, b"\n").unwrap();
    });
    let response = UnixSocketProvider::new(socket)
        .test_credential("ai.assistant", &json!({"provider":"deepseek"}))
        .unwrap();
    assert!(response.ok);
    assert_eq!(response.message, "configuration accepted");
    server.join().unwrap();

    assert!(
        UnixSocketProvider::new(directory.path().join("missing.sock"))
            .test_credential("unknown", &json!({}))
            .is_none()
    );
    assert!(
        UnixSocketProvider::new(directory.path().join("missing.sock"))
            .test_credential("voice.asr", &json!({"value":"x".repeat(16_384)}))
            .is_none()
    );
}

#[cfg(unix)]
#[test]
fn translation_provider_rejects_controls_at_the_socket_boundary() {
    let directory = private_tempdir();
    let request_socket = directory.path().join("translation-request.sock");
    let listener = UnixListener::bind(&request_socket).unwrap();
    listener.set_nonblocking(true).unwrap();
    let done = std::sync::Arc::new(std::sync::atomic::AtomicBool::new(false));
    let accepted = std::sync::Arc::new(std::sync::atomic::AtomicUsize::new(0));
    let server_done = done.clone();
    let server_accepted = accepted.clone();
    let server = std::thread::spawn(move || loop {
        match listener.accept() {
            Ok((mut stream, _)) => {
                server_accepted.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                std::io::Write::write_all(
                    &mut stream,
                    br#"{"translations":[{"text":"safe","translation":"safe"}]}"#,
                )
                .unwrap();
                std::io::Write::write_all(&mut stream, b"\n").unwrap();
            }
            Err(error) if error.kind() == std::io::ErrorKind::WouldBlock => {
                if server_done.load(std::sync::atomic::Ordering::Relaxed) {
                    break;
                }
                std::thread::sleep(Duration::from_millis(1));
            }
            Err(error) => panic!("translation fixture failed: {error}"),
        }
    });
    let provider = UnixSocketProvider::new(&request_socket);
    for codepoint in (0..=0x1f).chain(0x7f..=0x9f) {
        let control = char::from_u32(codepoint).unwrap();
        assert!(provider
            .translate(TranslationQuery {
                generation: 1,
                target_language: "en".into(),
                candidates: vec![format!("safe{control}")],
                custom_translation: None,
                niutrans: None,
            })
            .is_none());
    }
    done.store(true, std::sync::atomic::Ordering::Relaxed);
    server.join().unwrap();
    assert_eq!(accepted.load(std::sync::atomic::Ordering::Relaxed), 0);

    let response_socket = directory.path().join("translation-response.sock");
    let listener = UnixListener::bind(&response_socket).unwrap();
    let server = std::thread::spawn(move || {
        let reply = |mut stream: std::os::unix::net::UnixStream, response: &str| {
            let mut reader = std::io::BufReader::new(stream.try_clone().unwrap());
            let mut request = String::new();
            std::io::BufRead::read_line(&mut reader, &mut request).unwrap();
            std::io::Write::write_all(&mut stream, response.as_bytes()).unwrap();
            std::io::Write::write_all(&mut stream, b"\n").unwrap();
        };
        for codepoint in (0..=0x1f).chain(0x7f..=0x9f) {
            let (stream, _) = listener.accept().unwrap();
            let control = char::from_u32(codepoint).unwrap();
            let response = json!({
                "translations": [{"text":"safe","translation":format!("before{control}after")}]
            })
            .to_string();
            reply(stream, &response);
        }
        let (stream, _) = listener.accept().unwrap();
        reply(
            stream,
            r#"{"translations":[{"text":"safe","translation":"translated"}]}"#,
        );
    });
    let provider = UnixSocketProvider::new(response_socket);
    let query = TranslationQuery {
        generation: 1,
        target_language: "en".into(),
        candidates: vec!["safe".into()],
        custom_translation: None,
        niutrans: None,
    };
    for _ in (0..=0x1f).chain(0x7f..=0x9f) {
        assert!(provider.translate(query.clone()).is_none());
    }
    assert_eq!(
        provider.translate(query).unwrap(),
        vec![TranslationResult {
            text: "safe".into(),
            translation: "translated".into(),
        }]
    );
    server.join().unwrap();
}

#[cfg(unix)]
#[test]
fn voice_provider_rejects_events_without_generation_binding() {
    let directory = private_tempdir();
    let socket = directory.path().join("voice.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    let server = std::thread::spawn(move || {
        let (mut stream, _) = listener.accept().unwrap();
        let mut request = String::new();
        std::io::BufRead::read_line(
            &mut std::io::BufReader::new(stream.try_clone().unwrap()),
            &mut request,
        )
        .unwrap();
        std::io::Write::write_all(&mut stream, br#"{"text":"stale","type":"final"}"#).unwrap();
        std::io::Write::write_all(&mut stream, b"\n").unwrap();
    });
    let provider = UnixSocketProvider::new(socket);
    assert!(provider
        .voice_stream_with_options_feedback(
            "zh-cn",
            7,
            &Value::Null,
            None,
            &mut |_, _| {},
            None,
            None,
        )
        .is_none());
    server.join().unwrap();
}

#[cfg(unix)]
#[test]
fn dangling_segment_delimiter_cleanup_matches_windows_policy() {
    assert!(needs_dangling_segment_delimiter_backspace("ni'", 3));
    assert!(needs_dangling_segment_delimiter_backspace("ni''ma", 3));
    assert!(!needs_dangling_segment_delimiter_backspace("ni", 2));
    assert!(!needs_dangling_segment_delimiter_backspace("'ma", 0));
    assert!(!needs_dangling_segment_delimiter_backspace("ni'", 2));
    assert!(!needs_dangling_segment_delimiter_backspace("ni'", 9));
}

#[test]
fn voice_control_rejects_zero_generation_without_connecting() {
    let directory = private_tempdir();
    let socket = directory.path().join("voice-control.sock");
    let listener = UnixListener::bind(&socket).unwrap();
    listener.set_nonblocking(true).unwrap();
    let provider = UnixSocketProvider::new(&socket);
    assert!(!provider.voice_cancel(0));
    assert!(!provider.voice_stop(0));
    assert!(
        matches!(listener.accept(), Err(error) if error.kind() == std::io::ErrorKind::WouldBlock)
    );
}
impl InputEngine for Fixture {
    fn reset_cache(&mut self) -> Result<(), RuntimeError> {
        self.cache_resets += 1;
        Ok(())
    }
    fn balance_paired_punctuation_after_auto_close(
        &mut self,
        opening: u8,
    ) -> Result<(), RuntimeError> {
        self.balanced_openings.push(opening);
        Ok(())
    }
    fn set_nine_key_enabled(&mut self, enabled: bool) -> Result<(), RuntimeError> {
        self.nine_key = enabled;
        self.nine_key_spellings.clear();
        Ok(())
    }
    fn choose_nine_key_spelling(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        if !self.nine_key || index >= self.nine_key_spellings.len() {
            return Ok(empty_result(false));
        }
        self.text = self.nine_key_spellings[index].clone();
        self.nine_key_spellings = vec![self.text.clone()];
        Ok(empty_result(true))
    }
    fn punctuation(&mut self, value: u8) -> Result<EngineResult, RuntimeError> {
        if value == b'!' {
            return Err(RuntimeError::Engine("injected punctuation failure".into()));
        }
        if value != b',' {
            return Ok(empty_result(false));
        }
        Ok(EngineResult {
            handled: true,
            has_commit: true,
            commit: "，".into(),
            diagnostic: String::new(),
        })
    }
    fn finish(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        if self.text.is_empty() {
            return Ok(empty_result(false));
        }
        let mut result = self.select(index)?;
        result.commit.push_str("-remaining-segments");
        Ok(result)
    }
    fn snapshot(&self) -> Result<EngineSnapshot, RuntimeError> {
        if self.snapshot_fails {
            return Err(RuntimeError::Engine("injected snapshot failure".into()));
        }
        Ok(EngineSnapshot {
            scheme: self.scheme,
            nine_key: self.nine_key,
            nine_key_spellings: self.nine_key_spellings.clone(),
            candidate_codes: self.codes.clone(),
            candidate_annotations: self
                .words
                .iter()
                .enumerate()
                .map(|(index, _)| format!("({index})"))
                .collect(),
            candidate_sources: vec![0; self.words.len()],
            candidate_positions: vec![0; self.words.len()],
            candidate_corrected: vec![false; self.words.len()],
            microsoft_shuangpin: false,
            shuangpin_profile: "xiaohe".into(),
            answered_by_pinyin_fallback: false,
            local_mode: self.local_mode.clone(),
            dedicated_english: self.dedicated_english,
            preedit: self.text.clone(),
            reading: String::new(),
            editing_text: self.text.clone(),
            caret_position: self.text.len(),
            segment_raw_boundaries: vec![],
            candidates: if self.text.is_empty() {
                vec![]
            } else {
                self.words.clone()
            },
        })
    }
    fn character(&mut self, value: u8, _shift: bool) -> Result<EngineResult, RuntimeError> {
        if self.nine_key && (b'2'..=b'9').contains(&value) {
            self.text.push(value as char);
            self.nine_key_spellings = vec!["ni".into(), "mi".into()];
            return Ok(empty_result(true));
        }
        if value.is_ascii_digit() || value.is_ascii_punctuation() {
            return Ok(empty_result(false));
        }
        self.text.push(value as char);
        Ok(empty_result(true))
    }
    fn command(&mut self, _command: Command) -> Result<EngineResult, RuntimeError> {
        self.text.clear();
        self.nine_key_spellings.clear();
        Ok(empty_result(true))
    }
    fn select(&mut self, index: usize) -> Result<EngineResult, RuntimeError> {
        self.text.clear();
        self.nine_key_spellings.clear();
        self.local_mode = "none".into();
        Ok(EngineResult {
            handled: true,
            has_commit: true,
            commit: self.words[index].clone(),
            diagnostic: String::new(),
        })
    }
    fn select_edge(
        &mut self,
        index: usize,
        edge: CandidateEdge,
    ) -> Result<EngineResult, RuntimeError> {
        let mut result = self.select(index)?;
        result.commit.push_str(match edge {
            CandidateEdge::FirstHan => "-first",
            CandidateEdge::LastHan => "-last",
        });
        Ok(result)
    }
}
fn runtime() -> Runtime<Fixture> {
    Runtime::new(
        Fixture {
            scheme: 0,
            dedicated_english: false,
            nine_key: false,
            nine_key_spellings: Vec::new(),
            local_mode: "none".into(),
            words: (0..12).map(|n| format!("candidate-{n}")).collect(),
            codes: Vec::new(),
            text: String::new(),
            snapshot_fails: false,
            balanced_openings: Vec::new(),
            cache_resets: 0,
        },
        5,
    )
    .unwrap()
}

#[test]
fn auto_close_balance_accepts_only_the_book_title_opening() {
    let mut runtime = runtime();
    for invalid in [b'(', b'>', b'a', b' ', 0, 128, 255] {
        assert!(matches!(
            runtime.balance_paired_punctuation_after_auto_close(invalid),
            Err(RuntimeError::InvalidPunctuation)
        ));
    }
    assert!(runtime.engine.balanced_openings.is_empty());
    runtime
        .balance_paired_punctuation_after_auto_close(b'<')
        .unwrap();
    assert_eq!(runtime.engine.balanced_openings, vec![b'<']);
}

// The AI context accumulator. Every host but Linux sent an empty context,
// so AI suggestions had to guess from the pinyin alone.
#[test]
fn ai_context_keeps_the_recent_tail_on_a_character_boundary() {
    let mut runtime = runtime();
    runtime.focused = true;
    runtime.remember_commit("你好");
    runtime.remember_commit("世界");
    assert_eq!(runtime.ai_context, "你好世界");

    // Bounded at 1024 bytes, because query_candidates refuses anything
    // longer outright rather than trimming it.
    for _ in 0..400 {
        runtime.remember_commit("字");
    }
    assert!(runtime.ai_context.len() <= 1024);
    // The cut lands on a character boundary, so the context is still valid
    // UTF-8 and does not start with half a character.
    assert!(runtime.ai_context.is_char_boundary(0));
    assert!(std::str::from_utf8(runtime.ai_context.as_bytes()).is_ok());
    assert!(runtime.ai_context.ends_with('字'));
    // It is the tail that is kept, not the head.
    assert!(!runtime.ai_context.starts_with("你好"));
}

#[test]
fn ai_context_does_not_leak_between_clients() {
    let mut runtime = runtime();
    runtime.focused = true;
    runtime.remember_commit("上一个应用里的句子");
    assert!(!runtime.ai_context.is_empty());

    // A commit while unfocused is not context at all, and clears what was
    // there: the user has left.
    runtime.focused = false;
    runtime.remember_commit("anything");
    assert!(runtime.ai_context.is_empty());
}
fn type_key(runtime: &mut Runtime<Fixture>) -> Transition {
    runtime
        .dispatch(Action::Character {
            value: b'a',
            shift: false,
        })
        .unwrap()
}

#[test]
fn candidate_codes_follow_candidates_in_page_and_complete_snapshots() {
    let mut runtime = Runtime::new(
        Fixture {
            scheme: 2,
            dedicated_english: false,
            nine_key: false,
            nine_key_spellings: Vec::new(),
            local_mode: "none".into(),
            words: vec!["甲".into(), "乙".into()],
            codes: vec!["ab".into(), "ac".into()],
            text: String::new(),
            snapshot_fails: false,
            balanced_openings: Vec::new(),
            cache_resets: 0,
        },
        2,
    )
    .unwrap();
    runtime.focus(true).unwrap();
    let page = type_key(&mut runtime).view;
    assert_eq!(page.candidates[0].code, "ab");
    assert_eq!(page.candidates[1].code, "ac");
    let snapshot = runtime.all_candidates();
    assert_eq!(snapshot.candidates[0].code, "ab");
    assert_eq!(snapshot.candidates[1].code, "ac");
    assert!(snapshot.reading.is_empty());
    let serialized = serde_json::to_value(snapshot).unwrap();
    assert_eq!(serialized["candidates"][1]["code"], "ac");
    assert_eq!(serialized["reading"], "");
}

#[test]
fn online_provider_worker_is_bounded_and_filters_invalid_results() {
    let query = OnlineQuery {
        scheme: 0,
        generation: 4,
        identity: "identity".into(),
        query_text: "nihao".into(),
        cache_key: "cache".into(),
        pinyin_segments: vec!["ni".into(), "hao".into()],
        cloud_eligible: true,
        ai_eligible: true,
        cloud_candidates: true,
        session_id: 9,
        ai_context: String::new(),
        ai_assistant: None,
    };
    let worker = OnlineProviderWorker::spawn(1, |query| {
        if query.query_text == "nihao" {
            Some(("你好".into(), 0))
        } else {
            Some((String::new(), 7))
        }
    })
    .unwrap();
    assert!(worker.submit(query.clone()));
    let mut result = None;
    for _ in 0..100 {
        result = worker.try_recv();
        if result.is_some() {
            break;
        }
        std::thread::sleep(Duration::from_millis(1));
    }
    let result = result.expect("provider result");
    assert_eq!(result.query, query);
    assert_eq!(result.text, "你好");
    assert_eq!(result.source, 0);
    worker.shutdown();
}

#[test]
fn cloud_request_requires_eligible_query() {
    assert_eq!(
        WINDOWS_CLOUD_DEBOUNCE,
        std::time::Duration::from_millis(500)
    );
    let mut query = OnlineQuery {
        scheme: 0,
        generation: 1,
        identity: "x".into(),
        query_text: "ni".into(),
        cache_key: "x".into(),
        pinyin_segments: vec![],
        cloud_eligible: false,
        ai_eligible: false,
        cloud_candidates: true,
        session_id: 1,
        ai_context: String::new(),
        ai_assistant: None,
    };
    assert!(cloud_request_url(&query).is_none());
    query.cloud_eligible = true;
    assert!(cloud_request_url(&query)
        .unwrap()
        .contains("inputtools.google.com"));
    let response = serde_json::json!(["SUCCESS", [["ni", ["你"]]]]).to_string();
    let result = cloud_candidate_from_response(query, response.as_bytes()).unwrap();
    assert_eq!(result.text, "你");
    assert_eq!(result.source, 0);
}

#[test]
fn online_provider_worker_rejects_zero_capacity_and_shutdowns_idle() {
    assert!(OnlineProviderWorker::spawn(0, |_| None).is_err());
    let worker = OnlineProviderWorker::spawn(1, |_| None).unwrap();
    worker.shutdown();
}
#[test]
fn replacement_requires_verified_idle_and_preserves_session_focus() {
    let mut active = runtime();
    active.focus(true).unwrap();
    let old = type_key(&mut active).view;
    assert!(matches!(
        active.replace_engine(runtime().engine, 2),
        Err(RuntimeError::CompositionActive)
    ));
    assert_eq!(active.view().editing_text, old.editing_text);
    active.dispatch(Action::Command(Command::Cancel)).unwrap();
    active.replace_engine(runtime().engine, 2).unwrap();
    let updated = type_key(&mut active).view;
    assert_eq!(updated.session, old.session);
    assert!(updated.focused && updated.generation > old.generation);
    assert_eq!(updated.candidates.len(), 2);
    assert!(matches!(
        active.dispatch(Action::Select(old.candidates[0].id)),
        Err(RuntimeError::StaleCandidate)
    ));
    active.engine.snapshot_fails = true;
    assert!(active.refresh().is_err());
    assert!(active.view().editing_text.is_empty());
    assert!(
        !active.is_idle(),
        "missing snapshot is not proof of idle Engine"
    );
    assert!(matches!(
        active.replace_engine(runtime().engine, 2),
        Err(RuntimeError::CompositionActive)
    ));
}

#[test]
fn touch_layout_changes_atomically_with_engine_replacement() {
    let mut active = runtime();
    assert_eq!(
        active.view().touch_keyboard_layout,
        TouchKeyboardLayout::TwentySixKey
    );
    active.focus(true).unwrap();
    type_key(&mut active);
    assert!(matches!(
        active.replace_engine_with_touch_layout(runtime().engine, 2, TouchKeyboardLayout::NineKey),
        Err(RuntimeError::CompositionActive)
    ));
    assert_eq!(
        active.view().touch_keyboard_layout,
        TouchKeyboardLayout::TwentySixKey
    );
    active.dispatch(Action::Command(Command::Cancel)).unwrap();
    active
        .replace_engine_with_touch_layout(runtime().engine, 2, TouchKeyboardLayout::NineKey)
        .unwrap();
    assert_eq!(
        active.view().touch_keyboard_layout,
        TouchKeyboardLayout::NineKey
    );
    active
        .replace_engine_with_touch_layout(runtime().engine, 2, TouchKeyboardLayout::Handwriting)
        .unwrap();
    assert_eq!(
        active.view().touch_keyboard_layout,
        TouchKeyboardLayout::Handwriting
    );
}

#[test]
fn translations_are_generation_scoped_and_exposed_on_candidates() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    let view = type_key(&mut runtime).view;
    assert!(
        !runtime.apply_translations(view.generation - 1, [("candidate-0".into(), "old".into())])
    );
    assert!(runtime.apply_translations(
        view.generation,
        [("candidate-0".into(), "translated".into())]
    ));
    assert_eq!(
        runtime.view().candidates[0].translation.as_deref(),
        Some("translated")
    );
    runtime.dispatch(Action::Command(Command::Cancel)).unwrap();
    assert!(runtime
        .view()
        .candidates
        .iter()
        .all(|candidate| candidate.translation.is_none()));
}

#[test]
fn replacement_snapshot_failure_keeps_the_original_engine() {
    let mut active = runtime();
    active.focus(true).unwrap();
    let generation = active.view().generation;
    let mut replacement = runtime().engine;
    replacement.snapshot_fails = true;
    assert!(active.replace_engine(replacement, 2).is_err());
    assert_eq!(active.view().generation, generation);
    assert_eq!(type_key(&mut active).view.candidates.len(), 5);
}

#[test]
fn paging_and_selection_use_global_engine_indices() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    let page = runtime.dispatch(Action::NextPage).unwrap().view;
    assert_eq!(page.page, 1);
    assert_eq!(page.page_count, 3);
    assert_eq!(page.candidates[0].annotation, "(5)");
    assert_eq!(page.candidates[0].text, "candidate-5");
    let result = runtime
        .dispatch(Action::Select(page.candidates[2].id))
        .unwrap();
    assert_eq!(result.commit.as_deref(), Some("candidate-7"));
    assert!(result.view.candidates.is_empty());
}

#[test]
fn complete_candidate_snapshot_is_on_demand_and_preserves_global_identity() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    let page = type_key(&mut runtime).view;
    assert_eq!(page.candidates.len(), 5);
    assert!(runtime.apply_translations(
        page.generation,
        [("candidate-10".into(), "translated".into())]
    ));

    let snapshot = runtime.all_candidates();
    assert_eq!(snapshot.session, page.session);
    assert_eq!(snapshot.generation, page.generation);
    assert_eq!(snapshot.preedit, "a");
    assert_eq!(snapshot.candidates.len(), 12);
    assert_eq!(snapshot.candidates[10].id.index, 10);
    assert_eq!(snapshot.candidates[10].annotation, "(10)");
    assert_eq!(snapshot.candidates[10].source, 0);
    assert_eq!(snapshot.candidates[10].fixed_position, 0);
    assert_eq!(
        snapshot.candidates[10].translation.as_deref(),
        Some("translated")
    );
    assert!(snapshot.candidates[0].highlighted);
}

#[test]
fn expanded_panel_selection_accepts_only_any_candidate_from_current_generation() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    let page = type_key(&mut runtime).view;
    let outside_page = runtime.all_candidates().candidates[10].id;
    let generation = page.generation;

    assert!(matches!(
        runtime.dispatch(Action::Select(outside_page)),
        Err(RuntimeError::StaleCandidate)
    ));
    for invalid in [
        CandidateId {
            session: outside_page.session + 1,
            ..outside_page
        },
        CandidateId {
            generation: outside_page.generation + 1,
            ..outside_page
        },
        CandidateId {
            index: 12,
            ..outside_page
        },
    ] {
        assert!(matches!(
            runtime.dispatch(Action::SelectAnyCandidate(invalid)),
            Err(RuntimeError::StaleCandidate)
        ));
        assert_eq!(runtime.view().generation, generation);
    }

    let selected = runtime
        .dispatch(Action::SelectAnyCandidate(outside_page))
        .unwrap();
    assert_eq!(selected.commit.as_deref(), Some("candidate-10"));
    assert!(selected.view.candidates.is_empty());
}

#[test]
fn candidate_page_edges_stay_within_the_active_page() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    let first = runtime.dispatch(Action::FirstCandidateOnPage).unwrap().view;
    assert_eq!(
        first
            .candidates
            .iter()
            .find(|c| c.highlighted)
            .unwrap()
            .text,
        "candidate-0"
    );
    let last = runtime.dispatch(Action::LastCandidateOnPage).unwrap().view;
    assert_eq!(
        last.candidates.iter().find(|c| c.highlighted).unwrap().text,
        "candidate-4"
    );
    runtime.dispatch(Action::NextPage).unwrap();
    let page_last = runtime.dispatch(Action::LastCandidateOnPage).unwrap().view;
    assert_eq!(
        page_last
            .candidates
            .iter()
            .find(|c| c.highlighted)
            .unwrap()
            .text,
        "candidate-9"
    );
    let page_first = runtime.dispatch(Action::FirstCandidateOnPage).unwrap().view;
    assert_eq!(
        page_first
            .candidates
            .iter()
            .find(|c| c.highlighted)
            .unwrap()
            .text,
        "candidate-5"
    );
}

#[test]
fn edge_selection_checks_identity_and_routes_global_index() {
    for edge in [CandidateEdge::FirstHan, CandidateEdge::LastHan] {
        let mut active = runtime();
        active.focus(true).unwrap();
        let first = type_key(&mut active).view.candidates[0].id;
        let page = active.dispatch(Action::NextPage).unwrap().view;
        let id = page.candidates[1].id;
        assert_eq!(id.index, 6);
        let generation = active.view().generation;
        for invalid in [
            first,
            CandidateId {
                session: id.session + 1,
                ..id
            },
            CandidateId { index: 0, ..id },
            CandidateId { index: 10, ..id },
        ] {
            assert!(matches!(
                active.dispatch(Action::SelectEdge(invalid, edge)),
                Err(RuntimeError::StaleCandidate)
            ));
            assert_eq!(active.view().generation, generation);
        }
        let selected = active.dispatch(Action::SelectEdge(id, edge)).unwrap();
        assert_eq!(
            selected.commit.as_deref(),
            Some(match edge {
                CandidateEdge::FirstHan => "candidate-6-first",
                CandidateEdge::LastHan => "candidate-6-last",
            })
        );
        assert!(selected.view.editing_text.is_empty());
    }
}

#[test]
fn punctuation_finishes_highlighted_candidate_and_remaining_segments() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    runtime.dispatch(Action::NextPage).unwrap();
    let result = runtime
        .dispatch(Action::Character {
            value: b',',
            shift: false,
        })
        .unwrap();
    assert_eq!(
        result.commit.as_deref(),
        Some("candidate-5-remaining-segments，")
    );
    assert!(result.handled && result.view.editing_text.is_empty());
}

#[test]
fn ascii_punctuation_finishes_highlighted_candidate_for_keypad_marks() {
    for mark in *b".-+/*" {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        type_key(&mut runtime);
        let result = runtime.dispatch(Action::PunctuationAscii(mark)).unwrap();
        let expected = format!("candidate-0-remaining-segments{}", mark as char);
        assert_eq!(result.commit.as_deref(), Some(expected.as_str()));
        assert!(result.handled && result.view.editing_text.is_empty());
    }
}

#[test]
fn unsupported_punctuation_is_appended_only_after_a_composition() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    let idle = runtime
        .dispatch(Action::Character {
            value: b'@',
            shift: false,
        })
        .unwrap();
    assert!(!idle.handled && idle.commit.is_none());
    type_key(&mut runtime);
    let result = runtime
        .dispatch(Action::Character {
            value: b'@',
            shift: false,
        })
        .unwrap();
    assert_eq!(
        result.commit.as_deref(),
        Some("candidate-0-remaining-segments@")
    );
}

#[test]
fn punctuation_failure_does_not_lose_an_already_finished_commit() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    let result = runtime
        .dispatch(Action::Character {
            value: b'!',
            shift: false,
        })
        .unwrap();
    assert_eq!(
        result.commit.as_deref(),
        Some("candidate-0-remaining-segments!")
    );
    assert!(result
        .diagnostic
        .unwrap()
        .contains("injected punctuation failure"));
}

#[test]
fn number_keys_select_the_visible_page_and_pass_through_when_idle() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    assert!(
        !runtime
            .dispatch(Action::Character {
                value: b'2',
                shift: false
            })
            .unwrap()
            .handled
    );
    type_key(&mut runtime);
    runtime.dispatch(Action::NextPage).unwrap();
    let result = runtime
        .dispatch(Action::Character {
            value: b'2',
            shift: false,
        })
        .unwrap();
    assert_eq!(result.commit.as_deref(), Some("candidate-6"));
}

#[test]
fn nine_key_mode_owns_digits_and_spelling_choices_are_generation_scoped() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    let original_generation = runtime.view().generation;
    runtime.set_nine_key_enabled(true).unwrap();
    assert!(runtime.view().nine_key && runtime.view().generation > original_generation);
    let typed = runtime
        .dispatch(Action::Character {
            value: b'6',
            shift: false,
        })
        .unwrap();
    assert!(typed.handled && typed.commit.is_none());
    assert_eq!(
        typed.view.nine_key_spellings,
        vec!["ni".to_owned(), "mi".to_owned()]
    );
    let invalid_digit = runtime
        .dispatch(Action::Character {
            value: b'1',
            shift: false,
        })
        .unwrap();
    assert!(!invalid_digit.handled && invalid_digit.commit.is_none());
    let separator = runtime
        .dispatch(Action::Character {
            value: b'\'',
            shift: false,
        })
        .unwrap();
    assert!(!separator.handled && separator.commit.is_none());
    let generation = separator.view.generation;
    let stale = NineKeySpellingId {
        session: separator.view.session,
        generation: generation - 1,
        index: 0,
    };
    assert!(matches!(
        runtime.dispatch(Action::ChooseNineKeySpelling(stale)),
        Err(RuntimeError::StaleNineKeySpelling)
    ));
    let invalid = NineKeySpellingId {
        session: separator.view.session,
        generation,
        index: 2,
    };
    assert!(matches!(
        runtime.dispatch(Action::ChooseNineKeySpelling(invalid)),
        Err(RuntimeError::StaleNineKeySpelling)
    ));
    let selected = runtime
        .dispatch(Action::ChooseNineKeySpelling(NineKeySpellingId {
            session: separator.view.session,
            generation,
            index: 1,
        }))
        .unwrap();
    assert!(selected.handled && selected.view.editing_text == "mi");
    assert!(matches!(
        runtime.set_nine_key_enabled(false),
        Err(RuntimeError::CompositionActive)
    ));
    runtime.dispatch(Action::Command(Command::Cancel)).unwrap();
    runtime.set_nine_key_enabled(false).unwrap();
    assert!(!runtime.view().nine_key);
    runtime.engine.scheme = 1;
    runtime.refresh().unwrap();
    assert!(matches!(
        runtime.set_nine_key_enabled(true),
        Err(RuntimeError::InvalidNineKeyScheme)
    ));
}

#[test]
fn unavailable_numeric_slot_does_not_jump_back_to_first_page() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    runtime.dispatch(Action::NextPage).unwrap();
    runtime.dispatch(Action::NextPage).unwrap();
    let result = runtime
        .dispatch(Action::Character {
            value: b'9',
            shift: false,
        })
        .unwrap();
    assert!(result.handled && result.commit.is_none());
    assert_eq!(result.view.page, 2);
}

#[test]
fn engine_mode_is_authoritative_and_resets_old_highlight() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    runtime.dispatch(Action::NextPage).unwrap();
    runtime.engine.local_mode = "unicode".into();
    let result = runtime
        .dispatch(Action::Character {
            value: b'0',
            shift: false,
        })
        .unwrap();
    assert_eq!(result.view.local_mode, "unicode");
    assert_eq!(result.view.page, 0);
    assert!(!result.view.editing_text.starts_with('U'));
}

#[test]
fn dedicated_english_state_resets_highlight_without_guessing_from_text() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    runtime.dispatch(Action::NextPage).unwrap();
    let text = runtime.view().editing_text;
    assert!(!runtime.view().dedicated_english);
    assert_eq!(runtime.view().page, 1);
    runtime.engine.dedicated_english = true;
    runtime.refresh().unwrap();
    assert!(runtime.view().dedicated_english);
    assert_eq!(runtime.view().page, 0);
    assert_eq!(runtime.view().editing_text, text);
    assert_eq!(runtime.view().local_mode, "none");
    runtime.engine.dedicated_english = false;
    runtime.refresh().unwrap();
    assert!(!runtime.view().dedicated_english);
}

#[test]
fn commit_context_precedes_mode_reset_for_every_selection_route() {
    for route in 0..5 {
        let mut runtime = runtime();
        runtime.focus(true).unwrap();
        runtime.engine.local_mode = "unicode".into();
        let view = type_key(&mut runtime).view;
        let id = view.candidates[0].id;
        let action = match route {
            0 => Action::Select(id),
            1 => Action::SelectEdge(id, CandidateEdge::FirstHan),
            2 => Action::SelectHighlighted,
            3 => Action::Finish,
            _ => Action::Character {
                value: b'1',
                shift: false,
            },
        };
        let committed = runtime.dispatch(action).unwrap();
        assert!(committed.commit.is_some());
        assert_eq!(committed.commit_context.unwrap().local_mode, "unicode");
        assert_eq!(committed.view.local_mode, "none");
    }
}

#[test]
fn finish_preserves_engine_completion_of_remaining_segments() {
    let mut runtime = runtime();
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    runtime.dispatch(Action::NextPage).unwrap();
    let result = runtime.dispatch(Action::Finish).unwrap();
    assert_eq!(
        result.commit.as_deref(),
        Some("candidate-5-remaining-segments")
    );
    assert!(result.view.preedit.is_empty());
}
#[test]
fn stale_views_and_other_sessions_cannot_select() {
    let mut a = runtime();
    let mut b = runtime();
    a.focus(true).unwrap();
    b.focus(true).unwrap();
    let id = type_key(&mut a).view.candidates[0].id;
    type_key(&mut b);
    assert!(matches!(
        b.dispatch(Action::Select(id)),
        Err(RuntimeError::StaleCandidate)
    ));
    a.dispatch(Action::NextCandidate).unwrap();
    assert!(matches!(
        a.dispatch(Action::Select(id)),
        Err(RuntimeError::StaleCandidate)
    ));
}
#[test]
fn cache_maintenance_reaches_engine_without_acquiring_focus() {
    let mut runtime = runtime();
    let idle = runtime.dispatch(Action::ResetCache).unwrap();
    assert!(idle.handled);
    assert!(idle.commit.is_none());
    assert_eq!(runtime.engine.cache_resets, 1);
    assert!(!runtime.focused);
    assert!(!type_key(&mut runtime).handled);

    runtime.focus(true).unwrap();
    let composed = type_key(&mut runtime);
    let refreshed = runtime.dispatch(Action::ResetCache).unwrap();
    assert_eq!(runtime.engine.cache_resets, 2);
    assert_eq!(refreshed.view.preedit, composed.view.preedit);
    assert!(refreshed.commit.is_none());

    runtime.focus(false).unwrap();
    assert!(runtime.dispatch(Action::ResetCache).unwrap().handled);
    assert_eq!(runtime.engine.cache_resets, 3);
    assert!(!runtime.focused);
    assert!(!type_key(&mut runtime).handled);
}
#[test]
fn unfocused_keys_pass_through_and_blur_cancels_composition() {
    let mut runtime = runtime();
    assert!(!type_key(&mut runtime).handled);
    runtime.focus(true).unwrap();
    let id = type_key(&mut runtime).view.candidates[0].id;
    assert!(runtime.focus(false).unwrap().view.preedit.is_empty());
    assert!(!type_key(&mut runtime).handled);
    runtime.focus(true).unwrap();
    type_key(&mut runtime);
    assert!(matches!(
        runtime.dispatch(Action::Select(id)),
        Err(RuntimeError::StaleCandidate)
    ));
}
#[test]
fn character_width_conversion_preserves_non_ascii_and_roundtrips_ascii() {
    let full = crate::character_width::to_fullwidth("A 1!");
    assert_eq!(full, "Ａ　１！");
    assert_eq!(crate::character_width::to_halfwidth(&full), "A 1!");
    assert_eq!(crate::character_width::to_fullwidth("中文"), "中文");
}

/// `move_to_back` is the whole of the demotion rule that can be tested without an engine, and
/// the version this replaced shipped with no test at all — which is how it reached `develop`
/// dropping Japanese katakana and, separately, the model's own runner-up choices.
#[test]
fn demotion_moves_flagged_items_to_the_end_and_keeps_both_orders() {
    let mut items = vec!["a", "b", "c", "d", "e"];
    crate::move_to_back(&mut items, &[false, true, false, true, false]);
    assert_eq!(items, vec!["a", "c", "e", "b", "d"]);
}

#[test]
fn demotion_loses_nothing() {
    // The point of moving rather than removing: every candidate is still reachable by paging.
    let mut items: Vec<u32> = (0..9).collect();
    crate::move_to_back(
        &mut items,
        &[false, true, true, false, true, false, false, true, true],
    );
    let mut sorted = items.clone();
    sorted.sort_unstable();
    assert_eq!(sorted, (0..9).collect::<Vec<u32>>());
    assert_eq!(items.len(), 9);
}

#[test]
fn demotion_with_no_flags_is_identity() {
    let mut items = vec![1, 2, 3];
    crate::move_to_back(&mut items, &[false, false, false]);
    assert_eq!(items, vec![1, 2, 3]);
}

#[test]
fn a_short_flag_list_leaves_the_tail_in_place() {
    // Defensive: the parallel arrays are length-checked before this runs, but a mismatch must
    // not reorder anything it was not told about.
    let mut items = vec![1, 2, 3, 4];
    crate::move_to_back(&mut items, &[true]);
    assert_eq!(items, vec![2, 3, 4, 1]);
}

/// Only `CandidateSource::Generated` names alternative readings of one key. Every other source
/// is plural by design — English words, emoji, kaomoji, quick phrases, AI suggestions — and an
/// earlier version of this rule kept one of each and dropped the rest.
#[test]
fn only_the_lattice_source_is_treated_as_alternative_readings() {
    assert_eq!(crate::LATTICE_SOURCE, 8);
    for plural in [2u8, 3, 4, 5, 6, 7] {
        assert_ne!(crate::LATTICE_SOURCE, plural);
    }
}

// The real Engine, not the fixture. Unicode mode is the one place where a bare
// digit is input rather than a candidate index, and the two layers decide that
// separately: the Engine reports the digit as handled, and the runtime only
// falls through to selection for a digit the Engine refused. A regression in
// either one silently turns "U4e2d" into a candidate pick, and the Windows and
// macOS suites that would notice both need their own host to run.
fn real_engine_options(root: &std::path::Path) -> msime_engine_bridge::EngineOptions {
    let path = |name: &str| {
        let path = root.join(name);
        std::fs::create_dir_all(&path).unwrap();
        path.to_str().unwrap().to_owned()
    };
    msime_engine_bridge::EngineOptions {
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
        sentence_alternatives: true,
    }
}

#[test]
fn unicode_mode_digits_compose_a_code_point_rather_than_picking_a_candidate() {
    let directory = tempfile::tempdir().unwrap();
    let session =
        msime_engine_bridge::Session::new(&real_engine_options(directory.path())).unwrap();
    let mut runtime = Runtime::new(session, 5).unwrap();
    runtime.focus(true).unwrap();

    let shift_u = runtime
        .dispatch(Action::Character {
            value: b'U',
            shift: true,
        })
        .unwrap();
    assert_eq!(shift_u.view.local_mode, "unicode");

    for value in *b"4e2d" {
        let transition = runtime
            .dispatch(Action::Character {
                value,
                shift: false,
            })
            .unwrap();
        // A digit read as a candidate index would commit here and leave the mode.
        assert!(
            transition.commit.is_none(),
            "{} committed instead of extending the code point",
            value as char
        );
        assert_eq!(transition.view.local_mode, "unicode");
    }
    assert_eq!(runtime.view().editing_text, "U4e2d");
    assert!(runtime
        .view()
        .candidates
        .iter()
        .any(|candidate| candidate.text == "中"));
}

/// Without a settled model attached, the settle call is inert.
///
/// This is the shape every installation that ships one model is in, and the one where a mistake
/// would be invisible: a settle pass that quietly reordered candidates using the fast model would
/// look like the candidate window moving on its own after the user stopped typing.
#[test]
fn settling_without_a_second_model_changes_nothing() {
    let mut runtime = runtime();
    runtime.focus(true).expect("focus");
    for byte in b"nihao" {
        runtime
            .dispatch(Action::Character {
                value: *byte,
                shift: false,
            })
            .expect("type");
    }
    let before: Vec<String> = runtime
        .view()
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect();
    assert!(!runtime.rerank_settled(), "no settled model, nothing to do");
    let after: Vec<String> = runtime
        .view()
        .candidates
        .iter()
        .map(|candidate| candidate.text.clone())
        .collect();
    assert_eq!(after, before);
}

/// An idle session has no candidates to settle on, and asking is not an error.
#[test]
fn settling_while_idle_is_inert() {
    let mut runtime = runtime();
    runtime.focus(true).expect("focus");
    assert!(!runtime.rerank_settled());
}
