#!/usr/bin/env python3
"""Apply the Windows-source double-helpcode cache isolation to the locked Engine."""
from pathlib import Path


def replace_once(path: Path, before: str, after: str) -> None:
    """Patch the one place this text appears, and refuse if it appears anywhere else.

    The count is checked rather than assumed. Replacing the first of several identical matches is
    how this overlay quietly half-applied for as long as the Engine archive carried two copies of
    the same call: the anchor was found, nothing raised, and the second copy went on compiling
    against a defaulted argument. A run that finds a number it did not expect should stop.
    """
    text = path.read_text(encoding="utf-8")
    if after in text and before not in text:
        return
    found = text.count(before)
    if found != 1:
        raise RuntimeError(
            f"Engine overlay expected one match in {path}, found {found}; "
            f"use replace_every if the Engine now has more than one"
        )
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


def replace_every(path: Path, before: str, after: str) -> None:
    """Patch every place this text appears, for a call the Engine makes from more than one path."""
    text = path.read_text(encoding="utf-8")
    if before not in text:
        if after in text:
            return
        raise RuntimeError(f"Engine overlay did not match: {path}")
    path.write_text(text.replace(before, after), encoding="utf-8")


def apply(root: Path) -> None:
    provider = root / "providers/pinyin_candidate_provider.cpp"
    # Both single-word paths, not just the first. The Engine reaches this call from two places and
    # they have to cache the same thing; leaving one on the three-argument form still compiles,
    # because the fourth parameter defaults, so the word is simply cached without its helpcodes.
    replace_every(
        provider,
        "return shuangpin_engine_.insert_word_to_active_helpcode_cache(request.raw_input, word, source);",
        "return shuangpin_engine_.insert_word_to_active_helpcode_cache(\n"
        "            request.raw_input, word, source,\n"
        "            ShuangpinUtil::GetFullHelpCodes(pure_input_with_cases));",
    )

    engine_h = root / "shuangpin/engine.h"
    replace_once(
        engine_h,
        "int insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                             CandidateSource source);",
        "int insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                             CandidateSource source,\n"
        "                                             const std::string &double_helpcodes = {});",
    )
    engine_cpp = root / "shuangpin/engine.cpp"
    replace_once(
        engine_cpp,
        "int ShuangpinEngine::insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                                          CandidateSource source)\n{\n"
        "    return dictionary_.insert_word_to_active_helpcode_cache(pinyin, word, source);",
        "int ShuangpinEngine::insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                                          CandidateSource source,\n"
        "                                                          const std::string &double_helpcodes)\n{\n"
        "    return dictionary_.insert_word_to_active_helpcode_cache(pinyin, word, source, double_helpcodes);",
    )

    dictionary_h = root / "shuangpin/shuangpin_dictionary.h"
    replace_once(
        dictionary_h,
        "int insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                             CandidateSource source);",
        "int insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                             CandidateSource source,\n"
        "                                             const std::string &double_helpcodes = {});",
    )
    replace_once(
        dictionary_h,
        "int insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::vector<std::string> &words,\n"
        "                                             CandidateSource source);",
        "int insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::vector<std::string> &words,\n"
        "                                             CandidateSource source,\n"
        "                                             const std::string &double_helpcodes = {});",
    )
    dictionary_cpp = root / "shuangpin/shuangpin_dictionary.cpp"
    replace_once(
        dictionary_cpp,
        "namespace\n{\nstd::string remove_delimiters",
        "namespace\n{\nstd::string double_helpcode_cache_key(const std::string &pinyin,\n"
        "                                     const std::string &help_codes)\n{\n"
        "    return pinyin + \":\" + help_codes;\n}\n\n"
        "std::string remove_delimiters",
    )
    replace_once(
        dictionary_cpp,
        "if (_cached_buffer_dbl.contains(pinyin_sequence))\n        {\n"
        "            reset_cache_if_database_changed();\n"
        "            if (const auto cached = _cached_buffer_dbl.get(pinyin_sequence))",
        "const auto cache_key = double_helpcode_cache_key(pinyin_sequence, help_codes);\n"
        "        if (_cached_buffer_dbl.contains(cache_key))\n        {\n"
        "            reset_cache_if_database_changed();\n"
        "            if (const auto cached = _cached_buffer_dbl.get(cache_key))",
    )
    replace_once(
        dictionary_cpp,
        "_cached_buffer_dbl.insert(pinyin_sequence, result_list);",
        "_cached_buffer_dbl.insert(double_helpcode_cache_key(pinyin_sequence, help_codes), result_list);",
    )
    replace_once(
        dictionary_cpp,
        "int ShuangpinDictionary::insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                                              CandidateSource source)\n{\n"
        "    if (source == CandidateSource::AiSuggestion || source == CandidateSource::CloudSuggestion)\n"
        "        return insert_word_to_active_helpcode_cache(pinyin, std::vector<std::string>{word}, source);\n"
        "    auto insert_into_cache = [&](auto &cache) {\n"
        "        if (auto opt = cache.get(pinyin))",
        "int ShuangpinDictionary::insert_word_to_active_helpcode_cache(const std::string &pinyin, const std::string &word,\n"
        "                                                              CandidateSource source,\n"
        "                                                              const std::string &double_helpcodes)\n{\n"
        "    if (source == CandidateSource::AiSuggestion || source == CandidateSource::CloudSuggestion)\n"
        "        return insert_word_to_active_helpcode_cache(pinyin, std::vector<std::string>{word}, source, double_helpcodes);\n"
        "    const auto cache_key = double_helpcodes.empty() ? pinyin : double_helpcode_cache_key(pinyin, double_helpcodes);\n"
        "    auto insert_into_cache = [&](auto &cache) {\n"
        "        if (auto opt = cache.get(cache_key))",
    )
    # Both lookup paths cache under the same key, for the same reason the provider patches both.
    replace_every(dictionary_cpp, "cache.insert(pinyin, list);\n            return true;", "cache.insert(cache_key, list);\n            return true;")
    replace_once(
        dictionary_cpp,
        "    const bool updated_single = insert_into_cache(_cached_buffer_sgl);\n"
        "    const bool updated_reversed_single = insert_into_cache(_cached_buffer_sgl_reversed);\n"
        "    const bool updated_double = insert_into_cache(_cached_buffer_dbl);\n"
        "    return updated_single || updated_reversed_single || updated_double ? 0 : -1;",
        "    if (!double_helpcodes.empty())\n"
        "        return insert_into_cache(_cached_buffer_dbl) ? 0 : -1;\n"
        "    const bool updated_single = insert_into_cache(_cached_buffer_sgl);\n"
        "    const bool updated_reversed_single = insert_into_cache(_cached_buffer_sgl_reversed);\n"
        "    return updated_single || updated_reversed_single ? 0 : -1;",
    )
    replace_once(
        dictionary_cpp,
        "int ShuangpinDictionary::insert_word_to_active_helpcode_cache(const std::string &pinyin,\n"
        "                                                              const std::vector<std::string> &words,\n"
        "                                                              CandidateSource source)\n{\n"
        "    auto insert_into_cache = [&](auto &cache) {\n"
        "        if (auto cached = cache.get(pinyin))",
        "int ShuangpinDictionary::insert_word_to_active_helpcode_cache(const std::string &pinyin,\n"
        "                                                              const std::vector<std::string> &words,\n"
        "                                                              CandidateSource source,\n"
        "                                                              const std::string &double_helpcodes)\n{\n"
        "    const auto cache_key = double_helpcodes.empty() ? pinyin : double_helpcode_cache_key(pinyin, double_helpcodes);\n"
        "    auto insert_into_cache = [&](auto &cache) {\n"
        "        if (auto cached = cache.get(cache_key))",
    )
    replace_once(dictionary_cpp, "cache.insert(pinyin, list);\n            return true;", "cache.insert(cache_key, list);\n            return true;")
    replace_once(
        dictionary_cpp,
        "    const bool single = insert_into_cache(_cached_buffer_sgl);\n"
        "    const bool reversed = insert_into_cache(_cached_buffer_sgl_reversed);\n"
        "    const bool double_code = insert_into_cache(_cached_buffer_dbl);",
        "    if (!double_helpcodes.empty())\n"
        "        return insert_into_cache(_cached_buffer_dbl) ? 0 : -1;\n"
        "    const bool single = insert_into_cache(_cached_buffer_sgl);\n"
        "    const bool reversed = insert_into_cache(_cached_buffer_sgl_reversed);",
    )
    replace_once(
        dictionary_cpp,
        "    return single || reversed || double_code ? 0 : -1;",
        "    return single || reversed ? 0 : -1;",
    )


if __name__ == "__main__":
    apply(Path(__file__).resolve().parents[1] / "vendor/MSIME-Engine")
