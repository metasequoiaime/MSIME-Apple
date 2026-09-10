#include "ClipboardHistory.h"
#include "ClipboardPresentation.h"
#include <iostream>
#include <random>
#include <stdexcept>

namespace {
void require(bool value) {
  if (!value) throw std::runtime_error("Clipboard linkage regression failed");
}
struct TemporaryStore {
  std::filesystem::path directory;
  TemporaryStore() {
    std::random_device random;
    for (unsigned attempt = 0; attempt < 100; ++attempt) {
      auto candidate = std::filesystem::temp_directory_path() /
          ("msime-clipboard-link-" + std::to_string(random()));
      if (std::filesystem::create_directory(candidate)) {
        directory = std::move(candidate);
        return;
      }
    }
    throw std::runtime_error("Temporary fixture unavailable");
  }
  ~TemporaryStore() {
    std::error_code error;
    std::filesystem::remove(directory / "history.json", error);
    std::filesystem::remove(directory, error);
  }
};
}
int main() {
  try {
    TemporaryStore temporary;
    msime::windows::ClipboardHistory history(temporary.directory / "history.json");
    msime::windows::ClipboardMailbox mailbox;
    // Exercise the same archive through both storage and presentation APIs.
    require(history.add("synthetic-alpha"));
    require(history.add("synthetic-beta"));
    mailbox.publish(history.enabled(), history.load());
    const auto initial = mailbox.snapshot();
    require(initial && initial->enabled && initial->items.size() == 2);
    require(history.remove("synthetic-beta"));
    mailbox.publish(history.enabled(), history.load());
    const auto removed = mailbox.snapshot();
    require(removed && removed->revision > initial->revision &&
            removed->items == std::vector<std::string>{"synthetic-alpha"});
    history.set_enabled(false);
    mailbox.publish(history.enabled(), history.load());
    const auto disabled = mailbox.snapshot();
    require(disabled && !disabled->enabled && disabled->items.empty());
    require(!history.add("synthetic-disabled"));
    mailbox.clear();
    require(!mailbox.snapshot());
    std::cout << "Clipboard storage/presentation linkage passed\n";
    return 0;
  } catch (...) {
    std::cerr << "Clipboard linkage regression failed\n";
    return 1;
  }
}
