#include "InputSessionAdapter.h"
#include "ShuangpinKeymap.h"

#include <metasequoia/session.h>
#include <metasequoia/dictionary_state.h>

#include "user_dictionary/user_dictionary_journal.h"

#include <sqlite3.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

void TestRuntimeGenerationUpgrade(const std::filesystem::path &root)
{
    using metasequoia::apple::InputSessionAdapter;
    using metasequoia::apple::InputSnapshot;
    const auto resources = root / "bundled";
    const auto user = root / "user";
    const auto cache = root / "cache";
    std::filesystem::create_directories(resources);
    std::filesystem::create_directories(user);
    sqlite3 *database = nullptr;
    Require(sqlite3_open((resources / "msime.db").c_str(), &database) == SQLITE_OK, "Cannot create upgrade fixture.");
    Require(sqlite3_exec(database,
                         "CREATE TABLE tbl_2_b(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                         "INSERT INTO tbl_2_b VALUES('bu''hao','bh','不好',200);"
                         "INSERT INTO tbl_2_b VALUES('bu''hao','bh','补好',100);",
                         nullptr, nullptr, nullptr) == SQLITE_OK,
            "Cannot seed upgrade fixture.");
    sqlite3_close(database);
    Require(sqlite3_open((resources / "english.db").c_str(), &database) == SQLITE_OK,
            "Cannot create English upgrade fixture.");
    Require(sqlite3_exec(database, "CREATE TABLE fixture(value TEXT);", nullptr, nullptr, nullptr) == SQLITE_OK,
            "Cannot initialize English upgrade fixture.");
    sqlite3_close(database);
    const auto copyBundledMain = [&] {
        std::filesystem::copy_file(resources / "msime.db", user / "msime.db",
                                   std::filesystem::copy_options::overwrite_existing);
    };
    const auto type = [](InputSessionAdapter &adapter) {
        InputSnapshot snapshot;
        for (char c : std::string("buhao"))
            snapshot = adapter.handle_character(c);
        return snapshot;
    };
    copyBundledMain();
    // This is the previous private-directory layout. The journal must stay here during migration.
    const metasequoia::RuntimePaths legacy{user, user, cache, user};
    {
        InputSessionAdapter adapter(legacy);
        Require(adapter.set_learning_enabled(true), "Cannot enable upgrade fixture learning.");
        Require(type(adapter).candidates.at(1) == "补好", "Unexpected upgrade baseline.");
        Require(adapter.select_candidate(1).commit == "补好", "Cannot learn upgrade fixture word.");
    }
    {
        InputSessionAdapter adapter(legacy);
        Require(type(adapter).candidates.at(0) == "补好", "Legacy journal learning did not persist.");
    }
    // Reproduce the old installer's file replacement: the journal survives, but ranking is reset.
    copyBundledMain();
    {
        InputSessionAdapter adapter(legacy);
        Require(type(adapter).candidates.at(0) == "不好", "Replacement did not reproduce ranking reset.");
    }
    auto first = metasequoia::prepare_runtime_paths(resources, user, cache, "first");
    {
        InputSessionAdapter adapter(first);
        Require(type(adapter).candidates.at(0) == "补好", "Migration did not replay legacy learning.");
        adapter.cancel();
        adapter.switch_to_shuangpin_profile("ziranma");
        Require(adapter.set_learning_enabled(true), "Cannot update prepared session preferences.");
        adapter.switch_to_nine_key();
        InputSnapshot snapshot;
        for (char c : std::string("28426"))
            snapshot = adapter.handle_character(c);
        Require(snapshot.candidates.at(0) == "补好", "Scheme/preference change lost prepared paths.");
    }
    auto second = metasequoia::prepare_runtime_paths(resources, user, cache, "second");
    {
        InputSessionAdapter adapter(second);
        Require(type(adapter).candidates.at(0) == "补好", "Upgrade lost learned ranking.");
        auto removed = adapter.edit_candidate(0, "补好", metasequoia::apple::CandidateAction::Remove);
        Require(removed.handled && !removed.diagnostic, "Cannot remove upgraded candidate.");
    }
    first = metasequoia::prepare_runtime_paths(resources, user, cache, "first");
    {
        InputSessionAdapter adapter(first);
        for (const auto &word : type(adapter).candidates)
            Require(word != "补好", "Switching back resurrected a deleted candidate.");
    }
    const auto restored = metasequoia::stage_dictionary_state(resources, root / "restored", "base",
        [](metasequoia::DictionaryStateRecord &) { return false; });
    {
        InputSessionAdapter adapter(first);
        bool published = false;
        const auto publish = [&] { published = true; };
        type(adapter);
        Require(!adapter.activate_dictionary_generation(restored, publish) && !published,
                "Activation interrupted composition or published early.");
        Require(!adapter.handle_character('a').preedit.empty(), "Rejected activation lost composition.");
        adapter.cancel();
        adapter.open_local_mode('U');
        Require(!adapter.activate_dictionary_generation(restored, publish) && !published,
                "Activation interrupted local input mode.");
        adapter.cancel();
        bool failedPublish = false;
        try {
            adapter.activate_dictionary_generation(restored, [] { throw std::runtime_error("synthetic publication failure"); });
        } catch (const std::exception &) { failedPublish = true; }
        Require(failedPublish, "Publication failure was swallowed.");
        Require(type(adapter).candidates.size() == 1, "Failed publication changed active dictionary.");
        adapter.cancel();
        adapter.switch_to_shuangpin_profile("ziranma");
        Require(adapter.set_learning_enabled(true), "Cannot enable generation learning fixture.");
        Require(adapter.activate_dictionary_generation(restored, publish) && published &&
                    adapter.uses_shuangpin() && adapter.shuangpin_profile_name() == "ziranma" && adapter.learning_enabled(),
                "Successful activation lost settings or did not publish.");
        adapter.switch_to_nine_key();
        Require(adapter.activate_dictionary_generation(first, [] {}), "Cannot restore previous generation.");
        InputSnapshot snapshot;
        for (char c : std::string("28426")) snapshot = adapter.handle_character(c);
        Require(snapshot.candidates.size() == 1, "Activation lost nine-key mode or retained the wrong generation.");
        adapter.cancel();
        Require(adapter.activate_dictionary_generation(restored, [] {}), "Cannot activate clean snapshot.");
        for (char c : std::string("28426")) snapshot = adapter.handle_character(c);
        Require(snapshot.candidates.size() >= 2 && snapshot.candidates.at(1) == "补好",
                "Empty snapshot activation retained an old tombstone.");
    }
    // A replay failure must leave prepared generations usable and never publish a ready marker.
    const auto journal = user / "msime_user.db";
    std::filesystem::rename(journal, user / "journal.saved");
    std::filesystem::create_directory(journal);
    bool failed = false;
    try
    {
        metasequoia::prepare_runtime_paths(resources, user, cache, "broken");
    }
    catch (const std::exception &)
    {
        failed = true;
    }
    Require(failed && !std::filesystem::exists(user / "dictionaries" / "broken") &&
                !std::filesystem::exists(user / "dictionaries" / "broken.incoming"),
            "Failed replay published or left an incomplete generation.");
    std::filesystem::remove(journal);
    std::filesystem::rename(user / "journal.saved", journal);
    {
        InputSessionAdapter adapter(first);
        Require(type(adapter).candidates.at(0) == "不好", "Failed upgrade damaged the working generation.");
        adapter.cancel();
        adapter.switch_to_nine_key();
        Require(adapter.set_learning_enabled(true), "Cannot configure editor fixture learning.");
        adapter.handle_character('2');
        const metasequoia::PersonalDictionaryEntry personal{metasequoia::PersonalDictionaryKind::Pinyin, "bu'hao",
                                                            "布好", 100000};
        Require(!adapter.edit_personal_word(std::nullopt, personal, "adapter-add").success,
                "Personal dictionary edit interrupted a composition.");
        Require(!adapter.handle_character('8').preedit.empty(), "Rejected edit lost the composition.");
        adapter.cancel();
        Require(adapter.edit_personal_word(std::nullopt, personal, "adapter-add").success && adapter.learning_enabled(),
                "Idle edit failed or lost learning preference.");
        metasequoia::apple::InputSnapshot snapshot;
        for (char c : std::string("28426"))
            snapshot = adapter.handle_character(c);
        Require(snapshot.candidates.at(0) == "布好", "Personal edit lost nine-key mode or prepared paths.");
        adapter.cancel();
        Require(adapter.personal_words(0, 100).entries.size() == 1, "Personal list did not expose the new word.");
        Require(adapter.edit_personal_word(personal, std::nullopt, "adapter-remove").success,
                "Cannot remove editor fixture word.");
    }
}

int RunTest()
{
    const std::filesystem::path dataDirectory =
        std::filesystem::temp_directory_path() /
        ("metasequoia-apple-input-session-adapter-" +
         std::to_string(std::chrono::high_resolution_clock::now().time_since_epoch().count()));
    std::filesystem::create_directories(dataDirectory);
    if (setenv("METASEQUOIA_IME_DATA_DIR", dataDirectory.c_str(), 1) != 0)
    {
        throw std::runtime_error("Failed to set the adapter test data directory.");
    }

    {
        metasequoia::apple::InputSessionAdapter adapter;
        const auto first = adapter.handle_character('n');
        Require(first.handled && first.preedit == "n", "The first letter did not start an engine composition.");

        Require(!first.diagnostic.has_value(), "An ordinary keystroke produced a diagnostic.");

        const auto second = adapter.handle_character('i');
        Require(second.handled && second.preedit == "ni", "The second letter did not update the engine preedit.");

        const auto backspace = adapter.handle_backspace();
        Require(backspace.handled && backspace.preedit == "n", "Backspace did not edit the engine composition.");

        const auto committed = adapter.commit_candidate();
        Require(committed.handled && committed.commit.has_value() && *committed.commit == "n" &&
                    committed.preedit.empty(),
                "Candidate commit did not fall back to the raw composition.");

        Require(adapter.handle_character('h').handled && adapter.handle_character('i').handled,
                "The raw-commit fixture did not start a composition.");
        const auto rawCommitted = adapter.commit_raw();
        Require(rawCommitted.handled && rawCommitted.commit.has_value() && *rawCommitted.commit == "hi" &&
                    rawCommitted.preedit.empty(),
                "Raw commit did not clear and return the engine composition.");

        Require(!adapter.handle_backspace().handled, "Idle Backspace was swallowed by the engine adapter.");
        Require(!adapter.handle_character('N').handled, "Unsupported uppercase input was swallowed by the adapter.");

        // The engine treats A-Z during a composition as helpcode input, so testing uppercase with no
        // composition proves nothing any more: that path was always unhandled. Pin the state that
        // actually changed, and pin that the composition survives untouched.
        Require(adapter.handle_character('n').handled && adapter.handle_character('i').handled,
                "The uppercase fixture did not start a composition.");
        const auto uppercaseDuringComposition = adapter.handle_character('H');
        Require(!uppercaseDuringComposition.handled,
                "Uppercase input during a composition was swallowed instead of passed to the client.");
        Require(uppercaseDuringComposition.preedit == "ni",
                "Uppercase input during a composition altered the preedit.");
        Require(adapter.cancel().handled, "The uppercase fixture did not clear its composition.");

        const auto punctuation = adapter.handle_punctuation('.');
        Require(punctuation.handled && punctuation.commit.has_value() && *punctuation.commit == "。",
                "The adapter did not expose engine-owned Chinese punctuation.");

        Require(adapter.handle_character('x').handled && adapter.handle_character('i').handled,
                "The apostrophe fixture did not start a composition.");
        const auto apostrophe = adapter.handle_character('\'');
        Require(apostrophe.handled && apostrophe.preedit == "xi'",
                "An in-composition apostrophe did not reach the engine.");
        Require(adapter.cancel().handled, "The apostrophe fixture did not cancel its composition.");
        Require(!adapter.handle_character('\'').handled, "An idle apostrophe was swallowed by the engine adapter.");

        Require(!adapter.uses_shuangpin(), "The adapter did not start in full-pinyin mode.");
        Require(adapter.handle_character('n').handled && adapter.handle_character('i').handled,
                "The scheme-switch fixture did not start a composition.");
        const auto switchedToShuangpin = adapter.switch_to_shuangpin(true);
        Require(switchedToShuangpin.handled && switchedToShuangpin.commit.has_value() &&
                    *switchedToShuangpin.commit == "ni" && switchedToShuangpin.preedit.empty(),
                "Switching schemes did not commit and clear the composition.");
        Require(adapter.uses_shuangpin(), "The adapter did not retain double-pinyin mode.");
        Require(adapter.handle_character('n').handled, "The idempotent switch fixture did not start a composition.");
        const auto unchangedShuangpin = adapter.switch_to_shuangpin(true);
        Require(!unchangedShuangpin.handled && unchangedShuangpin.preedit == "n" && adapter.uses_shuangpin(),
                "Selecting the active scheme changed the composition.");
        Require(adapter.cancel().handled, "The idempotent switch fixture did not cancel its composition.");
        const auto switchedToQuanpin = adapter.switch_to_shuangpin(false);
        Require(!switchedToQuanpin.handled && !adapter.uses_shuangpin(),
                "The adapter did not switch an idle session back to full pinyin.");

        Require(adapter.handle_character('n').handled && adapter.handle_character('i').handled,
                "The candidate-key fixture did not start a composition.");
        const auto unavailableCandidate = adapter.handle_candidate_key('1');
        Require(!unavailableCandidate.handled && unavailableCandidate.preedit == "ni",
                "An unavailable numbered candidate was swallowed.");
        const auto composedPunctuation = adapter.handle_punctuation(',');
        Require(composedPunctuation.handled && composedPunctuation.commit.has_value() &&
                    *composedPunctuation.commit == "ni，" && composedPunctuation.preedit.empty(),
                "Punctuation did not atomically commit the raw composition.");
    }

    {
        sqlite3 *database = nullptr;
        Require(sqlite3_open((dataDirectory / "msime.db").c_str(), &database) == SQLITE_OK,
                "Cannot open the partial-selection fixture.");
        Require(sqlite3_exec(database,
                             "CREATE TABLE tbl_1_s(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                             "INSERT INTO tbl_1_s VALUES('shui','s','水',100);"
                             "CREATE TABLE tbl_1_l(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                             "INSERT INTO tbl_1_l VALUES('lin','l','林',100);"
                             "CREATE TABLE tbl_2_s(key TEXT,jp TEXT,value TEXT,weight INTEGER)",
                             nullptr, nullptr, nullptr) == SQLITE_OK,
                "Cannot populate the partial-selection fixture.");
        sqlite3_close(database);
        metasequoia::apple::InputSessionAdapter adapter;
        for (char c : std::string("shui'lin"))
            adapter.handle_character(c);
        const auto prefix = adapter.commit_candidate();
        Require(prefix.commit == "水" && prefix.preedit == "lin" && !prefix.candidates.empty(),
                "The keyboard snapshot lost the remaining input after partial selection.");
        const auto suffix = adapter.commit_candidate();
        Require(suffix.commit == "林" && suffix.preedit.empty(), "The keyboard repeated the committed prefix.");
        for (char c : std::string("shui'lin"))
            adapter.handle_character(c);
        const auto finished = adapter.finish_composition();
        Require(finished.commit == "水林" && finished.preedit.empty() && finished.candidates.empty(),
                "Return or direct-mode switching left a hidden keyboard composition.");
        for (char c : std::string("shui'lin"))
            adapter.handle_character(c);
        const auto switched = adapter.switch_to_shuangpin(true);
        Require(switched.commit == "水林" && switched.preedit.empty(),
                "Switching keyboard schemes lost the pending suffix.");
    }

    {
        metasequoia::apple::InputSessionAdapter adapter;
        adapter.switch_to_nine_key();
        for (char digit : std::string("7484"))
            Require(adapter.handle_character(digit).handled, "Nine-key digit was not handled.");
        Require(!adapter.nine_key_spellings().empty(), "Nine-key spelling choices were not bridged.");
        const auto unchanged = adapter.switch_to_nine_key();
        Require(!unchanged.handled && unchanged.preedit == "7484", "Idempotent nine-key switch cleared input.");
        const auto switched = adapter.switch_to_shuangpin(false);
        Require(switched.commit == "水" && switched.preedit.empty(), "Switching to 26 keys lost composition.");
        Require(!adapter.handle_character('7').handled, "Nine-key digits leaked into ordinary quanpin.");
        adapter.handle_character('s');
        adapter.handle_character('h');
        adapter.handle_character('u');
        adapter.handle_character('i');
        Require(adapter.switch_to_nine_key().commit == "水", "Switching to nine keys lost quanpin input.");
        Require(adapter.open_local_mode('U').handled && adapter.in_local_mode() && adapter.in_unicode_mode(),
                "Nine-key layout did not expose alphabetic local-mode requirements.");
        adapter.cancel();
        Require(!adapter.in_local_mode(), "Closing a local mode did not restore the pinyin layout.");
    }

    {
        metasequoia::apple::InputSessionAdapter adapter;
        // A capital typed as a key is still not a mode trigger. The keyboard has no shift in Chinese
        // mode, and the engine reads A-Z during a composition as helpcode, which no Apple frontend
        // offers, so it has to come back unhandled for the host application to insert.
        for (const char trigger : {'U', 'T', 'K', 'J', 'E', 'M', 'Y', 'R'})
        {
            const auto typed = adapter.handle_character(trigger);
            Require(!typed.handled && typed.preedit.empty(),
                    "A capital typed as a key was taken as a local input mode trigger.");
        }

        // Named explicitly, the modes backed by the packaged resources open.
        for (const char trigger : {'U', 'T', 'J', 'K', 'E', 'M', 'Y', 'R'})
        {
            const auto opened = adapter.open_local_mode(trigger);
            Require(opened.handled && opened.preedit == std::string(1, trigger),
                    "A serviceable local input mode did not open.");
            Require(adapter.cancel().handled, "Cancel did not close the local input mode.");
        }
        Require(adapter.open_local_mode('U').handled && adapter.in_unicode_mode(),
                "The Unicode mode did not report itself for digit routing.");
        // Hexadecimal digits are input here, not candidate numbers.
        const auto hexDigit = adapter.handle_character('4');
        Require(hexDigit.handled && hexDigit.preedit == "U4", "The Unicode mode rejected a hexadecimal digit.");
        Require(adapter.cancel().handled && !adapter.in_unicode_mode(), "Cancel left the Unicode mode open.");

        // Unknown mode names remain inert.
        for (const char trigger : {'B', 'Z'})
        {
            const auto refused = adapter.open_local_mode(trigger);
            Require(!refused.handled && refused.preedit.empty(),
                    "An unknown local input mode opened when it was named.");
        }

        // A mode cannot open on top of a composition; the engine guards every trigger on that.
        Require(adapter.handle_character('n').handled, "The guard fixture did not start a composition.");
        const auto duringComposition = adapter.open_local_mode('U');
        Require(!duringComposition.handled && duringComposition.preedit == "n" && !adapter.in_unicode_mode(),
                "A local input mode opened on top of a live composition.");
        Require(adapter.cancel().handled, "The guard fixture did not cancel its composition.");
    }

    Require(metasequoia::apple::shuangpin_key_hints(false).empty(), "Full pinyin produced double-pinyin key hints.");
    {
        const auto hints = metasequoia::apple::shuangpin_key_hints(true);
        Require(!hints.empty(), "Double pinyin produced no key hints.");
        // Xiaohe puts zh on v and ing on k; it is the Microsoft profile that puts ing on ;. Asserting
        // that one punctuation key is absent proved nothing, because the builder only ever emits the
        // 26 letters it iterates. Assert the invariant the keyboard actually depends on instead: every
        // key it describes has to exist on the letter grid.
        Require(hints.count("V") == 1 && hints.at("V").find("zh") != std::string::npos,
                "The V hint did not describe the zh initial.");
        for (const auto &[key, hint] : hints)
        {
            (void)hint;
            Require(key.size() == 1 && key[0] >= 'A' && key[0] <= 'Z',
                    "A hint was produced for a key outside the letter grid.");
        }
        // The engine spells the ü finals with a leading v because that is the key sequence. A person
        // reads the hint, so it has to show the vowel.
        bool showsUmlaut = false;
        for (const auto &[key, hint] : hints)
        {
            (void)key;
            if (hint.find("ü") != std::string::npos)
            {
                showsUmlaut = true;
            }
            Require(hint.find(" v") == std::string::npos && hint.rfind("v", 0) != 0,
                    "A hint exposed the engine's v spelling of a ü final.");
        }
        Require(showsUmlaut, "No hint showed a ü final.");
    }

    {
        sqlite3 *database = nullptr;
        Require(sqlite3_open((dataDirectory / "msime.db").c_str(), &database) == SQLITE_OK,
                "Cannot open candidate management fixture.");
        Require(sqlite3_exec(database, "INSERT INTO tbl_2_s VALUES('shui''lin','sl','水林',1000)", nullptr, nullptr,
                             nullptr) == SQLITE_OK,
                "Cannot add management fixture.");
        sqlite3_close(database);
        metasequoia::apple::InputSessionAdapter adapter;
        metasequoia::apple::InputSnapshot snapshot;
        for (char c : std::string("shuilin"))
            snapshot = adapter.handle_character(c);
        Require(!snapshot.candidates.empty() && snapshot.candidates[0] == "水林", "Missing management candidate.");
        using Action = metasequoia::apple::CandidateAction;
        const auto stale = adapter.edit_candidate(0, "other", Action::Remove);
        Require(!stale.handled && stale.candidates == snapshot.candidates && !stale.commit,
                "A stale candidate action mutated the session.");
        for (auto action : {Action::Promote, Action::FixFirst, Action::ClearPosition})
        {
            const auto edited = adapter.edit_candidate(0, "水林", action);
            Require(edited.handled && !edited.diagnostic && !edited.commit && !edited.preedit.empty(),
                    "Candidate management failed or committed text.");
        }
        const auto removed = adapter.edit_candidate(0, "水林", Action::Remove);
        Require(removed.handled && !removed.diagnostic && !removed.commit, "Candidate removal failed.");
        for (const auto &word : removed.candidates)
            Require(word != "水林", "Removed candidate remained visible.");
        adapter.cancel();
        metasequoia::apple::InputSessionAdapter reopened;
        for (char c : std::string("shuilin"))
            snapshot = reopened.handle_character(c);
        for (const auto &word : snapshot.candidates)
            Require(word != "水林", "Removal did not persist.");
    }

    {
        sqlite3 *database = nullptr;
        Require(sqlite3_open((dataDirectory / "msime.db").c_str(), &database) == SQLITE_OK,
                "Cannot open learning fixture.");
        Require(sqlite3_exec(database,
                             "CREATE TABLE tbl_2_b(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                             "INSERT INTO tbl_2_b VALUES('bu''hao','bh','不好',200);"
                             "INSERT INTO tbl_2_b VALUES('bu''hao','bh','补好',100);",
                             nullptr, nullptr, nullptr) == SQLITE_OK,
                "Cannot populate learning fixture.");
        sqlite3_close(database);
        auto type = [](metasequoia::apple::InputSessionAdapter &adapter) {
            metasequoia::apple::InputSnapshot snapshot;
            for (char c : std::string("buhao"))
                snapshot = adapter.handle_character(c);
            return snapshot;
        };
        metasequoia::apple::InputSessionAdapter adapter;
        auto initial = type(adapter);
        Require(initial.candidates.size() >= 2 && initial.candidates[0] == "不好", "Unexpected learning baseline.");
        Require(!adapter.set_learning_enabled(true) && !adapter.learning_enabled(),
                "Learning changed during a composition.");
        Require(adapter.select_candidate(1).commit == "补好", "Selecting with learning disabled failed.");
        auto unchanged = type(adapter);
        Require(unchanged.candidates[0] == "不好", "Disabled learning changed candidate order.");
        adapter.cancel();
        Require(adapter.set_learning_enabled(true) && adapter.learning_enabled(), "Idle learning change failed.");
        type(adapter);
        Require(!adapter.set_learning_enabled(false) && adapter.learning_enabled(),
                "Disabling interrupted composition.");
        Require(adapter.select_candidate(1).commit == "补好", "Learning selection failed.");
        Require(adapter.set_learning_enabled(false), "Learning could not be disabled when idle.");
        metasequoia::apple::InputSessionAdapter reopened;
        Require(type(reopened).candidates[0] == "补好", "Learning did not persist across sessions.");
        adapter.switch_to_shuangpin_profile("ziranma");
        Require(adapter.set_learning_enabled(true) && adapter.shuangpin_profile_name() == "ziranma" &&
                    adapter.uses_shuangpin(),
                "Changing learning lost the double-pinyin profile.");
        adapter.switch_to_nine_key();
        Require(adapter.learning_enabled() && adapter.set_learning_enabled(false),
                "Nine-key lost the learning setting.");
        Require(adapter.handle_character('7').handled, "Changing learning lost nine-key routing.");
    }

    TestRuntimeGenerationUpgrade(dataDirectory / "upgrade");
    user_dictionary::close_default_user_database();
    std::filesystem::remove_all(dataDirectory);
    return 0;
}
} // namespace

int main()
{
    try
    {
        return RunTest();
    }
    catch (const std::exception &exception)
    {
        std::fprintf(stderr, "%s\n", exception.what());
        return 1;
    }
}
