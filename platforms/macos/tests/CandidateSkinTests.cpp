#include "../src/CandidateSkin.h"

#include <filesystem>
#include <fstream>
#include <stdexcept>
#include <string>
#include <unistd.h>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

std::filesystem::path MakeTempRoot()
{
    char templatePath[] = "/tmp/metasequoia-skins-XXXXXX";
    Require(mkdtemp(templatePath) != nullptr, "Failed to create a temporary skins directory.");
    return templatePath;
}

void WriteFile(const std::filesystem::path &path, const std::string &text)
{
    std::filesystem::create_directories(path.parent_path());
    std::ofstream stream(path);
    Require(static_cast<bool>(stream), "Failed to write a skin fixture.");
    stream << text;
}
} // namespace

int main()
{
    Require(metasequoia::mac::IsBuiltInSkinId("fluent") && metasequoia::mac::IsBuiltInSkinId("wechat") &&
                metasequoia::mac::IsBuiltInSkinId("graphite") && metasequoia::mac::IsBuiltInSkinId("willow_green") &&
                !metasequoia::mac::IsBuiltInSkinId("niya-demo"),
            "Built-in skin ids did not match the Windows catalog.");
    Require(metasequoia::mac::IsSafeSkinId("niya-demo") && !metasequoia::mac::IsSafeSkinId("Fluent") &&
                !metasequoia::mac::IsSafeSkinId("../x") && metasequoia::mac::NormalizeSkinId("nope!") == "fluent",
            "Skin id validation did not match the Windows catalog.");
    Require(metasequoia::mac::BuiltInSkinEntries().size() == 4, "The built-in skin list was incomplete.");

    const auto fluentDark = metasequoia::mac::BuiltInSkinTokens("fluent", true);
    const auto fluentLight = metasequoia::mac::BuiltInSkinTokens("fluent", false);
    Require(fluentDark.showSelectedBar && fluentLight.showSelectedBar && fluentDark.accent.b > fluentDark.accent.r,
            "Fluent tokens lost the accent bar.");
    const auto wechatDark = metasequoia::mac::BuiltInSkinTokens("wechat", true);
    Require(!wechatDark.showSelectedBar && wechatDark.selected.g > 0.6f && wechatDark.selectedText.r > 0.9f,
            "WeChat tokens did not use a filled green selection.");
    const auto graphiteDark = metasequoia::mac::BuiltInSkinTokens("graphite", true);
    Require(!graphiteDark.showSelectedBar && graphiteDark.selected.a < 0.01f,
            "Graphite tokens did not keep a transparent selection.");
    const auto willowDark = metasequoia::mac::BuiltInSkinTokens("willow_green", true);
    Require(willowDark.borderWidth == 0.0f && willowDark.radius >= 8.0f,
            "Willow green tokens did not keep the full-bleed card.");

    const auto hex = metasequoia::mac::ParseCssColor("#07c160");
    const auto rgba = metasequoia::mac::ParseCssColor("rgba(224, 138, 168, 0.28)");
    Require(hex.has_value() && hex->g > 0.7f && rgba.has_value() && rgba->a > 0.2f && rgba->a < 0.3f,
            "CSS color parsing rejected valid skin colors.");
    Require(!metasequoia::mac::ParseCssColor("url(javascript:alert(1))").has_value(),
            "CSS color parsing accepted a non-color.");

    const std::filesystem::path root = MakeTempRoot();
    WriteFile(root / "niya-demo" / "skin.toml", R"toml(
schema_version = 1
id = "niya-demo"
name = "Niya Demo"
version = "0.1.1"
author = "Metasequoia IME contributors"
description = "demo"
base = "fluent"
preview = "assets/character.png"

[supports]
layouts = ["horizontal", "vertical"]
themes = ["dark", "light"]

[candidate_window]
min_width_dip = 176

[candidate_window.decoration]
top_inset_dip = 88
width_dip = 136

[candidate.dark]
accent = "#e08aa8"
selected = "rgba(224, 138, 168, 0.28)"
hover = "rgba(224, 138, 168, 0.16)"

[candidate.light]
accent = "#c45c7a"
selected = "rgba(196, 92, 122, 0.18)"
hover = "rgba(196, 92, 122, 0.10)"
surface = "#fff7fa"
border = "rgba(176, 80, 110, 0.22)"
)toml");
    WriteFile(root / "niya-demo" / "assets" / "character.png", "png");
    WriteFile(root / "broken" / "skin.toml", "schema_version = 2\nid = \"broken\"\n");

    std::string error;
    auto package = metasequoia::mac::LoadSkinPackage(root, "niya-demo", &error);
    Require(package.has_value() && package->name == "Niya Demo" && package->decorationTopDip == 88.0 &&
                package->dark.accent == "#e08aa8",
            "A valid external skin.toml was rejected.");
    Require(!metasequoia::mac::LoadSkinPackage(root, "broken", &error) &&
                error.find("schema_version") != std::string::npos,
            "An invalid external skin was accepted.");
    Require(!metasequoia::mac::LoadSkinPackage(root, "fluent", &error),
            "A built-in id was treated as an external package.");

    const auto catalog = metasequoia::mac::ScanSkinCatalog(root);
    Require(catalog.packages.size() == 1 && catalog.issues.size() == 1 && catalog.packages[0].id == "niya-demo",
            "Catalog scanning did not separate valid packages from issues.");

    const auto resolved = metasequoia::mac::ResolveSkin("niya-demo", true, root);
    Require(resolved.id == "niya-demo" && resolved.tokens.accent.r > 0.8f && resolved.decorationTopDip == 88.0 &&
                resolved.decorationPath.find("character.png") != std::string::npos,
            "External skin colors were not applied on top of Fluent.");
    const auto missing = metasequoia::mac::ResolveSkin("missing-skin", true, root);
    Require(missing.id == "fluent", "An unknown skin id did not fall back to Fluent.");

    const auto listed = metasequoia::mac::ListSkins(root);
    Require(listed.size() == 5 && listed[0].id == "fluent" && listed.back().id == "niya-demo",
            "The settings list did not keep built-in skins ahead of external packages.");

    WriteFile(root / "wechat-based" / "skin.toml", R"toml(
schema_version = 1
id = "wechat-based"
name = "WeChat Based"
version = "1.0"
base = "wechat"
toolbar_stylesheet = "toolbar.css"

[supports]
layouts = ["horizontal", "vertical"]
themes = ["dark", "light"]

[candidate_window]
min_width_dip = 0

[candidate_window.decoration]
top_inset_dip = 0
width_dip = 0

[candidate.dark]
accent = "#ff0000"
)toml");
    auto wechatBased = metasequoia::mac::LoadSkinPackage(root, "wechat-based", &error);
    Require(wechatBased.has_value() && wechatBased->base == "wechat",
            "A wechat-based skin with a missing toolbar stylesheet was rejected.");
    const auto resolvedWechat = metasequoia::mac::ResolveSkin("wechat-based", true, root);
    Require(resolvedWechat.id == "wechat-based" && !resolvedWechat.tokens.showSelectedBar &&
                resolvedWechat.tokens.selected.g > 0.6f && resolvedWechat.tokens.accent.r > 0.9f,
            "External skin tokens did not inherit the declared base skin.");

    std::filesystem::remove_all(root);
    return 0;
}
