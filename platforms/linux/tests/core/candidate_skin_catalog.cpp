#include "../src/core/CandidateSkinCatalog.h"

#include <cassert>
#include <string>
#include <vector>

using msime::linux_host::CandidateSkin;
using msime::linux_host::candidate_skin_list;
using msime::linux_host::candidate_skin_title;
using msime::linux_host::default_skin;
using msime::linux_host::next_candidate_skin;
using msime::linux_host::parse_builtin_skins;
using msime::linux_host::parse_configured_skins;
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
  return 0;
}
