//! Keystrokes, punctuation, mode switches and candidate selection - the composing surface.
//!
//! Part of the C ABI; see the parent module for what these shims guarantee.

use crate::*;

/// Native presentation override; changes wait for the current composition to end.
#[no_mangle]
pub extern "C" fn msime_client_set_candidate_page_size(handle: u64, size: u8) -> *mut c_char {
    response(|| {
        if !(1..=9).contains(&size) {
            return Err("candidate page size must be between 1 and 9".into());
        }
        with_session(handle, |session| {
            if session.runtime.is_idle() {
                session
                    .runtime
                    .set_page_size(size)
                    .map_err(|e| e.to_string())?;
            }
            session.page_size_override = Some(size);
            let view = session.runtime.view();
            Ok(json!({"deferred": view.page_size != usize::from(size), "view": view}))
        })
    })
}

/// Override the live host punctuation mode without persisting preferences.
#[no_mangle]
pub extern "C" fn msime_client_set_chinese_punctuation(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_chinese_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
            session.punctuation_override = Some(enabled);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_paired_punctuation(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_paired_punctuation_enabled(enabled)
                .map_err(|e| e.to_string())?;
            session.paired_punctuation_override = Some(enabled);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_punctuation_lock(handle: u64, lock: u8) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_punctuation_lock(lock)
                .map_err(|e| e.to_string())?;
            session.punctuation_lock_override = Some(lock);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_english_mode(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_dedicated_english(enabled)
                .map_err(|e| e.to_string())?;
            session.english_mode = enabled;
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

/// Enable Engine-owned quanpin nine-key digit handling after composition is idle.
#[no_mangle]
pub extern "C" fn msime_client_set_nine_key_mode(handle: u64, enabled: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .set_nine_key_enabled(enabled)
                .map_err(|e| e.to_string())?;
            session.nine_key_override = Some(enabled);
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_set_character_width(handle: u64, fullwidth: bool) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session.runtime.set_character_width(if fullwidth {
                CharacterWidth::Fullwidth
            } else {
                CharacterWidth::Halfwidth
            });
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_character(handle: u64, ascii: u8, shift: bool) -> *mut c_char {
    dispatch(
        handle,
        Action::Character {
            value: ascii,
            shift,
        },
    )
}

#[no_mangle]
pub extern "C" fn msime_client_command(handle: u64, command: u32) -> *mut c_char {
    let action = match command {
        0 => Action::Command(Command::Backspace),
        1 => Action::SelectHighlighted,
        2 => Action::Command(Command::CommitRaw),
        3 => Action::Command(Command::Cancel),
        4 => Action::Command(Command::MoveLeft),
        5 => Action::Command(Command::MoveRight),
        6 => Action::Command(Command::MoveHome),
        7 => Action::Command(Command::MoveEnd),
        8 => Action::Command(Command::DeleteForward),
        9 => Action::Finish,
        10 => Action::Command(Command::CycleKanaVariant),
        11 => Action::Command(Command::CommitReading),
        12 => Action::SegmentBackspace,
        13 => Action::SegmentMoveLeft,
        14 => Action::SegmentMoveRight,
        100 => Action::NextPage,
        101 => Action::PreviousPage,
        102 => Action::NextCandidate,
        103 => Action::PreviousCandidate,
        104 => Action::FirstCandidateOnPage,
        105 => Action::LastCandidateOnPage,
        _ => return response(|| Err("unknown input command".into())),
    };
    dispatch(handle, action)
}

/// Explicit native punctuation route, even when a local mode consumes characters.
#[no_mangle]
pub extern "C" fn msime_client_punctuation(handle: u64, ascii: u8) -> *mut c_char {
    dispatch(handle, Action::Punctuation(ascii))
}

/// Resolve punctuation using the platform editor's immediately preceding
/// Unicode scalar. Zero means that no preceding scalar is available. Only the
/// scalar value crosses the host boundary; document text is never retained.
#[no_mangle]
pub extern "C" fn msime_client_punctuation_with_context(
    handle: u64,
    ascii: u8,
    preceding: u32,
) -> *mut c_char {
    if !ascii.is_ascii_punctuation() {
        return response(|| Err("invalid punctuation".into()));
    }
    let preceding = if preceding == 0 {
        None
    } else {
        match char::from_u32(preceding) {
            Some(value) => Some(value),
            None => return response(|| Err("invalid preceding character".into())),
        }
    };
    let action = SESSIONS.with(|sessions| {
        let sessions = sessions
            .try_borrow()
            .map_err(|_| "reentrant host call".to_owned())?;
        let session = sessions
            .get(&handle)
            .ok_or_else(|| "unknown session or wrong thread".to_owned())?;
        let view = session.runtime.view();
        let lock = match session.punctuation_lock_override {
            Some(1) => msime_client_core::preferences::PunctuationLock::Chinese,
            Some(2) => msime_client_core::preferences::PunctuationLock::English,
            Some(_) => msime_client_core::preferences::PunctuationLock::Follow,
            None => session.applied.punctuation_lock,
        };
        let route = punctuation_route(PunctuationContext {
            character: ascii,
            preceding,
            host_context_available: !session.english_mode
                && !view.dedicated_english
                && view.local_mode == "none"
                && view.scheme != 3,
            has_composition: !session.runtime.is_idle(),
            chinese_punctuation: session
                .punctuation_override
                .unwrap_or(session.applied.chinese_punctuation),
            smart_punctuation: session.applied.smart_punctuation,
            lock,
        });
        Ok(match route {
            PunctuationRoute::Engine => Action::Punctuation(ascii),
            PunctuationRoute::Ascii => Action::PunctuationAscii(ascii),
        })
    });
    match action {
        Ok(action) => dispatch(handle, action),
        Err(error) => response(|| Err(error)),
    }
}

/// Notify Engine that a host-emitted paired closing mark completed the opening.
#[no_mangle]
pub extern "C" fn msime_client_balance_paired_punctuation_after_auto_close(
    handle: u64,
    opening: u8,
) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            session
                .runtime
                .balance_paired_punctuation_after_auto_close(opening)
                .map_err(|e| e.to_string())?;
            serde_json::to_value(session.runtime.view()).map_err(|e| e.to_string())
        })
    })
}

/// Finish the highlighted composition and append a literal ASCII punctuation
/// mark. This is kept separate from Engine punctuation so a platform host can
/// apply its own surrounding-text policy without changing the shared table.
#[no_mangle]
pub extern "C" fn msime_client_punctuation_ascii(handle: u64, ascii: u8) -> *mut c_char {
    dispatch(handle, Action::PunctuationAscii(ascii))
}

/// Re-rank the visible candidates with the settled model, after the host's typing pause elapses.
///
/// The host owns the clock. It already runs a settle timer for cloud candidates, and it is the
/// only side that knows whether a keystroke arrived while this was being decided — the runtime
/// would have to guess. Call it when the composition has been unchanged for the pause, and not
/// while keys are still arriving.
///
/// Answers `{"moved": bool, "view": ...}`. `moved` is false when the order did not change, which
/// is the common case and the signal to leave the candidate window alone: repainting it
/// identically on every pause is a flicker with no explanation behind it.
#[no_mangle]
pub extern "C" fn msime_client_rerank_settled(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            let moved = session.runtime.rerank_settled();
            let view = session.runtime.view();
            Ok(serde_json::json!({"moved": moved, "view": view}))
        })
    })
}

#[no_mangle]
pub extern "C" fn msime_client_select(handle: u64, generation: u64, index: usize) -> *mut c_char {
    dispatch(
        handle,
        Action::Select(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

/// Select any candidate returned by `msime_client_all_candidates` for the exact
/// session generation. Regular `msime_client_select` remains page-bounded.
#[no_mangle]
pub extern "C" fn msime_client_select_any_candidate(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::SelectAnyCandidate(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_pin_candidate(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::PinCandidate(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_remove_candidate(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::RemoveCandidate(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_fix_candidate_position(
    handle: u64,
    generation: u64,
    index: usize,
    position: u8,
) -> *mut c_char {
    if !(1..=5).contains(&position) {
        return response(|| Err("candidate position must be between 1 and 5".into()));
    }
    dispatch(
        handle,
        Action::FixCandidatePosition(
            CandidateId {
                session: handle,
                generation,
                index,
            },
            position,
        ),
    )
}

#[no_mangle]
pub extern "C" fn msime_client_clear_candidate_position(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::ClearCandidatePosition(CandidateId {
            session: handle,
            generation,
            index,
        }),
    )
}

/// Select one spelling from View.nine_key_spellings for the exact view generation.
#[no_mangle]
pub extern "C" fn msime_client_choose_nine_key_spelling(
    handle: u64,
    generation: u64,
    index: usize,
) -> *mut c_char {
    dispatch(
        handle,
        Action::ChooseNineKeySpelling(NineKeySpellingId {
            session: handle,
            generation,
            index,
        }),
    )
}

/// Copy every cached Engine candidate only when a host opens an expanded panel.
#[no_mangle]
pub extern "C" fn msime_client_all_candidates(handle: u64) -> *mut c_char {
    response(|| {
        with_session(handle, |session| {
            serde_json::to_value(session.runtime.all_candidates()).map_err(|e| e.to_string())
        })
    })
}

/// Return bounded, lower-case English completions for the word immediately before the cursor.
/// This query is read-only and does not touch the Engine session's composition state.
///
/// # Safety
/// `prefix` must point to `prefix_length` readable UTF-8 bytes. The buffer is not retained.
#[no_mangle]
pub unsafe extern "C" fn msime_client_english_completions(
    handle: u64,
    prefix: *const u8,
    prefix_length: usize,
    limit: usize,
) -> *mut c_char {
    response(|| {
        if prefix.is_null() || !(1..=64).contains(&prefix_length) || !(1..=32).contains(&limit) {
            return Err("invalid English completion buffer".into());
        }
        let bytes = unsafe { std::slice::from_raw_parts(prefix, prefix_length) };
        let prefix = std::str::from_utf8(bytes).map_err(|_| "invalid English completion prefix")?;
        if !prefix.bytes().all(|value| value.is_ascii_alphabetic()) {
            return Err("invalid English completion prefix".into());
        }
        with_session(handle, |session| {
            let words = msime_engine_bridge::english_completions(
                &session.options.dictionaries,
                prefix,
                limit,
            )
            .map_err(|error| error.to_string())?;
            Ok(json!({"completions": words}))
        })
    })
}
