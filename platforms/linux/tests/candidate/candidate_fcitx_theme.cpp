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

  assert(host::fcitx_theme_color(0x07C160u) == "#07c160");
  assert(host::fcitx_theme_color(0xFBFBFCu, true) == "#fbfbfc00");

  const auto theme = host::fcitx_candidate_theme(wechat_dark);
  assert(contains(theme, "[InputPanel]\nNormalColor=#b7b7b7\nHighlightCandidateColor=#ffffff\n"));
  assert(contains(theme, "HighlightBackgroundColor=#07c160\n"));
  assert(contains(theme, "[InputPanel/Background]\nColor=#151515\n"));
  assert(contains(theme, "[InputPanel/Highlight]\nColor=#07c160\n"));
  assert(contains(theme, "[Menu/Background]\nColor=#151515\n"));

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
