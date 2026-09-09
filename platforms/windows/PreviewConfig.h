#pragma once
#include "EditPolicy.h"
#include <array>
#include <filesystem>
#include <nlohmann/json.hpp>

namespace msime::windows {
struct PreviewConfig {
  std::filesystem::path resources;
  std::filesystem::path state_root;
  std::string pipe_namespace;
  TsfPreeditStyle style;
  static PreviewConfig parse(const std::string &document) {
    if (document.size() > 16384)
      throw std::invalid_argument("Oversized preview configuration");
    const auto value = nlohmann::json::parse(document);
    if (!value.is_object() || value.size() != 5 ||
        !value.at("format_version").is_number_integer() ||
        value.at("format_version") != 1)
      throw std::invalid_argument("Invalid preview configuration");
    PreviewConfig result{
        std::filesystem::u8path(value.at("resources").get<std::string>()),
        std::filesystem::u8path(value.at("state_root").get<std::string>()),
        value.at("pipe_namespace").get<std::string>(), TsfPreeditStyle::Local};
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
    else if (style != "local")
      throw std::invalid_argument("Invalid preview preedit style");
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
