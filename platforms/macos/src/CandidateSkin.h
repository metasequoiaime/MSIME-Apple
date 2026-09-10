#pragma once

#include <filesystem>
#include <optional>
#include <string>
#include <string_view>
#include <vector>

namespace metasequoia::mac
{
struct Rgba
{
    float r = 0.0f;
    float g = 0.0f;
    float b = 0.0f;
    float a = 1.0f;
};

struct SkinTokens
{
    Rgba surface;
    Rgba border;
    Rgba text;
    Rgba number;
    Rgba selected;
    Rgba selectedText;
    Rgba hover;
    Rgba accent;
    float radius = 6.0f;
    float borderWidth = 1.5f;
    float pad = 5.0f;
    bool showSelectedBar = true;
};

struct SkinColors
{
    std::string accent;
    std::string selected;
    std::string hover;
    std::string surface;
    std::string border;
    std::string text;
    std::string number;
    std::optional<bool> showSelectedBar;
};

struct SkinPackage
{
    std::string id;
    std::string name;
    std::string version;
    std::string author;
    std::string description;
    std::string base = "fluent";
    std::string toolbarStylesheet;
    std::string preview;
    std::vector<std::string> layouts;
    std::vector<std::string> themes;
    double minWidthDip = 0.0;
    double decorationTopDip = 0.0;
    double decorationWidthDip = 0.0;
    SkinColors dark;
    SkinColors light;
};

struct SkinIssue
{
    std::string folder;
    std::string reason;
};

struct SkinCatalog
{
    std::vector<SkinPackage> packages;
    std::vector<SkinIssue> issues;
};

struct SkinListEntry
{
    std::string id;
    std::string name;
    bool builtin = false;
};

struct ResolvedSkin
{
    std::string id;
    std::string name;
    SkinTokens tokens;
    std::string decorationPath;
    double decorationTopDip = 0.0;
    double decorationWidthDip = 0.0;
    double minWidthDip = 0.0;
};

std::optional<std::string> RenameSkinManifest(const std::string &text, const std::string &name);
bool IsBuiltInSkinId(std::string_view id);
bool IsSafeSkinId(std::string_view id);
std::string NormalizeSkinId(std::string_view id);
const std::vector<SkinListEntry> &BuiltInSkinEntries();
SkinTokens BuiltInSkinTokens(std::string_view id, bool dark);
std::optional<Rgba> ParseCssColor(std::string_view text);
std::optional<SkinPackage> LoadSkinPackage(const std::filesystem::path &skinsRoot, const std::string &id,
                                           std::string *error = nullptr);
SkinCatalog ScanSkinCatalog(const std::filesystem::path &skinsRoot);
std::vector<SkinListEntry> ListSkins(const std::filesystem::path &skinsRoot);
ResolvedSkin ResolveSkin(std::string_view id, bool dark, const std::filesystem::path &skinsRoot);
std::filesystem::path DefaultSkinsRoot();
} // namespace metasequoia::mac
