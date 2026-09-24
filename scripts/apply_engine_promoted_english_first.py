#!/usr/bin/env python3
"""Let a pinned or promoted English word take the first seat of the mixed candidate list.

MSIME-Windows ranks an English word against the whole candidate window it shows, Chinese candidates included: `event_listener.cpp` hands `Global::candidate_ui.items` to `adjust_english_candidate_ranking`, so a pin (置顶) or learning that reaches the top writes the maximum weight of the mixed list plus 1000. Its `NormalizeMixedCandidateOrder` (`server/src/ipc/candidate_selection_policy.h`, added in 2af10f56) then moves an EnglishDictionary candidate whose weight is the unique maximum of the list, and which has no fixed position, to index zero. `PromotedEnglishCandidateCanBecomeTheFirstMixedCandidate` pins that order.

The locked Engine does neither. `adjust_candidate_frequency` ranks English among the English words alone, so the new weight need not beat a Chinese one, and `CandidateQueries::mixed` seats the first English word after the leading Chinese candidate with no weight check. A pinned English word therefore never came first and Space committed Chinese.

This overlay ranks a mixed-input English word against the full mixed list and adds the reference's promotion rule at the end of `CandidateQueries::mixed`. Dedicated and temporary English keep ranking among their English words: the temporary list leads with the raw text as a Generated candidate, and counting it would change every learning step there. A word with a stored position is left to `apply_candidate_positions`, which reseats it afterwards, the same outcome as the reference's `fixed_position == 0` guard followed by its fixed-English reseat. The shipped dictionaries keep English weights far below Chinese ones, so nothing moves until the user pins or learns a word. The Engine test fixtures whose English weights sat above their Chinese ones are lifted so they keep describing the default order, and new cases cover the pin and the fixed-position exception.
"""

from pathlib import Path

APPLIED = "promoted English word takes the first seat"


def replace_once(path: Path, before: str, after: str) -> None:
    text = path.read_text(encoding="utf-8")
    count = text.count(before)
    if count != 1:
        raise RuntimeError(f"Engine overlay expected one match in {path}, found {count}")
    path.write_text(text.replace(before, after, 1), encoding="utf-8")


RANKING_BEFORE = """        std::vector<WordItem> ranked_candidates;
        std::copy_if(candidates().begin(), candidates().end(), std::back_inserter(ranked_candidates),
                     [](const WordItem &candidate) { return candidate.source == CandidateSource::EnglishDictionary; });
"""

RANKING_AFTER = """        // In mixed input the English word is ranked against the whole list the user sees, Chinese candidates included, as the reference does with its full candidate window. A pin or learning that reaches the top then writes a weight above every Chinese candidate, so the promoted English word takes the first seat in CandidateQueries::mixed. Dedicated and temporary English rank among their English words only; the temporary list leads with the raw text, which is not a ranking neighbour.
        const bool mixed_list = !dedicated_english_mode_ && local_input_mode_ == LocalInputMode::None;
        std::vector<WordItem> ranked_candidates;
        std::copy_if(candidates().begin(), candidates().end(), std::back_inserter(ranked_candidates),
                     [mixed_list](const WordItem &candidate) {
                         return mixed_list || candidate.source == CandidateSource::EnglishDictionary;
                     });
"""

MIXED_BEFORE = """    for (auto *source : {&english_candidates, &emoji_candidates, &kaomoji_candidates})
    {
        candidates.insert(candidates.end(), std::make_move_iterator(source->begin()),
                          std::make_move_iterator(source->end()));
    }
    return candidates;
}
"""

MIXED_AFTER = """    for (auto *source : {&english_candidates, &emoji_candidates, &kaomoji_candidates})
    {
        candidates.insert(candidates.end(), std::make_move_iterator(source->begin()),
                          std::make_move_iterator(source->end()));
    }

    // A promoted English word takes the first seat: an English candidate whose weight is the unique maximum of the mixed list moves to index zero, as the reference's NormalizeMixedCandidateOrder does. Pinning it, or learning that reaches the top, writes the list's maximum weight plus 1000, so this is how Space comes to commit it. A tie keeps the default order, and a word with a stored position is reseated by apply_candidate_positions afterwards.
    const auto promoted =
        std::max_element(candidates.begin(), candidates.end(),
                         [](const WordItem &left, const WordItem &right) { return left.weight < right.weight; });
    if (promoted != candidates.end() && promoted->source == CandidateSource::EnglishDictionary &&
        promoted->fixed_position == 0 && std::count_if(candidates.begin(), candidates.end(), [&](const WordItem &item) {
                                             return item.weight == promoted->weight;
                                         }) == 1)
    {
        std::rotate(candidates.begin(), promoted, std::next(promoted));
    }
    return candidates;
}
"""

FIXTURE_BEFORE = """    database.execute("INSERT INTO tbl_1_n VALUES('ni','n','你',200)");
    if (two_candidates)
    {
        database.execute("INSERT INTO tbl_1_n VALUES('ni','n','倪',100)");
    }
"""

# The mixed-order assertions describe the default seating, so their Chinese weights have to stay above the English ones the way the shipped dictionaries' do. Before this overlay the weights never met.
FIXTURE_AFTER = """    database.execute("INSERT INTO tbl_1_n VALUES('ni','n','你',2000)");
    if (two_candidates)
    {
        database.execute("INSERT INTO tbl_1_n VALUES('ni','n','倪',1000)");
    }
"""

EXPRESSIVE_FIXTURE_BEFORE = """                     "INSERT INTO tbl_1_n VALUES('ni','n','你',200);"
                     "INSERT INTO tbl_1_n VALUES('ni','n','倪',100);"
"""

EXPRESSIVE_FIXTURE_AFTER = """                     "INSERT INTO tbl_1_n VALUES('ni','n','你',2000);"
                     "INSERT INTO tbl_1_n VALUES('ni','n','倪',1000);"
"""

TEST_BEFORE = """    metasequoia::InputSession threshold(SchemeType::Quanpin);
    mixed_options.minimum_prefix = 3;
"""

TEST_AFTER = """    {
        // A promoted English word takes the first seat, so Space commits it: pinning ranks it against the whole mixed list, Chinese included, and the list then seats the unique maximum first. A word with a stored position keeps that position instead.
        const std::filesystem::path pinned_directory = root / "english-pinned";
        prepare_main_database(pinned_directory, true);
        {
            Database database(pinned_directory / "english.db");
            database.execute("CREATE TABLE english_words(word TEXT COLLATE BINARY NOT NULL,display TEXT NOT NULL,"
                             "weight INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(word,display)) WITHOUT ROWID");
            database.execute("CREATE TABLE en_zh_glosses(english TEXT PRIMARY KEY,chinese_gloss TEXT NOT NULL)");
            database.execute("CREATE TABLE zh_en_glosses(chinese TEXT PRIMARY KEY,english_gloss TEXT NOT NULL)");
            database.execute("INSERT INTO english_words VALUES('nimbus','Nimbus',20)");
            database.execute("INSERT INTO english_words VALUES('ninja','Ninja',10)");
        }
        set_data_directory(pinned_directory);
        metasequoia::InputSession pinned(SchemeType::Quanpin);
        require(pinned.set_english_input_options(mixed_options), "Valid mixed-English options were rejected.");
        type(pinned, "ni");
        require(pinned.candidates().size() == 4 && pinned.candidates()[0].word == "你" &&
                    pinned.candidates()[1].word == "Nimbus" && pinned.candidates()[3].word == "Ninja",
                "An unpinned English word left its default mixed seat.");
        require(pinned.pin_candidate(3).handled, "Pinning a mixed English candidate was not handled.");
        require(pinned.candidates().size() == 4 && pinned.candidates()[0].word == "Ninja" &&
                    pinned.candidates()[0].source == CandidateSource::EnglishDictionary &&
                    pinned.candidates()[1].word == "你",
                "A pinned English word did not take the first mixed seat.");
        {
            Database database(pinned_directory / "english.db");
            require(database.query_integer("SELECT weight FROM english_words WHERE word='ninja' AND "
                                           "display='Ninja'") == 3000,
                    "Pinning a mixed English word did not rank it above the Chinese candidates.");
        }
        const auto committed = pinned.select_candidate(0);
        require(committed.handled && committed.commit == "Ninja",
                "The first seat did not commit the pinned English word.");

        metasequoia::InputSession positioned(SchemeType::Quanpin);
        positioned.enable_fixed_positions();
        require(positioned.set_english_input_options(mixed_options), "Valid mixed-English options were rejected.");
        type(positioned, "ni");
        require(positioned.candidates()[0].word == "Ninja", "The pinned English word lost the first seat.");
        require(positioned.set_candidate_position(0, 3).handled, "Fixing a mixed English position was not handled.");
        require(positioned.candidates().size() == 4 && positioned.candidates()[0].word == "你" &&
                    positioned.candidates()[2].word == "Ninja",
                "An English word with a stored position took the first seat instead of its position.");
        set_data_directory(english_mode_directory);
    }

    metasequoia::InputSession threshold(SchemeType::Quanpin);
    mixed_options.minimum_prefix = 3;
"""


def apply(root: Path) -> None:
    queries = root / "core/candidate_queries.cpp"
    if APPLIED in queries.read_text(encoding="utf-8"):
        return
    replace_once(root / "core/input_session.cpp", RANKING_BEFORE, RANKING_AFTER)
    replace_once(queries, MIXED_BEFORE, MIXED_AFTER)
    tests = root / "tests/src/test_english_input_session.cpp"
    replace_once(tests, FIXTURE_BEFORE, FIXTURE_AFTER)
    replace_once(tests, TEST_BEFORE, TEST_AFTER)
    replace_once(root / "tests/src/test_mixed_expressive_input_session.cpp", EXPRESSIVE_FIXTURE_BEFORE, EXPRESSIVE_FIXTURE_AFTER)


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
