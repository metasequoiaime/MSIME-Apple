#pragma once

#include <charconv>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <optional>
#include <string>
#include <string_view>
#include <unistd.h>

namespace msime::linux_host {

// The Windows installer stops the IME processes before it replaces their files and starts the new ones afterwards. dpkg (and `cmake --install`, and a relink in a build tree) instead renames a new file over the old path while the running process keeps executing the old inode, so after an upgrade the hosts would go on running the previous build indefinitely. The kernel marks such a file in /proc: the target of /proc/self/exe and the pathname of a /proc/self/maps entry gain this suffix once the path no longer names the file the process has open.
inline constexpr std::string_view kDeletedSuffix = " (deleted)";

enum class ProgramFileState {
  // The path still names the file the process runs, or the state could not be read.
  Current,
  // A new file sits at the original path: an upgrade or a rebuild. Restarting picks it up.
  Replaced,
  // Nothing (usable) sits at the original path any more: the package was removed. Restarting would fail, so a host must not restart itself into it.
  Removed,
};

// Classifies one /proc path. `access_mode` is what the replacement must allow for the restart to work: X_OK for an executable, F_OK for a mapped library.
inline ProgramFileState classify_proc_path(std::string_view proc_path, int access_mode) {
  if (proc_path.size() <= kDeletedSuffix.size() ||
      proc_path.substr(proc_path.size() - kDeletedSuffix.size()) != kDeletedSuffix)
    return ProgramFileState::Current;
  const std::string original(proc_path.substr(0, proc_path.size() - kDeletedSuffix.size()));
  return access(original.c_str(), access_mode) == 0 ? ProgramFileState::Replaced
                                                     : ProgramFileState::Removed;
}

// The state of the program this process was started from.
inline ProgramFileState running_executable_state() {
  char target[4096 + kDeletedSuffix.size()];
  const auto length = readlink("/proc/self/exe", target, sizeof target);
  if (length <= 0 || static_cast<size_t>(length) == sizeof target)
    return ProgramFileState::Current;
  return classify_proc_path(std::string_view(target, static_cast<size_t>(length)), X_OK);
}

// One /proc/<pid>/maps line is "start-end perms offset dev inode" followed, after padding, by the pathname, which may itself contain spaces. Returns the pathname when the mapping contains `address`; an anonymous mapping yields an empty pathname.
inline std::optional<std::string_view> maps_line_path(std::string_view line, std::uintptr_t address) {
  const auto dash = line.find('-');
  const auto space = line.find(' ');
  if (dash == std::string_view::npos || space == std::string_view::npos || dash > space)
    return std::nullopt;
  std::uintptr_t start = 0, end = 0;
  if (std::from_chars(line.data(), line.data() + dash, start, 16).ptr != line.data() + dash ||
      std::from_chars(line.data() + dash + 1, line.data() + space, end, 16).ptr != line.data() + space)
    return std::nullopt;
  if (address < start || address >= end)
    return std::nullopt;
  // Skip the range and the four fixed fields after it.
  auto position = space;
  for (int field = 0; field < 4; ++field) {
    position = line.find_first_not_of(' ', position);
    if (position == std::string_view::npos)
      return std::nullopt;
    position = line.find(' ', position);
    if (position == std::string_view::npos)
      return std::string_view{};
  }
  position = line.find_first_not_of(' ', position);
  if (position == std::string_view::npos)
    return std::string_view{};
  auto path = line.substr(position);
  if (!path.empty() && path.back() == '\n')
    path.remove_suffix(1);
  return path;
}

// The state of the file mapped at `address` in this process, which for an address inside a shared library is that library. Scans /proc/self/maps rather than asking dladdr for the name, because the kernel reports the replacement against the path it resolved, which need not be the one the loader was given.
inline ProgramFileState mapped_file_state(const void *address) {
  FILE *maps = std::fopen("/proc/self/maps", "re");
  if (!maps)
    return ProgramFileState::Current;
  char *line = nullptr;
  size_t capacity = 0;
  ssize_t length;
  auto state = ProgramFileState::Current;
  const auto target = reinterpret_cast<std::uintptr_t>(address);
  while ((length = getline(&line, &capacity, maps)) > 0) {
    if (const auto path = maps_line_path(std::string_view(line, static_cast<size_t>(length)), target)) {
      if (!path->empty() && path->front() == '/')
        state = classify_proc_path(*path, F_OK);
      break;
    }
  }
  std::free(line);
  std::fclose(maps);
  return state;
}

}  // namespace msime::linux_host
