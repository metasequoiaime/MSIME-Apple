#pragma once

#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>

#include <cstddef>

namespace metasequoia::mac
{
constexpr size_t NormalizeCandidateFontSize(size_t fontSize)
{
    return fontSize == 16 || fontSize == 18 || fontSize == 20 ? fontSize : 18;
}

constexpr size_t CandidateFontSizeForOptionIndex(size_t index)
{
    constexpr size_t options[] = {16, 18, 20};
    return index < 3 ? options[index] : 18;
}

constexpr size_t CandidateFontSizeOptionIndex(size_t fontSize)
{
    switch (NormalizeCandidateFontSize(fontSize))
    {
    case 16:
        return 0;
    case 20:
        return 2;
    default:
        return 1;
    }
}

inline NSDictionary *CandidatePanelAttributes(size_t fontSize)
{
    return @{
        IMKCandidatesSendServerKeyEventFirst : @YES,
        NSFontAttributeName : [NSFont systemFontOfSize:static_cast<CGFloat>(NormalizeCandidateFontSize(fontSize))],
    };
}
} // namespace metasequoia::mac
