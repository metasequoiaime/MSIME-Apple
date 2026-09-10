#pragma once
// Built-in palette subset of MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
#include <string_view>
namespace msime::mac {
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

SkinTokens BuiltInSkinTokens(std::string_view id, bool dark);
}
