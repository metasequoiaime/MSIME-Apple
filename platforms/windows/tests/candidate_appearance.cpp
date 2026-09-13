#include "CandidateAppearance.h"
#include "PreviewConfig.h"
#include <iostream>

using namespace msime::windows;
namespace {
[[noreturn]] void require_failed(int line) {
  throw std::runtime_error("Candidate appearance test failed at line " +
                           std::to_string(line));
}
#define require(value)                                                         \
  do {                                                                         \
    if (!(value))                                                              \
      require_failed(__LINE__);                                                \
  } while (false)
} // namespace
int main() {
  try {
    const auto root = std::filesystem::temp_directory_path();
    const auto state = root / "state";
    // Everything the appearance block is assembled from must survive
    // PreviewConfig, so each case below is fed straight back through it.
    auto loads = [&](const nlohmann::json &appearance) {
      nlohmann::json document{
          {"format_version", 1},
          {"resources", (root / "resources").u8string()},
          {"state_root", state.u8string()},
          {"pipe_namespace", "production"},
          {"preedit_style", "local"},
          {"appearance", appearance}};
      return PreviewConfig::parse(document.dump());
    };

    // A store with nothing set still yields a loadable block, and the skin root
    // is the state directory's skins folder.
    const auto empty = candidate_appearance(state, nlohmann::json::object(), false);
    const auto defaults = loads(empty);
    require(defaults.skin_directory == state / "skins");
    require(defaults.dark_theme);          // The shipped card is dark.
    require(!defaults.horizontal_candidates); // The stored default is vertical.
    require(defaults.candidate_show_preedit);

    // The user's choices reach the card.
    nlohmann::json preferences{
        {"theme", "light"},
        {"candidate_layout", "horizontal"},
        {"candidate_preedit_style", "empty"},
        {"candidate_skin", "wechat"},
        {"candidate_font_size", 22},
        {"candidate_preedit_font_size", 18},
        {"candidate_font_family", "Microsoft YaHei"},
        {"candidate_fallback_fonts",
         nlohmann::json::array({"Segoe UI Emoji", "Noto Color Emoji"})},
        {"candidate_text_color", "#ffffff"},
        {"candidate_accent_color", "#07c160"}};
    const auto configured = loads(candidate_appearance(state, preferences, false));
    require(!configured.dark_theme);
    require(configured.horizontal_candidates);
    require(!configured.candidate_show_preedit);
    require(configured.skin_id == "wechat");
    require(configured.candidate_font_size == 22);
    require(configured.candidate_preedit_font_size == 18);
    require(configured.candidate_font == "Microsoft YaHei");
    require(configured.candidate_fallback_fonts.size() == 2 &&
            configured.candidate_fallback_fonts[0] == "Segoe UI Emoji");
    require(configured.candidate_text_color == "#ffffff");
    require(configured.candidate_accent_color == "#07c160");

    // "system" is the only value that defers to Windows, and it defers both ways.
    require(!candidate_appearance(state, {{"theme", "system"}}, false)
                 .at("dark_theme")
                 .get<bool>());
    require(candidate_appearance(state, {{"theme", "system"}}, true)
                .at("dark_theme")
                .get<bool>());
    // An explicit choice ignores the system entirely.
    require(!candidate_appearance(state, {{"theme", "light"}}, true)
                 .at("dark_theme")
                 .get<bool>());
    require(candidate_appearance(state, {{"theme", "dark"}}, false)
                .at("dark_theme")
                .get<bool>());

    // The point of the filtering: a stored value PreviewConfig would reject is
    // dropped, so it costs the user a colour rather than their IME.
    const nlohmann::json hostile{
        {"candidate_font_size", 900},
        {"candidate_preedit_font_size", 0},
        {"candidate_text_color", std::string(64, 'x')},
        {"candidate_number_color", std::string("rgb(0,0,0)\nInjected")},
        {"candidate_font_family", std::string(400, 'y')},
        {"candidate_skin", std::string(200, 'z')},
        {"candidate_fallback_fonts",
         nlohmann::json::array({"", std::string(400, 'w'), 7, "Segoe UI"})},
        {"theme", 12},
        {"candidate_layout", nullptr}};
    const auto filtered = candidate_appearance(state, hostile, false);
    require(!filtered.contains("candidate_font_size"));
    require(!filtered.contains("candidate_preedit_font_size"));
    require(!filtered.contains("candidate_text_color"));
    require(!filtered.contains("candidate_number_color"));
    require(!filtered.contains("candidate_font"));
    require(!filtered.contains("candidate_skin"));
    require(!filtered.contains("candidate_fallback_fonts"));
    // Non-string theme/layout fall back rather than propagating a bad type.
    require(filtered.at("dark_theme").get<bool>());
    require(filtered.at("layout") == "vertical");
    const auto survived = loads(filtered); // The whole point: it still loads.
    require(survived.candidate_font == "Segoe UI");

    // Only the three known inline-preedit values are passed through, and the
    // stored "raw" is PreviewConfig's "local".
    require(tsf_preedit_style(nlohmann::json::object()) == "local");
    require(tsf_preedit_style({{"tsf_preedit_style", "raw"}}) == "local");
    require(tsf_preedit_style({{"tsf_preedit_style", "pinyin"}}) == "pinyin");
    require(tsf_preedit_style({{"tsf_preedit_style", "empty"}}) == "empty");
    require(tsf_preedit_style({{"tsf_preedit_style", "nonsense"}}) == "local");
    require(tsf_preedit_style({{"tsf_preedit_style", 3}}) == "local");

    std::cout << "Candidate appearance: stored preferences reach the card\n";
  } catch (const std::exception &failure) {
    std::cerr << failure.what() << '\n';
    return 1;
  } catch (...) {
    std::cerr << "Candidate appearance test failed with an unknown error\n";
    return 1;
  }
}
