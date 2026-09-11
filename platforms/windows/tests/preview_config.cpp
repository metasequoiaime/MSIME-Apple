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
    require(good.floating_toolbar_enabled);
    require(!good.navigation.minus_equal && !good.navigation.comma_period &&
            !good.navigation.brackets && !good.navigation.tab &&
            !good.navigation.page_up_down && !good.navigation.arrows &&
            good.word_character == WordCharacterBinding::Disabled);
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
    document["floating_toolbar_enabled"] = false;
    require(!PreviewConfig::parse(document.dump()).floating_toolbar_enabled);
    document["floating_toolbar_enabled"] = 1;
    reject(document);
    document["floating_toolbar_enabled"] = true;
    const nlohmann::json bindings{
        {"minus_equal", false},        {"comma_period", false},
        {"brackets", false},           {"tab", false},
        {"page_up_down", false},       {"arrows", false},
        {"word_character", "disabled"}};
    for (const char *name : {"minus_equal", "comma_period", "brackets", "tab",
                             "page_up_down", "arrows"}) {
      auto config = document;
      config["key_bindings"] = bindings;
      config["key_bindings"][name] = true;
      const auto loaded = PreviewConfig::parse(config.dump());
      require(loaded.navigation.minus_equal ==
              (std::string(name) == "minus_equal"));
      require(loaded.navigation.comma_period ==
              (std::string(name) == "comma_period"));
      require(loaded.navigation.brackets == (std::string(name) == "brackets"));
      require(loaded.navigation.tab == (std::string(name) == "tab"));
      require(loaded.navigation.page_up_down ==
              (std::string(name) == "page_up_down"));
      require(loaded.navigation.arrows == (std::string(name) == "arrows"));
      config["key_bindings"][name] = 1;
      reject(config);
      config["key_bindings"].erase(name);
      reject(config);
    }
    document["key_bindings"] = bindings;
    for (const auto &[name, expected] :
         std::array<std::pair<const char *, WordCharacterBinding>, 3>{
             {{"disabled", WordCharacterBinding::Disabled},
              {"brackets", WordCharacterBinding::Brackets},
              {"minus_equal", WordCharacterBinding::MinusEqual}}}) {
      document["key_bindings"]["word_character"] = name;
      require(PreviewConfig::parse(document.dump()).word_character == expected);
    }
    document["key_bindings"]["word_character"] = "unknown";
    reject(document);
    document["key_bindings"] = bindings;
    document["key_bindings"]["extra"] = false;
    reject(document);
    document["key_bindings"] = nullptr;
    reject(document);
    std::cout
        << "Preview configuration: isolated names and strict fields passed\n";
  } catch (...) {
    return 1;
  }
}
