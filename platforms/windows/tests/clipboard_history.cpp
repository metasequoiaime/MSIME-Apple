#include "ClipboardHistory.h"
#include <cassert>
#include <filesystem>
int main() {
  const auto path = std::filesystem::temp_directory_path() / "msime-clipboard-history-test.json";
  std::error_code error; std::filesystem::remove(path, error);
  msime::windows::ClipboardHistory history(path);
  assert(history.add(" first\r\nsecond \t\n"));
  assert(history.load().front() == " first\nsecond");
  assert(!history.add(" first\nsecond"));
  assert(history.add("second"));
  assert(history.remove("second"));
  assert(history.clear());
  assert(history.load().empty());
  std::filesystem::remove(path, error);
}
