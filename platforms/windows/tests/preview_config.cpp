#include "PreviewConfig.h"
#include <iostream>

using namespace msime::windows;
void require(bool value) {
  if (!value)
    throw std::runtime_error("Preview configuration test failed");
}
int main() {
  try {
    const auto root = std::filesystem::temp_directory_path();
    nlohmann::json document{{"format_version", 1},
                            {"resources", (root / "resources").u8string()},
                            {"state_root", (root / "state").u8string()},
                            {"pipe_namespace", "fixture-12"},
                            {"preedit_style", "pinyin"}};
    const auto good = PreviewConfig::parse(document.dump());
    require(good.style == TsfPreeditStyle::Pinyin);
    const auto names = good.pipe_names();
    require(names[0] == L"\\\\.\\pipe\\msime-client-preview-fixture-12-0" &&
            names[0] != names[1] && names[1] != names[2]);
    auto reject = [&](nlohmann::json bad) {
      bool rejected = false;
      try {
        PreviewConfig::parse(bad.dump());
      } catch (...) {
        rejected = true;
      }
      require(rejected);
    };
    for (const char *field : {"resources", "state_root", "preedit_style",
                              "format_version", "pipe_namespace"}) {
      auto bad = document;
      bad.erase(field);
      reject(bad);
    }
    for (const std::string &token :
         {std::string{}, std::string("../server"), std::string("pipe\\name"),
          std::string(49, 'a'), std::string("a\0b", 3)}) {
      auto bad = document;
      bad["pipe_namespace"] = token;
      reject(bad);
    }
    auto bad = document;
    bad["state_root"] = "relative";
    reject(bad);
    bad = document;
    bad["resources"] = "relative";
    reject(bad);
    bad = document;
    bad["extra"] = true;
    reject(bad);
    bad = document;
    bad["format_version"] = 2;
    reject(bad);
    bad["format_version"] = 1.0;
    reject(bad);
    bad = document;
    bad["preedit_style"] = "unknown";
    reject(bad);
    bad = document;
    bad["resources"] = std::string(16385, 'x');
    reject(bad);
    document["preedit_style"] = "local";
    require(PreviewConfig::parse(document.dump()).style ==
            TsfPreeditStyle::Local);
    std::cout
        << "Preview configuration: isolated names and strict fields passed\n";
  } catch (...) {
    return 1;
  }
}
