#pragma once
#include "PrepareHost.h"

namespace msime::windows {
// Called only after acquiring the production single-instance guard and before
// StateRootLease (which would itself create the directory). An existing state,
// even incomplete or invalid, belongs to the user and is never rebuilt here.
inline bool prepare_first_run(
    const std::filesystem::path &executable,
    const std::filesystem::path &state,
    const std::function<std::string(const std::string &)> &prepare) {
  if (!state.is_absolute())
    throw std::runtime_error("Production state directory unavailable");
  const auto status = std::filesystem::symlink_status(state);
  if (status.type() != std::filesystem::file_type::not_found)
    return false;
  if (!executable.is_absolute())
    throw std::runtime_error("Installed resource directory unavailable");
  prepare_host_state(executable / "resources", state, prepare);
  return true;
}
} // namespace msime::windows
