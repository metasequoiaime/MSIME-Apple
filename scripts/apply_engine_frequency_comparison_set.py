#!/usr/bin/env python3
"""Rank a picked candidate against everything the user can see, in weight order.

One candidate list mixes several dictionary keys: the context `y` shows 一 beside 有, a nine-key
digit mixes whole single-character tables, and a re-segmentation puts 吉安 (`ji'an`) inside the
`jian` list. 调频 means "move this above what I can see", so all of them have to share one scale.

The midpoint arithmetic that writes the new weight assumes the comparison set is sorted by weight,
descending: it brackets the target position between its neighbours' weights and splits the gap. The
*displayed* order does not satisfy that - an alternative segmentation takes a protected slot near
the top and pinned candidates sit at fixed positions, both regardless of weight - and ranking on
display order is what once wrote 写 as 506, being 西鄂's weight of 6 plus 500.

The pinned Engine's answer to that was to restrict the comparison set to keys with the same
syllable count. It keeps 西鄂 out, but it also walls every candidate into its own group: 吉安 has
weight 1 and can only ever be compared against 积案 and 几案, so its learnable weight is capped
around ten thousand and it can never pass 见 at 3460998 no matter how often the user picks it. That
is a candidate that does not move however much you choose it.

This is a port of the reference's `e32eeade`, which sorts the comparison set by weight instead. The
invariant is restored at its source - no row can sit above its own weight and act as the basis - so
the walls are unnecessary and come down. Writes still land only on `entry_key` rows, so a rebalance
cannot touch another key's row.
"""
from pathlib import Path

BEFORE = """    // Single-letter and jianpin contexts show several entry keys in one list
    // (context "y" mixes 一/yi with 有/you). Rank against the list the user
    // actually sees; ranking against only the rows sharing entry_key makes the
    // selection permanently rank 0 and no weight is ever written. Writes still
    // go to entry_key rows only, so a rebalance can never land on another key's
    // row the way it did in #36.
    const auto ranking_scale = [kind](const std::string &key) -> std::size_t {
        return kind == DictionaryKind::Wubi ? 0 : pinyin_segments(key).size();
    };
    const std::size_t entry_scale = ranking_scale(entry_key);
    std::vector<WordItem> database_candidates;
    std::vector<bool> owns_entry_key;
    for (const auto &item : ordered_candidates)
    {
        if (item.source != CandidateSource::Database && item.source != CandidateSource::UserDatabase)
            continue;
        const std::string item_key =
            kind == DictionaryKind::Wubi ? item.pinyin : candidate_dictionary_key(item, context_key);
        if (entry_scale != 0 && ranking_scale(item_key) != entry_scale)
            continue;
        database_candidates.push_back(item);
        owns_entry_key.push_back(item_key == entry_key);
    }
"""

AFTER = """    // One list mixes several entry keys: the context "y" shows 一/yi beside 有/you, a nine-key
    // digit mixes whole single-character tables, and a re-segmentation puts 吉安 (ji'an) inside
    // the jian list. All of them share one scale, because the user's 调频 means "move this above
    // what I can see".
    //
    // The midpoint arithmetic below assumes this vector is sorted by weight, descending: it
    // brackets the target position between its neighbours' weights and splits the gap. The
    // displayed order does not satisfy that - an alternative segmentation takes a protected slot
    // near the top and pinned candidates sit at fixed positions, both regardless of weight - and
    // ranking on display order is what wrote 写 as 506, being 西鄂's weight of 6 plus 500. Sorting
    // by weight fixes it at the source: no row can sit above its own weight and be the basis.
    //
    // Restricting the set to one syllable count kept 西鄂 out too, but walled every candidate into
    // its own group: 吉安 (weight 1) could only be compared against 积案 and 几案, so its learnable
    // weight was capped around ten thousand and it could never pass 见 at 3460998 however often it
    // was picked. Weight order removes the wall without bringing the bug back. Writes still go to
    // entry_key rows only, so a rebalance cannot land on another key's row the way it did in #36.
    std::vector<WordItem> database_candidates;
    for (const auto &item : ordered_candidates)
    {
        if (item.source != CandidateSource::Database && item.source != CandidateSource::UserDatabase)
            continue;
        database_candidates.push_back(item);
    }
    std::stable_sort(database_candidates.begin(), database_candidates.end(),
                     [](const WordItem &lhs, const WordItem &rhs) { return lhs.weight > rhs.weight; });
    std::vector<bool> owns_entry_key;
    owns_entry_key.reserve(database_candidates.size());
    for (const auto &item : database_candidates)
    {
        const std::string item_key =
            kind == DictionaryKind::Wubi ? item.pinyin : candidate_dictionary_key(item, context_key);
        owns_entry_key.push_back(item_key == entry_key);
    }
"""

APPLIED = "Weight order removes the wall without bringing the bug back"


def apply(root: Path) -> None:
    path = root / "user_dictionary/user_dictionary_journal.cpp"
    text = path.read_text(encoding="utf-8")
    if APPLIED in text:
        return
    if BEFORE not in text:
        raise RuntimeError(f"Engine overlay did not match: {path}")
    path.write_text(text.replace(BEFORE, AFTER, 1), encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
