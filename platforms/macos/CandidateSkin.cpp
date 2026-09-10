#include "CandidateSkin.h"
namespace msime::mac {
namespace {
constexpr Rgba Rgb(unsigned rgb, float alpha = 1.0f)
{
    return {((rgb >> 16) & 0xFFu) / 255.0f, ((rgb >> 8) & 0xFFu) / 255.0f, (rgb & 0xFFu) / 255.0f, alpha};
}

SkinTokens FluentTokens(bool dark)
{
    SkinTokens tokens;
    if (dark)
    {
        tokens.surface = Rgb(0x202020);
        tokens.border = Rgb(0x9B9B9B, 0x2E / 255.0f);
        tokens.text = Rgb(0xE9E8E8);
        tokens.number = Rgb(0xE9E8E8, 0.616f);
        tokens.selected = Rgb(0x3E3E3E, 0.725f);
        tokens.hover = Rgb(0x414141);
    }
    else
    {
        tokens.surface = Rgb(0xFFFFFF);
        tokens.border = Rgba{0.0f, 0.0f, 0.0f, 0.12f};
        tokens.text = Rgb(0x1A1A1A);
        tokens.number = Rgb(0x1A1A1A, 0.55f);
        tokens.selected = Rgb(0xE8E8E8);
        tokens.hover = Rgb(0xECECEC);
    }
    tokens.selectedText = tokens.text;
    tokens.accent = Rgb(0x6B69D6);
    tokens.radius = 6.0f;
    tokens.borderWidth = 1.5f;
    tokens.pad = 5.0f;
    tokens.showSelectedBar = true;
    return tokens;
}

SkinTokens WeChatTokens(bool dark)
{
    SkinTokens tokens = FluentTokens(dark);
    tokens.surface = dark ? Rgb(0x151515) : Rgb(0xF7F7F7);
    tokens.border = dark ? Rgb(0x292929) : Rgb(0xDEDEDE);
    tokens.text = dark ? Rgb(0xB7B7B7) : Rgb(0x333333);
    tokens.number = dark ? Rgb(0x858585) : Rgb(0x757575);
    tokens.accent = Rgb(0x07C160);
    tokens.selected = Rgb(0x07C160);
    tokens.selectedText = Rgb(0xFFFFFF);
    tokens.hover = Rgb(0x07C160, dark ? 0.32f : 0.14f);
    tokens.radius = 5.0f;
    tokens.borderWidth = 1.0f;
    tokens.pad = 2.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

SkinTokens GraphiteTokens(bool dark)
{
    SkinTokens tokens = FluentTokens(dark);
    if (dark)
    {
        tokens.surface = Rgb(0x1C1F23);
        tokens.border = Rgb(0x30353B);
        tokens.text = Rgb(0xAEB6C2);
        tokens.number = Rgb(0x707987);
        tokens.selected = Rgba{0.0f, 0.0f, 0.0f, 0.0f};
        tokens.selectedText = Rgb(0xF1F3F5);
        tokens.hover = Rgba{1.0f, 1.0f, 1.0f, 0.055f};
        tokens.accent = Rgb(0x8993A0);
    }
    else
    {
        tokens.surface = Rgb(0xFBFBFC);
        tokens.border = Rgb(0xE2E5E9);
        tokens.text = Rgb(0x586476);
        tokens.number = Rgb(0x8993A1);
        tokens.selected = Rgba{0.0f, 0.0f, 0.0f, 0.0f};
        tokens.selectedText = Rgb(0x111827);
        tokens.hover = Rgba{31.0f / 255.0f, 41.0f / 255.0f, 55.0f / 255.0f, 0.055f};
        tokens.accent = Rgb(0x5F6B7A);
    }
    tokens.radius = 3.0f;
    tokens.borderWidth = 1.0f;
    tokens.pad = 5.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

SkinTokens WillowGreenTokens(bool dark)
{
    SkinTokens tokens = FluentTokens(dark);
    if (dark)
    {
        tokens.surface = Rgb(0x2D2F2E);
        tokens.text = Rgb(0xD8DBD8);
        tokens.number = Rgb(0xA6ABA7);
        tokens.accent = Rgb(0x65C98D);
        tokens.selected = Rgb(0x65C98D);
        tokens.hover = Rgb(0x65C98D, 0.22f);
    }
    else
    {
        tokens.surface = Rgb(0xF4F5F3);
        tokens.text = Rgb(0x333333);
        tokens.number = Rgb(0x757575);
        tokens.accent = Rgb(0x58B980);
        tokens.selected = Rgb(0x58B980);
        tokens.hover = Rgb(0x58B980, 0.16f);
    }
    tokens.selectedText = Rgb(0xFFFFFF);
    tokens.border = Rgba{0.0f, 0.0f, 0.0f, 0.0f};
    tokens.radius = 9.0f;
    tokens.borderWidth = 0.0f;
    tokens.pad = 0.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

}
SkinTokens BuiltInSkinTokens(std::string_view id, bool dark)
{
    if (id == "wechat")
    {
        return WeChatTokens(dark);
    }
    if (id == "graphite")
    {
        return GraphiteTokens(dark);
    }
    if (id == "willow_green")
    {
        return WillowGreenTokens(dark);
    }
    return FluentTokens(dark);
}

}
