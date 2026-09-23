#!/usr/bin/env python3
"""Let the dictionary manager find, re-weight and delete the words the dictionary ships with, as the reference's does.

The reference's dictionary manager (MSIME-Windows `server/src/settings/dictionary_manager.cpp`) queries `msime.db` and `english.db` directly, so every word the Engine can offer is listed, a shipped word can be given another weight or deleted, and the change is journaled with `user_dictionary::record_upsert` / `record_delete` so that it survives the replay onto a fresh dictionary after an upgrade. Its pinyin export reads every `upsert` row of the journal, learned weight changes to shipped words included, and drops single characters; the other exports stay limited to user-inserted rows.

The locked Engine only exposes the journal's user-inserted rows (`personal_dictionary_entries`) and edits nothing else (`edit_personal_dictionary` requires `user_inserted=1`). This overlay adds, without changing either existing call:

- `dictionary_table_entries`, a read-only lookup by code prefix over the pinyin tables, `wubi86`, `quick_parases` and `english_words`. The dictionary is opened read-only and the journal attached read-only, so it takes no write lock and can run while a keyboard session is open. Each row says whether it is a user-inserted word, which is what decides how it may be edited.
- `edit_bundled_dictionary_entry`, which changes the weight of, or deletes, a row that is not user-inserted. The row change and its journal row commit in one attached-database transaction, with the same request receipts and stale-entry check as `edit_personal_dictionary`. The journal row is written the way `record_upsert` / `record_delete` write it, so replay applies it with no new code: a delete that finds nothing to delete still succeeds, which keeps a deleted shipped word deleted after an upgrade.
- an `include_learned_pinyin` argument to `personal_dictionary_entries`, which additionally lists the journal's pinyin `upsert` rows that are not user-inserted and leaves out single characters, as the reference's pinyin export does.
"""
from pathlib import Path

HEADER_BEFORE = """// Lists user-inserted words (including automatically created words), excluding ranking-only
// operations and deleted entries. Stable kind/key/value ordering; limit 1..1000, offset <= 1000000.
PersonalDictionaryPage personal_dictionary_entries(const RuntimePaths &paths, std::size_t offset = 0,
                                                   std::size_t limit = 100);
"""

HEADER_AFTER = """// Lists user-inserted words (including automatically created words), excluding ranking-only
// operations and deleted entries. Stable kind/key/value ordering; limit 1..1000, offset <= 1000000.
// With include_learned_pinyin, pinyin rows whose weight was learned or edited but that are not user-inserted are listed as well, and pinyin rows of a single character are left out, as the reference's pinyin export does.
PersonalDictionaryPage personal_dictionary_entries(const RuntimePaths &paths, std::size_t offset = 0,
                                                   std::size_t limit = 100, bool include_learned_pinyin = false);
struct DictionaryTableEntry
{
    PersonalDictionaryEntry entry;
    // True for a word the user added; such a word is edited through edit_personal_dictionary. Any other row ships with the dictionary (or was learned) and only its weight can change.
    bool user_inserted = false;
};
struct DictionaryTablePage
{
    std::vector<DictionaryTableEntry> entries;
    bool has_more = false;
    std::string error;
};
// Read-only lookup of the dictionary tables by code prefix: the pinyin tables (separators and case ignored), wubi86, quick_parases (an empty query lists every phrase) and english_words. A query holding a character no code of the kind can contain matches nothing. User-inserted words come first, then exact code matches, then by weight. Limit 1..1000, offset <= 1000000, query <= 256 bytes.
DictionaryTablePage dictionary_table_entries(const RuntimePaths &paths, PersonalDictionaryKind kind,
                                             const std::string &query, std::size_t offset = 0,
                                             std::size_t limit = 100);
// Sets the weight of (weight present) or deletes (weight absent) a row that is not user-inserted, and journals it the way record_upsert / record_delete do so replay repeats it on a fresh dictionary. previous must match the row's current weight; a stale or user-inserted entry is refused. Request IDs behave as for edit_personal_dictionary.
PersonalDictionaryEditResult edit_bundled_dictionary_entry(const RuntimePaths &paths,
                                                           const PersonalDictionaryEntry &previous,
                                                           const std::optional<std::int64_t> &weight,
                                                           const std::string &request_id = {});
"""

SIGNATURE_BEFORE = """PersonalDictionaryPage personal_dictionary_entries(const RuntimePaths &paths, std::size_t offset, std::size_t limit)
{"""

SIGNATURE_AFTER = """PersonalDictionaryPage personal_dictionary_entries(const RuntimePaths &paths, std::size_t offset, std::size_t limit,
                                                   bool include_learned_pinyin)
{"""

QUERY_BEFORE = """                     "SELECT dictionary,key,value,weight FROM user_dictionary_operations"
                     " WHERE user_inserted=1 AND operation='upsert' ORDER BY dictionary,key,value LIMIT ?1 OFFSET ?2")
               : Stmt{};
        if (!rows || sqlite3_bind_int64(rows.get(), 1, static_cast<sqlite3_int64>(limit + 1)) != SQLITE_OK ||
            sqlite3_bind_int64(rows.get(), 2, static_cast<sqlite3_int64>(offset)) != SQLITE_OK)"""

QUERY_AFTER = """                     "SELECT dictionary,key,value,weight FROM user_dictionary_operations"
                     " WHERE operation='upsert' AND (user_inserted=1 OR (?3 AND dictionary='pinyin'))"
                     " AND NOT (?3 AND dictionary='pinyin' AND length(value)<=1)"
                     " ORDER BY dictionary,key,value LIMIT ?1 OFFSET ?2")
               : Stmt{};
        if (!rows || sqlite3_bind_int64(rows.get(), 1, static_cast<sqlite3_int64>(limit + 1)) != SQLITE_OK ||
            sqlite3_bind_int64(rows.get(), 2, static_cast<sqlite3_int64>(offset)) != SQLITE_OK ||
            sqlite3_bind_int(rows.get(), 3, include_learned_pinyin ? 1 : 0) != SQLITE_OK)"""

TAIL_BEFORE = """        result.error = "Cannot access personal dictionary storage";
    }
    return result;
}
} // namespace metasequoia
"""

TAIL_AFTER = r"""        result.error = "Cannot access personal dictionary storage";
    }
    return result;
}
namespace
{
// The table a row of the kind lives in, or empty for a malformed pinyin key; English rows live in the attached English dictionary.
std::string bundled_table(PersonalDictionaryKind kind, const std::string &key)
{
    switch (kind)
    {
    case PersonalDictionaryKind::Pinyin:
        return user_dictionary::pinyin_table(key);
    case PersonalDictionaryKind::Wubi:
        return "wubi86";
    case PersonalDictionaryKind::QuickPhrase:
        return "quick_parases";
    case PersonalDictionaryKind::English:
        return "english_words";
    }
    return {};
}
std::string quoted_identifier(const std::string &name)
{
    return '"' + name + '"';
}
bool valid_request_id(const std::string &request_id)
{
    return request_id.size() <= 128 && std::all_of(request_id.begin(), request_id.end(), [](unsigned char ch) {
               return (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') || ch == '-' ||
                      ch == '_';
           });
}
std::string column_text(sqlite3_stmt *stmt, int index)
{
    const auto *value = sqlite3_column_text(stmt, index);
    return value ? std::string(reinterpret_cast<const char *>(value), sqlite3_column_bytes(stmt, index)) : std::string{};
}
// The query folded to the form codes of the kind are stored in, or nothing when it holds a character no such code can contain. Pinyin drops its separators so a query matches a key however it was split.
std::optional<std::string> lookup_code(PersonalDictionaryKind kind, const std::string &query)
{
    std::string code;
    for (const unsigned char raw : query)
    {
        const unsigned char ch = raw >= 'A' && raw <= 'Z' ? static_cast<unsigned char>(raw - 'A' + 'a') : raw;
        if (kind == PersonalDictionaryKind::Pinyin && (ch == '\'' || ch == ' '))
            continue;
        const bool allowed = (ch >= 'a' && ch <= 'z') ||
                             (kind == PersonalDictionaryKind::QuickPhrase && ch >= '0' && ch <= '9') ||
                             (kind == PersonalDictionaryKind::English && (ch == '\'' || ch == '-'));
        if (!allowed)
            return std::nullopt;
        code.push_back(static_cast<char>(ch));
    }
    return code;
}
} // namespace
DictionaryTablePage dictionary_table_entries(const RuntimePaths &paths, PersonalDictionaryKind kind,
                                             const std::string &query, std::size_t offset, std::size_t limit)
{
    using namespace user_dictionary;
    DictionaryTablePage result;
    if (limit == 0 || limit > 1000 || offset > 1000000 || query.size() > 256)
    {
        result.error = "Invalid dictionary lookup";
        return result;
    }
    const auto code = lookup_code(kind, query);
    if (!code || (code->empty() && kind != PersonalDictionaryKind::QuickPhrase))
        return result;
    try
    {
        paths.validate();
        const bool english = kind == PersonalDictionaryKind::English;
        const auto dictionary_path = paths.dictionary(english ? assets::english_dictionary : assets::main_dictionary);
        if (!std::filesystem::exists(dictionary_path))
            return result;
        auto db = open_database(path_to_utf8(dictionary_path), SQLITE_OPEN_READONLY);
        if (!db)
        {
            result.error = "Cannot open dictionary";
            return result;
        }
        // Attached through a read-only connection, the journal is read-only too: the lookup never takes a write lock.
        bool journal = false;
        const auto journal_path = paths.user(assets::user_journal);
        if (std::filesystem::exists(journal_path))
        {
            auto attach = prepare(db.get(), "ATTACH DATABASE ?1 AS lookup_journal");
            if (!attach || !bind_text(attach.get(), 1, path_to_utf8(journal_path)) ||
                sqlite3_step(attach.get()) != SQLITE_DONE)
            {
                result.error = "Cannot attach personal dictionary storage";
                return result;
            }
            attach.reset();
            auto table = prepare(db.get(), "SELECT 1 FROM lookup_journal.sqlite_master"
                                           " WHERE type='table' AND name='user_dictionary_operations'");
            journal = table && sqlite3_step(table.get()) == SQLITE_ROW;
        }
        std::vector<std::string> candidates;
        if (kind == PersonalDictionaryKind::Pinyin)
        {
            for (std::size_t syllables = 1; syllables <= dictionary_format::maximum_numbered_syllables + 1; ++syllables)
                candidates.push_back(dictionary_format::quanpin_table(syllables, code->front()));
        }
        else
            candidates.push_back(bundled_table(kind, *code));
        const std::string key_column = english ? "word" : "key";
        const std::string value_column = english ? "display" : "value";
        std::string match;
        std::string exact;
        switch (kind)
        {
        case PersonalDictionaryKind::Pinyin:
            match = "substr(replace(key,'''',''),1,?2)=?1";
            exact = "replace(key,'''','')=?1";
            break;
        case PersonalDictionaryKind::QuickPhrase:
            match = "substr(lower(key),1,?2)=?1";
            exact = "lower(key)=?1";
            break;
        default:
            // Wubi and English codes are stored lower-case, so the prefix is a range the primary index answers.
            match = key_column + ">=?1 AND " + key_column + "<?3";
            exact = key_column + "=?1";
            break;
        }
        std::string rows;
        auto exists = prepare(db.get(), "SELECT 1 FROM main.sqlite_master WHERE type='table' AND name=?1");
        if (!exists)
        {
            result.error = "Cannot read dictionary";
            return result;
        }
        for (const auto &table : candidates)
        {
            sqlite3_reset(exists.get());
            if (table.empty() || !bind_text(exists.get(), 1, table) || sqlite3_step(exists.get()) != SQLITE_ROW)
                continue;
            if (!rows.empty())
                rows += " UNION ALL ";
            rows += "SELECT " + key_column + " AS key," + value_column + " AS value,weight," + exact +
                    " AS exact FROM main." + quoted_identifier(table) + " WHERE " + match;
        }
        exists.reset();
        if (rows.empty())
            return result;
        std::string sql = std::string("SELECT r.key,r.value,") +
                          (journal ? "COALESCE(j.weight,r.weight)" : "r.weight") + " AS entry_weight," +
                          (journal ? "j.key IS NOT NULL" : "0") +
                          " AS user_row FROM (SELECT key,value,MAX(weight) AS weight,MAX(exact) AS exact FROM (" +
                          rows + ") GROUP BY key,value) AS r";
        if (journal)
            sql += " LEFT JOIN lookup_journal.user_dictionary_operations AS j ON j.dictionary=?4 AND j.key=r.key"
                   " AND j.value=r.value AND j.user_inserted=1 AND j.operation='upsert'";
        sql += " ORDER BY user_row DESC,r.exact DESC,entry_weight DESC,r.key,r.value LIMIT ?5 OFFSET ?6";
        std::string upper = *code;
        if (!upper.empty())
            upper.back() = static_cast<char>(upper.back() + 1);
        auto stmt = prepare(db.get(), sql);
        if (!stmt || !bind_text(stmt.get(), 1, *code) ||
            sqlite3_bind_int64(stmt.get(), 2, static_cast<sqlite3_int64>(code->size())) != SQLITE_OK ||
            !bind_text(stmt.get(), 3, upper) || !bind_text(stmt.get(), 4, kind_name(journal_kind(kind))) ||
            sqlite3_bind_int64(stmt.get(), 5, static_cast<sqlite3_int64>(limit + 1)) != SQLITE_OK ||
            sqlite3_bind_int64(stmt.get(), 6, static_cast<sqlite3_int64>(offset)) != SQLITE_OK)
        {
            result.error = "Cannot read dictionary";
            return result;
        }
        int step;
        while ((step = sqlite3_step(stmt.get())) == SQLITE_ROW)
        {
            if (result.entries.size() == limit)
            {
                result.has_more = true;
                break;
            }
            result.entries.push_back({{kind, column_text(stmt.get(), 0), column_text(stmt.get(), 1),
                                       sqlite3_column_int64(stmt.get(), 2)},
                                      sqlite3_column_int(stmt.get(), 3) != 0});
        }
        if (step != SQLITE_DONE && !result.has_more)
        {
            result.entries.clear();
            result.error = "Cannot finish reading dictionary";
        }
    }
    catch (const std::exception &)
    {
        result.entries.clear();
        result.error = "Cannot access personal dictionary storage";
    }
    return result;
}
PersonalDictionaryEditResult edit_bundled_dictionary_entry(const RuntimePaths &paths,
                                                           const PersonalDictionaryEntry &previous,
                                                           const std::optional<std::int64_t> &weight,
                                                           const std::string &request_id)
{
    using namespace user_dictionary;
    if (!valid_request_id(request_id))
        return {false, "Invalid personal dictionary request ID"};
    if (weight && (*weight < 1 || *weight > 100000000))
        return {false, "Weight is outside 1 to 100000000"};
    const std::string table = bundled_table(previous.kind, previous.key);
    if (previous.key.empty() || previous.value.empty() || previous.key.size() > 1024 || previous.value.size() > 4096 ||
        table.empty())
        return {false, "Invalid bundled dictionary entry"};
    const bool english = previous.kind == PersonalDictionaryKind::English;
    const std::string target =
        std::string(english ? "replay_english." : "main.") + quoted_identifier(table);
    const std::string row = english ? " WHERE word=?1 AND display=?2" : " WHERE key=?1 AND value=?2";
    const std::string dictionary = kind_name(journal_kind(previous.kind));
    try
    {
        paths.validate();
        const auto journal_path = path_to_utf8(paths.user(assets::user_journal));
        const auto english_path = path_to_utf8(paths.dictionary(assets::english_dictionary));
        if (!ensure_user_database(journal_path) || !EnglishDictionary::ensure_schema(english_path))
            return {false, "Cannot prepare personal dictionary storage"};
        auto db = open_database(path_to_utf8(paths.dictionary(assets::main_dictionary)), SQLITE_OPEN_READWRITE);
        if (!db)
            return {false, "Cannot open dictionary"};
        for (const auto &attachment :
             {std::make_pair("personal_journal", journal_path), std::make_pair("replay_english", english_path)})
        {
            auto attach = prepare(db.get(), std::string("ATTACH DATABASE ?1 AS ") + attachment.first);
            if (!attach || !bind_text(attach.get(), 1, attachment.second) || sqlite3_step(attach.get()) != SQLITE_DONE)
                return {false, "Cannot attach personal dictionary storage"};
        }
        if (!execute_sql(db.get(), "BEGIN IMMEDIATE"))
            return {false, "Cannot begin personal dictionary edit"};
        const auto fail = [&](const char *message) {
            execute_sql(db.get(), "ROLLBACK");
            return PersonalDictionaryEditResult{false, message};
        };
        // Prefixed so a receipt can never be mistaken for one written by edit_personal_dictionary.
        const std::string payload = "bundled;" + dictionary + ";" + std::to_string(previous.weight) + ";" +
                                    (weight ? std::to_string(*weight) : std::string("delete")) + ";" +
                                    std::to_string(previous.key.size()) + ":" + previous.key +
                                    std::to_string(previous.value.size()) + ":" + previous.value;
        if (!request_id.empty())
        {
            auto receipt = prepare(
                db.get(), "SELECT payload FROM personal_journal.personal_dictionary_receipts WHERE request_id=?1");
            if (!receipt || !bind_text(receipt.get(), 1, request_id))
                return fail("Cannot read edit receipt");
            const int step = sqlite3_step(receipt.get());
            if (step == SQLITE_ROW)
            {
                const auto *stored = sqlite3_column_text(receipt.get(), 0);
                const bool same = stored && payload == reinterpret_cast<const char *>(stored);
                receipt.reset();
                if (!same)
                    return fail("Request ID was already used for another edit");
                if (!execute_sql(db.get(), "COMMIT"))
                    return fail("Cannot finish edit retry");
                return {true, {}};
            }
            if (step != SQLITE_DONE)
                return fail("Cannot finish reading edit receipt");
        }
        auto user_row = prepare(db.get(), "SELECT 1 FROM personal_journal.user_dictionary_operations"
                                          " WHERE dictionary=?1 AND key=?2 AND value=?3 AND user_inserted=1"
                                          " AND operation='upsert'");
        if (!user_row || !bind_text(user_row.get(), 1, dictionary) || !bind_text(user_row.get(), 2, previous.key) ||
            !bind_text(user_row.get(), 3, previous.value))
            return fail("Cannot read personal dictionary");
        const int user_step = sqlite3_step(user_row.get());
        user_row.reset();
        if (user_step == SQLITE_ROW)
            return fail("The entry is a user entry; edit it as one");
        if (user_step != SQLITE_DONE)
            return fail("Cannot read personal dictionary");
        // Pinyin tables have no unique key, so a pair can repeat; the lookup lists the highest weight, and that is what previous carries.
        auto current = prepare(db.get(), "SELECT MAX(weight) FROM " + target + row);
        if (!current || !bind_text(current.get(), 1, previous.key) || !bind_text(current.get(), 2, previous.value) ||
            sqlite3_step(current.get()) != SQLITE_ROW || sqlite3_column_type(current.get(), 0) == SQLITE_NULL ||
            sqlite3_column_int64(current.get(), 0) != previous.weight)
            return fail("The entry changed; reload it before editing");
        current.reset();
        auto change = prepare(db.get(), weight ? "UPDATE " + target + " SET weight=?3" + row : "DELETE FROM " + target + row);
        if (!change || !bind_text(change.get(), 1, previous.key) || !bind_text(change.get(), 2, previous.value) ||
            (weight && sqlite3_bind_int64(change.get(), 3, *weight) != SQLITE_OK) ||
            sqlite3_step(change.get()) != SQLITE_DONE || sqlite3_changes(db.get()) == 0)
            return fail(weight ? "Cannot save dictionary entry" : "Cannot remove dictionary entry");
        change.reset();
        // The same rows record_upsert and record_delete write, so replay repeats the change on a fresh dictionary.
        auto journal =
            weight ? prepare(db.get(),
                             "INSERT INTO personal_journal.user_dictionary_operations("
                             "dictionary,key,value,operation,weight,display,user_inserted)"
                             " VALUES(?1,?2,?3,'upsert',?4,?5,0) ON CONFLICT(dictionary,key,value) DO UPDATE SET"
                             " operation='upsert',weight=excluded.weight,display=excluded.display,user_inserted=0,"
                             " updated_at=unixepoch()")
                   : prepare(db.get(), "INSERT INTO personal_journal.user_dictionary_operations(dictionary,key,value,"
                                       "operation) VALUES(?1,?2,?3,'delete') ON CONFLICT(dictionary,key,value) DO"
                                       " UPDATE SET operation='delete',weight=0,display='',updated_at=unixepoch()");
        if (!journal || !bind_text(journal.get(), 1, dictionary) || !bind_text(journal.get(), 2, previous.key) ||
            !bind_text(journal.get(), 3, previous.value) ||
            (weight && (sqlite3_bind_int64(journal.get(), 4, *weight) != SQLITE_OK ||
                        !bind_text(journal.get(), 5, english ? previous.value : std::string{}))) ||
            sqlite3_step(journal.get()) != SQLITE_DONE)
            return fail("Cannot journal dictionary edit");
        journal.reset();
        if (!request_id.empty())
        {
            auto receipt =
                prepare(db.get(),
                        "INSERT INTO personal_journal.personal_dictionary_receipts(request_id,payload) VALUES(?1,?2)");
            if (!receipt || !bind_text(receipt.get(), 1, request_id) || !bind_text(receipt.get(), 2, payload) ||
                sqlite3_step(receipt.get()) != SQLITE_DONE)
                return fail("Cannot save edit receipt");
        }
        if (!execute_sql(db.get(), "COMMIT"))
            return fail("Cannot commit dictionary edit");
        return {true, {}};
    }
    catch (const std::exception &)
    {
        return {false, "Cannot access personal dictionary storage"};
    }
}
} // namespace metasequoia
"""

EDITS = {
    "include/metasequoia/personal_dictionary.h": [(HEADER_BEFORE, HEADER_AFTER)],
    "user_dictionary/user_dictionary_journal.cpp": [
        (SIGNATURE_BEFORE, SIGNATURE_AFTER),
        (QUERY_BEFORE, QUERY_AFTER),
        (TAIL_BEFORE, TAIL_AFTER),
    ],
}


def apply(root: Path) -> None:
    for relative, replacements in EDITS.items():
        path = root / relative
        text = path.read_text(encoding="utf-8")
        changed = text
        for before, after in replacements:
            if after in changed:
                continue
            if changed.count(before) != 1:
                raise RuntimeError(f"Engine overlay did not match: {path}")
            changed = changed.replace(before, after, 1)
        if changed != text:
            path.write_text(changed, encoding="utf-8")


if __name__ == "__main__":
    import sys

    apply(Path(sys.argv[1]))
