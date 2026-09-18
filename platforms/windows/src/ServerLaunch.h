#pragma once
#include <string>

namespace msime::windows {
// How the Server was asked to start. Keeping the decision in one pure function
// means the Watchdog contract is unit-testable without launching anything.
enum class ServerLaunchKind { Invalid, Help, Managed, Config };

struct ServerLaunch {
  ServerLaunchKind kind = ServerLaunchKind::Invalid;
  // Only meaningful for Config; Managed resolves its own state directory.
  std::wstring config;
};

// The Watchdog starts the Server with --watchdog-managed (Watchdog.cpp). It is
// the same request as --production: run against the installed state directory.
// Treating it as unknown made the supervised Server exit 2, which
// WatchdogPolicy reads as an unclean crash, so it restarted forever.
inline ServerLaunch parse_server_arguments(int argc, const wchar_t *const *argv) {
  if (argc == 2 && argv && argv[1]) {
    const std::wstring option(argv[1]);
    if (option == L"--help")
      return {ServerLaunchKind::Help, {}};
    if (option == L"--production" || option == L"--watchdog-managed")
      return {ServerLaunchKind::Managed, {}};
    return {};
  }
  if (argc == 3 && argv && argv[1] && argv[2] &&
      std::wstring(argv[1]) == L"--config")
    return {ServerLaunchKind::Config, std::wstring(argv[2])};
  return {};
}
} // namespace msime::windows
