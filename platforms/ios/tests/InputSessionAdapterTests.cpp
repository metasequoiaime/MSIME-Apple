#include "InputSessionAdapter.h"
#include "ShuangpinKeymap.h"

#include "user_dictionary/user_dictionary_journal.h"

#include <sqlite3.h>

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace {
void Require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

int RunTest() {
  const std::filesystem::path dataDirectory =
      std::filesystem::temp_directory_path() /
      ("metasequoia-apple-input-session-adapter-" +
       std::to_string(std::chrono::high_resolution_clock::now()
                          .time_since_epoch()
                          .count()));
  std::filesystem::create_directories(dataDirectory);
  if (setenv("METASEQUOIA_IME_DATA_DIR", dataDirectory.c_str(), 1) != 0) {
    throw std::runtime_error("Failed to set the adapter test data directory.");
  }

  {
    metasequoia::apple::InputSessionAdapter adapter;
    const auto first = adapter.handle_character('n');
    Require(first.handled && first.preedit == "n",
            "The first letter did not start an engine composition.");

    Require(!first.diagnostic.has_value(),
            "An ordinary keystroke produced a diagnostic.");

    const auto second = adapter.handle_character('i');
    Require(second.handled && second.preedit == "ni",
            "The second letter did not update the engine preedit.");

    const auto backspace = adapter.handle_backspace();
    Require(backspace.handled && backspace.preedit == "n",
            "Backspace did not edit the engine composition.");

    const auto committed = adapter.commit_candidate();
    Require(committed.handled && committed.commit.has_value() &&
                *committed.commit == "n" && committed.preedit.empty(),
            "Candidate commit did not fall back to the raw composition.");

    Require(adapter.handle_character('h').handled &&
                adapter.handle_character('i').handled,
            "The raw-commit fixture did not start a composition.");
    const auto rawCommitted = adapter.commit_raw();
    Require(rawCommitted.handled && rawCommitted.commit.has_value() &&
                *rawCommitted.commit == "hi" && rawCommitted.preedit.empty(),
            "Raw commit did not clear and return the engine composition.");

    Require(!adapter.handle_backspace().handled,
            "Idle Backspace was swallowed by the engine adapter.");
    Require(!adapter.handle_character('N').handled,
            "Unsupported uppercase input was swallowed by the adapter.");

    // The engine treats A-Z during a composition as helpcode input, so testing uppercase with no
    // composition proves nothing any more: that path was always unhandled. Pin the state that
    // actually changed, and pin that the composition survives untouched.
    Require(adapter.handle_character('n').handled &&
                adapter.handle_character('i').handled,
            "The uppercase fixture did not start a composition.");
    const auto uppercaseDuringComposition = adapter.handle_character('H');
    Require(!uppercaseDuringComposition.handled,
            "Uppercase input during a composition was swallowed instead of passed to the client.");
    Require(uppercaseDuringComposition.preedit == "ni",
            "Uppercase input during a composition altered the preedit.");
    Require(adapter.cancel().handled, "The uppercase fixture did not clear its composition.");

    const auto punctuation = adapter.handle_punctuation('.');
    Require(punctuation.handled && punctuation.commit.has_value() &&
                *punctuation.commit == "。",
            "The adapter did not expose engine-owned Chinese punctuation.");

    Require(adapter.handle_character('x').handled &&
                adapter.handle_character('i').handled,
            "The apostrophe fixture did not start a composition.");
    const auto apostrophe = adapter.handle_character('\'');
    Require(apostrophe.handled && apostrophe.preedit == "xi'",
            "An in-composition apostrophe did not reach the engine.");
    Require(adapter.cancel().handled,
            "The apostrophe fixture did not cancel its composition.");
    Require(!adapter.handle_character('\'').handled,
            "An idle apostrophe was swallowed by the engine adapter.");

    Require(!adapter.uses_shuangpin(),
            "The adapter did not start in full-pinyin mode.");
    Require(adapter.handle_character('n').handled &&
                adapter.handle_character('i').handled,
            "The scheme-switch fixture did not start a composition.");
    const auto switchedToShuangpin = adapter.switch_to_shuangpin(true);
    Require(switchedToShuangpin.handled &&
                switchedToShuangpin.commit.has_value() &&
                *switchedToShuangpin.commit == "ni" &&
                switchedToShuangpin.preedit.empty(),
            "Switching schemes did not commit and clear the composition.");
    Require(adapter.uses_shuangpin(),
            "The adapter did not retain double-pinyin mode.");
    Require(adapter.handle_character('n').handled,
            "The idempotent switch fixture did not start a composition.");
    const auto unchangedShuangpin = adapter.switch_to_shuangpin(true);
    Require(!unchangedShuangpin.handled && unchangedShuangpin.preedit == "n" &&
                adapter.uses_shuangpin(),
            "Selecting the active scheme changed the composition.");
    Require(adapter.cancel().handled,
            "The idempotent switch fixture did not cancel its composition.");
    const auto switchedToQuanpin = adapter.switch_to_shuangpin(false);
    Require(!switchedToQuanpin.handled && !adapter.uses_shuangpin(),
            "The adapter did not switch an idle session back to full pinyin.");

    Require(adapter.handle_character('n').handled &&
                adapter.handle_character('i').handled,
            "The candidate-key fixture did not start a composition.");
    const auto unavailableCandidate = adapter.handle_candidate_key('1');
    Require(!unavailableCandidate.handled &&
                unavailableCandidate.preedit == "ni",
            "An unavailable numbered candidate was swallowed.");
    const auto composedPunctuation = adapter.handle_punctuation(',');
    Require(composedPunctuation.handled &&
                composedPunctuation.commit.has_value() &&
                *composedPunctuation.commit == "ni，" &&
                composedPunctuation.preedit.empty(),
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
        nullptr, nullptr, nullptr) == SQLITE_OK, "Cannot populate the partial-selection fixture.");
    sqlite3_close(database);
    metasequoia::apple::InputSessionAdapter adapter;
    for (char c : std::string("shui'lin")) adapter.handle_character(c);
    const auto prefix = adapter.commit_candidate();
    Require(prefix.commit == "水" && prefix.preedit == "lin" && !prefix.candidates.empty(),
            "The keyboard snapshot lost the remaining input after partial selection.");
    const auto suffix = adapter.commit_candidate();
    Require(suffix.commit == "林" && suffix.preedit.empty(), "The keyboard repeated the committed prefix.");
    for (char c : std::string("shui'lin")) adapter.handle_character(c);
    const auto finished = adapter.finish_composition();
    Require(finished.commit == "水林" && finished.preedit.empty() && finished.candidates.empty(),
            "Return or direct-mode switching left a hidden keyboard composition.");
    for (char c : std::string("shui'lin")) adapter.handle_character(c);
    const auto switched = adapter.switch_to_shuangpin(true);
    Require(switched.commit == "水林" && switched.preedit.empty(),
            "Switching keyboard schemes lost the pending suffix.");
  }

  {
    metasequoia::apple::InputSessionAdapter adapter;
    // A capital typed as a key is still not a mode trigger. The keyboard has no shift in Chinese
    // mode, and the engine reads A-Z during a composition as helpcode, which no Apple frontend
    // offers, so it has to come back unhandled for the host application to insert.
    for (const char trigger : {'U', 'T', 'K', 'J', 'E', 'M', 'Y', 'R'}) {
      const auto typed = adapter.handle_character(trigger);
      Require(!typed.handled && typed.preedit.empty(),
              "A capital typed as a key was taken as a local input mode trigger.");
    }

    // Named explicitly, the three modes this frontend can answer open.
    for (const char trigger : {'U', 'T', 'J'}) {
      const auto opened = adapter.open_local_mode(trigger);
      Require(opened.handled && opened.preedit == std::string(1, trigger),
              "A serviceable local input mode did not open.");
      Require(adapter.cancel().handled, "Cancel did not close the local input mode.");
    }
    Require(adapter.open_local_mode('U').handled && adapter.in_unicode_mode(),
            "The Unicode mode did not report itself for digit routing.");
    // Hexadecimal digits are input here, not candidate numbers.
    const auto hexDigit = adapter.handle_character('4');
    Require(hexDigit.handled && hexDigit.preedit == "U4",
            "The Unicode mode rejected a hexadecimal digit.");
    Require(adapter.cancel().handled && !adapter.in_unicode_mode(),
            "Cancel left the Unicode mode open.");

    // The modes whose data the mobile dictionary product does not carry stay shut even when named.
    for (const char trigger : {'K', 'E', 'M', 'Y', 'R'}) {
      const auto refused = adapter.open_local_mode(trigger);
      Require(!refused.handled && refused.preedit.empty(),
              "A local input mode without packaged data opened when it was named.");
    }

    // A mode cannot open on top of a composition; the engine guards every trigger on that.
    Require(adapter.handle_character('n').handled, "The guard fixture did not start a composition.");
    const auto duringComposition = adapter.open_local_mode('U');
    Require(!duringComposition.handled && duringComposition.preedit == "n" && !adapter.in_unicode_mode(),
            "A local input mode opened on top of a live composition.");
    Require(adapter.cancel().handled, "The guard fixture did not cancel its composition.");
  }

  Require(metasequoia::apple::shuangpin_key_hints(false).empty(),
          "Full pinyin produced double-pinyin key hints.");
  {
    const auto hints = metasequoia::apple::shuangpin_key_hints(true);
    Require(!hints.empty(), "Double pinyin produced no key hints.");
    // Xiaohe puts zh on v and ing on k; it is the Microsoft profile that puts ing on ;. Asserting
    // that one punctuation key is absent proved nothing, because the builder only ever emits the
    // 26 letters it iterates. Assert the invariant the keyboard actually depends on instead: every
    // key it describes has to exist on the letter grid.
    Require(hints.count("V") == 1 && hints.at("V").find("zh") != std::string::npos,
            "The V hint did not describe the zh initial.");
    for (const auto &[key, hint] : hints) {
      (void)hint;
      Require(key.size() == 1 && key[0] >= 'A' && key[0] <= 'Z',
              "A hint was produced for a key outside the letter grid.");
    }
    // The engine spells the ü finals with a leading v because that is the key sequence. A person
    // reads the hint, so it has to show the vowel.
    bool showsUmlaut = false;
    for (const auto &[key, hint] : hints) {
      (void)key;
      if (hint.find("ü") != std::string::npos) {
        showsUmlaut = true;
      }
      Require(hint.find(" v") == std::string::npos && hint.rfind("v", 0) != 0,
              "A hint exposed the engine's v spelling of a ü final.");
    }
    Require(showsUmlaut, "No hint showed a ü final.");
  }

  user_dictionary::close_default_user_database();
  std::filesystem::remove_all(dataDirectory);
  return 0;
}
} // namespace

int main() {
  try {
    return RunTest();
  } catch (const std::exception &exception) {
    std::fprintf(stderr, "%s\n", exception.what());
    return 1;
  }
}
