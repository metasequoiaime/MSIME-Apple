#!/usr/bin/env python3
"""Translate canonical ü spellings at Google decoder and cloud-query boundaries.

The dictionary and lattice canonicalize l/n ü syllables as ``lve``/``nve`` and
j/q/x/y as ``ju``/``jue``. googlepinyinime-rev and the InputTools endpoint use
``lue``/``nue`` and u after j/q/x/y instead. Keep canonical readings unchanged
inside the Engine and rewrite only the strings crossing those two boundaries.
This ports MSIME-Windows ``ccbaa3a6`` to the locked shared Engine.
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
    utils_header = root / "quanpin/quanpin_utils.h"
    replace_once(
        utils_header,
        "bool is_complete_pinyin_input(const std::string &pinyin);\n",
        "bool is_complete_pinyin_input(const std::string &pinyin);\n"
        "// Translate canonical ü syllables to the spelling accepted by Google-Pinyin and InputTools.\n"
        "// Use this only at decoder/query boundaries; dictionary and lattice keys stay canonical.\n"
        "std::string to_google_spelling(const std::string &segmentation);\n",
        "std::string to_google_spelling",
    )

    utils = root / "quanpin/quanpin_utils.cpp"
    before = """size_t detect_active_helpcode_length(const std::string &raw_input, const std::string &raw_input_with_cases)
"""
    after = """std::string to_google_spelling(const std::string &segmentation)
{
    static const std::unordered_map<std::string, std::string> spellings = {
        {"jv", "ju"},   {"qv", "qu"},   {"xv", "xu"},   {"yv", "yu"},   {"jve", "jue"},
        {"qve", "que"}, {"xve", "xue"}, {"yve", "yue"}, {"lve", "lue"}, {"nve", "nue"},
    };
    std::string result;
    result.reserve(segmentation.size());
    size_t chunk_start = 0;
    while (true)
    {
        const size_t separator = segmentation.find('\\'', chunk_start);
        const size_t chunk_end = separator == std::string::npos ? segmentation.size() : separator;
        const std::string chunk = segmentation.substr(chunk_start, chunk_end - chunk_start);
        const auto found = spellings.find(chunk);
        result += found == spellings.end() ? chunk : found->second;
        if (separator == std::string::npos)
            break;
        result += '\\'';
        chunk_start = separator + 1;
    }
    return result;
}

size_t detect_active_helpcode_length(const std::string &raw_input, const std::string &raw_input_with_cases)
"""
    replace_once(utils, before, after, "std::string to_google_spelling(const std::string &segmentation)")

    composition = root / "core/input_session_composition.cpp"
    replace_once(
        composition,
        "            state.query_text = shuangpin::normalize_input_with_delimiters(state.cache_key, shuangpin_profile_);\n",
        "            const std::string quanpin_segmentation =\n"
        "                shuangpin::normalize_input_with_delimiters(state.cache_key, shuangpin_profile_);\n"
        "            state.query_text = quanpin::to_google_spelling(quanpin_segmentation);\n",
        "state.query_text = quanpin::to_google_spelling(quanpin_segmentation);",
    )
    replace_once(
        composition,
        "    state.query_text = request().normalized_input;\n",
        "    state.query_text = quanpin::to_google_spelling(request().normalized_input);\n",
        "to_google_spelling(request().normalized_input)",
    )

    quanpin_dictionary = root / "quanpin/quanpin_dictionary.cpp"
    replace_once(
        quanpin_dictionary,
        "        const std::string normalized = remove_delimiters(segmentation.empty() ? raw_input : segmentation);\n"
        "        const std::string google_sentence = search_sentence_from_ime_engine(normalized);\n",
        "        // A manual apostrophe is explicit segmentation and must reach the decoder unchanged\n"
        "        // (nu'e is not nue). Automatic cuts may be flattened after rewriting each syllable.\n"
        "        const std::string google_input =\n"
        "            raw_input.find('\\'') != std::string::npos\n"
        "                ? quanpin::to_google_spelling(raw_input)\n"
        "                : remove_delimiters(quanpin::to_google_spelling(segmentation.empty() ? raw_input : segmentation));\n"
        "        const std::string google_sentence = search_sentence_from_ime_engine(google_input);\n",
        "const std::string google_input",
    )

    shuangpin_dictionary = root / "shuangpin/shuangpin_dictionary.cpp"
    text = shuangpin_dictionary.read_text(encoding="utf-8")
    old = "search_sentence_from_ime_engine(quanpin_str)"
    new = "search_sentence_from_ime_engine(quanpin::to_google_spelling(quanpin_str))"
    if new not in text:
        if text.count(old) != 1:
            raise RuntimeError(f"Engine overlay expected one shuangpin sparse decoder call, found {text.count(old)}")
        text = text.replace(old, new, 1)
    old = "search_sentence_from_ime_engine(quanpin_segmentation)"
    new = "search_sentence_from_ime_engine(quanpin::to_google_spelling(quanpin_segmentation))"
    if new not in text:
        if text.count(old) != 1:
            raise RuntimeError(f"Engine overlay expected one shuangpin sentence decoder call, found {text.count(old)}")
        text = text.replace(old, new, 1)
    shuangpin_dictionary.write_text(text, encoding="utf-8")

    tests = root / "tests/src/test_input_session.cpp"
    before = """        metasequoia::InputSession shuangpin_session(SchemeType::Shuangpin);
        require(shuangpin_session.scheme_type() == SchemeType::Shuangpin,
                "The requested double-pinyin scheme was not retained.");
        require(shuangpin_session.handle_character('n').handled && shuangpin_session.preedit() == "n",
                "A valid Shuangpin letter was rejected.");
"""
    after = """        metasequoia::InputSession shuangpin_session(SchemeType::Shuangpin);
        require(shuangpin_session.scheme_type() == SchemeType::Shuangpin,
                "The requested double-pinyin scheme was not retained.");
        require(shuangpin_session.handle_character('n').handled && shuangpin_session.preedit() == "n",
                "A valid Shuangpin letter was rejected.");

        require(quanpin::to_google_spelling("nve'dai'dong'wu") == "nue'dai'dong'wu" &&
                    quanpin::to_google_spelling("wo'men'lve'de") == "wo'men'lue'de" &&
                    quanpin::to_google_spelling("jv'qve'xve'yv") == "ju'que'xue'yu" &&
                    quanpin::to_google_spelling("nv'er") == "nv'er" &&
                    quanpin::to_google_spelling("nvedaidongwu") == "nvedaidongwu",
                "Google spelling did not rewrite only complete canonical ü syllables.");
        metasequoia::InputSession shuangpin_umlaut(SchemeType::Shuangpin);
        type(shuangpin_umlaut, "ntdddswu");
        const auto umlaut_cloud = shuangpin_umlaut.get_cloud_query_state();
        require(umlaut_cloud.should_query && umlaut_cloud.query_text == "nue'dai'dong'wu" &&
                    umlaut_cloud.cache_key == "ntdddswu",
                "The Shuangpin cloud query exposed canonical nve instead of Google nue spelling.");
"""
    replace_once(tests, before, after, "Google spelling did not rewrite only complete canonical ü syllables.")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
