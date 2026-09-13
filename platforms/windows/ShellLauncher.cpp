#include "ShellLauncher.h"
#include <memory>
#include <windows.h>

namespace msime::windows {
namespace {
bool launch_shell_surface_impl(const std::filesystem::path &executable,
                               const ShellSurfaceRequest &request,
                               const ShellLaunchContext *context) {
  if (executable.empty() || !executable.is_absolute())
    return false;
  std::unique_ptr<wchar_t, decltype(&FreeEnvironmentStringsW)> inherited(
      GetEnvironmentStringsW(), FreeEnvironmentStringsW);
  if (!inherited)
    return false;
  std::wstring environment;
  try {
    environment = shell_environment_block(inherited.get(), request, context);
  } catch (const std::invalid_argument &) {
    return false;
  }
  // CreateProcessW may write to the command line buffer, so it owns a copy.
  std::wstring command_line = L"\"" + executable.wstring() + L"\" --route=";
  try {
    command_line += shell_route_argument(request);
  } catch (const std::invalid_argument &) {
    return false;
  }
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
} // namespace

bool launch_shell_surface(const std::filesystem::path &executable,
                          const ShellSurfaceRequest &request) {
  return launch_shell_surface_impl(executable, request, nullptr);
}

bool launch_shell_surface(const std::filesystem::path &executable,
                          const ShellSurfaceRequest &request,
                          const ShellLaunchContext &context) {
  return launch_shell_surface_impl(executable, request, &context);
}
} // namespace msime::windows
