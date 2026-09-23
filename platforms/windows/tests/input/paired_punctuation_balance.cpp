// With candidates open the Server's Engine resolves '<' and counts the book-title nesting. When the TSF auto-closes that pair the closing key never reaches the Server, so the TSF sends PairedPunctuationAutoClosed and the Server pays the count back; without it every following book title degrades into 〈〉. Run against a real Engine session.
#include "ipc/ServerSession.h"
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>
using namespace msime::windows;

namespace {
void require(bool value, const char *what) {
  if (!value) {
    std::fprintf(stderr, "FAIL: %s\n", what);
    std::exit(EXIT_FAILURE);
  }
}
} // namespace

int main() {
  const auto root = std::filesystem::temp_directory_path() /
                    ("msime-paired-balance-" +
                     std::to_string(std::chrono::steady_clock::now().time_since_epoch().count()));
  std::filesystem::create_directory(root);
  struct Cleanup {
    std::filesystem::path root;
    ~Cleanup() {
      std::error_code ec;
      std::filesystem::remove_all(root, ec);
    }
  } cleanup{root};
  nlohmann::json options{{"api_version", 1},
                         {"preferences",
                          {{"scheme", "quanpin"},
                           {"learning", false},
                           {"candidate_page_size", 5},
                           {"chinese_punctuation", true},
                           {"paired_punctuation", true}}}};
  for (const char *name : {"resources", "user_data", "cache", "dictionaries"}) {
    const auto directory = root / name;
    std::filesystem::create_directories(directory);
    options[name] = directory.string();
  }

  constexpr uint64_t epoch = 1;
  ServerSession session(42, options.dump());
  session.activate(epoch);
  uint64_t request = 0;
  auto opening = [&] {
    FanyImeNamedpipeData packet{};
    packet.client_id = 42;
    packet.event_type = FanyImePipeEventType::KeyEvent;
    packet.request_id = ++request;
    packet.keycode = 0xBC;
    packet.wch = static_cast<FanyImeWireChar>('<');
    packet.modifiers_down = 1;
    const auto commit = session.punctuation(packet, epoch).transition.at("commit");
    return commit.is_string() ? commit.get<std::string>() : std::string{};
  };

  require(opening() == "《", "the first '<' did not open a book title");
  session.balance_paired_punctuation(epoch, '<');
  require(opening() == "《", "a balanced auto-close still nested the next book title");
  // The unbalanced case is what the TSF used to leave behind, and it is what makes the check above mean something.
  require(opening() == "〈", "an unbalanced opening did not nest");
  session.balance_paired_punctuation(epoch, '<');
  session.balance_paired_punctuation(epoch, '<');
  // Paying back more than was opened is harmless: the count stops at zero.
  session.balance_paired_punctuation(epoch, '<');
  require(opening() == "《", "balancing past zero changed the next book title");

  bool rejected = false;
  try {
    session.balance_paired_punctuation(epoch, '(');
  } catch (const std::exception &) {
    rejected = true;
  }
  require(rejected, "a paired punctuation without nesting was accepted");
  return EXIT_SUCCESS;
}
