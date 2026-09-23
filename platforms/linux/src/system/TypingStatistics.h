#pragma once

#include <sys/stat.h>

#include <atomic>
#include <cerrno>
#include <cstddef>
#include <cstdint>
#include <mutex>
#include <string>
#include <string_view>

namespace msime::linux_host {

enum class TypingSource {
  Quanpin,
  NineKey,
  Shuangpin,
  Ziranma,
  Microsoft,
  Shoudao,
  Wubi,
  Japanese,
  Handwriting,
  English,
  Local,
  Ai,
  Reply,
  Voice,
  Unknown,
};

constexpr std::string_view typing_source_id(TypingSource source) {
  switch (source) {
  case TypingSource::Quanpin:
    return "quanpin";
  case TypingSource::NineKey:
    return "nineKey";
  case TypingSource::Shuangpin:
    return "shuangpin";
  case TypingSource::Ziranma:
    return "ziranma";
  case TypingSource::Microsoft:
    return "microsoft";
  case TypingSource::Shoudao:
    return "shoudao";
  case TypingSource::Wubi:
    return "wubi";
  case TypingSource::Japanese:
    return "japanese";
  case TypingSource::Handwriting:
    return "handwriting";
  case TypingSource::English:
    return "english";
  case TypingSource::Local:
    return "local";
  case TypingSource::Ai:
    return "ai";
  case TypingSource::Reply:
    return "reply";
  case TypingSource::Voice:
    return "voice";
  case TypingSource::Unknown:
    return "unknown";
  }
  return "unknown";
}

// The shared Engine exposes numeric schemes in its View: 0 quanpin, 1
// shuangpin, 2 wubi, and 3 Japanese. Local modes take precedence over the
// keyboard scheme, matching the Android and Apple hosts.
constexpr TypingSource
resolve_typing_source(int scheme, bool nine_key, bool dedicated_english,
                      std::string_view local_mode,
                      std::string_view shuangpin_profile) {
  if (local_mode == "temporary_japanese")
    return TypingSource::Japanese;
  if (!local_mode.empty() && local_mode != "none")
    return TypingSource::Local;
  if (dedicated_english)
    return TypingSource::English;
  switch (scheme) {
  case 0:
    return nine_key ? TypingSource::NineKey : TypingSource::Quanpin;
  case 1:
    if (shuangpin_profile == "ziranma")
      return TypingSource::Ziranma;
    if (shuangpin_profile == "microsoft")
      return TypingSource::Microsoft;
    if (shuangpin_profile == "shoudao")
      return TypingSource::Shoudao;
    return TypingSource::Shuangpin;
  case 2:
    return TypingSource::Wubi;
  case 3:
    return TypingSource::Japanese;
  default:
    return TypingSource::Unknown;
  }
}

// Modifiers that turn a key press into a shortcut rather than typed text. Shift and the level-3/level-5 shifts are deliberately absent: they select which character a key produces, so a character typed with them is still text.
struct PassthroughModifiers {
  bool control = false;
  bool alt = false;
  bool super = false;
  bool hyper = false;
  bool meta = false;
};

// Whether a key the IME handed back to the application still counts as a typed character. Mirrors the Windows ShouldCountPassthroughChar rule: no shortcut modifier held, and a printable scalar value - no C0 control, no DEL, no surrogate, nothing past U+10FFFF. The caller has already ruled out releases, keys the IME consumed, and blocked or private contexts.
constexpr bool should_count_passthrough_character(char32_t character,
                                                  PassthroughModifiers held) {
  if (held.control || held.alt || held.super || held.hyper || held.meta)
    return false;
  if (character < 0x20 || character == 0x7f || character > 0x10ffff)
    return false;
  return character < 0xd800 || character > 0xdfff;
}

// The typing-statistics master switch, cached so that an opt-out stops at the capture boundary: with statistics off a commit formats no date, serializes no request, starts no worker and never takes the store's lock or reads its file. This matches the Windows server, which keeps the switch in an atomic loaded with its configuration, and the macOS host, which caches the same FFI answer.
//
// Hosts refresh it at startup and on every preference reload tick. The switch lives in the statistics document rather than in the preferences, so a tick cannot learn about a change from the preference revision; instead it compares the document's identity (directory, device, inode, size, modification time) with the one it last read, and only asks the store again when that changed. An idle tick costs one stat. The store replaces the document by rename on every write, so turning statistics on or off in the settings always changes that identity.
//
// Until a read succeeds the switch is off, the privacy-preserving default the macOS host uses too. Commits made between turning statistics on and the next tick are not recorded.
class TypingStatisticsSwitch {
public:
  // msime_client_typing_statistics_enabled in the hosts: 1 on, 0 off, negative when the store cannot be read.
  using Query = int32_t (*)(const uint8_t *directory, std::size_t length);

  explicit TypingStatisticsSwitch(Query query) : query_(query) {}

  bool enabled() const { return enabled_.load(std::memory_order_relaxed); }

  // Safe to call from any thread. Hosts call it from their preference workers, so a read that waits on the store's lock while another commit is being written never stalls the event loop.
  void refresh(const std::string &directory) {
    std::lock_guard<std::mutex> guard(mutex_);
    Identity next;
    next.directory = directory;
    // The same bound and absolute-path rule the FFI enforces; anything else cannot hold statistics.
    if (directory.empty() || directory.front() != '/' || directory.size() > 16384) {
      enabled_.store(false, std::memory_order_relaxed);
      read_ = false;
      return;
    }
    struct stat info {};
    if (::stat((directory + "/typing-statistics.json").c_str(), &info) == 0) {
      next.device = static_cast<uint64_t>(info.st_dev);
      next.inode = static_cast<uint64_t>(info.st_ino);
      next.size = static_cast<int64_t>(info.st_size);
      next.modified_seconds = static_cast<int64_t>(info.st_mtim.tv_sec);
      next.modified_nanoseconds = static_cast<int64_t>(info.st_mtim.tv_nsec);
    } else {
      next.error = errno;
    }
    if (read_ && next == identity_)
      return;
    const int32_t answer = query_(reinterpret_cast<const uint8_t *>(directory.data()), directory.size());
    enabled_.store(answer == 1, std::memory_order_relaxed);
    // A failed read stays off but is not remembered, so the next tick asks again instead of trusting a document that did not change.
    read_ = answer >= 0;
    identity_ = std::move(next);
  }

private:
  struct Identity {
    std::string directory;
    int error = 0;
    uint64_t device = 0;
    uint64_t inode = 0;
    int64_t size = 0;
    int64_t modified_seconds = 0;
    int64_t modified_nanoseconds = 0;
    bool operator==(const Identity &other) const {
      return directory == other.directory && error == other.error && device == other.device &&
             inode == other.inode && size == other.size && modified_seconds == other.modified_seconds &&
             modified_nanoseconds == other.modified_nanoseconds;
    }
  };

  Query query_;
  std::atomic_bool enabled_{false};
  std::mutex mutex_;
  Identity identity_;
  bool read_ = false;
};

} // namespace msime::linux_host
