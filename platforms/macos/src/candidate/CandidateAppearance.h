#pragma once

#import <Foundation/Foundation.h>

#include <cstddef>

namespace metasequoia::mac {

constexpr std::size_t NormalizeCandidateFontSize(std::size_t value)
{
    return value == 16 || value == 18 || value == 20 ? value : 18;
}

inline bool IsVerticalCandidateOrientation(NSString *value)
{
    return value == nil || ![value isEqualToString:@"horizontal"];
}

} // namespace metasequoia::mac
