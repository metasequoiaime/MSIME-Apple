#pragma once

#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>

#include <cstddef>
#include "CandidateAppearancePreferences.h"

namespace metasequoia::mac
{
constexpr size_t NormalizeCandidateFontSize(size_t fontSize)
{
    return fontSize >= 12 && fontSize <= 36 ? fontSize : 18;
}

constexpr size_t CandidateFontSizeForOptionIndex(size_t index)
{
    return index < 25 ? index + 12 : 18;
}

constexpr size_t CandidateFontSizeOptionIndex(size_t fontSize)
{
    return NormalizeCandidateFontSize(fontSize) - 12;
}

inline NSDictionary *CandidatePanelAttributes(size_t fontSize)
{
    return @{
        IMKCandidatesSendServerKeyEventFirst : @YES,
        NSFontAttributeName : MetasequoiaCandidateFont(static_cast<CGFloat>(NormalizeCandidateFontSize(fontSize))),
    };
}
} // namespace metasequoia::mac
