#pragma once
#include "EditPolicy.h"
#include "NavigationPolicy.h"
#include "WordCharacterPolicy.h"
#include <array>
#include <filesystem>
#include <nlohmann/json.hpp>

namespace msime::windows {
struct PreviewConfig {
  std::filesystem::path resources;
  std::filesystem::path state_root;
  std::string pipe_namespace;
  TsfPreeditStyle style;
  NavigationBindings navigation{};
  bool explicit_key_bindings = false;
  bool floating_toolbar_enabled = true;
  double floating_toolbar_scale = 1.0;
  int floating_toolbar_font_size = 24;
  WordCharacterBinding word_character = WordCharacterBinding::Disabled;
  // Optional appearance. Without it the presenters keep their built-in theme.
  std::filesystem::path skin_directory;
  std::string skin_id;
  bool dark_theme = true;
  // The shipped card lays candidates out on one row; vertical stays available.
  bool horizontal_candidates = true;
  static PreviewConfig parse(const std::string &document) {
    if (document.size() > 16384)
      throw std::invalid_argument("Oversized preview configuration");
    const auto value = nlohmann::json::parse(document);
    if (!value.is_object() ||
        value.size() != ((value.contains("key_bindings") ? 6u : 5u) +
                         (value.contains("floating_toolbar_enabled") ? 1u : 0u) +
                         (value.contains("floating_toolbar_scale") ? 1u : 0u) +
                         (value.contains("floating_toolbar_font_size") ? 1u : 0u) +
                         (value.contains("appearance") ? 1u : 0u)) ||
        !value.at("format_version").is_number_integer() ||
        value.at("format_version") != 1)
      throw std::invalid_argument("Invalid preview configuration");
    PreviewConfig result{
        std::filesystem::u8path(value.at("resources").get<std::string>()),
        std::filesystem::u8path(value.at("state_root").get<std::string>()),
        value.at("pipe_namespace").get<std::string>(), TsfPreeditStyle::Local,
        NavigationBindings{}, false, true, 1.0, 24, WordCharacterBinding::Disabled,
        std::filesystem::path{}, std::string{}, true, true};
    if (!result.resources.is_absolute() || !result.state_root.is_absolute() ||
        result.resources.u8string().find('\0') != std::string::npos ||
        result.state_root.u8string().find('\0') != std::string::npos)
      throw std::invalid_argument("Preview paths must be absolute");
    if (result.pipe_namespace.empty() || result.pipe_namespace.size() > 48)
      throw std::invalid_argument("Invalid preview pipe namespace");
    for (unsigned char c : result.pipe_namespace)
      if (!((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
            (c >= '0' && c <= '9') || c == '-'))
        throw std::invalid_argument("Invalid preview pipe namespace");
    const auto style = value.at("preedit_style").get<std::string>();
    if (style == "pinyin")
      result.style = TsfPreeditStyle::Pinyin;
    else if (style == "empty")
      result.style = TsfPreeditStyle::Empty;
    else if (style != "local")
      throw std::invalid_argument("Invalid preview preedit style");
    if (value.contains("appearance")) {
      const auto &appearance = value.at("appearance");
      if (!appearance.is_object() || appearance.size() > 4 ||
          !appearance.contains("skin_directory") ||
          !appearance.at("skin_directory").is_string())
        throw std::invalid_argument("Invalid preview appearance");
      result.skin_directory = std::filesystem::u8path(
          appearance.at("skin_directory").get<std::string>());
      if (!result.skin_directory.is_absolute() ||
          result.skin_directory.u8string().find('\0') != std::string::npos)
        throw std::invalid_argument("Preview paths must be absolute");
      if (appearance.contains("skin")) {
        if (!appearance.at("skin").is_string())
          throw std::invalid_argument("Invalid preview appearance");
        result.skin_id = appearance.at("skin").get<std::string>();
        // The catalog bounds identifiers; refuse anything longer here too.
        if (result.skin_id.size() > 64)
          throw std::invalid_argument("Invalid preview appearance");
      }
      if (appearance.contains("layout")) {
        if (!appearance.at("layout").is_string())
          throw std::invalid_argument("Invalid preview appearance");
        const auto layout = appearance.at("layout").get<std::string>();
        if (layout == "vertical")
          result.horizontal_candidates = false;
        else if (layout != "horizontal")
          throw std::invalid_argument("Invalid preview appearance");
      }
      if (appearance.contains("dark_theme")) {
        if (!appearance.at("dark_theme").is_boolean())
          throw std::invalid_argument("Invalid preview appearance");
        result.dark_theme = appearance.at("dark_theme").get<bool>();
      }
    }
    if (value.contains("key_bindings")) {
      result.explicit_key_bindings = true;
      const auto &keys = value.at("key_bindings");
      if (!keys.is_object() || keys.size() != 7)
        throw std::invalid_argument("Invalid preview key bindings");
      result.navigation.minus_equal = keys.at("minus_equal").get<bool>();
      result.navigation.comma_period = keys.at("comma_period").get<bool>();
      result.navigation.brackets = keys.at("brackets").get<bool>();
      result.navigation.tab = keys.at("tab").get<bool>();
      result.navigation.page_up_down = keys.at("page_up_down").get<bool>();
      result.navigation.arrows = keys.at("arrows").get<bool>();
      const auto word = keys.at("word_character").get<std::string>();
      if (word == "brackets")
        result.word_character = WordCharacterBinding::Brackets;
      else if (word == "minus_equal")
        result.word_character = WordCharacterBinding::MinusEqual;
      else if (word != "disabled")
        throw std::invalid_argument("Invalid preview word binding");
    }
    if (value.contains("floating_toolbar_enabled"))
      result.floating_toolbar_enabled = value.at("floating_toolbar_enabled").get<bool>();
    if (value.contains("floating_toolbar_scale")) {
      result.floating_toolbar_scale = value.at("floating_toolbar_scale").get<double>();
      if (result.floating_toolbar_scale < 0.75 || result.floating_toolbar_scale > 1.5)
        throw std::invalid_argument("Invalid floating toolbar scale");
    }
    if (value.contains("floating_toolbar_font_size")) {
      result.floating_toolbar_font_size = value.at("floating_toolbar_font_size").get<int>();
      if (result.floating_toolbar_font_size < 16 || result.floating_toolbar_font_size > 28)
        throw std::invalid_argument("Invalid floating toolbar font size");
    }
    return result;
  }
  std::array<std::wstring, 3> pipe_names() const {
    std::array<std::wstring, 3> names;
    const std::wstring token(pipe_namespace.begin(), pipe_namespace.end());
    for (size_t role = 0; role < names.size(); ++role)
      names[role] = L"\\\\.\\pipe\\msime-client-preview-" + token + L"-" +
                    std::to_wstring(role);
    return names;
  }
};
} // namespace msime::windows
