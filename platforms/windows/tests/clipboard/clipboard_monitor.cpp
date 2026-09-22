#include "ClipboardHistory.h"

#ifdef _WIN32
#include <windows.h>
#endif

#include <filesystem>
#include <iostream>

int main() {
#ifndef _WIN32
  std::cout << "Clipboard monitor requires Windows\n";
  return 0;
#else
  using msime::windows::ClipboardHistory;
  using msime::windows::ClipboardMonitor;
  ClipboardHistory history(std::filesystem::temp_directory_path() /
                           "msime-clipboard-monitor-native-test.json");
  int callbacks = 0;
  ClipboardMonitor monitor(history, [&](std::string) { ++callbacks; });

  if (!monitor.start() || !monitor.start()) {
    std::cerr << "ClipboardMonitor::start did not register a listener\n";
    return 1;
  }

  MSG message{};
  while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
    TranslateMessage(&message);
    DispatchMessageW(&message);
  }

  monitor.stop();
  monitor.stop();
  if (callbacks != 0) {
    std::cerr << "unexpected clipboard callback during registration test\n";
    return 1;
  }

  std::cout << "Clipboard monitor registration and idempotent shutdown passed\n";
  return 0;
#endif
}
