#include "TypingStatistics.h"
#include <iostream>
#include <stdexcept>

using namespace msime::windows;
using Json = nlohmann::json;
namespace {
void require(bool value) {
  if (!value)
    throw std::runtime_error("Windows typing statistics assertion failed");
}
Json transition(int scheme, const char *local_mode, bool dedicated_english,
                const char *shuangpin_profile, Json commit_context = nullptr) {
  return {{"commit", "你好"},
          {"commit_context", std::move(commit_context)},
          {"view",
           {{"scheme", scheme},
            {"nine_key", false},
            {"dedicated_english", dedicated_english},
            {"local_mode", local_mode},
            {"shuangpin_profile", shuangpin_profile}}}};
}
} // namespace
int main() {
  try {
    // Same mapping as the Linux and Apple hosts: they write the same document,
    // so a source identifier that differs here would split one user's history
    // across two buckets.
    require(resolve_typing_source(0, false, false, "none", "xiaohe") ==
            TypingSource::Quanpin);
    require(resolve_typing_source(0, true, false, "none", "xiaohe") ==
            TypingSource::NineKey);
    require(resolve_typing_source(1, false, false, "none", "xiaohe") ==
            TypingSource::Shuangpin);
    require(resolve_typing_source(1, false, false, "none", "ziranma") ==
            TypingSource::Ziranma);
    require(resolve_typing_source(1, false, false, "none", "microsoft") ==
            TypingSource::Microsoft);
    require(resolve_typing_source(1, false, false, "none", "shoudao") ==
            TypingSource::Shoudao);
    require(resolve_typing_source(2, false, false, "none", "xiaohe") ==
            TypingSource::Wubi);
    require(resolve_typing_source(3, false, false, "none", "xiaohe") ==
            TypingSource::Japanese);
    require(resolve_typing_source(-1, false, false, "none", "xiaohe") ==
            TypingSource::Unknown);
    // Local modes outrank the keyboard scheme, and the temporary Japanese mode
    // is reported as Japanese rather than as a generic local mode.
    require(resolve_typing_source(0, false, false, "emoji", "xiaohe") ==
            TypingSource::Local);
    require(resolve_typing_source(0, false, false, "temporary_japanese",
                                  "xiaohe") == TypingSource::Japanese);
    require(resolve_typing_source(0, false, false, "", "xiaohe") ==
            TypingSource::Quanpin);
    // Dedicated English loses to a local mode and wins over the scheme.
    require(resolve_typing_source(0, false, true, "none", "xiaohe") ==
            TypingSource::English);
    require(resolve_typing_source(0, false, true, "emoji", "xiaohe") ==
            TypingSource::Local);
    require(typing_source_id(TypingSource::NineKey) == "nineKey");
    require(typing_source_id(TypingSource::Unknown) == "unknown");

    // Attribution follows the mode in force when the key was dispatched.
    // Committing an Emoji-mode candidate clears the local mode, so the
    // post-commit view alone would file it under quanpin.
    require(resolve_typing_source_from_transition(
                transition(0, "none", false, "xiaohe",
                           Json{{"scheme", 0}, {"local_mode", "emoji"}})) ==
            TypingSource::Local);
    // Without a commit context the view is all there is.
    require(resolve_typing_source_from_transition(
                transition(2, "none", false, "xiaohe")) == TypingSource::Wubi);
    require(resolve_typing_source_from_transition(
                transition(1, "none", false, "ziranma")) ==
            TypingSource::Ziranma);
    // A transition missing the fields entirely must not throw on the input
    // path; an unknown bucket is the honest answer.
    require(resolve_typing_source_from_transition(Json::object()) ==
            TypingSource::Unknown);

    const auto local = local_time_parts(0);
    require(local.has_value());
    require(local->day.size() == 10 && local->day[4] == '-' &&
            local->day[7] == '-');
    require(local->hour >= 0 && local->hour <= 23);

    const auto request =
        typing_statistics_record_request("C:\\Users\\ime\\state", "你好",
                                         TypingSource::Quanpin, "2026-09-21", 9);
    const auto parsed = Json::parse(request);
    require(parsed.at("directory") == "C:\\Users\\ime\\state");
    require(parsed.at("action").at("operation") == "record");
    require(parsed.at("action").at("text") == "你好");
    require(parsed.at("action").at("source") == "quanpin");
    require(parsed.at("action").at("day") == "2026-09-21");
    require(parsed.at("action").at("hour") == 9);
    // Nothing usable in, nothing out: a record with no text, no home, or no
    // resolvable day or hour would have to invent one of them.
    require(typing_statistics_record_request("C:\\state", "", TypingSource::Ai,
                                             "2026-09-21", 0)
                .empty());
    require(typing_statistics_record_request("", "你好", TypingSource::Ai,
                                             "2026-09-21", 0)
                .empty());
    require(typing_statistics_record_request("C:\\state", "你好",
                                             TypingSource::Ai, "", 0)
                .empty());
    // Both ends of the hour range, so an off-by-one on either bound shows up.
    require(!typing_statistics_record_request("C:\\state", "你好",
                                              TypingSource::Ai, "2026-09-21", 0)
                 .empty());
    require(!typing_statistics_record_request("C:\\state", "你好",
                                              TypingSource::Ai, "2026-09-21", 23)
                 .empty());
    require(typing_statistics_record_request("C:\\state", "你好",
                                             TypingSource::Ai, "2026-09-21", 24)
                .empty());
    require(typing_statistics_record_request("C:\\state", "你好",
                                             TypingSource::Ai, "2026-09-21", -1)
                .empty());
    // The shared entry point refuses buffers past 64 KiB, so an oversized
    // commit is dropped whole rather than counted as a shorter one.
    require(typing_statistics_record_request("C:\\state",
                                             std::string(70'000, 'a'),
                                             TypingSource::Reply, "2026-09-21", 9)
                .empty());
    std::cout << "Windows typing statistics checks passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
