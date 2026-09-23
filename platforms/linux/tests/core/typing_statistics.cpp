#include "../src/system/TypingStatistics.h"
#include "msime_client.h"

#include <sys/stat.h>
#include <unistd.h>

#include <cassert>
#include <cstdint>
#include <filesystem>
#include <string>
#include <string_view>

using msime::linux_host::PassthroughModifiers;
using msime::linux_host::resolve_typing_source;
using msime::linux_host::should_count_passthrough_character;
using msime::linux_host::typing_source_id;
using msime::linux_host::TypingSource;
using msime::linux_host::TypingStatisticsSwitch;

namespace {

int queries = 0;
int32_t counted_query(const uint8_t *directory, std::size_t length) {
  ++queries;
  return msime_client_typing_statistics_enabled(directory, length);
}
int failed_queries = 0;
int32_t failing_query(const uint8_t *, std::size_t) {
  ++failed_queries;
  return -1;
}

std::string call(const std::string &directory, const std::string &action) {
  const auto request = "{\"directory\":\"" + directory + "\",\"action\":" + action + "}";
  char *raw = msime_client_typing_statistics(reinterpret_cast<const uint8_t *>(request.data()), request.size());
  assert(raw);
  std::string result(raw);
  msime_client_string_free(raw);
  return result;
}

// What the settings page's switch does to the shared store.
void set_enabled(const std::string &directory, bool enabled) {
  const auto result = call(directory, std::string("{\"operation\":\"set_enabled\",\"enabled\":") +
                                          (enabled ? "true" : "false") + "}");
  assert(result.find(enabled ? "\"enabled\":true" : "\"enabled\":false") != std::string::npos);
}

struct FileIdentity {
  ino_t inode = 0;
  timespec modified{};
  bool operator==(const FileIdentity &other) const {
    return inode == other.inode && modified.tv_sec == other.modified.tv_sec &&
           modified.tv_nsec == other.modified.tv_nsec;
  }
};
FileIdentity identity(const std::string &path) {
  struct stat info {};
  const int status = ::stat(path.c_str(), &info);
  assert(status == 0);
  (void)status;
  return {info.st_ino, info.st_mtim};
}

void switch_follows_the_store() {
  const auto root = std::filesystem::temp_directory_path() /
                    ("msime-linux-typing-statistics-" + std::to_string(::getpid()));
  std::filesystem::remove_all(root);
  std::filesystem::create_directories(root);
  const auto directory = root.string();
  const auto document = (root / "typing-statistics.json").string();

  TypingStatisticsSwitch statistics{counted_query};
  // Off until the store has been read: nothing is recorded on a guess.
  assert(!statistics.enabled());
  // A host without an absolute preferences directory has no store to ask.
  statistics.refresh("");
  statistics.refresh("relative/directory");
  assert(!statistics.enabled());
  assert(queries == 0);

  // A fresh profile: no document yet, and the store ships statistics off.
  statistics.refresh(directory);
  assert(queries == 1);
  assert(!statistics.enabled());
  statistics.refresh(directory);
  assert(queries == 1);
  assert(!std::filesystem::exists(document));

  // Statistics turned off explicitly. The host's capture gate stays shut, and preference ticks while it is off only stat the document: it is neither read again nor written.
  set_enabled(directory, false);
  const auto off = identity(document);
  statistics.refresh(directory);
  assert(queries == 2);
  assert(!statistics.enabled());
  for (int tick = 0; tick < 5; ++tick)
    statistics.refresh(directory);
  assert(queries == 2);
  assert(!statistics.enabled());
  assert(identity(document) == off);

  // Turned on in the settings: the next preference tick sees the rewritten document and opens the gate. That the hosts then record commits, and record none while it is shut, is checked end to end in fcitx5/tests/native.cpp; this test only covers the switch.
  set_enabled(directory, true);
  assert(!statistics.enabled());
  statistics.refresh(directory);
  assert(queries == 3);
  assert(statistics.enabled());
  // Any store write replaces the document, a recorded commit included; this one goes straight to the store only to change the document's identity, and the tick after it reads it again and stays on.
  const auto recorded = call(directory, "{\"operation\":\"record\",\"text\":\"输入法\",\"source\":\"quanpin\",\"day\":\"2026-09-23\",\"hour\":10}");
  assert(recorded.find("\"recorded\":3") != std::string::npos);
  statistics.refresh(directory);
  assert(queries == 4);
  assert(statistics.enabled());
  statistics.refresh(directory);
  assert(queries == 4);

  // Turned off again: the next tick shuts the gate.
  set_enabled(directory, false);
  statistics.refresh(directory);
  assert(queries == 5);
  assert(!statistics.enabled());

  // Moving to another store always asks it, even when both documents happen to look alike.
  const auto other = (root / "other").string();
  statistics.refresh(other);
  assert(queries == 6);
  assert(!statistics.enabled());

  // A store that cannot be read keeps the gate shut and is asked again on the next tick instead of being trusted as unchanged.
  TypingStatisticsSwitch unreadable{failing_query};
  unreadable.refresh(directory);
  unreadable.refresh(directory);
  assert(failed_queries == 2);
  assert(!unreadable.enabled());

  std::filesystem::remove_all(root);
}

} // namespace

int main() {
  assert(resolve_typing_source(0, false, false, "none", "xiaohe") ==
         TypingSource::Quanpin);
  assert(resolve_typing_source(0, true, false, "none", "xiaohe") ==
         TypingSource::NineKey);
  assert(resolve_typing_source(1, false, false, "none", "xiaohe") ==
         TypingSource::Shuangpin);
  assert(resolve_typing_source(1, false, false, "none", "ziranma") ==
         TypingSource::Ziranma);
  assert(resolve_typing_source(1, false, false, "none", "microsoft") ==
         TypingSource::Microsoft);
  assert(resolve_typing_source(1, false, false, "none", "shoudao") ==
         TypingSource::Shoudao);
  assert(resolve_typing_source(2, false, false, "none", "xiaohe") ==
         TypingSource::Wubi);
  assert(resolve_typing_source(3, false, false, "none", "xiaohe") ==
         TypingSource::Japanese);
  assert(resolve_typing_source(0, false, true, "none", "xiaohe") ==
         TypingSource::English);
  assert(resolve_typing_source(0, false, false, "temporary_japanese",
                               "xiaohe") == TypingSource::Japanese);
  assert(resolve_typing_source(0, false, false, "emoji", "xiaohe") ==
         TypingSource::Local);
  assert(resolve_typing_source(99, false, false, "none", "xiaohe") ==
         TypingSource::Unknown);
  assert(typing_source_id(TypingSource::NineKey) ==
         std::string_view("nineKey"));
  assert(typing_source_id(TypingSource::Voice) == std::string_view("voice"));

  // Passthrough keys count as typed text only when they are printable and no shortcut modifier is held; Shift picks a character and does not make a shortcut.
  assert(should_count_passthrough_character(U'a', {}));
  assert(should_count_passthrough_character(U' ', {}));
  assert(should_count_passthrough_character(U'~', {}));
  assert(should_count_passthrough_character(U'\u00e9', {}));
  assert(should_count_passthrough_character(U'\U0001F600', {}));
  assert(!should_count_passthrough_character(U'\t', {}));
  assert(!should_count_passthrough_character(U'\r', {}));
  assert(!should_count_passthrough_character(0x1b, {}));
  assert(!should_count_passthrough_character(0x7f, {}));
  assert(!should_count_passthrough_character(0, {}));
  assert(!should_count_passthrough_character(0xd800, {}));
  assert(!should_count_passthrough_character(0x110000, {}));
  PassthroughModifiers control;
  control.control = true;
  assert(!should_count_passthrough_character(U'c', control));
  PassthroughModifiers alt;
  alt.alt = true;
  assert(!should_count_passthrough_character(U'f', alt));
  PassthroughModifiers super;
  super.super = true;
  assert(!should_count_passthrough_character(U'l', super));
  PassthroughModifiers hyper;
  hyper.hyper = true;
  assert(!should_count_passthrough_character(U'h', hyper));
  PassthroughModifiers meta;
  meta.meta = true;
  assert(!should_count_passthrough_character(U'm', meta));

  switch_follows_the_store();
  return 0;
}
