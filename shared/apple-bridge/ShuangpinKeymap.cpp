#include "ShuangpinKeymap.h"

#include "shuangpin/shuangpin_profile.h"

#include <algorithm>
#include <cctype>
#include <unordered_map>
#include <vector>

namespace metasequoia::apple
{
namespace
{
// The engine spells the ü finals with a leading v because that is what the key sequence uses. The
// hint is read by a person, so show the vowel.
std::string display_unit(const std::string &unit)
{
    if (!unit.empty() && unit.front() == 'v')
    {
        return "ü" + unit.substr(1);
    }
    return unit;
}

std::string upper(const std::string &value)
{
    std::string result = value;
    std::transform(result.begin(), result.end(), result.begin(),
                   [](unsigned char character) { return static_cast<char>(std::toupper(character)); });
    return result;
}

void collect(const std::unordered_map<std::string, std::string> &mapping,
             std::map<std::string, std::vector<std::string>> &units_by_key)
{
    for (const auto &[unit, key] : mapping)
    {
        units_by_key[upper(key)].push_back(display_unit(unit));
    }
}

std::string join(std::vector<std::string> units)
{
    std::sort(units.begin(), units.end());
    std::string joined;
    for (const auto &unit : units)
    {
        if (!joined.empty())
        {
            joined += " ";
        }
        joined += unit;
    }
    return joined;
}
} // namespace

std::map<std::string, std::string> shuangpin_key_hints(bool uses_shuangpin, const std::string &profile_name)
{
    if (!uses_shuangpin)
    {
        return {};
    }

    const ShuangpinProfile &profile = GetShuangpinProfile(profile_name);
    std::map<std::string, std::vector<std::string>> initials_by_key;
    std::map<std::string, std::vector<std::string>> finals_by_key;
    collect(profile.initials, initials_by_key);
    collect(profile.finals, finals_by_key);

    std::map<std::string, std::string> hints;
    for (const auto &key : {"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "A", "S", "D", "F",
                            "G", "H", "J", "K", "L", "Z", "X", "C", "V", "B", "N", "M", ";"})
    {
        const std::string initials = join(initials_by_key[key]);
        const std::string finals = join(finals_by_key[key]);
        if (initials.empty() && finals.empty())
        {
            continue;
        }
        if (initials.empty())
        {
            hints[key] = finals;
        }
        else if (finals.empty())
        {
            hints[key] = initials;
        }
        else
        {
            hints[key] = initials + " / " + finals;
        }
    }
    return hints;
}
} // namespace metasequoia::apple
