#!/usr/bin/env python3
"""Keep whole-sentence lattice edges on the exact reading the user typed.

MSIME-Windows fixed this in ``e2a5f5f9``. The locked Engine has a different
bigram/trigram scorer whose unigram edge score already supplies the rare-reading
prior, but its lattice lookup still falls back to prefix and jianpin ranges.
That lets a span such as ``gun'qi`` borrow ``gun'qiu`` rows. This overlay makes
the lookup exact, normalizes the two accepted spellings of ü before querying,
and lets a two-syllable lattice answer rank ahead of those fallback rows.
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
    query_header = root / "quanpin/quanpin_query.h"
    replace_once(
        query_header,
        "WordLatticeLookup make_lattice_db_lookup(sqlite3 *db, std::unordered_map<std::string, sqlite3_stmt *> &statement_cache,\n"
        "                                         QuerySource source, int span_limit);\n",
        "// Lattice spans must match the typed reading exactly. Prefix and jianpin fallback rows are\n"
        "// useful on the candidate page, but become mispronounced words when used as sentence edges.\n"
        "WordLatticeLookup make_lattice_db_lookup(sqlite3 *db,\n"
        "                                         std::unordered_map<std::string, sqlite3_stmt *> &statement_cache,\n"
        "                                         int span_limit);\n",
        "Lattice spans must match the typed reading exactly.",
    )

    query = root / "quanpin/quanpin_query.cpp"
    before = """WordLatticeLookup make_lattice_db_lookup(sqlite3 *db, std::unordered_map<std::string, sqlite3_stmt *> &statement_cache,
                                         QuerySource source, int span_limit)
{
    return [db, &statement_cache, source, span_limit](const Segments &span) {
        const auto rows = query_segments_keyed_flat(span, db, statement_cache, span_limit, source);
        std::vector<LatticeLexeme> lexemes;
        lexemes.reserve(rows.size());
        for (const auto &row : rows)
            lexemes.push_back({row.key, row.value, row.weight});
        return lexemes;
    };
}
"""
    after = """const std::string &canonical_lattice_syllable(const std::string &syllable)
{
    // The segmenter accepts both spellings of ü, while the dictionary stores one canonical form.
    static const std::unordered_map<std::string, std::string> spellings = {
        {"jv", "ju"},   {"qv", "qu"},   {"xv", "xu"},   {"yv", "yu"},   {"jve", "jue"},
        {"qve", "que"}, {"xve", "xue"}, {"yve", "yue"}, {"lue", "lve"}, {"nue", "nve"},
    };
    const auto found = spellings.find(syllable);
    return found == spellings.end() ? syllable : found->second;
}

WordLatticeLookup make_lattice_db_lookup(sqlite3 *db,
                                         std::unordered_map<std::string, sqlite3_stmt *> &statement_cache,
                                         int span_limit)
{
    return [db, &statement_cache, span_limit](const Segments &span) {
        Segments normalized;
        normalized.reserve(span.size());
        for (const auto &syllable : span)
            normalized.push_back(canonical_lattice_syllable(syllable));

        // query_segments_keyed_flat falls back to prefix ranges and jianpin when the exact key is
        // absent. That is correct for visible prefix candidates, but not for a sentence edge:
        // gun'qi must never borrow gun'qiu's 滚球.
        const auto rows = query_exact_segmentations_keyed_flat({normalized}, db, statement_cache, span_limit);
        std::vector<LatticeLexeme> lexemes;
        lexemes.reserve(rows.size());
        for (const auto &row : rows)
            lexemes.push_back({row.key, row.value, row.weight});
        return lexemes;
    };
}
"""
    replace_once(query, before, after, "canonical_lattice_syllable")

    lattice_header = root / "quanpin/word_lattice.h"
    replace_once(
        lattice_header,
        "// merge_lattice_candidates only runs at 3+ complete syllables. One- and\n"
        "// two-syllable keys are already covered by exact SQLite lookup. Abbreviated\n",
        "// merge_lattice_candidates runs at 2+ complete syllables. A two-syllable key can miss\n"
        "// exact SQLite lookup and otherwise leave prefix-range rows ahead of the sentence. Abbreviated\n",
        "merge_lattice_candidates runs at 2+ complete syllables.",
    )
    replace_once(
        lattice_header,
        "size_t whole_sentence_insert_position(const std::vector<WordItem> &candidates, size_t n_syllables);\n",
        "size_t whole_sentence_insert_position(const std::vector<WordItem> &candidates, const Segments &syllables);\n",
        "const Segments &syllables);",
    )

    lattice = root / "quanpin/word_lattice.cpp"
    replace_once(lattice, "    if (!lookup || syllables.size() < 3)\n", "    if (!lookup || syllables.size() < 2)\n", "syllables.size() < 2")
    replace_once(
        lattice,
        "    const size_t insert_at = whole_sentence_insert_position(candidates, syllables.size());\n",
        "    const size_t insert_at = whole_sentence_insert_position(candidates, syllables);\n",
        "whole_sentence_insert_position(candidates, syllables);",
    )
    before = """size_t whole_sentence_insert_position(const std::vector<WordItem> &candidates, size_t n_syllables)
{
    size_t insert_at = 0;
    while (insert_at < candidates.size() && covers_all_syllables(candidates[insert_at], n_syllables) &&
           (candidates[insert_at].source == CandidateSource::Database ||
            candidates[insert_at].source == CandidateSource::UserDatabase))
        ++insert_at;
    return insert_at;
}
"""
    after = """size_t whole_sentence_insert_position(const std::vector<WordItem> &candidates, const Segments &syllables)
{
    if (syllables.empty())
        return 0;
    const std::string typed_key = join_span(syllables);
    const auto is_exact_full_key_hit = [&](const WordItem &item) {
        if (item.source != CandidateSource::Database && item.source != CandidateSource::UserDatabase)
            return false;
        if (!item.canonical_pinyin.empty())
            return item.canonical_pinyin == typed_key;
        return covers_all_syllables(item, syllables.size());
    };
    size_t insert_at = 0;
    while (insert_at < candidates.size() && is_exact_full_key_hit(candidates[insert_at]))
        ++insert_at;
    return insert_at;
}
"""
    replace_once(lattice, before, after, "is_exact_full_key_hit")

    tests = root / "tests/src/test_pinyin.cpp"
    before = """    {
        std::unordered_map<std::string, std::vector<LatticeLexeme>> table;
        table["nie"] = {{"nie", "捏", 8000}};
        table["zi"] = {{"zi", "子", 9000}};
        table["nie'zi"] = {{"nie'zi", "镊子", 18000}};
        std::vector<WordItem> candidates;
        candidates.emplace_back("nxzi", "镊子", 18000, CandidateSource::Database, "nie'zi");
        quanpin::merge_lattice_candidates(candidates, {"nie", "zi"}, make_table_lattice_lookup(table), "nxzi");
        expect(candidates.size() == 1 && candidates.front().source == CandidateSource::Database,
               "Two-syllable merge is a no-op; exact SQLite already covers the key.");
    }
"""
    after = """    {
        std::unordered_map<std::string, std::vector<LatticeLexeme>> table;
        table["nie"] = {{"nie", "捏", 8000}};
        table["zi"] = {{"zi", "子", 9000}};
        table["nie'zi"] = {{"nie'zi", "镊子", 18000}};
        std::vector<WordItem> candidates;
        candidates.emplace_back("nxzi", "捏子", 12000, CandidateSource::Database, "nie'zi");
        quanpin::merge_lattice_candidates(candidates, {"nie", "zi"}, make_table_lattice_lookup(table), "nxzi");
        expect(candidates.front().word == "捏子" && candidates.front().source == CandidateSource::Database,
               "An exact two-syllable dictionary row must stay ahead of a generated sentence.");
        expect(find_candidate(candidates, "镊子") != nullptr,
               "A two-syllable lattice sentence should be offered when it differs from the exact row.");
    }

    {
        // A prefix-range row with the same character count is not an exact hit. It must not pin a
        // correctly pronounced generated sentence behind gun'qiu's 滚球 for typed gun'qi.
        std::unordered_map<std::string, std::vector<LatticeLexeme>> table;
        table["gun"] = {{"gun", "滚", 10000}};
        table["qi"] = {{"qi", "起", 9000}};
        std::vector<WordItem> candidates;
        candidates.emplace_back("gunqi", "滚球", 30000, CandidateSource::Database, "gun'qiu");
        quanpin::merge_lattice_candidates(candidates, {"gun", "qi"}, make_table_lattice_lookup(table), "gunqi");
        expect(candidates.front().word == "滚起" && candidates.front().source == CandidateSource::Generated,
               "A prefix-range row must not outrank the exact-reading lattice sentence.");
    }

    {
        // The real DB lookup must never return prefix rows to the lattice, and must canonicalize
        // the alternative ü spellings before doing the exact lookup.
        sqlite3 *db = nullptr;
        expect(sqlite3_open(":memory:", &db) == SQLITE_OK, "Failed to open the lattice lookup fixture.");
        sqlite3_exec(db, "CREATE TABLE tbl_2_g (key TEXT, value TEXT, weight INTEGER);", nullptr, nullptr, nullptr);
        sqlite3_exec(db, "CREATE TABLE tbl_1_j (key TEXT, value TEXT, weight INTEGER);", nullptr, nullptr, nullptr);
        sqlite3_exec(db, "CREATE TABLE tbl_1_l (key TEXT, value TEXT, weight INTEGER);", nullptr, nullptr, nullptr);
        sqlite3_exec(db, "INSERT INTO tbl_2_g VALUES ('gun''qiu', '滚球', 30000), ('gun''qi', '滚起', 12000);",
                     nullptr, nullptr, nullptr);
        sqlite3_exec(db, "INSERT INTO tbl_1_j VALUES ('ju', '居', 10000);", nullptr, nullptr, nullptr);
        sqlite3_exec(db, "INSERT INTO tbl_1_l VALUES ('lve', '略', 10000);", nullptr, nullptr, nullptr);
        std::unordered_map<std::string, sqlite3_stmt *> statements;
        const auto lookup = quanpin::make_lattice_db_lookup(db, statements, 32);
        const auto gun_qi = lookup({"gun", "qi"});
        expect(gun_qi.size() == 1 && gun_qi.front().key == "gun'qi" && gun_qi.front().value == "滚起",
               "The lattice lookup admitted a non-exact prefix row.");
        expect(!lookup({"jv"}).empty() && !lookup({"lue"}).empty(),
               "The exact lattice lookup did not canonicalize accepted ü spellings.");
        for (auto &[sql, statement] : statements)
        {
            (void)sql;
            sqlite3_finalize(statement);
        }
        sqlite3_close(db);
    }
"""
    replace_once(tests, before, after, "The lattice lookup admitted a non-exact prefix row.")

    quanpin_dictionary = root / "quanpin/quanpin_dictionary.cpp"
    text = quanpin_dictionary.read_text(encoding="utf-8")
    text = text.replace("segments.size() >= 3 && quanpin::has_only_complete_pinyin_segments(segments)",
                        "segments.size() >= 2 && quanpin::has_only_complete_pinyin_segments(segments)")
    text = text.replace("quanpin::whole_sentence_insert_position(result, segments.size())",
                        "quanpin::whole_sentence_insert_position(result, segments)")
    text = text.replace(
        "quanpin::make_lattice_db_lookup(db_, statement_cache_, quanpin::QuerySource::Quanpin,\n"
        "                                            lattice_options.span_limit)",
        "quanpin::make_lattice_db_lookup(db_, statement_cache_, lattice_options.span_limit)",
    )
    if "segments.size() >= 2 && quanpin::has_only_complete_pinyin_segments(segments)" not in text or \
            "make_lattice_db_lookup(db_, statement_cache_, lattice_options.span_limit)" not in text:
        raise RuntimeError("Engine overlay did not update quanpin sentence calls")
    quanpin_dictionary.write_text(text, encoding="utf-8")

    shuangpin_dictionary = root / "shuangpin/shuangpin_dictionary.cpp"
    text = shuangpin_dictionary.read_text(encoding="utf-8")
    text = text.replace("quanpin_segments.size() >= 3 &&", "quanpin_segments.size() >= 2 &&")
    text = text.replace("quanpin::whole_sentence_insert_position(candidate_list, quanpin_segments.size())",
                        "quanpin::whole_sentence_insert_position(candidate_list, quanpin_segments)")
    text = text.replace(
        "quanpin::make_lattice_db_lookup(quanpin_db_, quanpin_statement_cache_,\n"
        "                                                                          quanpin::QuerySource::Shuangpin,\n"
        "                                                                          lattice_options.span_limit)",
        "quanpin::make_lattice_db_lookup(quanpin_db_, quanpin_statement_cache_,\n"
        "                                                                          lattice_options.span_limit)",
    )
    if "quanpin_segments.size() >= 2" not in text or \
            "make_lattice_db_lookup(quanpin_db_, quanpin_statement_cache_,\n" \
            "                                                                          lattice_options.span_limit)" not in text:
        raise RuntimeError("Engine overlay did not update shuangpin sentence calls")
    shuangpin_dictionary.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
