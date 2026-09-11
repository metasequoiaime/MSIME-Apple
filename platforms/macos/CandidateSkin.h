#pragma once

#include <string_view>
#include <vector>

namespace msime::mac {

struct Rgba {
    float r = 0.0f;
    float g = 0.0f;
    float b = 0.0f;
    float a = 1.0f;
};

struct SkinTokens {
    Rgba surface;
    Rgba border;
    Rgba text;
    Rgba number;
    Rgba selected;
    Rgba selectedText;
    Rgba hover;
    Rgba accent;
    float radius = 6.0f;
    float borderWidth = 1.0f;
    bool showSelectedBar = true;
};

struct SkinListEntry {
    std::string_view id;
    std::string_view name;
};

const std::vector<SkinListEntry> &BuiltInSkinEntries();
bool IsBuiltInSkinId(std::string_view id);
std::string_view NormalizeSkinId(std::string_view id);
SkinTokens BuiltInSkinTokens(std::string_view id, bool dark);

} // namespace msime::mac
