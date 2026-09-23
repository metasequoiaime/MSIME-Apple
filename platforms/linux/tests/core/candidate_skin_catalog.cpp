#include "../src/core/CandidateSkinCatalog.h"
#include "../src/candidates/CandidateColors.h"

#include <cassert>
#include <string>
#include <vector>

using msime::linux_host::CandidateSkin;
using msime::linux_host::candidate_display_preferences;
using msime::linux_host::candidate_skin_list;
using msime::linux_host::candidate_skin_title;
using msime::linux_host::default_skin;
using msime::linux_host::next_candidate_skin;
using msime::linux_host::parse_builtin_skins;
using msime::linux_host::parse_configured_skins;
using msime::linux_host::resolve_candidate_colors;
using msime::linux_host::safe_skin_id;

int main() {
  // 共享层发布的内置目录，宿主只解析不补充。
  const auto builtin = parse_builtin_skins(nlohmann::json::parse(
      R"({"skins":[{"id":"fluent","title":"Fluent"},{"id":"wechat","title":"微信绿"},)"
      R"({"id":"graphite","title":"石墨"},{"id":"willow_green","title":"杨柳青"}],)"
      R"("default":"willow_green"})"));
  assert(builtin.size() == 4);
  assert(builtin.front().id == "fluent");
  // 同一个 id 在两个宿主上必须是同一个名字。这里钉的就是曾经漂掉的那个：IBus 显示
  // Graphite、Fcitx5 显示石墨。
  assert(candidate_skin_title(builtin, "graphite") == "石墨");

  // 解析不了就是空列表，不是一份偷偷补上的内置表。
  assert(parse_builtin_skins(nlohmann::json::parse("not json", nullptr, false)).empty());
  assert(parse_builtin_skins(nlohmann::json::parse(R"({"skins":{}})")).empty());
  assert(default_skin(nlohmann::json::parse(R"({"skins":[]})")).empty());

  // 配置目录：可用 id 收下，越界的丢掉。
  const auto options = nlohmann::json::parse(
      R"({"candidate_skin_catalog":{"packages":[{"id":"solarized","title":"Solarized"},)"
      R"({"id":"unsafe/id","title":"Ignored"},{"id":"fluent","title":"重名"}]}})");
  const auto configured = parse_configured_skins(options);
  assert(configured.size() == 2);
  assert(configured.front().id == "solarized");
  assert(!safe_skin_id("unsafe/id"));
  assert(!safe_skin_id(""));
  assert(safe_skin_id("solarized"));

  // 合成列表：内置在前，外部在后，与内置重名的不再出现第二次。
  const auto skins = candidate_skin_list(builtin, configured, "willow_green");
  assert(skins.size() == 5);
  assert(skins.back().id == "solarized");

  // 循环每次前进一格，走到末尾回到开头。整圈回到原地。
  assert(next_candidate_skin(skins, "willow_green") == "solarized");
  assert(next_candidate_skin(skins, "solarized") == "fluent");
  std::string current = "willow_green";
  for (std::size_t step = 0; step < skins.size(); ++step)
    current = next_candidate_skin(skins, current);
  assert(current == "willow_green");

  // 当前皮肤两边都不在时，它作为「外部」条目留在列表里并照实显示，而不是被当作不存
  // 在——后者会让它在一次循环里丢掉，并且一路被标成默认皮肤的名字。
  const auto external = candidate_skin_list(builtin, {}, "user.custom");
  assert(external.size() == 5);
  assert(external.back().id == "user.custom");
  assert(candidate_skin_title(external, "user.custom") == "外部：user.custom");
  assert(next_candidate_skin(external, "user.custom") == "fluent");

  // 列表为空时不改变当前选择。
  assert(next_candidate_skin({}, "willow_green") == "willow_green");

  // The document the desktop settings write (sync_runtime_options in apps/desktop/src-tauri/src/lib.rs, pinned by runtime_options_sync_publishes_the_installed_skin_catalog): the manifest name under `title` and only the colours the hosts draw, per declared theme.
  const auto synced = nlohmann::json::parse(
      R"({"api_version":1,"preferences":{"candidate_skin":"sakura","candidate_theme":"follow","theme":"dark"},)"
      R"("candidate_skin_catalog":{"packages":[{"id":"sakura","title":"樱花","candidate":{)"
      R"("light":{"surface":"#fff0f5","selected":"#ff69b4","text":"#301020"},)"
      R"("dark":{"surface":"#301020","text":"#ffe4e1","border":"#ff000080"}}}]}})");
  const auto synced_skins = parse_configured_skins(synced);
  assert(synced_skins.size() == 1);
  assert(candidate_skin_title(candidate_skin_list(builtin, synced_skins, "sakura"), "sakura") == "樱花");
  const auto &catalog = synced["candidate_skin_catalog"];
  // Following a dark global theme on a light desktop still takes the skin's dark palette.
  const auto dark = resolve_candidate_colors(
      candidate_display_preferences(synced["preferences"], false, builtin, "willow_green", catalog), "willow_green");
  assert(dark.background == 0x301020u);
  assert(dark.text == 0xffe4e1u);
  assert(!dark.selected);
  assert(dark.border == msime::linux_host::composite_color(0xff0000u, 0x80, 0x301020u));
  auto light_preferences = synced["preferences"];
  light_preferences["theme"] = "light";
  const auto light = resolve_candidate_colors(
      candidate_display_preferences(light_preferences, true, builtin, "willow_green", catalog), "willow_green");
  assert(light.background == 0xfff0f5u);
  assert(light.selected == 0xff69b4u);
  assert(light.text == 0x301020u);
  // A colour the user set keeps winning over the skin's.
  light_preferences["candidate_text_color"] = "#000000";
  const auto custom = resolve_candidate_colors(
      candidate_display_preferences(light_preferences, true, builtin, "willow_green", catalog), "willow_green");
  assert(custom.text == 0x000000u);
  assert(custom.background == 0xfff0f5u);

  // A decoration comes with its bounds and an absolute image path, as the shared host catalog publishes it; IBus reads the same package and simply has no use for it.
  using msime::linux_host::candidate_skin_decoration;
  using msime::linux_host::parse_skin_decoration;
  const auto decorated = nlohmann::json::parse(
      R"({"id":"sakura","title":"樱花","decoration_top_dip":24.5,"decoration_width_dip":180,)"
      R"("decoration_image":"/home/u/.local/share/msime/skins/sakura/images/ears.png"})");
  const auto decoration = parse_skin_decoration(decorated);
  assert(decoration && decoration->top_dip == 24.5 && decoration->width_dip == 180);
  assert(decoration->image == "/home/u/.local/share/msime/skins/sakura/images/ears.png");
  assert(parse_configured_skins(nlohmann::json{{"candidate_skin_catalog", {{"packages", nlohmann::json::array({decorated})}}}}).size() == 1);
  // The manifest's own bounds hold at both ends.
  auto edge = decorated;
  edge["decoration_top_dip"] = 500;
  edge["decoration_width_dip"] = 1000;
  assert(parse_skin_decoration(edge));
  // Anything outside them, a missing key, a relative or embedded-NUL path, and the package keeps its place with no decoration.
  const auto rejected = [&decorated](const char *key, const nlohmann::json &value) {
    auto package = decorated;
    if (value.is_discarded()) package.erase(key);
    else package[key] = value;
    return !parse_skin_decoration(package);
  };
  const auto absent = nlohmann::json(nlohmann::json::value_t::discarded);
  assert(rejected("decoration_top_dip", 0));
  assert(rejected("decoration_top_dip", -1));
  assert(rejected("decoration_top_dip", 500.5));
  assert(rejected("decoration_top_dip", "24"));
  assert(rejected("decoration_top_dip", absent));
  assert(rejected("decoration_width_dip", 0));
  assert(rejected("decoration_width_dip", 1000.1));
  assert(rejected("decoration_width_dip", absent));
  assert(rejected("decoration_image", "images/ears.png"));
  assert(rejected("decoration_image", ""));
  assert(rejected("decoration_image", std::string("/skins/a\0b.png", 14)));
  assert(rejected("decoration_image", "/" + std::string(4096, 'a')));
  assert(rejected("decoration_image", 7));
  assert(rejected("decoration_image", absent));
  assert(!parse_skin_decoration(nlohmann::json::array()));
  // Only the selected installed skin's decoration is drawn; a built-in id never takes one from a package of the same name.
  auto shadowing = decorated;
  shadowing["id"] = "fluent";
  const nlohmann::json decorated_catalog = {{"packages", nlohmann::json::array({decorated, shadowing})}};
  assert(candidate_skin_decoration(decorated_catalog, "sakura", builtin));
  assert(!candidate_skin_decoration(decorated_catalog, "fluent", builtin));
  assert(!candidate_skin_decoration(decorated_catalog, "absent", builtin));
  assert(!candidate_skin_decoration(catalog, "sakura", builtin));
  assert(!candidate_skin_decoration(nlohmann::json(), "sakura", builtin));
  return 0;
}
