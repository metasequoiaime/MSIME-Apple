#pragma once

#include <metasequoia/session.h>
#include <cstring>

namespace metasequoia::mac
{
inline int NormalizeFrequencyAdjustmentCount(int value)
{
    return value >= 1 && value <= 6 ? value : 1;
}

inline const char *NormalizeFrequencyAdjustmentMode(const char *value)
{
    if (value != nullptr &&
        (std::strcmp(value, "pin") == 0 || std::strcmp(value, "halve") == 0 || std::strcmp(value, "linear") == 0))
        return value;
    return "promote";
}

inline int FrequencyAdjustmentModeOptionIndex(const char *value)
{
    value = NormalizeFrequencyAdjustmentMode(value);
    if (std::strcmp(value, "pin") == 0)
        return 0;
    if (std::strcmp(value, "halve") == 0)
        return 1;
    if (std::strcmp(value, "linear") == 0)
        return 2;
    return 3;
}

inline const char *FrequencyAdjustmentModeForOptionIndex(int index)
{
    switch (index)
    {
    case 0:
        return "pin";
    case 1:
        return "halve";
    case 2:
        return "linear";
    default:
        return "promote";
    }
}

inline FrequencyAdjustmentOptions EngineFrequencyOptions(bool learning, const char *mode, int trigger, int step)
{
    FrequencyAdjustmentOptions options;
    if (!learning)
        return options;
    const char *normalized = NormalizeFrequencyAdjustmentMode(mode);
    if (std::strcmp(normalized, "pin") == 0)
        options.mode = FrequencyAdjustmentMode::Pin;
    else if (std::strcmp(normalized, "halve") == 0)
        options.mode = FrequencyAdjustmentMode::Halve;
    else if (std::strcmp(normalized, "linear") == 0)
        options.mode = FrequencyAdjustmentMode::Linear;
    else
        options.mode = FrequencyAdjustmentMode::Promote;
    options.trigger_count = NormalizeFrequencyAdjustmentCount(trigger);
    options.linear_step = NormalizeFrequencyAdjustmentCount(step);
    return options;
}
} // namespace metasequoia::mac
