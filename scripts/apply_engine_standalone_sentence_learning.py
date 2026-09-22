#!/usr/bin/env python3
"""Learn a directly selected generated sentence, matching MSIME-Windows.

The Engine already learns a phrase assembled from several selections, including the case where a
Generated/Fallback sentence completes a selected prefix. It does not learn that same sentence when
the user selects it directly, nor an injected CloudSuggestion/AiSuggestion. Frequency adjustment
cannot help: those candidates have no SQLite row whose weight could be changed, so the next session
has to guess them again.

MSIME-Windows fixed the Engine path in `01c5bca3` and its separate Server online-selection path in
`663f7230` / `99a8a355`. This repository's hosts all select through the public Engine session, so
both behaviors meet here instead of being copied into IBus and Fcitx5. The seven-syllable cap,
pinyin-only guards, complete canonical-reading validation, and learning preference remain shared.
"""
from pathlib import Path


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
        "    std::optional<std::string> learn_candidate(std::size_t index);\n",
        "    std::optional<std::string> learn_candidate(std::size_t index);\n"
        "    // Generated whole sentences have no dictionary row to adjust; selecting one creates it.\n"
        "    std::optional<std::string> learn_sentence_candidate(const WordItem &selected);\n",
        "learn_sentence_candidate(const WordItem &selected)",
    )

    session = root / "core/input_session.cpp"
    before = """    const WordItem &selected = candidates()[index];
    if (!frequency_adjustment_configured_)
"""
    after = """    const WordItem &selected = candidates()[index];
    // Generated/Fallback and injected online sentences are not dictionary rows, so frequency
    // adjustment has nowhere to persist them. Store the selected sentence as a user phrase instead.
    // This applies even at index zero and is independent of the frequency-adjustment mode.
    if (selected.source == CandidateSource::Generated || selected.source == CandidateSource::Fallback ||
        selected.source == CandidateSource::CloudSuggestion || selected.source == CandidateSource::AiSuggestion)
    {
        return learn_sentence_candidate(selected);
    }
    if (!frequency_adjustment_configured_)
"""
    replace_once(session, before, after, "return learn_sentence_candidate(selected);")

    composition = root / "core/input_session_composition.cpp"
    replace_once(
        composition,
        "std::string normalize_canonical_pinyin_for_word(const std::string &pinyin, const std::string &word)\n",
        "// Match the Engine's own maximum stored phrase width. Longer generated sentences are useful\n"
        "// for this commit only and would otherwise grow the user dictionary without bound.\n"
        "constexpr size_t kMaxLearnedSentenceSyllables = 7;\n\n"
        "std::string normalize_canonical_pinyin_for_word(const std::string &pinyin, const std::string &word)\n",
        "kMaxLearnedSentenceSyllables = 7",
    )
    before = """int InputSession::pin_candidate(std::string pinyin, std::string word)
{
    return engine_.update_weight_by_pinyin_and_word(std::move(pinyin), std::move(word));
}
"""
    after = """std::optional<std::string> InputSession::learn_sentence_candidate(const WordItem &selected)
{
    // Local shortcuts and English/Japanese modes also use Generated candidates, but they are not
    // pinyin sentences and must never enter the pinyin user dictionary.
    if (local_input_mode_ != LocalInputMode::None || dedicated_english_mode_ || is_japanese() ||
        !candidates_follow_pinyin())
    {
        return std::nullopt;
    }

    // Both quanpin and shuangpin sentences carry canonical quanpin. Require a complete reading
    // with one syllable per Han character before creating the row.
    // Online cloud/AI rows are injected after the local query and therefore carry no
    // canonical_pinyin.  For a complete full-pinyin query the session's explicit segmentation is
    // the canonical key; using committed_pinyin would erase apostrophes and let correction
    // re-segment a reading such as qi'e'huan before it is stored.
    const bool online_candidate = selected.source == CandidateSource::CloudSuggestion ||
                                  selected.source == CandidateSource::AiSuggestion;
    const std::string selected_canonical =
        selected.canonical_pinyin.empty() && online_candidate && is_all_complete_pure_pinyin()
            ? get_pinyin_segmentation()
            : selected.canonical_pinyin;
    const std::string canonical = normalize_canonical_pinyin_for_word(selected_canonical, selected.word);
    if (canonical.empty() || quanpin::split_segments(canonical).size() > kMaxLearnedSentenceSyllables)
    {
        return std::nullopt;
    }
    if (store_user_phrase_from_canonical_pinyin(canonical, selected.word) != 0)
    {
        return "Unable to persist the selected sentence.";
    }
    return std::nullopt;
}

int InputSession::pin_candidate(std::string pinyin, std::string word)
{
    return engine_.update_weight_by_pinyin_and_word(std::move(pinyin), std::move(word));
}
"""
    replace_once(
        composition,
        before,
        after,
        "Unable to persist the selected sentence.",
    )

    dictionary = root / "quanpin/quanpin_dictionary.cpp"
    replace_once(
        dictionary,
        "    pinyin = quanpin::join_segments(segments);\n"
        "    const std::string jp = quanpin::segments_to_jianpin(segments);\n"
        "    if (!do_validate(pinyin, jp, word))\n"
        "    {\n"
        "        return ERROR_CODE;\n"
        "    }\n",
        "    // The caller supplied an explicit canonical segmentation. The checks above already\n"
        "    // prove one complete syllable per Han character; do_validate would erase those\n"
        "    // boundaries and greedily re-cut qi'e'huan as qie'huan, rejecting a valid phrase.\n"
        "    pinyin = quanpin::join_segments(segments);\n"
        "    const std::string jp = quanpin::segments_to_jianpin(segments);\n",
        "do_validate would erase those boundaries",
    )


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
