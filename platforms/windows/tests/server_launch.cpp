#include "ServerLaunch.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace msime::windows;
namespace {
void require_at(bool value, int line) {
  if (!value)
    throw std::runtime_error("Server launch test failed at line " +
                             std::to_string(line));
}
ServerLaunch parse(std::initializer_list<const wchar_t *> arguments) {
  std::vector<const wchar_t *> argv{L"MetasequoiaImeServer.exe"};
  for (const auto *argument : arguments)
    argv.push_back(argument);
  return parse_server_arguments(static_cast<int>(argv.size()), argv.data());
}
} // namespace
#define require(...) require_at((__VA_ARGS__), __LINE__)

int main() {
  try {
    // The Watchdog starts the Server with this exact argument. Rejecting it made
    // the supervised Server exit 2, which WatchdogPolicy reads as an unclean
    // crash, so it restarted forever and never came up once.
    require(parse({L"--watchdog-managed"}).kind == ServerLaunchKind::Managed);
    // It is the same request as the documented production switch.
    require(parse({L"--production"}).kind == ServerLaunchKind::Managed);
    require(parse({L"--production"}).config.empty());

    require(parse({L"--help"}).kind == ServerLaunchKind::Help);

    const auto configured = parse({L"--config", L"C:\\state\\runtime.json"});
    require(configured.kind == ServerLaunchKind::Config);
    require(configured.config == L"C:\\state\\runtime.json");

    // Anything else stays invalid so an unknown option cannot silently start a
    // Server against the installed state directory.
    require(parse({}).kind == ServerLaunchKind::Invalid);
    require(parse({L"--managed"}).kind == ServerLaunchKind::Invalid);
    require(parse({L"--config"}).kind == ServerLaunchKind::Invalid);
    require(parse({L"--config", L"a", L"b"}).kind == ServerLaunchKind::Invalid);
    require(parse({L"--watchdog-managed", L"extra"}).kind ==
            ServerLaunchKind::Invalid);
    require(parse({L"--PRODUCTION"}).kind == ServerLaunchKind::Invalid);

    std::cout << "Server launch contract: watchdog and config forms accepted\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << "\n";
    return 1;
  }
}
