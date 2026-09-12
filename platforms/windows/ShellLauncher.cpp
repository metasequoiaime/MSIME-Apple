#include "ShellLauncher.h"
#include <memory>
#include <windows.h>

namespace msime::windows {
bool launch_shell_surface(const std::filesystem::path &executable,
                          const ShellSurfaceRequest &request) {
  if (executable.empty() || !executable.is_absolute())
    return false;
  std::unique_ptr<wchar_t, decltype(&FreeEnvironmentStringsW)> inherited(
      GetEnvironmentStringsW(), FreeEnvironmentStringsW);
  if (!inherited)
    return false;
  auto environment = shell_environment_block(inherited.get(), request);
  // CreateProcessW may write to the command line buffer, so it owns a copy.
  std::wstring command_line = L"\"" + executable.wstring() + L"\"";
  STARTUPINFOW startup{};
  startup.cb = sizeof(startup);
  startup.dwFlags = STARTF_USESHOWWINDOW;
  startup.wShowWindow = SW_SHOWNORMAL;
  PROCESS_INFORMATION process{};
  const auto directory = executable.parent_path().wstring();
  if (!CreateProcessW(executable.c_str(), command_line.data(), nullptr, nullptr,
                      FALSE, CREATE_UNICODE_ENVIRONMENT | CREATE_NO_WINDOW,
                      environment.data(), directory.c_str(), &startup,
                      &process))
    return false;
  // The shell owns its own lifetime; this process only started it.
  CloseHandle(process.hThread);
  CloseHandle(process.hProcess);
  return true;
}
} // namespace msime::windows
