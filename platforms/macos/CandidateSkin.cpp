#include "CandidateSkin.h"

namespace msime::mac {
namespace {

constexpr Rgba rgb(unsigned value, float alpha = 1.0f)
{
    return {((value >> 16) & 0xffu) / 255.0f, ((value >> 8) & 0xffu) / 255.0f,
            (value & 0xffu) / 255.0f, alpha};
}

SkinTokens fluent(bool dark)
{
    SkinTokens tokens;
    tokens.surface = dark ? rgb(0x202020) : rgb(0xffffff);
    tokens.border = dark ? rgb(0x9b9b9b, 0.18f) : rgb(0x000000, 0.12f);
    tokens.text = dark ? rgb(0xe9e8e8) : rgb(0x1a1a1a);
    tokens.number = dark ? rgb(0xe9e8e8, 0.62f) : rgb(0x1a1a1a, 0.55f);
    tokens.selected = dark ? rgb(0x3e3e3e, 0.73f) : rgb(0xe8e8e8);
    tokens.hover = dark ? rgb(0x414141) : rgb(0xececec);
    tokens.selectedText = tokens.text;
    tokens.accent = rgb(0x6b69d6);
    tokens.radius = 6.0f;
    tokens.borderWidth = 1.5f;
    tokens.showSelectedBar = true;
    return tokens;
}

SkinTokens wechat(bool dark)
{
    SkinTokens tokens = fluent(dark);
    tokens.surface = dark ? rgb(0x151515) : rgb(0xf7f7f7);
    tokens.border = dark ? rgb(0x292929) : rgb(0xdedede);
    tokens.text = dark ? rgb(0xb7b7b7) : rgb(0x333333);
    tokens.number = dark ? rgb(0x858585) : rgb(0x757575);
    tokens.accent = rgb(0x07c160);
    tokens.selected = rgb(0x07c160);
    tokens.selectedText = rgb(0xffffff);
    tokens.hover = rgb(0x07c160, dark ? 0.32f : 0.14f);
    tokens.radius = 5.0f;
    tokens.borderWidth = 1.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

SkinTokens graphite(bool dark)
{
    SkinTokens tokens = fluent(dark);
    tokens.surface = dark ? rgb(0x1c1f23) : rgb(0xfbfbfc);
    tokens.border = dark ? rgb(0x30353b) : rgb(0xe2e5e9);
    tokens.text = dark ? rgb(0xaeb6c2) : rgb(0x586476);
    tokens.number = dark ? rgb(0x707987) : rgb(0x8993a1);
    tokens.selected = {0, 0, 0, 0};
    tokens.selectedText = dark ? rgb(0xf1f3f5) : rgb(0x111827);
    tokens.hover = dark ? Rgba{1, 1, 1, 0.055f} : Rgba{0.12f, 0.16f, 0.22f, 0.055f};
    tokens.accent = dark ? rgb(0x8993a0) : rgb(0x5f6b7a);
    tokens.radius = 3.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

SkinTokens willowGreen(bool dark)
{
    SkinTokens tokens = fluent(dark);
    tokens.surface = dark ? rgb(0x2d2f2e) : rgb(0xf4f5f3);
    tokens.text = dark ? rgb(0xd8dbd8) : rgb(0x333333);
    tokens.number = dark ? rgb(0xa6aba7) : rgb(0x757575);
    tokens.accent = dark ? rgb(0x65c98d) : rgb(0x58b980);
    tokens.selected = tokens.accent;
    tokens.selectedText = rgb(0xffffff);
    tokens.hover = rgb(dark ? 0x65c98d : 0x58b980, dark ? 0.22f : 0.16f);
    tokens.border = {0, 0, 0, 0};
    tokens.radius = 9.0f;
    tokens.borderWidth = 0.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

} // namespace

const std::vector<SkinListEntry> &BuiltInSkinEntries()
{
    static const std::vector<SkinListEntry> entries = {
        {"fluent", "Fluent"}, {"wechat", "微信绿"}, {"graphite", "Graphite"}, {"willow_green", "柳绿"},
    };
    return entries;
}

bool IsBuiltInSkinId(std::string_view id)
{
    for (const auto &entry : BuiltInSkinEntries()) {
        if (entry.id == id) return true;
    }
    return false;
}

std::string_view NormalizeSkinId(std::string_view id)
{
    return IsBuiltInSkinId(id) ? id : "fluent";
}

SkinTokens BuiltInSkinTokens(std::string_view id, bool dark)
{
    id = NormalizeSkinId(id);
    if (id == "wechat") return wechat(dark);
    if (id == "graphite") return graphite(dark);
    if (id == "willow_green") return willowGreen(dark);
    return fluent(dark);
}

} // namespace msime::mac
