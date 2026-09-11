#pragma once

#include <cstddef>

namespace metasequoia::mac
{
constexpr size_t NormalizeCandidatePageSize(size_t value)
{
    return value == 5 || value == 7 || value == 9 ? value : 9;
}

constexpr size_t CandidatePageSizeForOptionIndex(size_t index)
{
    return index == 0 ? 5 : index == 1 ? 7 : 9;
}

constexpr size_t CandidatePageSizeOptionIndex(size_t pageSize)
{
    pageSize = NormalizeCandidatePageSize(pageSize);
    return pageSize == 5 ? 0 : pageSize == 7 ? 1 : 2;
}
} // namespace metasequoia::mac

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

namespace metasequoia::mac
{
inline NSArray<NSNumber *> *CandidateSelectionKeys(size_t pageSize)
{
    NSArray<NSNumber *> *allKeys = @[
        @(kVK_ANSI_1),
        @(kVK_ANSI_2),
        @(kVK_ANSI_3),
        @(kVK_ANSI_4),
        @(kVK_ANSI_5),
        @(kVK_ANSI_6),
        @(kVK_ANSI_7),
        @(kVK_ANSI_8),
        @(kVK_ANSI_9),
    ];
    return [allKeys subarrayWithRange:NSMakeRange(0, NormalizeCandidatePageSize(pageSize))];
}
} // namespace metasequoia::mac
#endif
