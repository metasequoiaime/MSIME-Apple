#!/usr/bin/env python3
"""Let an English entry's code differ from the word it types out, the way the reference's does.

The reference's English table is `english_words(word, display, weight)`: `word` is what the user
types and `display` is what goes into the document. That is how `dont` types out `don't`, and its
importer accepts any non-empty display beside a `word` of letters, hyphens and apostrophes
(`IsAsciiWord` in `server/src/settings/dictionary_manager.cpp`).

The Engine stores exactly that - `english_words` has the display column here too, and
`apply_english` writes it - but `validate_personal_dictionary_entry` refuses any English entry
whose value is not the key again, ignoring case, and refuses a key that is not letters only. The
two rules together allow `hello`/`Hello` and nothing else, so every row with an apostrophe or a
hyphen was rejected at that step.

Worth being exact about why this is an overlay rather than a lock bump, because the parity record
had it wrong: the reference's in-repo Engine carries this identical validation, character for
character. Nothing upstream has relaxed it and there is no newer Engine to move to. What differs
is which door the importer knocks on - the reference writes `english_words` directly and then
records the journal row itself, never calling the validator - and this repository routes every
personal-dictionary write through the Engine's own request/receipt path, which is what gives it
retries, conflict detection, staging into a new dictionary generation and cloud sync. Keeping that
path and widening the rule to the reference's is a smaller change than growing a second write path
beside it, and it leaves one validator rather than two disagreeing ones.

The widening only admits entries: everything valid before is still valid, so no stored dictionary
can be invalidated by it. Removing this script from `engine-lock.json` restores the narrow rule,
and entries already stored under the wide one keep working - they live in a table that always had
room for them.
"""
from pathlib import Path

BEFORE = """    case PersonalDictionaryKind::English: {
        std::string normalized = entry.value;
        for (char &ch : normalized)
            if (ch >= 'A' && ch <= 'Z')
                ch = static_cast<char>(ch - 'A' + 'a');
        if (entry.key.size() > 64 || !std::all_of(entry.key.begin(), entry.key.end(), letters) ||
            normalized != entry.key)
            return invalid("English code must match the word's letters, ignoring case");
        break;
    }
"""

AFTER = """    case PersonalDictionaryKind::English: {
        // The code is what the user types; the word is what it types out, and the two need not be
        // the same text. `dont` typing out `don't` is the case that matters, and the reference
        // accepts it: its importer asks only that the code be letters, hyphens and apostrophes and
        // that the display be non-empty, which the bounds above already require of every kind.
        auto code = [](unsigned char ch) {
            return (ch >= 'a' && ch <= 'z') || ch == '-' || ch == '\\'';
        };
        if (entry.key.size() > 64 || !std::all_of(entry.key.begin(), entry.key.end(), code))
            return invalid("English codes contain letters, hyphens and apostrophes");
        break;
    }
"""

APPLIED = "English codes contain letters, hyphens and apostrophes"


def apply(root: Path) -> None:
    path = root / "user_dictionary/personal_dictionary.cpp"
    text = path.read_text(encoding="utf-8")
    if APPLIED in text:
        return
    if BEFORE not in text:
        raise RuntimeError(f"Engine overlay did not match: {path}")
    path.write_text(text.replace(BEFORE, AFTER, 1), encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
