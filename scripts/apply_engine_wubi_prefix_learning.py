"""Apply the Windows reference's Wubi prefix ordering and learning transaction."""

from pathlib import Path


def replace(path: Path, old: str, new: str) -> None:
    text = path.read_text()
    if old in text:
        path.write_text(text.replace(old, new, 1))
    elif new not in text:
        raise RuntimeError(f"Wubi overlay did not match {path}")


def apply(root: Path) -> None:
    provider = root / "providers/wubi_candidate_provider.cpp"
    header = root / "providers/wubi_candidate_provider.h"
    registry = root / "providers/provider_registry.cpp"
    journal = root / "user_dictionary/user_dictionary_journal.cpp"
    journal_header = root / "user_dictionary/user_dictionary_journal.h"
    session_header = root / "core/input_session.h"
    session_composition = root / "core/input_session_composition.cpp"
    ime_session_header = root / "core/ime_session.h"
    wubi_scheme_header = root / "schemes/wubi_scheme.h"
    public_session_header = root / "include/metasequoia/session.h"
    public_session_source = root / "core/session.cpp"

    replace(wubi_scheme_header, """    void set_mixed_pinyin_allowed(bool allowed);

  private:
""", """    void set_mixed_pinyin_allowed(bool allowed);
    // Wubi table codes are complete at four letters. Mixed-pinyin input may continue beyond that,
    // but those longer spellings are fallback queries rather than complete Wubi codes.
    bool has_complete_code() const { return raw_input_.size() == kMaxCodeLength; }

  private:
""")
    replace(ime_session_header, """    bool answered_by_pinyin_fallback() const
    {
        return state_.answered_by_pinyin_fallback;
    }
    const std::vector<WordItem> &get_candidates() const;
""", """    bool answered_by_pinyin_fallback() const
    {
        return state_.answered_by_pinyin_fallback;
    }
    bool wubi_code_is_complete() const
    {
        return wubi_scheme_ != nullptr && wubi_scheme_->has_complete_code();
    }
    const std::vector<WordItem> &get_candidates() const;
""")
    replace(public_session_header, """    bool answered_by_pinyin_fallback = false;
    std::string shuangpin_profile;
""", """    bool answered_by_pinyin_fallback = false;
    bool wubi_unique_four_code = false;
    std::string shuangpin_profile;
""")
    replace(public_session_source, """    view.answered_by_pinyin_fallback = session.answered_by_pinyin_fallback();
    view.candidate_sources.reserve(view.candidates.size());
""", """    view.answered_by_pinyin_fallback = session.answered_by_pinyin_fallback();
    view.wubi_unique_four_code = session.wubi_unique_four_code();
    view.candidate_sources.reserve(view.candidates.size());
""")

    replace(session_header, """    bool is_all_complete_pure_pinyin() const;
    bool has_active_helpcode() const;
""", """    bool is_all_complete_pure_pinyin() const;
    // A complete four-letter Wubi code answered by the Wubi table with exactly one candidate.
    // Hosts decide whether to auto-commit; the Engine only reports the composition fact.
    bool wubi_unique_four_code() const;
    bool has_active_helpcode() const;
""")
    replace(session_composition, """bool InputSession::has_active_helpcode() const
{
""", """bool InputSession::wubi_unique_four_code() const
{
    if (dedicated_english_mode_ || local_input_mode_ != LocalInputMode::None)
        return false;
    if (!wubi_candidates_are_native() || !engine_.wubi_code_is_complete())
        return false;
    return candidates().size() == 1;
}

bool InputSession::has_active_helpcode() const
{
""")

    replace(provider, '#include "wubi_candidate_provider.h"\n#include "../quanpin/quanpin_query.h"',
            '#include "wubi_candidate_provider.h"\n#include "../contracts/assets/assets.h"\n#include "../core/data_path.h"\n#include "../quanpin/quanpin_query.h"\n#include "../user_dictionary/user_dictionary_journal.h"')
    replace(provider, "#include <unordered_set>\n", "")
    replace(provider, """constexpr int kNoMutation = 0;
// A one-letter code prefixes several thousand rows, and the window pages through whatever this
// returns. Long enough to page through, short enough to build on every keystroke; a user who wants
// what lies past it types another letter, which is what the remaining letters of the code are for.
constexpr int kMaxCandidates = 200;

// Wubi codes are lowercase letters, all of which sort below '{', so the range covers exactly the
// keys carrying the typed prefix.
std::string prefix_upper_bound(const std::string &prefix)
{
    return prefix + "{";
}
""", """constexpr int kNoMutation = 0;
constexpr int kMutationFailed = -1;
constexpr int kWubiQueryRowLimit = 50;
""")
    replace(provider, "WubiCandidateProvider::WubiCandidateProvider(std::string db_path)\n    : db_path_(db_path.empty() ? quanpin::get_default_db_path() : std::move(db_path))",
            "WubiCandidateProvider::WubiCandidateProvider(std::string db_path, metasequoia::RuntimePaths paths)\n    : db_path_(db_path.empty() ? quanpin::get_default_db_path() : std::move(db_path)), paths_(std::move(paths))")
    replace(provider, """    const std::string upper_bound = prefix_upper_bound(request.normalized_input);
    sqlite3_reset(query_statement_);
    sqlite3_clear_bindings(query_statement_);
    if (sqlite3_bind_text(query_statement_, 1, request.normalized_input.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK ||
        sqlite3_bind_text(query_statement_, 2, upper_bound.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK ||
        sqlite3_bind_int(query_statement_, 3, kMaxCandidates) != SQLITE_OK)
""", """    sqlite3_reset(query_statement_);
    sqlite3_clear_bindings(query_statement_);
    std::string upper_bound = request.normalized_input;
    ++upper_bound.back();
    if (sqlite3_bind_text(query_statement_, 1, request.normalized_input.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK ||
        sqlite3_bind_text(query_statement_, 2, upper_bound.c_str(), -1, SQLITE_TRANSIENT) != SQLITE_OK)
""")
    replace(provider, "    std::unordered_set<std::string> seen;\n", "")
    replace(provider, "key == nullptr || value == nullptr || !seen.insert(value).second", "key == nullptr || value == nullptr")
    replace(provider, """int WubiCandidateProvider::update_weight_by_pinyin_and_word(SchemeType, std::string, std::string)
{
    return kNoMutation;
}

int WubiCandidateProvider::delete_by_pinyin_and_word(SchemeType, std::string, std::string)
{
    return kNoMutation;
}
""", """int WubiCandidateProvider::update_weight_by_pinyin_and_word(SchemeType, std::string code, std::string word)
{
    if (!user_dictionary::bump_wubi_weight(db_path_, journal_db_path(), code, word))
        return kMutationFailed;
    reset_cache();
    return kNoMutation;
}

int WubiCandidateProvider::delete_by_pinyin_and_word(SchemeType, std::string code, std::string word)
{
    if (!user_dictionary::delete_dictionary_candidate(db_path_, journal_db_path(), user_dictionary::DictionaryKind::Wubi, code, word))
        return kMutationFailed;
    reset_cache();
    return kNoMutation;
}
""")
    replace(provider, r"""    // An unfinished code is a prefix of the codes it can still become, so it answers with all of
    // them: a table matched on the code alone leaves 你 as the only candidate for wq and the two or
    // three simplified codes as the whole list for most of the alphabet. Shorter codes first, since
    // a code that is already complete is the one being typed; the typed code itself is the shortest
    // match there is and stays at the head of the list.
    constexpr const char *query_sql = "SELECT \"key\", \"value\", \"weight\" FROM wubi86 "
                                      "WHERE \"key\" >= ?1 AND \"key\" < ?2 "
                                      "ORDER BY length(\"key\") ASC, \"weight\" DESC, rowid ASC LIMIT ?3";
    if (sqlite3_prepare_v2(db_, query_sql, -1, &query_statement_, nullptr) != SQLITE_OK)
""", r"""    const std::string query_sql =
        "SELECT \"key\", \"value\", \"weight\" FROM wubi86 "
        "WHERE \"key\" >= ?1 AND \"key\" < ?2 "
        "ORDER BY (\"key\" = ?1) DESC, \"weight\" DESC, \"key\" ASC, rowid ASC LIMIT " +
        std::to_string(kWubiQueryRowLimit);
    if (sqlite3_prepare_v2(db_, query_sql.c_str(), -1, &query_statement_, nullptr) != SQLITE_OK)
""")
    replace(provider, "void WubiCandidateProvider::close_database()", """std::string WubiCandidateProvider::journal_db_path() const
{
    return metasequoia::path_to_utf8(paths_.user(metasequoia::assets::user_journal));
}

void WubiCandidateProvider::close_database()""")

    replace(header, '#include "candidate_provider.h"\n#include <sqlite3.h>', '#include "candidate_provider.h"\n#include "../core/runtime_paths.h"\n#include <sqlite3.h>')
    replace(header, 'explicit WubiCandidateProvider(std::string db_path = {});', 'explicit WubiCandidateProvider(std::string db_path = {},\n                                   metasequoia::RuntimePaths paths = metasequoia::RuntimePaths::legacy());')
    replace(header, '    void close_database();\n\n    std::string db_path_;', '    void close_database();\n    std::string journal_db_path() const;\n\n    std::string db_path_;\n    metasequoia::RuntimePaths paths_;')
    replace(registry, 'wubi_provider_(metasequoia::path_to_utf8(paths.dictionary(metasequoia::assets::main_dictionary))),', 'wubi_provider_(metasequoia::path_to_utf8(paths.dictionary(metasequoia::assets::main_dictionary)), paths),')

    journal_function = """bool bump_wubi_weight(const std::string &main_db_path, const std::string &user_db_path,
                      const std::string &key, const std::string &value)
{
    if (key.empty() || value.empty() || !ensure_user_database(user_db_path))
        return false;
    auto database = open_database(main_db_path, SQLITE_OPEN_READWRITE);
    auto attach = database ? prepare(database.get(), "ATTACH DATABASE ?1 AS candidate_journal") : Stmt{};
    if (!attach || !bind_text(attach.get(), 1, user_db_path) || sqlite3_step(attach.get()) != SQLITE_DONE ||
        !execute_sql(database.get(), "BEGIN IMMEDIATE"))
        return false;
    auto current = prepare(database.get(), "SELECT MAX(weight) FROM main.\\\"wubi86\\\" WHERE \\\"key\\\"=?1");
    if (!current || !bind_text(current.get(), 1, key) || sqlite3_step(current.get()) != SQLITE_ROW)
        return false;
    const auto weight = clamp_managed_weight(sqlite3_column_int64(current.get(), 0) + 1);
    auto bump = prepare(database.get(), "UPDATE main.\\\"wubi86\\\" SET weight=?1 WHERE \\\"key\\\"=?2 AND \\\"value\\\"=?3");
    if (!bump || sqlite3_bind_int64(bump.get(), 1, weight) != SQLITE_OK || !bind_text(bump.get(), 2, key) ||
        !bind_text(bump.get(), 3, value) || sqlite3_step(bump.get()) != SQLITE_DONE || sqlite3_changes(database.get()) == 0) {
        (void)execute_sql(database.get(), "ROLLBACK");
        return false;
    }
    auto entry = prepare(database.get(), "INSERT INTO candidate_journal.user_dictionary_operations(dictionary,key,value,operation,weight,display) VALUES(?1,?2,?3,'upsert',?4,'') ON CONFLICT(dictionary,key,value) DO UPDATE SET operation='upsert',weight=excluded.weight,display='',updated_at=unixepoch()");
    if (!entry || !bind_text(entry.get(), 1, kind_name(DictionaryKind::Wubi)) || !bind_text(entry.get(), 2, key) ||
        !bind_text(entry.get(), 3, value) || sqlite3_bind_int64(entry.get(), 4, weight) != SQLITE_OK ||
        sqlite3_step(entry.get()) != SQLITE_DONE || !execute_sql(database.get(), "COMMIT")) {
        (void)execute_sql(database.get(), "ROLLBACK");
        return false;
    }
    return true;
}

"""
    replace(journal, 'bool learn_entered_english_word(const std::string &english_db_path', journal_function + 'bool learn_entered_english_word(const std::string &english_db_path')
    replace(journal_header, 'bool ensure_user_database(const std::string &user_db_path);\n', 'bool ensure_user_database(const std::string &user_db_path);\nbool bump_wubi_weight(const std::string &main_db_path, const std::string &user_db_path,\n                      const std::string &key, const std::string &value);\n')
