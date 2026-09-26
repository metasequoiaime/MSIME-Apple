#include "StateDirectory.h"
#include <iostream>
#include <stdexcept>

// The environment override is the one input a test can set without touching the machine: HKLM DataDir and the known folder are whatever this host has, so those cases only compare against the resolution without the override.
namespace {
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}
void set_override(const wchar_t *value) {
  require(SetEnvironmentVariableW(msime::windows::state_directory_environment_variable, value) != 0,
          "SetEnvironmentVariableW failed");
}
} // namespace

int main() {
  try {
    set_override(nullptr);
    const auto without_override = msime::windows::resolve_state_directory();
    require(without_override.empty() || without_override.is_absolute(),
            "The resolved root must be absolute");

    // An absolute override wins over DataDir and LocalAppData. Set through the process environment block, the way a launcher injects it, so this also covers the lookup not going through the CRT's copy.
    const std::filesystem::path configured = L"C:\\msime state\\override";
    set_override(configured.c_str());
    require(msime::windows::resolve_state_directory() == configured,
            "An absolute override must win");

    // A relative or empty override is ignored rather than resolved against the working directory.
    set_override(L"relative\\state");
    require(msime::windows::resolve_state_directory() == without_override,
            "A relative override must be ignored");
    set_override(L"");
    require(msime::windows::resolve_state_directory() == without_override,
            "An empty override must be ignored");

    set_override(nullptr);
    std::cout << "state directory tests passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
