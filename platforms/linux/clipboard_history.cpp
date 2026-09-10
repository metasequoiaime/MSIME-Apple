#include <nlohmann/json.hpp>
#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <string>
#include <vector>

using Json = nlohmann::json;
namespace {
constexpr size_t kMaxItems = 50;
constexpr size_t kMaxChars = 4000;
std::string normalize(std::string text) {
  text.erase(std::remove(text.begin(), text.end(), '\0'), text.end());
  std::string out;
  out.reserve(std::min(text.size(), kMaxChars));
  for (size_t i = 0; i < text.size() && out.size() < kMaxChars; ++i) {
    if (text[i] == '\r') {
      if (i + 1 < text.size() && text[i + 1] == '\n') ++i;
      out.push_back('\n');
    } else out.push_back(text[i]);
  }
  while (!out.empty() && (out.back() == '\n' || out.back() == ' ' || out.back() == '\t')) out.pop_back();
  return out;
}
std::vector<std::string> load(const std::filesystem::path &path) {
  std::ifstream input(path); if (!input) return {};
  try { auto value = Json::parse(input); if (!value.is_array()) return {};
    std::vector<std::string> items;
    for (const auto &item : value) if (item.is_string() && items.size() < kMaxItems) {
      auto text = normalize(item.get<std::string>()); if (!text.empty()) items.push_back(std::move(text));
    }
    return items;
  } catch (...) { return {}; }
}
bool save(const std::filesystem::path &path, const std::vector<std::string> &items) {
  std::error_code error; std::filesystem::create_directories(path.parent_path(), error);
  std::ofstream output(path, std::ios::trunc); if (!output) return false;
  output << Json(items).dump();
  if (!output) return false;
  // Clipboard history can contain private user text; do not leave it readable
  // by other local users even when the process umask is permissive.
  std::filesystem::permissions(
      path, std::filesystem::perms::owner_read |
                std::filesystem::perms::owner_write,
      std::filesystem::perm_options::replace, error);
  return !error;
}
}
int main(int argc, char **argv) {
  if (argc < 3) return 2;
  const std::filesystem::path path = argv[1];
  const std::string op = argv[2];
  auto items = load(path);
  if (op == "list") { std::cout << Json(items).dump() << '\n'; return 0; }
  // A compositor or desktop launcher can use this explicit stream operation to
  // paste a selected entry.  It never touches the system clipboard itself.
  if (op == "get" && argc == 4) {
    try {
      const auto index = std::stoul(argv[3]);
      if (index >= items.size()) return 1;
      std::cout << items[index];
      return static_cast<bool>(std::cout) ? 0 : 1;
    } catch (...) { return 2; }
  }
  if (op == "add" && argc == 4) {
    auto text = normalize(argv[3]); if (text.empty() || (!items.empty() && items.front() == text)) return 0;
    items.erase(std::remove(items.begin(), items.end(), text), items.end()); items.insert(items.begin(), std::move(text));
    if (items.size() > kMaxItems) items.resize(kMaxItems);
    return save(path, items) ? 0 : 1;
  }
  if (op == "remove" && argc == 4) { auto old = items.size(); items.erase(std::remove(items.begin(), items.end(), argv[3]), items.end()); return old == items.size() ? 0 : (save(path, items) ? 0 : 1); }
  if (op == "clear") { std::error_code error; return std::filesystem::remove(path, error) || !std::filesystem::exists(path) ? 0 : 1; }
  return 2;
}
