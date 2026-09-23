#include "../src/candidates/CandidateFcitxTheme.h"

#include <cassert>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iterator>
#include <string>
#include <unistd.h>

namespace {

using Json = nlohmann::json;
namespace host = msime::linux_host;

bool contains(const std::string &text, const std::string &needle) {
  return text.find(needle) != std::string::npos;
}

const std::vector<host::CandidateSkin> builtin = {
    {"fluent", "Fluent"}, {"wechat", "微信"}, {"graphite", "石墨"}, {"willow_green", "柳绿"}};

host::CandidateColors resolve(Json preferences, bool system_dark = false, const Json &catalog = Json()) {
  return host::resolve_candidate_colors(
      host::candidate_display_preferences(std::move(preferences), system_dark, builtin, "fluent", catalog),
      "fluent");
}

std::string read(const std::filesystem::path &file) {
  std::ifstream in(file, std::ios::binary);
  return std::string(std::istreambuf_iterator<char>(in), {});
}

}  // namespace

int main() {
  // "follow" resolves against the system appearance, as the IBus panel does.
  const auto wechat_dark = resolve({{"candidate_skin", "wechat"}}, true);
  assert(wechat_dark.background == 0x151515u && wechat_dark.text == 0xB7B7B7u);
  assert(wechat_dark.selected == 0x07C160u && wechat_dark.selected_text == 0xFFFFFFu);
  const auto wechat_light = resolve({{"candidate_skin", "wechat"}, {"candidate_theme", "follow"}}, false);
  assert(wechat_light.background == 0xF7F7F7u);

  // A custom text colour covers the selected row too; a custom surface wins over the skin's.
  const auto custom = resolve({{"candidate_skin", "wechat"},
                               {"candidate_theme", "light"},
                               {"candidate_text_color", "#123456"},
                               {"candidate_background_color", "#abcdef"}});
  assert(custom.text == 0x123456u && custom.selected_text == 0x123456u);
  assert(custom.background == 0xABCDEFu);

  // An installed skin supplies its palette for the resolved appearance; unset colours fall back to contrast.
  const Json catalog = {{"packages",
                         Json::array({{{"id", "sakura"},
                                       {"candidate",
                                        {{"light", {{"surface", "#fff0f5"}, {"selected", "#ff69b4"}}},
                                         {"dark", {{"surface", "#301020"}, {"text", "#ffe4e1"}}}}}}})}};
  const auto sakura_light = resolve({{"candidate_skin", "sakura"}}, false, catalog);
  assert(sakura_light.background == 0xFFF0F5u && sakura_light.selected == 0xFF69B4u);
  assert(sakura_light.text == 0x000000u);
  const auto sakura_dark = resolve({{"candidate_skin", "sakura"}}, true, catalog);
  assert(sakura_dark.background == 0x301020u && sakura_dark.text == 0xFFE4E1u);
  assert(!sakura_dark.selected);
  // An installed skin sits on fluent's card, so without a border of its own it has fluent's outline.
  assert(sakura_light.border == 0xE0D3D7u && sakura_light.border_width == 1);

  // A package border is honoured, with alpha; the user's colour still wins over it; a form this host does not parse keeps fluent's.
  const Json outlined = {{"packages",
                          Json::array({{{"id", "sakura"},
                                        {"candidate",
                                         {{"light", {{"surface", "#fff0f5"}, {"border", "rgba(255,0,0,0.5)"}}},
                                          {"dark", {{"surface", "#301020"}, {"border", "#ff000080"}}}}}}})}};
  assert(resolve({{"candidate_skin", "sakura"}}, true, outlined).border == 0x980810u);
  assert(resolve({{"candidate_skin", "sakura"}, {"candidate_border_color", "#00ff00"}}, true, outlined).border == 0x00FF00u);
  assert(resolve({{"candidate_skin", "sakura"}}, false, outlined).border == 0xE0D3D7u);
  const Json hidden = {{"packages", Json::array({{{"id", "sakura"}, {"candidate", {{"light", {{"border", "transparent"}}}}}}})}};
  const auto borderless = resolve({{"candidate_skin", "sakura"}}, false, hidden);
  assert(!borderless.border && borderless.border_width == 0);
  // A built-in skin never takes a package's colours, even with a package of the same id in the catalog.
  const Json shadow = {{"packages", Json::array({{{"id", "wechat"}, {"candidate", {{"dark", {{"border", "#ff0000"}}}}}}})}};
  assert(resolve({{"candidate_skin", "wechat"}}, true, shadow).border == 0x292929u);

  // The outline is composited over the surface, since the classic UI would otherwise punch a translucent border through to the desktop.
  const auto fluent_light = resolve({{"candidate_skin", "fluent"}, {"candidate_theme", "light"}});
  assert(fluent_light.border == 0xE0E0E0u && fluent_light.border_width == 1);
  const auto fluent_dark = resolve({{"candidate_skin", "fluent"}, {"candidate_theme", "dark"}});
  assert(fluent_dark.border == 0x363636u && fluent_dark.border_width == 1);
  assert(wechat_dark.border == 0x292929u && wechat_dark.border_width == 1);
  const auto willow = resolve({{"candidate_skin", "willow_green"}, {"candidate_theme", "light"}});
  assert(!willow.border && willow.border_width == 0);
  // A custom border colour replaces the skin's but keeps its width, so willow_green stays unoutlined.
  const auto custom_border = resolve({{"candidate_skin", "graphite"}, {"candidate_theme", "light"}, {"candidate_border_color", "#123456"}});
  assert(custom_border.border == 0x123456u && custom_border.border_width == 1);
  assert(!resolve({{"candidate_skin", "willow_green"}, {"candidate_border_color", "#123456"}}).border);
  // The border is composited over a custom surface, not the skin's.
  assert(resolve({{"candidate_skin", "fluent"}, {"candidate_theme", "light"}, {"candidate_background_color", "#fff0f5"}}).border == 0xE0D3D7u);

  assert(host::candidate_border_color(Json("#ff000080"))->alpha == 0x80);
  assert(host::candidate_border_color(Json("#ABCDEF"))->rgb == 0xABCDEFu);
  assert(host::candidate_border_color(Json("transparent"))->alpha == 0);
  assert(!host::candidate_border_color(Json("rgba(0,0,0,0.1)")));
  assert(!host::candidate_border_color(Json("#12345")));
  assert(!host::candidate_border_color(Json("#1234567g")));
  assert(!host::candidate_border_color(Json(nullptr)));

  assert(host::fcitx_theme_color(0x07C160u) == "#07c160");
  assert(host::fcitx_theme_color(0xFBFBFCu, true) == "#fbfbfc00");

  const auto theme = host::fcitx_candidate_theme(wechat_dark);
  assert(contains(theme, "[InputPanel]\nNormalColor=#b7b7b7\nHighlightCandidateColor=#ffffff\n"));
  assert(contains(theme, "HighlightBackgroundColor=#07c160\n"));
  assert(contains(theme, "[InputPanel/Background]\nColor=#151515\n"));
  assert(contains(theme, "[InputPanel/Highlight]\nColor=#07c160\n"));
  assert(contains(theme, "[Menu/Background]\nColor=#151515\n"));
  assert(contains(theme, "[InputPanel/Background]\nColor=#151515\nBorderColor=#292929\nBorderWidth=1\n"));
  assert(contains(theme, "[InputPanel/Background/Margin]\nLeft=2\nRight=2\nTop=2\nBottom=2\n"));
  assert(contains(theme, "[InputPanel/ContentMargin]\nLeft=2\nRight=2\nTop=2\nBottom=2\n"));
  // No outline: a transparent border of width 0, as before borders were drawn.
  assert(contains(host::fcitx_candidate_theme(willow), "BorderColor=#f4f5f300\nBorderWidth=0\n"));
  // A wider outline widens both margins, so the border stays inside the background and the highlight off it.
  auto wide = wechat_dark;
  wide.border_width = 3;
  const auto wide_theme = host::fcitx_candidate_theme(wide);
  assert(contains(wide_theme, "BorderWidth=3\n\n[InputPanel/Background/Margin]\nLeft=4\nRight=4\nTop=4\nBottom=4\n"));
  assert(contains(wide_theme, "[InputPanel/ContentMargin]\nLeft=4\nRight=4\nTop=4\nBottom=4\n"));

  // Graphite has no selected fill: the highlight is transparent and only the text colour changes.
  const auto graphite = host::fcitx_candidate_theme(resolve({{"candidate_skin", "graphite"}, {"candidate_theme", "light"}}));
  assert(contains(graphite, "[InputPanel/Highlight]\nColor=#fbfbfc00\n"));
  assert(contains(graphite, "HighlightCandidateColor=#111827\n"));
  assert(contains(graphite, "NormalColor=#586476\n"));

  assert(host::fcitx_theme_replaceable(""));
  assert(host::fcitx_theme_replaceable("default"));
  assert(host::fcitx_theme_replaceable("default-dark"));
  assert(host::fcitx_theme_replaceable("msime"));
  assert(!host::fcitx_theme_replaceable("Nord-Dark"));

  assert(host::fcitx_theme_file("/data", "/home/u") == std::filesystem::path("/data/fcitx5/themes/msime/theme.conf"));
  assert(host::fcitx_theme_file("relative", "/home/u") ==
         std::filesystem::path("/home/u/.local/share/fcitx5/themes/msime/theme.conf"));
  assert(host::fcitx_theme_file(nullptr, "/home/u") ==
         std::filesystem::path("/home/u/.local/share/fcitx5/themes/msime/theme.conf"));
  assert(!host::fcitx_theme_file(nullptr, nullptr));

  char pattern[] = "/tmp/msime-fcitx-theme-XXXXXX";
  const std::filesystem::path root = mkdtemp(pattern);
  const auto file = *host::fcitx_theme_file(root.c_str(), nullptr);
  assert(host::write_fcitx_theme(file, theme));
  assert(read(file) == theme);
  const auto written = std::filesystem::last_write_time(file);
  assert(host::write_fcitx_theme(file, theme));
  assert(std::filesystem::last_write_time(file) == written);
  assert(host::write_fcitx_theme(file, graphite));
  assert(read(file) == graphite);
  assert(!std::filesystem::exists(file.string() + ".new"));
  std::filesystem::remove_all(root);
  return 0;
}
