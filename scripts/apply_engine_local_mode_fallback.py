#!/usr/bin/env python3
"""Show an incomplete or unmatched special-mode input as a raw-text Fallback candidate, as the reference does.

The reference's `PrepareCandidateList` (MSIME-Windows `server/src/ipc/event_listener.cpp`, the special-mode branch and the `items.empty()` check right after it) leaves the list empty for a K/U/T/E/M/J/Y prefix that is not yet a complete input ("K", "U+", "Txin", a bare "Y"), and R mode's romaji session can come back empty too. Whenever the list is empty outside English mode it then adds `items.emplace_back(pinyin, pinyin, 1, CandidateSource::Fallback)`, where `pinyin` is the visible composition including the prefix letter. The candidate window therefore always shows the raw text, and Space takes the ordinary selection path and commits it: the README's local-mode table says the same of Y mode ("空格上屏当前输入").

The locked Engine instead leaves `local_candidates_` empty in all of those states, so a host has no candidate window to show, and `commit` deliberately drops a bare Y/R prefix. This overlay adds one private helper that appends the same Fallback row when the local list is empty and the preedit is not, and calls it wherever the local list is rebuilt: the eight Shift entries, `update_local_candidates` (after fixed positions, so the synthetic row is never repositioned), and the three places temporary Japanese copies the romaji session's candidates. `reset_composition` is left alone. `commit(0)` then selects the Fallback like any other row, so a bare Y/R commits "Y"/"R" on Space, with punctuation, or when a host flushes the composition, exactly as the reference's composition text would; Enter (CommitRaw) still strips the Y/R prefix. Learning and pinning already ignore a local-mode Fallback row, so nothing reaches the user dictionary.

The Engine's own tests that pinned the empty list and the dropped bare prefix are rewritten to the reference behaviour, and new cases cover R, an unmatched "Txin", and a completed "Yhe" that must not gain an extra row.
"""
from pathlib import Path

HELPER_MARKER = "void add_local_fallback_candidate();"


def replace_once(path: Path, before: str, after: str, applied: str) -> None:
    text = path.read_text(encoding="utf-8")
    if applied in text:
        return
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"Engine overlay expected one match in {path}, found {count}")
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


def apply(root: Path) -> None:
    header = root / "core/input_session.h"
    replace_once(
        header,
        "    std::optional<std::string> update_local_candidates();\n",
        "    std::optional<std::string> update_local_candidates();\n"
        "    // Adds the visible preedit as a Fallback row when a local mode has nothing else to show, like the reference's PrepareCandidateList.\n"
        "    " + HELPER_MARKER + "\n",
        HELPER_MARKER,
    )

    session = root / "core/input_session.cpp"
    for prefix in "UTKEMJYR":
        before = f'        local_preedit_ = "{prefix}";\n        local_candidates_.clear();\n'
        after = before + "        add_local_fallback_candidate();\n"
        replace_once(session, before, after, after)

    replace_once(
        session,
        '                local_preedit_ = "R" + engine_.get_preedit();\n                local_candidates_ = engine_.get_candidates();\n',
        '                local_preedit_ = "R" + engine_.get_preedit();\n                local_candidates_ = engine_.get_candidates();\n'
        "                add_local_fallback_candidate();\n",
        "                local_candidates_ = engine_.get_candidates();\n                add_local_fallback_candidate();\n",
    )
    replace_once(
        session,
        '        engine_.handle_key(key_code, 0, static_cast<ImeCharacter>(unsigned_character));\n'
        '        local_preedit_ = "R" + engine_.get_preedit();\n        local_candidates_ = engine_.get_candidates();\n',
        '        engine_.handle_key(key_code, 0, static_cast<ImeCharacter>(unsigned_character));\n'
        '        local_preedit_ = "R" + engine_.get_preedit();\n        local_candidates_ = engine_.get_candidates();\n'
        "        add_local_fallback_candidate();\n",
        "        local_candidates_ = engine_.get_candidates();\n        add_local_fallback_candidate();\n        return",
    )
    replace_once(
        session,
        """    local_candidates_ = std::move(result.candidates);
    apply_candidate_positions(local_candidates_);
    return std::move(result.diagnostic);
}
""",
        """    local_candidates_ = std::move(result.candidates);
    apply_candidate_positions(local_candidates_);
    add_local_fallback_candidate();
    return std::move(result.diagnostic);
}

void InputSession::add_local_fallback_candidate()
{
    // The reference shows the raw composition, prefix letter included, whenever a special mode has no candidate, and Space commits it through the ordinary selection path.
    if (local_candidates_.empty() && !local_preedit_.empty())
    {
        local_candidates_.emplace_back(local_preedit_, local_preedit_, 1, CandidateSource::Fallback);
    }
}
""",
        "void InputSession::add_local_fallback_candidate()",
    )

    editing = root / "core/input_session_editing.cpp"
    replace_once(
        editing,
        '            local_preedit_ = "R" + engine_.get_preedit();\n            local_candidates_ = engine_.get_candidates();\n',
        '            local_preedit_ = "R" + engine_.get_preedit();\n            local_candidates_ = engine_.get_candidates();\n'
        "            add_local_fallback_candidate();\n",
        "add_local_fallback_candidate();",
    )

    temporary = root / "tests/src/test_temporary_input_session.cpp"
    replace_once(
        temporary,
        """                english.preedit() == "Y" && english.candidates().empty(),
            "Shift+Y did not enter an empty temporary English composition.");
    const auto bare_english_punctuation = english.handle_punctuation(',');
    require(bare_english_punctuation.handled && bare_english_punctuation.commit == "，" &&
                english.local_input_mode() == metasequoia::LocalInputMode::None && !english.has_composition(),
            "Engine punctuation committed or retained the bare temporary-English display prefix.");
""",
        """                english.preedit() == "Y" && english.candidates().size() == 1 &&
                english.candidates()[0].word == "Y" && english.candidates()[0].source == CandidateSource::Fallback,
            "Shift+Y did not show the bare prefix as a single Fallback candidate.");
    const auto bare_english_punctuation = english.handle_punctuation(',');
    require(bare_english_punctuation.handled && bare_english_punctuation.commit == "Y，" &&
                english.local_input_mode() == metasequoia::LocalInputMode::None && !english.has_composition(),
            "Engine punctuation did not commit the bare temporary-English Fallback with the punctuation.");
""",
        "Shift+Y did not show the bare prefix as a single Fallback candidate.",
    )
    replace_once(
        temporary,
        """    require(english.preedit() == "Yhe" && english.candidates().size() == 3 && english.candidates()[0].word == "he" &&""",
        """    require(english.preedit() == "Yhe" && english.candidates().size() == 3 && english.candidates()[0].word == "he" &&
                std::none_of(english.candidates().begin(), english.candidates().end(),
                             [](const WordItem &candidate) { return candidate.source == CandidateSource::Fallback; }) &&""",
        "[](const WordItem &candidate) { return candidate.source == CandidateSource::Fallback; }) &&",
    )
    replace_once(
        temporary,
        """    require(bare_english_commit.handled && !bare_english_commit.commit.has_value() &&
                english.local_input_mode() == metasequoia::LocalInputMode::None,
            "A bare temporary-English display prefix escaped into committed text.");
""",
        """    require(bare_english_commit.handled && bare_english_commit.commit == "Y" &&
                english.local_input_mode() == metasequoia::LocalInputMode::None,
            "Space on a bare temporary-English prefix did not commit the Fallback \\"Y\\".");
""",
        "Space on a bare temporary-English prefix did not commit the Fallback",
    )
    replace_once(
        temporary,
        """                japanese.preedit() == "R" && japanese.scheme() == SchemeType::Quanpin &&
                japanese.scheme_type() == SchemeType::Quanpin,
            "Shift+R did not enter a temporary Japanese session with a visible prefix.");
    const auto bare_japanese_punctuation = japanese.handle_punctuation(',');
    require(bare_japanese_punctuation.handled && bare_japanese_punctuation.commit == "，" &&""",
        """                japanese.preedit() == "R" && japanese.scheme() == SchemeType::Quanpin &&
                japanese.scheme_type() == SchemeType::Quanpin && japanese.candidates().size() == 1 &&
                japanese.candidates()[0].word == "R" && japanese.candidates()[0].source == CandidateSource::Fallback,
            "Shift+R did not enter a temporary Japanese session showing the prefix as a Fallback candidate.");
    const auto bare_japanese_punctuation = japanese.handle_punctuation(',');
    require(bare_japanese_punctuation.handled && bare_japanese_punctuation.commit == "R，" &&""",
        "Shift+R did not enter a temporary Japanese session showing the prefix as a Fallback candidate.",
    )
    replace_once(
        temporary,
        """            "Engine punctuation committed the bare R prefix or failed to restore Quanpin.");""",
        """            "Engine punctuation did not commit the bare R Fallback with the punctuation or failed to restore Quanpin.");""",
        "Engine punctuation did not commit the bare R Fallback",
    )
    replace_once(
        temporary,
        """    require(japanese.preedit() == "Rka" && contains(japanese.candidates(), "か"),""",
        """    require(japanese.preedit() == "Rka" && contains(japanese.candidates(), "か") &&
                std::none_of(japanese.candidates().begin(), japanese.candidates().end(),
                             [](const WordItem &candidate) { return candidate.source == CandidateSource::Fallback; }),""",
        """contains(japanese.candidates(), "か") &&
                std::none_of""",
    )
    replace_once(
        temporary,
        """    require(bare_japanese_commit.handled && !bare_japanese_commit.commit.has_value() &&
                japanese.local_input_mode() == metasequoia::LocalInputMode::None &&
                japanese.scheme() == SchemeType::Quanpin,
            "A bare temporary-Japanese display prefix escaped into committed text.");
    require(japanese.handle_character('R', true).handled, "Temporary Japanese could not start for a flush.");
    const auto empty_flush = japanese.finish_composition();
    require(empty_flush.handled && !empty_flush.commit.has_value() && !japanese.has_composition(),
            "Flushing a bare local-mode prefix produced a spurious client insertion.");
""",
        """    require(bare_japanese_commit.handled && bare_japanese_commit.commit == "R" &&
                japanese.local_input_mode() == metasequoia::LocalInputMode::None &&
                japanese.scheme() == SchemeType::Quanpin,
            "Space on a bare temporary-Japanese prefix did not commit the Fallback \\"R\\".");
    require(japanese.handle_character('R', true).handled, "Temporary Japanese could not start for a flush.");
    const auto bare_flush = japanese.finish_composition();
    require(bare_flush.handled && bare_flush.commit == "R" && !japanese.has_composition() &&
                japanese.scheme() == SchemeType::Quanpin,
            "Flushing a bare temporary-Japanese prefix did not keep the visible composition text.");
    require(japanese.handle_character('R', true).handled &&
                japanese.handle_character('k').handled && japanese.handle_command(metasequoia::Command::Backspace).handled &&
                japanese.preedit() == "R" && japanese.candidates().size() == 1 &&
                japanese.candidates()[0].word == "R" && japanese.candidates()[0].source == CandidateSource::Fallback,
            "Backspace back to the bare R prefix did not restore its Fallback candidate.");
    require(japanese.handle_command(metasequoia::Command::Cancel).handled &&
                japanese.local_input_mode() == metasequoia::LocalInputMode::None,
            "Cancel did not leave temporary Japanese after the Backspace check.");
""",
        "Backspace back to the bare R prefix did not restore its Fallback candidate.",
    )
    replace_once(
        temporary,
        """    metasequoia::LocalModeOptions disabled_options;
""",
        """    metasequoia::InputSession unmatched(SchemeType::Quanpin);
    require(unmatched.handle_character('T', true).handled, "Shift+T did not enter date-time mode.");
    require(unmatched.candidates().size() == 1 && unmatched.candidates()[0].word == "T" &&
                unmatched.candidates()[0].source == CandidateSource::Fallback,
            "A bare date-time prefix did not show a Fallback candidate.");
    type(unmatched, "xin");
    require(unmatched.preedit() == "Txin" && unmatched.candidates().size() == 1 &&
                unmatched.candidates()[0].word == "Txin" && unmatched.candidates()[0].pinyin == "Txin" &&
                unmatched.candidates()[0].source == CandidateSource::Fallback,
            "An unmatched date-time input did not show the raw text as a Fallback candidate.");
    const auto unmatched_commit = unmatched.handle_command(metasequoia::Command::CommitCandidate);
    require(unmatched_commit.handled && unmatched_commit.commit == "Txin" && !unmatched.has_composition() &&
                unmatched.local_input_mode() == metasequoia::LocalInputMode::None,
            "Space did not commit the unmatched date-time Fallback candidate.");

    metasequoia::LocalModeOptions disabled_options;
""",
        "An unmatched date-time input did not show the raw text as a Fallback candidate.",
    )

    session_tests = root / "tests/src/test_input_session.cpp"
    replace_once(
        session_tests,
        """void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}
""",
        """void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

// A local mode with nothing to offer shows only the raw composition as a Fallback row, like the reference.
bool shows_only_fallback(const metasequoia::InputSession &session)
{
    return session.candidates().size() == 1 && session.candidates()[0].word == session.preedit() &&
           session.candidates()[0].source == CandidateSource::Fallback;
}
""",
        "bool shows_only_fallback(const metasequoia::InputSession &session)",
    )
    text = session_tests.read_text(encoding="utf-8")
    if "shows_only_fallback(unicode_session)" not in text:
        for name, expected in (
            ("unicode_session", 3),
            ("date_time_session", 2),
            ("quick_phrase_session", 1),
            ("missing_quick_phrase", 1),
            ("corrupt_quick_phrase", 1),
            # The longer name first, since it contains the shorter one.
            ("missing_emoji_session", 1),
            ("emoji_session", 1),
        ):
            before = f"{name}.candidates().empty()"
            count = text.count(before)
            if count != expected:
                raise RuntimeError(f"Engine overlay expected {expected} '{before}' in {session_tests}, found {count}")
            text = text.replace(before, f"shows_only_fallback({name})")
        for mode in ("Unicode", "date/time", "quick-phrase", "Emoji"):
            before = f"did not enter an empty {mode} composition."
            if text.count(before) != 1:
                raise RuntimeError(f"Engine overlay expected one '{before}' in {session_tests}")
            text = text.replace(before, f"did not enter a {mode} composition showing only the raw prefix.")
        for before, after in (
            ("Unicode mode produced an invalid scalar candidate.", "Unicode mode offered more than the raw text for an invalid scalar."),
            ("An incomplete date keyword produced candidates.", "An incomplete date keyword offered more than the raw text."),
        ):
            if text.count(before) != 1:
                raise RuntimeError(f"Engine overlay expected one '{before}' in {session_tests}")
            text = text.replace(before, after)
        session_tests.write_text(text, encoding="utf-8")

    jianpin = root / "tests/src/test_jianpin_input_session.cpp"
    replace_once(
        jianpin,
        """                session.candidates().empty(),
            "Shift+J did not enter an empty super-jianpin composition.");
""",
        """                session.candidates().size() == 1 && session.candidates()[0].word == "J" &&
                session.candidates()[0].source == CandidateSource::Fallback,
            "Shift+J did not show the bare prefix as a single Fallback candidate.");
""",
        "Shift+J did not show the bare prefix as a single Fallback candidate.",
    )


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
