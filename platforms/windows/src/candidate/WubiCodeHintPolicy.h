#pragma once
#include <cstdint>
#include <nlohmann/json.hpp>
#include <string>
#include <string_view>

namespace msime::windows {
inline constexpr unsigned wubi_scheme = 2;
inline constexpr std::size_t wubi_code_hint_max_length = 64;

// The Wubi code that remains after the typed prefix, the rule macOS, Android and HarmonyOS apply to the shared `wubi_code_hint` preference. Pinyin fallback and local-mode candidates are not Wubi codes, so they advertise nothing.
inline std::string wubi_code_hint(std::string_view code, std::string_view typed, unsigned scheme,
                                  std::string_view local_mode, bool answered_by_pinyin_fallback) {
  if (scheme != wubi_scheme || answered_by_pinyin_fallback || local_mode != "none" || typed.empty() ||
      code.size() > wubi_code_hint_max_length || typed.size() > wubi_code_hint_max_length ||
      code.size() <= typed.size() || code.compare(0, typed.size(), typed) != 0)
    return {};
  return std::string(code.substr(typed.size()));
}

// The same rule read from a runtime view and one of its candidates. The typed prefix is the preedit, falling back to editing_text, as on macOS.
inline std::string wubi_code_hint(const nlohmann::json &view, const nlohmann::json &candidate) {
  const auto string_at = [](const nlohmann::json &object, const char *key) -> const std::string * {
    const auto found = object.find(key);
    return found != object.end() && found->is_string() ? found->get_ptr<const std::string *>() : nullptr;
  };
  const auto *code = string_at(candidate, "code");
  const auto *typed = string_at(view, "preedit");
  if (!typed) typed = string_at(view, "editing_text");
  const auto scheme = view.find("scheme");
  if (!code || !typed || scheme == view.end() || !scheme->is_number_integer() ||
      scheme->get<std::int64_t>() != static_cast<std::int64_t>(wubi_scheme))
    return {};
  const auto *local_mode = string_at(view, "local_mode");
  const auto fallback = view.find("answered_by_pinyin_fallback");
  return wubi_code_hint(*code, *typed, wubi_scheme, local_mode ? *local_mode : "none",
                        fallback != view.end() && fallback->is_boolean() && fallback->get<bool>());
}

// Shows each candidate's remaining code in its annotation run, written "(hint)" as macOS writes it, when the preference is on. Candidates without a hint keep their own annotation.
template <class Presentation>
Presentation with_wubi_code_hints(Presentation presentation, bool enabled) {
  if (!enabled) return presentation;
  for (auto &candidate : presentation.candidates)
    if (!candidate.wubi_code_hint.empty())
      candidate.annotation = "(" + candidate.wubi_code_hint + ")";
  return presentation;
}
} // namespace msime::windows
