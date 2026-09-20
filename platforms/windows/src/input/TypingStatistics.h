#pragma once
#include <ctime>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <string_view>

namespace msime::windows {
// Private aggregate typing statistics for the Windows Server.
//
// The Server is the only process that sees every committed string, so it is
// where the shared store is fed from. Nothing here retains text: the string is
// handed straight to `msime_client_typing_statistics`, which classifies it in
// memory and persists counts only. Same enum and identifiers as the Linux and
// macOS hosts, because they all write the same document.
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
// keyboard scheme, matching the Android, Apple and Linux hosts.
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

// Attribute a commit to the mode that produced it, not to the mode left behind.
// Committing can clear a local mode, so `commit_context` - the Engine's own
// record of the scheme and local mode in force when the key was dispatched - is
// authoritative for those two fields; an Emoji-mode commit read off the
// post-commit view would otherwise be counted as quanpin. The remaining fields
// have no pre-dispatch counterpart and come from the view.
inline TypingSource
resolve_typing_source_from_transition(const nlohmann::json &transition) {
  static const nlohmann::json empty = nlohmann::json::object();
  // By reference throughout: this runs on the input queue, and value() would
  // deep-copy the candidate list hanging off the view on every commit.
  const auto view_field = transition.find("view");
  const nlohmann::json &view =
      view_field != transition.end() && view_field->is_object() ? *view_field
                                                                : empty;
  const auto context_field = transition.find("commit_context");
  const nlohmann::json &context =
      context_field != transition.end() && context_field->is_object()
          ? *context_field
          : view;
  return resolve_typing_source(
      context.value("scheme", -1), view.value("nine_key", false),
      view.value("dedicated_english", false),
      context.value("local_mode", std::string("none")),
      view.value("shuangpin_profile", std::string("xiaohe")));
}

// Resolved local calendar fields, or nothing when the conversion failed. The
// day and hour axes both have to be the user's, and only this process knows
// which timezone that is; a failure means the caller skips the record rather
// than attributing it to a guessed day.
struct LocalTimeParts {
  std::string day; // YYYY-MM-DD
  int hour = 0;    // 0-23
};

inline std::optional<LocalTimeParts> local_time_parts(std::time_t instant) {
  std::tm local{};
#ifdef _WIN32
  if (localtime_s(&local, &instant) != 0)
    return std::nullopt;
#else
  if (localtime_r(&instant, &local) == nullptr)
    return std::nullopt;
#endif
  char day[11]{};
  if (std::strftime(day, sizeof(day), "%Y-%m-%d", &local) == 0)
    return std::nullopt;
  return LocalTimeParts{std::string(day), local.tm_hour};
}

// Build the shared host request for one commit. Empty text, an empty directory,
// or a day or hour that did not resolve all yield an empty string: statistics
// are best effort and must never manufacture a record they cannot place.
// Whether the directory is absolute is not re-decided here - the shared host
// owns that rule and rejects the request - because a second copy would drift.
inline std::string typing_statistics_record_request(std::string_view directory,
                                                    const std::string &text,
                                                    TypingSource source,
                                                    const std::string &day,
                                                    int hour) {
  if (text.empty() || directory.empty() || day.size() != 10 || hour < 0 ||
      hour > 23)
    return {};
  const auto request =
      nlohmann::json{
          {"directory", std::string(directory)},
          {"action",
           nlohmann::json{{"operation", "record"},
                          {"text", text},
                          {"source", std::string(typing_source_id(source))},
                          {"day", day},
                          {"hour", hour}}}}
          .dump();
  // The shared entry point rejects buffers past 64 KiB. A single commit never
  // approaches that; a pathological paste is dropped instead of truncated,
  // because a truncated commit would be counted as a shorter one.
  if (request.size() > 65'536)
    return {};
  return request;
}
} // namespace msime::windows
