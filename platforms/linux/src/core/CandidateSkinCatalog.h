#pragma once
#include <cctype>
#include <cmath>
#include <cstddef>
#include <nlohmann/json.hpp>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace msime::linux_host {

// 一款可选的候选皮肤：id 是身份，title 只用于展示。
struct CandidateSkin {
  std::string id;
  std::string title;
};

// 外部皮肤 id 的可用字符，与共享层 skin::catalog 的 safe_id 同一条规则。宿主不放宽
// 它：目录里的 id 会被拼进属性名和菜单项标识。
inline bool safe_skin_id(std::string_view id) {
  if (id.empty() || id.size() > 64) return false;
  const auto first = static_cast<unsigned char>(id.front());
  if (!std::isalnum(first)) return false;
  for (const char value : id) {
    const auto byte = static_cast<unsigned char>(value);
    const bool allowed = (byte >= 'a' && byte <= 'z') || (byte >= '0' && byte <= '9') ||
                         byte == '.' || byte == '_' || byte == '-';
    if (!allowed) return false;
  }
  return true;
}

// 共享层 msime_client_builtin_skins() 的响应。解析失败返回空列表，由调用方决定如何
// 处理——宿主不在这里补一份内置表当兜底，那正是这个函数存在的理由。
inline std::vector<CandidateSkin> parse_builtin_skins(const nlohmann::json &parsed) {
  std::vector<CandidateSkin> skins;
  if (!parsed.is_object()) return skins;
  const auto listed = parsed.find("skins");
  if (listed == parsed.end() || !listed->is_array()) return skins;
  for (const auto &entry : *listed) {
    if (!entry.is_object()) continue;
    auto id = entry.value("id", std::string{});
    if (id.empty()) continue;
    auto title = entry.value("title", id);
    skins.push_back({std::move(id), std::move(title)});
  }
  return skins;
}


// 共享层发布的默认皮肤。文档给不出时返回空串，由调用方决定，宿主不另写一个默认值。
inline std::string default_skin(const nlohmann::json &parsed) {
  if (!parsed.is_object()) return {};
  return parsed.value("default", std::string{});
}

// 运行配置里 candidate_skin_catalog.packages 的那些外部皮肤。
inline std::vector<CandidateSkin> parse_configured_skins(const nlohmann::json &options) {
  std::vector<CandidateSkin> skins;
  const auto catalog = options.find("candidate_skin_catalog");
  if (catalog == options.end() || !catalog->is_object()) return skins;
  const auto packages = catalog->find("packages");
  if (packages == catalog->end() || !packages->is_array()) return skins;
  for (const auto &package : *packages) {
    if (!package.is_object()) continue;
    auto id = package.value("id", std::string{});
    if (!safe_skin_id(id)) continue;
    auto title = package.value("title", id);
    if (title.empty() || title.size() > 128) continue;
    bool listed = false;
    for (const auto &existing : skins) listed = listed || existing.id == id;
    if (listed) continue;
    skins.push_back({std::move(id), std::move(title)});
  }
  return skins;
}

// The decoration an installed skin draws above its candidate list: an image, trailing-aligned in a band top_dip tall and width_dip wide on Windows (candidate_presenter.cpp). The shared host catalog (skin::catalog::host_candidate_catalog) publishes it only for a package that declares one, with the image as an absolute path inside that package. The bounds are the manifest's (0 < top <= 500, 0 < width <= 1000) and are checked again here, because the document is read as untrusted input. Only Fcitx5 draws it; IBus text attributes have no way to show an image, and IBus never reads these keys.
struct CandidateSkinDecoration {
  std::string image;
  double top_dip = 0;
  double width_dip = 0;
};

// One package's decoration. A package without all three keys, or with any of them out of bounds, has none; that costs the skin its decoration, not its place in the catalogue.
inline std::optional<CandidateSkinDecoration> parse_skin_decoration(const nlohmann::json &package) {
  if (!package.is_object()) return std::nullopt;
  const auto top = package.find("decoration_top_dip");
  const auto width = package.find("decoration_width_dip");
  const auto image = package.find("decoration_image");
  if (top == package.end() || width == package.end() || image == package.end()) return std::nullopt;
  if (!top->is_number() || !width->is_number() || !image->is_string()) return std::nullopt;
  const auto top_dip = top->get<double>();
  const auto width_dip = width->get<double>();
  if (!std::isfinite(top_dip) || !std::isfinite(width_dip) || !(top_dip > 0 && top_dip <= 500) ||
      !(width_dip > 0 && width_dip <= 1000))
    return std::nullopt;
  auto path = image->get<std::string>();
  if (path.empty() || path.size() > 4096 || path.front() != '/' || path.find('\0') != std::string::npos)
    return std::nullopt;
  return CandidateSkinDecoration{std::move(path), top_dip, width_dip};
}

// The decoration of the selected skin when it is an installed one. A built-in skin never takes a package's decoration, even with a package of the same id in the catalogue, as it never takes its colours (candidate_display_preferences).
inline std::optional<CandidateSkinDecoration> candidate_skin_decoration(
    const nlohmann::json &catalog, std::string_view selected, const std::vector<CandidateSkin> &builtin) {
  for (const auto &skin : builtin)
    if (skin.id == selected) return std::nullopt;
  if (!catalog.is_object()) return std::nullopt;
  const auto packages = catalog.find("packages");
  if (packages == catalog.end() || !packages->is_array()) return std::nullopt;
  for (const auto &package : *packages)
    if (package.is_object() && package.value("id", std::string{}) == selected) return parse_skin_decoration(package);
  return std::nullopt;
}

// 宿主实际展示和循环的那份列表：内置在前，配置目录在后，去重。
//
// 当前皮肤如果两边都不在——运行配置换过、或者偏好是别处写的——它会作为一个「外部」
// 条目补在末尾，而不是被当作不存在。这条曾经在两个宿主之间不一致：IBus 的属性菜单把
// 它显示为「外部：<id>」并保持选中，Fcitx5 的循环动作则因为在列表里找不到它而直接跳
// 回列表头，用户配的皮肤按一下就没了，而且它在此之前一直被标成杨柳青。
inline std::vector<CandidateSkin> candidate_skin_list(
    const std::vector<CandidateSkin> &builtin, const std::vector<CandidateSkin> &configured,
    std::string_view current) {
  std::vector<CandidateSkin> skins = builtin;
  const auto listed = [&skins](std::string_view id) {
    for (const auto &skin : skins)
      if (skin.id == id) return true;
    return false;
  };
  for (const auto &skin : configured)
    if (!listed(skin.id)) skins.push_back(skin);
  if (!current.empty() && !listed(current))
    skins.push_back({std::string(current), "外部：" + std::string(current)});
  return skins;
}

// 循环里的下一款，走到末尾回到开头。列表为空时保持当前不动。
inline std::string next_candidate_skin(const std::vector<CandidateSkin> &skins,
                                       std::string_view current) {
  if (skins.empty()) return std::string(current);
  for (std::size_t index = 0; index < skins.size(); ++index)
    if (skins[index].id == current) return skins[(index + 1) % skins.size()].id;
  return skins.front().id;
}

// 展示标题。认识的皮肤用它自己的标题，不认识的按「外部：<id>」，两个宿主同一条规则。
inline std::string candidate_skin_title(const std::vector<CandidateSkin> &skins,
                                        std::string_view current) {
  for (const auto &skin : skins)
    if (skin.id == current) return skin.title;
  return "外部：" + std::string(current);
}

}  // namespace msime::linux_host
