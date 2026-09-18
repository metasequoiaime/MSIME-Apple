#include "../src/candidate/CandidateThemeSettings.h"
#include <cassert>
#include <chrono>
#include <fstream>

int main() {
  using namespace msime::windows;
  for (const auto &id : {std::string("willow_green"),
                         std::string("sample.skin-1"), std::string(64, 'a')}) {
    assert(valid_candidate_skin_id(id));
    assert(
        candidate_theme_values({{"candidate_skin", id}}).at("candidate_skin") ==
        id);
  }
  for (const auto &id :
       {std::string(""), std::string("../escape"), std::string("Upper"),
        std::string("/absolute"), std::string(65, 'a')}) {
    assert(!valid_candidate_skin_id(id));
    assert(!candidate_theme_values({{"candidate_skin", id}})
                .contains("candidate_skin"));
  }
  const auto root =
      std::filesystem::temp_directory_path() /
      ("msime-skin-reload-" +
       std::to_string(
           std::chrono::steady_clock::now().time_since_epoch().count()));
  std::filesystem::create_directories(root / "sample");
  // A synthetic file is enough for the resource-selection test; no renderer
  // or real image is involved in this portable test.
  std::ofstream(root / "sample" / "preview.png") << "synthetic";
  const nlohmann::json catalog{
      {"packages", nlohmann::json::array({{{"id", "sample"},
                                           {"preview", "preview.png"},
                                           {"min_width_dip", 320},
                                           {"decoration_top_dip", 50},
                                           {"decoration_width_dip", 180}}})}};
  const auto external = candidate_skin_assets(catalog, "sample", root);
  assert(external.min_width == 320 && external.decoration.top_dip == 50 &&
         external.decoration.width_dip == 180);
  assert(external.decoration.image ==
         (root / "sample" / "preview.png").wstring());
  // Switching back or to an unavailable package must clear old artwork/width.
  for (const char *id :
       {"fluent", "wechat", "graphite", "willow_green", "missing"}) {
    const auto reset = candidate_skin_assets(catalog, id, root);
    assert(reset.min_width == 0 && reset.decoration.image.empty());
    assert(reset.decoration.top_dip == 0 && reset.decoration.width_dip == 0);
  }
  std::filesystem::remove(root / "sample" / "preview.png");
  assert(
      candidate_skin_assets(catalog, "sample", root).decoration.image.empty());
  std::filesystem::remove(root / "sample");
  std::filesystem::remove(root);
  CandidateThemeMailbox mailbox;
  mailbox.publish({{"candidate_skin", "sample"}});
  mailbox.publish({{"candidate_skin", "wechat"}});
  assert(mailbox.take()->at("candidate_skin") == "wechat");
}
