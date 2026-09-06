#include "PublicSessionTestOptions.h"
#include "../src/CandidateSelectionState.h"
#include "../../../vendor/MetasequoiaImeEngine/core/data_path.h"
#include "../../../vendor/MetasequoiaImeEngine/user_dictionary/user_dictionary_journal.h"

#include <sqlite3.h>

#include <chrono>
#include <cstdlib>
#include <filesystem>
#include <stdexcept>
#include <string>

namespace {
class Database {
public:
  explicit Database(const std::filesystem::path &path) {
    if (sqlite3_open(metasequoia::path_to_utf8(path).c_str(), &database_) !=
        SQLITE_OK) {
      throw std::runtime_error(
          "Failed to create the candidate-selection test dictionary.");
    }
  }

  ~Database() { sqlite3_close(database_); }

  void execute(const char *sql) {
    char *error = nullptr;
    if (sqlite3_exec(database_, sql, nullptr, nullptr, &error) != SQLITE_OK) {
      const std::string message =
          error == nullptr ? "SQLite operation failed." : error;
      sqlite3_free(error);
      throw std::runtime_error(message);
    }
  }

private:
  sqlite3 *database_ = nullptr;
};

void type(metasequoia::Session &session, const std::string &text) {
  for (const char character : text) {
    if (!session.character(character).handled) {
      throw std::runtime_error("A pinyin character was not handled.");
    }
  }
}

void require(bool condition, const char *message) {
  if (!condition) {
    throw std::runtime_error(message);
  }
}

void run_tests() {
  metasequoia::mac::CandidateSelectionState candidate_selection;

  metasequoia::Session unarmed_session(SessionTestOptions());
  type(unarmed_session, "nihao");
  const std::string leading_candidate =
      unarmed_session.snapshot().candidates.front().word;
  candidate_selection.update(1, unarmed_session.snapshot().candidates[1].word);
  const auto unarmed = candidate_selection.commit(unarmed_session);
  require(unarmed.handled && unarmed.commit == leading_candidate,
          "An unsolicited panel callback replaced the leading candidate.");

  metasequoia::Session highlighted_session(SessionTestOptions());
  type(highlighted_session, "nihao");
  const std::string highlighted_candidate =
      highlighted_session.snapshot().candidates[1].word;
  candidate_selection.begin_navigation();
  candidate_selection.update(1, highlighted_candidate);
  require(candidate_selection.selected_index() == 1,
          "The highlighted engine index was not available for a display-only refresh.");
  const auto highlighted = candidate_selection.commit(highlighted_session);
  require(
      highlighted.handled && highlighted.commit == highlighted_candidate,
      "Space did not commit the candidate highlighted by the native panel.");

  metasequoia::Session reset_session(SessionTestOptions());
  type(reset_session, "nihao");
  const std::string reset_leading_candidate =
      reset_session.snapshot().candidates.front().word;
  candidate_selection.begin_navigation();
  candidate_selection.update(1, reset_session.snapshot().candidates[1].word);
  candidate_selection.reset();
  require(!candidate_selection.selected_index().has_value(),
          "Reset retained a stale engine index.");
  const auto reset = candidate_selection.commit(reset_session);
  require(
      reset.handled && reset.commit == reset_leading_candidate,
      "Clearing the native highlight did not restore the leading candidate.");

  metasequoia::Session stale_session(SessionTestOptions());
  type(stale_session, "nihao");
  const std::string stale_fallback = stale_session.snapshot().candidates.front().word;
  candidate_selection.begin_navigation();
  candidate_selection.update(1, "candidate-from-an-old-composition");
  const auto stale = candidate_selection.commit(stale_session);
  require(
      stale.handled && stale.commit == stale_fallback,
      "A stale native highlight did not fall back to the leading candidate.");

  // Every automatic commit — losing focus, a modifier, a key the session does not take — finishes
  // the composition, and it has to finish it from the candidate the user arrowed onto rather than
  // from the engine's own first one.
  metasequoia::Session flush_session(SessionTestOptions());
  type(flush_session, "nihao");
  const std::string flush_highlighted = flush_session.snapshot().candidates[1].word;
  candidate_selection.begin_navigation();
  candidate_selection.update(1, flush_highlighted);
  require(candidate_selection.live_selected_index(flush_session.snapshot()) == 1,
          "A live highlight was not offered to the automatic commit.");
  const auto flushed = flush_session.finish(
      candidate_selection.live_selected_index(flush_session.snapshot()).value_or(0));
  require(flushed.handled && flushed.commit == flush_highlighted,
          "An automatic commit discarded the highlighted candidate.");

  // With nothing highlighted, and with a highlight that no longer names the same word, the index
  // has to come back empty so the automatic commit keeps its previous behaviour.
  metasequoia::Session flush_default_session(SessionTestOptions());
  type(flush_default_session, "nihao");
  const std::string flush_default_leading =
      flush_default_session.snapshot().candidates.front().word;
  candidate_selection.reset();
  require(!candidate_selection.live_selected_index(flush_default_session.snapshot()).has_value(),
          "A cleared highlight still offered an index to the automatic commit.");
  candidate_selection.begin_navigation();
  candidate_selection.update(1, "candidate-from-an-old-composition");
  require(!candidate_selection.live_selected_index(flush_default_session.snapshot()).has_value(),
          "A stale highlight still offered an index to the automatic commit.");
  const auto flushed_default = flush_default_session.finish(
      candidate_selection.live_selected_index(flush_default_session.snapshot()).value_or(0));
  require(flushed_default.handled && flushed_default.commit == flush_default_leading,
          "An automatic commit without a highlight did not take the leading candidate.");

  metasequoia::Session paged_session(SessionTestOptions());
  type(paged_session, "nihao");
  require(paged_session.snapshot().candidates.size() >= 11,
          "The paging fixture did not return enough candidates.");
  const std::string second_page_candidate = paged_session.snapshot().candidates[9].word;
  candidate_selection.begin_navigation();
  candidate_selection.update(9, second_page_candidate);
  const auto unavailable_digit =
      candidate_selection.commit_number(paged_session, '9');
  require(!unavailable_digit.handled && (!paged_session.snapshot().preedit.empty()),
          "An unavailable number on the current page changed composition.");
  const auto page_digit = candidate_selection.commit_number(paged_session, '1');
  require(page_digit.handled && page_digit.commit == second_page_candidate,
          "The 1 key did not commit the first candidate on the visible page.");

  metasequoia::Session compact_page_session(SessionTestOptions());
  type(compact_page_session, "nihao");
  const std::string compact_page_candidate =
      compact_page_session.snapshot().candidates[5].word;
  candidate_selection.begin_navigation();
  candidate_selection.update(5, compact_page_candidate);
  const auto compact_page_digit =
      candidate_selection.commit_number(compact_page_session, '1', 5);
  require(compact_page_digit.handled &&
              compact_page_digit.commit == compact_page_candidate,
          "The configured five-candidate page boundary was ignored.");
}
} // namespace

int main() {
  const auto suffix = std::to_string(
      std::chrono::high_resolution_clock::now().time_since_epoch().count());
  const std::filesystem::path data_directory =
      std::filesystem::temp_directory_path() /
      std::filesystem::u8path("metasequoia-mac-selection-" + suffix);
  std::filesystem::create_directories(data_directory);
  if (setenv("METASEQUOIA_IME_DATA_DIR",
             metasequoia::path_to_utf8(data_directory).c_str(), 1) != 0) {
    throw std::runtime_error("Failed to set the test data directory.");
  }

  try {
    {
      Database database(data_directory / "msime.db");
      database.execute("CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, "
                       "weight INTEGER)");
      database.execute("INSERT INTO tbl_2_n VALUES"
                       "('ni''hao', 'nh', '候选一', 110),"
                       "('ni''hao', 'nh', '候选二', 100),"
                       "('ni''hao', 'nh', '候选三', 90),"
                       "('ni''hao', 'nh', '候选四', 80),"
                       "('ni''hao', 'nh', '候选五', 70),"
                       "('ni''hao', 'nh', '候选六', 60),"
                       "('ni''hao', 'nh', '候选七', 50),"
                       "('ni''hao', 'nh', '候选八', 40),"
                       "('ni''hao', 'nh', '候选九', 30),"
                       "('ni''hao', 'nh', '候选十', 20),"
                       "('ni''hao', 'nh', '候选十一', 10)");
      run_tests();
    }
    user_dictionary::close_default_user_database();
    std::filesystem::remove_all(data_directory);
  } catch (...) {
    user_dictionary::close_default_user_database();
    std::filesystem::remove_all(data_directory);
    throw;
  }
  return 0;
}
