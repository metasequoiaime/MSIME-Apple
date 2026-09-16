// Adapted from MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
#include "CandidateSkin.h"

#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <map>
#include <sstream>
#include <system_error>
#include <unordered_map>
#include <utility>

namespace msime::mac
{
namespace
{
constexpr Rgba Rgb(unsigned rgb, float alpha = 1.0f)
{
    return {((rgb >> 16) & 0xFFu) / 255.0f, ((rgb >> 8) & 0xFFu) / 255.0f, (rgb & 0xFFu) / 255.0f, alpha};
}

float LinearChannel(float component)
{
    return component <= 0.04045f ? component / 12.92f : std::pow((component + 0.055f) / 1.055f, 2.4f);
}

float RelativeLuminance(Rgba color)
{
    return (0.2126f * LinearChannel(color.r)) + (0.7152f * LinearChannel(color.g)) + (0.0722f * LinearChannel(color.b));
}

Rgba ContrastingText(Rgba fill, Rgba fallback)
{
    if (fill.a < 0.85f)
    {
        return fallback;
    }
    return RelativeLuminance(fill) < 0.45f ? Rgba{1.0f, 1.0f, 1.0f, 1.0f} : Rgba{0.1f, 0.1f, 0.1f, 1.0f};
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
    tokens.selectedHover = tokens.hover;
    tokens.accent = Rgb(0x6B69D6);
    tokens.radius = 6.0f;
    tokens.candidateRadius = 4.0f;
    tokens.selectedRadius = 4.0f;
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
    tokens.selectedHover = tokens.selected;
    tokens.radius = 5.0f;
    tokens.candidateRadius = 4.0f;
    tokens.selectedRadius = 5.0f;
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
        tokens.selectedHover = tokens.hover;
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
        tokens.selectedHover = tokens.hover;
        tokens.accent = Rgb(0x5F6B7A);
    }
    tokens.radius = 3.0f;
    tokens.candidateRadius = 2.0f;
    tokens.selectedRadius = 2.0f;
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
    tokens.selectedHover = tokens.selected;
    tokens.selectedText = Rgb(0xFFFFFF);
    tokens.border = Rgba{0.0f, 0.0f, 0.0f, 0.0f};
    tokens.radius = 9.0f;
    tokens.candidateRadius = 0.0f;
    tokens.selectedRadius = 0.0f;
    tokens.borderWidth = 0.0f;
    tokens.pad = 0.0f;
    tokens.showSelectedBar = false;
    return tokens;
}

std::string Trim(std::string text)
{
    while (!text.empty() && std::isspace(static_cast<unsigned char>(text.front())))
    {
        text.erase(text.begin());
    }
    while (!text.empty() && std::isspace(static_cast<unsigned char>(text.back())))
    {
        text.pop_back();
    }
    return text;
}

std::string StripComment(const std::string &line)
{
    bool inString = false;
    bool escape = false;
    for (std::size_t index = 0; index < line.size(); ++index)
    {
        const char ch = line[index];
        if (escape)
        {
            escape = false;
            continue;
        }
        if (inString && ch == '\\')
        {
            escape = true;
            continue;
        }
        if (ch == '"')
        {
            inString = !inString;
            continue;
        }
        if (!inString && ch == '#')
        {
            return line.substr(0, index);
        }
    }
    return line;
}

bool IsSafeFileName(const std::string &name, const std::string &extension)
{
    if (name.empty() || name.size() > 128 || name.size() <= extension.size() ||
        name.substr(name.size() - extension.size()) != extension)
    {
        return false;
    }
    return std::all_of(name.begin(), name.end(),
                       [](unsigned char ch) { return std::isalnum(ch) || ch == '.' || ch == '_' || ch == '-'; });
}

bool IsSafeRelativeResource(const std::string &name)
{
    if (name.empty() || name.size() > 256 || name.front() == '/' || name.find('\\') != std::string::npos)
    {
        return false;
    }
    if (!std::all_of(name.begin(), name.end(), [](unsigned char ch) {
            return std::isalnum(ch) || ch == '/' || ch == '.' || ch == '_' || ch == '-';
        }))
    {
        return false;
    }
    const std::filesystem::path path(name);
    if (path.is_absolute())
    {
        return false;
    }
    for (const auto &part : path)
    {
        if (part == ".." || part == "." || part.empty())
        {
            return false;
        }
    }
    return true;
}

struct TomlTable
{
    std::map<std::string, std::string> scalars;
    std::map<std::string, std::vector<std::string>> arrays;
    std::map<std::string, TomlTable> children;
};

bool DecodeString(const std::string &raw, std::string &out)
{
    if (raw.size() < 2 || raw.front() != '"' || raw.back() != '"')
    {
        return false;
    }
    out.clear();
    bool escape = false;
    for (std::size_t index = 1; index + 1 < raw.size(); ++index)
    {
        const char ch = raw[index];
        if (escape)
        {
            if (ch == 'n')
            {
                out.push_back('\n');
            }
            else
            {
                out.push_back(ch);
            }
            escape = false;
            continue;
        }
        if (ch == '\\')
        {
            escape = true;
            continue;
        }
        out.push_back(ch);
    }
    return !escape;
}

bool ParseScalar(const std::string &raw, std::string &out)
{
    const std::string value = Trim(raw);
    if (value.empty())
    {
        return false;
    }
    if (value.front() == '"')
    {
        return DecodeString(value, out);
    }
    out = value;
    return true;
}

bool ParseStringArray(const std::string &raw, std::vector<std::string> &out)
{
    const std::string value = Trim(raw);
    if (value.size() < 2 || value.front() != '[' || value.back() != ']')
    {
        return false;
    }
    out.clear();
    std::string inner = Trim(value.substr(1, value.size() - 2));
    if (inner.empty())
    {
        return true;
    }
    std::string current;
    bool inString = false;
    bool escape = false;
    for (char ch : inner)
    {
        if (escape)
        {
            current.push_back(ch);
            escape = false;
            continue;
        }
        if (inString && ch == '\\')
        {
            current.push_back(ch);
            escape = true;
            continue;
        }
        if (ch == '"')
        {
            current.push_back(ch);
            inString = !inString;
            continue;
        }
        if (!inString && ch == ',')
        {
            std::string item;
            if (!ParseScalar(current, item))
            {
                return false;
            }
            out.push_back(std::move(item));
            current.clear();
            continue;
        }
        current.push_back(ch);
    }
    if (inString)
    {
        return false;
    }
    std::string item;
    if (!ParseScalar(current, item))
    {
        return false;
    }
    out.push_back(std::move(item));
    return true;
}

TomlTable *EnsureTable(TomlTable &root, const std::vector<std::string> &path)
{
    TomlTable *current = &root;
    for (const std::string &part : path)
    {
        current = &current->children[part];
    }
    return current;
}

std::vector<std::string> SplitDotted(const std::string &path)
{
    std::vector<std::string> parts;
    std::string current;
    for (char ch : path)
    {
        if (ch == '.')
        {
            if (current.empty())
            {
                return {};
            }
            parts.push_back(current);
            current.clear();
        }
        else
        {
            current.push_back(ch);
        }
    }
    if (!current.empty())
    {
        parts.push_back(current);
    }
    return parts;
}

bool ParseToml(const std::string &text, TomlTable &root)
{
    root = {};
    std::vector<std::string> currentPath;
    std::istringstream stream(text);
    std::string rawLine;
    while (std::getline(stream, rawLine))
    {
        if (!rawLine.empty() && rawLine.back() == '\r')
        {
            rawLine.pop_back();
        }
        const std::string line = Trim(StripComment(rawLine));
        if (line.empty())
        {
            continue;
        }
        if (line.front() == '[' && line.back() == ']')
        {
            const std::string header = Trim(line.substr(1, line.size() - 2));
            currentPath = SplitDotted(header);
            if (currentPath.empty())
            {
                return false;
            }
            EnsureTable(root, currentPath);
            continue;
        }
        const auto equal = line.find('=');
        if (equal == std::string::npos)
        {
            return false;
        }
        const std::string key = Trim(line.substr(0, equal));
        const std::string rawValue = Trim(line.substr(equal + 1));
        if (key.empty())
        {
            return false;
        }
        TomlTable *table = EnsureTable(root, currentPath);
        if (!rawValue.empty() && rawValue.front() == '[')
        {
            std::vector<std::string> items;
            if (!ParseStringArray(rawValue, items))
            {
                return false;
            }
            table->arrays[key] = std::move(items);
        }
        else
        {
            std::string scalar;
            if (!ParseScalar(rawValue, scalar))
            {
                return false;
            }
            table->scalars[key] = std::move(scalar);
        }
    }
    return true;
}

const TomlTable *Child(const TomlTable &table, const char *key)
{
    const auto found = table.children.find(key);
    return found == table.children.end() ? nullptr : &found->second;
}

bool ReadString(const TomlTable &table, const char *key, std::string &out, std::size_t maximum, bool required)
{
    const auto found = table.scalars.find(key);
    if (found == table.scalars.end())
    {
        return !required;
    }
    out = found->second;
    return (!required || !out.empty()) && out.size() <= maximum;
}

bool ReadEnumArray(const TomlTable &table, const char *key, const std::vector<std::string> &allowed,
                   std::vector<std::string> &out)
{
    const auto found = table.arrays.find(key);
    if (found == table.arrays.end() || found->second.empty())
    {
        return false;
    }
    for (const std::string &text : found->second)
    {
        if (std::find(allowed.begin(), allowed.end(), text) == allowed.end() ||
            std::find(out.begin(), out.end(), text) != out.end())
        {
            return false;
        }
        out.push_back(text);
    }
    return true;
}

double BoundedNumber(const TomlTable &table, const char *key, double maximum)
{
    const auto found = table.scalars.find(key);
    if (found == table.scalars.end())
    {
        return 0.0;
    }
    char *end = nullptr;
    const double value = std::strtod(found->second.c_str(), &end);
    if (end == found->second.c_str() || (end != nullptr && *end != '\0') || !std::isfinite(value) || value < 0.0 ||
        value > maximum)
    {
        return -1.0;
    }
    return value;
}

bool ReadColors(const TomlTable *table, SkinColors &out)
{
    if (table == nullptr)
    {
        return true;
    }
    if ((table->scalars.count("accent") && !ReadString(*table, "accent", out.accent, 80, false)) ||
        (table->scalars.count("selected") && !ReadString(*table, "selected", out.selected, 80, false)) ||
        (table->scalars.count("hover") && !ReadString(*table, "hover", out.hover, 80, false)) ||
        (table->scalars.count("surface") && !ReadString(*table, "surface", out.surface, 80, false)) ||
        (table->scalars.count("border") && !ReadString(*table, "border", out.border, 80, false)) ||
        (table->scalars.count("text") && !ReadString(*table, "text", out.text, 80, false)) ||
        (table->scalars.count("number") && !ReadString(*table, "number", out.number, 80, false)))
    {
        return false;
    }
    const auto bar = table->scalars.find("show_selected_bar");
    if (bar != table->scalars.end())
    {
        if (bar->second != "true" && bar->second != "false")
        {
            return false;
        }
        out.showSelectedBar = bar->second == "true";
    }
    return true;
}

void ApplyPackageColors(const SkinColors &colors, SkinTokens &tokens)
{
    if (const auto parsed = ParseCssColor(colors.accent))
    {
        tokens.accent = *parsed;
    }
    if (const auto parsed = ParseCssColor(colors.selected))
    {
        tokens.selected = *parsed;
    }
    if (const auto parsed = ParseCssColor(colors.hover))
    {
        tokens.hover = *parsed;
    }
    if (const auto parsed = ParseCssColor(colors.surface))
    {
        tokens.surface = *parsed;
    }
    if (const auto parsed = ParseCssColor(colors.border))
    {
        tokens.border = *parsed;
    }
    if (const auto parsed = ParseCssColor(colors.text))
    {
        tokens.text = *parsed;
    }
    if (const auto parsed = ParseCssColor(colors.number))
    {
        tokens.number = *parsed;
    }
    if (colors.showSelectedBar.has_value())
    {
        tokens.showSelectedBar = *colors.showSelectedBar;
    }
    tokens.selectedText = ContrastingText(tokens.selected, tokens.text);
}

void SetError(std::string *error, const std::string &message)
{
    if (error != nullptr)
    {
        *error = message;
    }
}

bool IsContained(const std::filesystem::path &root, const std::filesystem::path &resource)
{
    if (root.empty()) return false;
    std::error_code ec;
    const auto canonicalRoot = std::filesystem::weakly_canonical(root, ec);
    if (ec) return false;
    const auto canonicalResource = std::filesystem::weakly_canonical(resource, ec);
    if (ec) return false;
    const auto relative = canonicalResource.lexically_relative(canonicalRoot);
    return !relative.empty() && !relative.is_absolute() &&
           std::none_of(relative.begin(), relative.end(), [](const auto &part) { return part == ".."; });
}

void ApplyToolbarStylesheet(const std::filesystem::path &skinsRoot, const SkinPackage &package, bool dark,
                            SkinTokens &tokens);
} // namespace

bool IsBuiltInSkinId(std::string_view id)
{
    return id == "fluent" || id == "wechat" || id == "graphite" || id == "willow_green";
}

bool IsSafeSkinId(std::string_view id)
{
    if (id.empty() || id.size() > 64 || !std::isalnum(static_cast<unsigned char>(id.front())))
    {
        return false;
    }
    return std::all_of(id.begin(), id.end(), [](unsigned char ch) {
        return std::islower(ch) || std::isdigit(ch) || ch == '.' || ch == '_' || ch == '-';
    });
}

std::string NormalizeSkinId(std::string_view id)
{
    return IsSafeSkinId(id) ? std::string(id) : std::string("fluent");
}

const std::vector<SkinListEntry> &BuiltInSkinEntries()
{
    static const std::vector<SkinListEntry> entries = {
        {"fluent", "Fluent", true},
        {"wechat", "微信绿", true},
        {"graphite", "石墨 Graphite", true},
        {"willow_green", "杨柳青", true},
    };
    return entries;
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

SkinTokens ToolbarSkinTokens(std::string_view id, bool dark)
{
    return ToolbarSkinTokens(id, dark, DefaultSkinsRoot());
}

std::optional<Rgba> ParseCssColor(std::string_view text)
{
    std::string value = Trim(std::string(text));
    if (value.empty() || value == "auto" || value == "none")
    {
        return std::nullopt;
    }
    if (value == "transparent")
    {
        return Rgba{0.0f, 0.0f, 0.0f, 0.0f};
    }
    if (value.rfind("rgba(", 0) == 0 || value.rfind("rgb(", 0) == 0)
    {
        const auto open = value.find('(');
        const auto close = value.rfind(')');
        if (open == std::string::npos || close == std::string::npos || close <= open || close != value.size() - 1)
        {
            return std::nullopt;
        }
        std::string inner = value.substr(open + 1, close - open - 1);
        for (char &ch : inner)
        {
            if (ch == ',' || ch == '/')
            {
                ch = ' ';
            }
        }
        std::istringstream stream(inner);
        float r = 0;
        float g = 0;
        float b = 0;
        float a = 1.0f;
        if (!(stream >> r >> g >> b))
        {
            return std::nullopt;
        }
        stream >> std::ws;
        if (!stream.eof()) {
            if (!(stream >> a)) return std::nullopt;
            stream >> std::ws;
        }
        if (!stream.eof() || !std::isfinite(r) || !std::isfinite(g) || !std::isfinite(b) || !std::isfinite(a) ||
            r < 0 || r > 255 || g < 0 || g > 255 || b < 0 || b > 255 || a < 0 || a > 1)
            return std::nullopt;
        return Rgba{r / 255.0f, g / 255.0f, b / 255.0f, a};
    }
    if (value.front() == '#')
    {
        value.erase(value.begin());
    }
    if (!std::all_of(value.begin(), value.end(), [](unsigned char ch) { return std::isxdigit(ch); }))
        return std::nullopt;
    auto hexByte = [](const std::string &hex) { return static_cast<int>(std::stoul(hex, nullptr, 16)); };
    try
    {
        if (value.size() == 3)
        {
            return Rgba{hexByte(std::string(2, value[0])) / 255.0f, hexByte(std::string(2, value[1])) / 255.0f,
                        hexByte(std::string(2, value[2])) / 255.0f, 1.0f};
        }
        if (value.size() == 6)
        {
            return Rgb(static_cast<unsigned>(std::stoul(value, nullptr, 16)));
        }
        if (value.size() == 8)
        {
            const unsigned long packed = std::stoul(value, nullptr, 16);
            return Rgb(static_cast<unsigned>((packed >> 8) & 0xFFFFFFu), static_cast<float>(packed & 0xFFu) / 255.0f);
        }
    }
    catch (...)
    {
    }
    return std::nullopt;
}

namespace
{
std::string Lowercase(std::string value)
{
    std::transform(value.begin(), value.end(), value.begin(),
                   [](unsigned char ch) { return static_cast<char>(std::tolower(ch)); });
    return value;
}

std::string StripCssComments(std::string text)
{
    std::size_t cursor = 0;
    while ((cursor = text.find("/*", cursor)) != std::string::npos)
    {
        const std::size_t end = text.find("*/", cursor + 2);
        if (end == std::string::npos)
        {
            text.erase(cursor);
            break;
        }
        text.erase(cursor, end + 2 - cursor);
    }
    return text;
}

std::optional<Rgba> FindCssColor(std::string value)
{
    value = Trim(value);
    if (const auto direct = ParseCssColor(value))
    {
        return direct;
    }
    for (const char *prefix : {"rgba(", "rgb("})
    {
        const std::size_t begin = value.find(prefix);
        if (begin != std::string::npos)
        {
            const std::size_t end = value.find(')', begin + std::char_traits<char>::length(prefix));
            if (end != std::string::npos)
            {
                if (const auto parsed = ParseCssColor(value.substr(begin, end - begin + 1)))
                {
                    return parsed;
                }
            }
        }
    }
    const std::size_t hash = value.find('#');
    if (hash != std::string::npos)
    {
        std::size_t end = hash + 1;
        while (end < value.size() && std::isxdigit(static_cast<unsigned char>(value[end]))) ++end;
        if (const auto parsed = ParseCssColor(value.substr(hash, end - hash)))
        {
            return parsed;
        }
    }
    return std::nullopt;
}

std::optional<float> ParseCssLength(std::string value)
{
    value = Trim(value);
    char *end = nullptr;
    const float number = std::strtof(value.c_str(), &end);
    if (end == value.c_str() || !std::isfinite(number) || number < 0.0f || number > 64.0f)
    {
        return std::nullopt;
    }
    const std::string unit = Lowercase(Trim(end));
    if (!unit.empty() && unit != "px")
    {
        return std::nullopt;
    }
    return number;
}

std::string ResolveCssVariable(std::string value, const std::unordered_map<std::string, std::string> &variables)
{
    for (int pass = 0; pass < 4; ++pass)
    {
        const std::size_t begin = value.find("var(");
        if (begin == std::string::npos) break;
        const std::size_t end = value.find(')', begin + 4);
        if (end == std::string::npos) break;
        std::string key = Trim(value.substr(begin + 4, end - begin - 4));
        const std::size_t fallback = key.find(',');
        std::string replacement;
        if (fallback != std::string::npos)
        {
            replacement = Trim(key.substr(fallback + 1));
            key = Trim(key.substr(0, fallback));
        }
        key = Lowercase(key);
        const auto found = variables.find(key);
        if (found != variables.end()) replacement = found->second;
        if (replacement.empty()) break;
        value.replace(begin, end - begin + 1, replacement);
    }
    return value;
}

void ApplyToolbarCssProperty(std::string property, std::string value, const std::string &selector,
                             const std::unordered_map<std::string, std::string> &variables, SkinTokens &tokens)
{
    property = Lowercase(Trim(property));
    value = ResolveCssVariable(Trim(value), variables);
    const std::string loweredSelector = Lowercase(selector);
    const bool hover = loweredSelector.find(":hover") != std::string::npos || loweredSelector.find("hover") != std::string::npos;
    const bool selected = loweredSelector.find(":active") != std::string::npos ||
                          loweredSelector.find("selected") != std::string::npos ||
                          loweredSelector.find("active") != std::string::npos;
    auto colorTarget = [&](const std::optional<Rgba> &color, const std::string &customProperty) {
        if (!color) return;
        if (customProperty == "accent") tokens.accent = *color;
        else if (customProperty == "selected") tokens.selected = *color;
        else if (customProperty == "hover") tokens.hover = *color;
        else if (customProperty == "surface") tokens.surface = *color;
        else if (customProperty == "border") tokens.border = *color;
        else if (customProperty == "text") tokens.text = *color;
    };
    if (!property.empty() && property.front() == '-')
    {
        static const std::pair<const char *, const char *> names[] = {
            {"--toolbar-accent", "accent"}, {"--ftb-accent", "accent"}, {"--accent-color", "accent"},
            {"--accent-strong", "accent"},   {"--toolbar-selected", "selected"}, {"--ftb-selected", "selected"},
            {"--toolbar-hover", "hover"},    {"--ftb-hover", "hover"}, {"--toolbar-bg", "surface"},
            {"--toolbar-background", "surface"}, {"--toolbar-surface", "surface"}, {"--ftb-bg", "surface"},
            {"--toolbar-border", "border"},  {"--ftb-border", "border"}, {"--toolbar-text", "text"},
            {"--ftb-text", "text"},
        };
        for (const auto &[name, target] : names)
        {
            if (property == name)
            {
                colorTarget(FindCssColor(value), target);
                break;
            }
        }
        if (property == "--toolbar-radius" || property == "--ftb-radius")
        {
            if (const auto length = ParseCssLength(value)) tokens.radius = *length;
        }
        if (property == "--toolbar-border-width" || property == "--ftb-border-width")
        {
            if (const auto length = ParseCssLength(value)) tokens.borderWidth = *length;
        }
        if (property == "--toolbar-padding" || property == "--ftb-padding")
        {
            if (const auto length = ParseCssLength(value)) tokens.pad = *length;
        }
        return;
    }
    if (property == "color")
    {
        colorTarget(FindCssColor(value), "text");
    }
    else if (property == "background" || property == "background-color")
    {
        colorTarget(FindCssColor(value), selected ? "selected" : hover ? "hover" : "surface");
    }
    else if (property == "border-color" || property == "outline-color")
    {
        colorTarget(FindCssColor(value), "border");
    }
    else if (property == "border")
    {
        colorTarget(FindCssColor(value), "border");
        const std::string width = Trim(value.substr(0, value.find_first_of(" \\t")));
        if (const auto length = ParseCssLength(width)) tokens.borderWidth = *length;
    }
    else if (property == "accent-color")
    {
        colorTarget(FindCssColor(value), "accent");
    }
    else if (property == "border-radius")
    {
        if (const auto length = ParseCssLength(value)) tokens.radius = *length;
    }
    else if (property == "border-width")
    {
        if (const auto length = ParseCssLength(value)) tokens.borderWidth = *length;
    }
    else if (property == "padding" || property == "padding-left" || property == "padding-inline")
    {
        if (const auto length = ParseCssLength(value)) tokens.pad = *length;
    }
}

void ApplyToolbarStylesheet(const std::filesystem::path &skinsRoot, const SkinPackage &package, bool dark,
                            SkinTokens &tokens)
{
    if (package.toolbarStylesheet.empty()) return;
    const std::filesystem::path stylesheet = skinsRoot / package.id / package.toolbarStylesheet;
    std::error_code ec;
    if (!IsContained(skinsRoot / package.id, stylesheet) || !std::filesystem::is_regular_file(stylesheet, ec) || ec)
        return;
    std::ifstream stream(stylesheet);
    if (!stream) return;
    stream.seekg(0, std::ios::end);
    const std::streamoff size = stream.tellg();
    if (size < 0 || static_cast<std::size_t>(size) > 65536) return;
    stream.seekg(0);
    const std::string css = StripCssComments(std::string((std::istreambuf_iterator<char>(stream)), {}));
    std::unordered_map<std::string, std::string> variables;
    std::size_t cursor = 0;
    while (cursor < css.size())
    {
        const std::size_t open = css.find('{', cursor);
        if (open == std::string::npos) break;
        const std::size_t close = css.find('}', open + 1);
        if (close == std::string::npos) break;
        const std::string selector = Trim(css.substr(cursor, open - cursor));
        cursor = close + 1;
        if (selector.empty() || selector.front() == '@') continue;
        const std::string lowered = Lowercase(selector);
        if ((lowered.find("dark") != std::string::npos && !dark) ||
            (lowered.find("light") != std::string::npos && dark))
            continue;
        std::vector<std::pair<std::string, std::string>> declarations;
        std::stringstream block(css.substr(open + 1, close - open - 1));
        std::string declaration;
        while (std::getline(block, declaration, ';'))
        {
            const std::size_t colon = declaration.find(':');
            if (colon == std::string::npos) continue;
            std::string property = Trim(declaration.substr(0, colon));
            std::string value = Trim(declaration.substr(colon + 1));
            if (property.empty() || value.empty()) continue;
            if (value.size() >= 10 && Lowercase(value.substr(value.size() - 10)) == "!important")
                value = Trim(value.substr(0, value.size() - 10));
            declarations.emplace_back(std::move(property), std::move(value));
        }
        for (const auto &[property, value] : declarations)
            if (!property.empty() && property.front() == '-') variables[Lowercase(Trim(property))] = value;
        for (const auto &[property, value] : declarations)
            ApplyToolbarCssProperty(property, value, selector, variables, tokens);
    }
    tokens.selectedText = ContrastingText(tokens.selected, tokens.text);
}
} // namespace

SkinTokens ToolbarSkinTokens(std::string_view id, bool dark, const std::filesystem::path &skinsRoot)
{
    const bool builtin = IsBuiltInSkinId(id);
    SkinTokens tokens = BuiltInSkinTokens(builtin ? id : "fluent", dark);
    // The default toolbar accent is intentionally lighter than the Fluent
    // candidate-card accent. External packages may override this native
    // palette only through the primitive properties understood above; CSS
    // layout, scripts, images and effects never enter the AppKit view.
    if (!builtin || id == "fluent") tokens.accent = Rgb(0x8E8CD8);
    if (!builtin)
    {
        std::string error;
        if (const auto package = LoadSkinPackage(skinsRoot, std::string(id), &error))
            ApplyToolbarStylesheet(skinsRoot, *package, dark, tokens);
    }
    return tokens;
}

std::optional<SkinPackage> LoadSkinPackage(const std::filesystem::path &skinsRoot, const std::string &id,
                                           std::string *error)
{
    if (!IsSafeSkinId(id) || IsBuiltInSkinId(id))
    {
        SetError(error, "目录名不是有效的外部皮肤 ID");
        return std::nullopt;
    }
    const std::filesystem::path directory = skinsRoot / id;
    const std::filesystem::path manifest = directory / "skin.toml";
    std::error_code ec;
    if (!IsContained(skinsRoot, directory) || !IsContained(directory, manifest) ||
        !std::filesystem::is_regular_file(manifest, ec) || ec)
    {
        SetError(error, "皮肤 manifest 不在有效包目录内");
        return std::nullopt;
    }
    std::ifstream stream(manifest);
    if (!stream)
    {
        SetError(error, "缺少或无法解析 skin.toml");
        return std::nullopt;
    }
    stream.seekg(0, std::ios::end);
    const std::streamoff size = stream.tellg();
    if (size < 0 || static_cast<std::size_t>(size) > 65536)
    {
        SetError(error, "skin.toml 过大");
        return std::nullopt;
    }
    stream.seekg(0);
    const std::string text((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
    TomlTable root;
    if (!ParseToml(text, root))
    {
        SetError(error, "skin.toml 不是有效的 TOML manifest");
        return std::nullopt;
    }
    if (root.scalars["schema_version"] != "1")
    {
        SetError(error, "仅支持 schema_version 1");
        return std::nullopt;
    }
    SkinPackage package;
    if (!ReadString(root, "id", package.id, 64, true) || package.id != id ||
        !ReadString(root, "name", package.name, 80, true) || !ReadString(root, "version", package.version, 32, true) ||
        !ReadString(root, "author", package.author, 120, false) ||
        !ReadString(root, "description", package.description, 500, false) ||
        !ReadString(root, "base", package.base, 32, true) || !IsBuiltInSkinId(package.base))
    {
        SetError(error, "manifest 的基本信息无效");
        return std::nullopt;
    }
    if (root.scalars.count("toolbar_stylesheet") &&
        (!ReadString(root, "toolbar_stylesheet", package.toolbarStylesheet, 128, true) ||
         !IsSafeFileName(package.toolbarStylesheet, ".css") ||
         !IsContained(directory, directory / package.toolbarStylesheet)))
    {
        SetError(error, "toolbar_stylesheet 文件名无效");
        return std::nullopt;
    }
    if (!package.toolbarStylesheet.empty() &&
        !std::filesystem::is_regular_file(directory / package.toolbarStylesheet, ec))
    {
        SetError(error, "找不到 toolbar_stylesheet 文件");
        return std::nullopt;
    }
    if (root.scalars.count("preview") &&
        (!ReadString(root, "preview", package.preview, 256, false) || !IsSafeRelativeResource(package.preview) ||
         !IsContained(directory, directory / package.preview)))
    {
        SetError(error, "preview 必须是皮肤目录内的相对路径");
        return std::nullopt;
    }
    const TomlTable *supports = Child(root, "supports");
    if (supports == nullptr || !ReadEnumArray(*supports, "layouts", {"horizontal", "vertical"}, package.layouts) ||
        !ReadEnumArray(*supports, "themes", {"dark", "light"}, package.themes))
    {
        SetError(error, "supports.layouts 或 supports.themes 无效");
        return std::nullopt;
    }
    const TomlTable *window = Child(root, "candidate_window");
    if (window == nullptr)
    {
        SetError(error, "缺少 candidate_window");
        return std::nullopt;
    }
    package.minWidthDip = BoundedNumber(*window, "min_width_dip", 1000.0);
    if (package.minWidthDip < 0.0)
    {
        SetError(error, "candidate_window.min_width_dip 超出范围");
        return std::nullopt;
    }
    const TomlTable *decoration = Child(*window, "decoration");
    if (decoration == nullptr)
    {
        SetError(error, "缺少 candidate_window.decoration");
        return std::nullopt;
    }
    package.decorationTopDip = BoundedNumber(*decoration, "top_inset_dip", 500.0);
    package.decorationWidthDip = BoundedNumber(*decoration, "width_dip", 1000.0);
    if (package.decorationTopDip < 0.0 || package.decorationWidthDip < 0.0 ||
        ((package.decorationTopDip == 0.0) != (package.decorationWidthDip == 0.0)))
    {
        SetError(error, "decoration 尺寸无效");
        return std::nullopt;
    }
    const TomlTable *candidate = Child(root, "candidate");
    if (candidate != nullptr && (!ReadColors(Child(*candidate, "dark"), package.dark) ||
                                 !ReadColors(Child(*candidate, "light"), package.light)))
    {
        SetError(error, "candidate 配色无效");
        return std::nullopt;
    }
    return package;
}

bool SupportsSkin(const SkinPackage &package, std::string_view layout, std::string_view theme)
{
    const auto contains = [](const std::vector<std::string> &values, std::string_view value) {
        return std::find(values.begin(), values.end(), value) != values.end();
    };
    return contains(package.layouts, layout) && contains(package.themes, theme);
}

SkinCatalog ScanSkinCatalog(const std::filesystem::path &skinsRoot)
{
    SkinCatalog result;
    std::error_code ec;
    if (skinsRoot.empty() || !std::filesystem::exists(skinsRoot, ec))
    {
        return result;
    }
    for (std::filesystem::directory_iterator it(skinsRoot, ec), end; !ec && it != end; it.increment(ec))
    {
        if (!it->is_directory(ec))
        {
            continue;
        }
        const std::string folder = it->path().filename().string();
        std::string error;
        auto package = LoadSkinPackage(skinsRoot, folder, &error);
        if (package)
        {
            result.packages.push_back(std::move(*package));
        }
        else
        {
            result.issues.push_back({folder, error});
        }
    }
    if (ec)
    {
        result.issues.push_back({"skins", "无法完整读取皮肤目录"});
    }
    std::sort(result.packages.begin(), result.packages.end(),
              [](const SkinPackage &a, const SkinPackage &b) { return a.name < b.name; });
    std::sort(result.issues.begin(), result.issues.end(),
              [](const SkinIssue &a, const SkinIssue &b) { return a.folder < b.folder; });
    return result;
}

std::vector<SkinListEntry> ListSkins(const std::filesystem::path &skinsRoot)
{
    std::vector<SkinListEntry> entries = BuiltInSkinEntries();
    const SkinCatalog catalog = ScanSkinCatalog(skinsRoot);
    for (const SkinPackage &package : catalog.packages)
    {
        entries.push_back({package.id, package.name, false});
    }
    return entries;
}

ResolvedSkin ResolveSkin(std::string_view id, bool dark, const std::filesystem::path &skinsRoot)
{
    return ResolveSkin(id, dark, skinsRoot, {}, {});
}

ResolvedSkin ResolveSkin(std::string_view id, bool dark, const std::filesystem::path &skinsRoot,
                         std::string_view layout, std::string_view theme)
{
    const std::string normalized = NormalizeSkinId(id);
    ResolvedSkin resolved;
    resolved.id = "fluent";
    resolved.name = "Fluent";
    resolved.tokens = FluentTokens(dark);
    if (IsBuiltInSkinId(normalized))
    {
        resolved.id = normalized;
        for (const SkinListEntry &entry : BuiltInSkinEntries())
        {
            if (entry.id == normalized)
            {
                resolved.name = entry.name;
                break;
            }
        }
        resolved.tokens = BuiltInSkinTokens(normalized, dark);
        return resolved;
    }
    std::optional<SkinPackage> package = LoadSkinPackage(skinsRoot, normalized);
    if (!package)
    {
        return resolved;
    }
    if ((!layout.empty() || !theme.empty()) && !SupportsSkin(*package, layout, theme))
    {
        return resolved;
    }
    resolved.id = package->id;
    resolved.name = package->name;
    resolved.tokens = BuiltInSkinTokens(package->base, dark);
    ApplyPackageColors(dark ? package->dark : package->light, resolved.tokens);
    resolved.decorationTopDip = package->decorationTopDip;
    resolved.decorationWidthDip = package->decorationWidthDip;
    resolved.minWidthDip = package->minWidthDip;
    if (!package->preview.empty())
    {
        resolved.decorationPath = (skinsRoot / package->id / package->preview).string();
    }
    return resolved;
}

std::filesystem::path DefaultSkinsRoot()
{
    const char *home = std::getenv("HOME");
    if (home == nullptr || home[0] == '\0')
    {
        return {};
    }
    return std::filesystem::path(home) / "Library" / "Application Support" / "app.msime.client.preview" / "skins";
}
} // namespace msime::mac
