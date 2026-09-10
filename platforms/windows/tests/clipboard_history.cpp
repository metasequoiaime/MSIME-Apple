#include "ClipboardHistory.h"
#include <cassert>
#include <filesystem>
#include <fstream>
#include <stdexcept>
namespace {
void require(bool value) { if (!value) throw std::runtime_error("clipboard history contract failed"); }
}
int main() {
  const auto directory = std::filesystem::temp_directory_path() / "msime-clipboard-history-test";
  const auto path = directory / "history.json";
  std::error_code error; std::filesystem::remove_all(directory, error);
  std::filesystem::create_directory(directory);
  msime::windows::ClipboardHistory history(path);
  require(history.add(" first\r\nsecond \t\n"));
  require(history.load().front() == " first\nsecond");
  require(!history.add(" first\nsecond"));
  require(history.add("second"));
  require(history.remove("second"));
  require(history.clear());
  require(history.load().empty());
  std::string oversized(5000, 'x'); oversized.insert(17, 1, '\0'); oversized += " \r\n";
  require(history.add(oversized));
  const auto normalized = history.load().front();
  require(normalized.size() == msime::windows::ClipboardHistory::max_chars);
  require(normalized.find('\0') == std::string::npos && normalized.back() == 'x');
  history.clear();
  for (size_t index = 0; index < msime::windows::ClipboardHistory::max_items + 10; ++index)
    require(history.add("item-" + std::to_string(index)));
  require(history.load().size() == msime::windows::ClipboardHistory::max_items);
  { std::ofstream output(path, std::ios::trunc); output << "not-json"; }
  require(history.load().empty());
  std::filesystem::remove_all(directory, error);
}
