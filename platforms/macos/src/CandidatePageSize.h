#pragma once

#include <cstddef>

namespace metasequoia::mac
{
constexpr size_t NormalizeCandidatePageSize(size_t value)
{
    return value >= 1 && value <= 9 ? value : 9;
}

constexpr size_t CandidatePageSizeForOptionIndex(size_t index)
{
    return index < 9 ? index + 1 : 9;
}

constexpr size_t CandidatePageSizeOptionIndex(size_t pageSize)
{
    pageSize = NormalizeCandidatePageSize(pageSize);
    return pageSize - 1;
}
} // namespace metasequoia::mac

#ifdef __OBJC__
#import <AppKit/AppKit.h>
#import <Carbon/Carbon.h>

namespace metasequoia::mac
{
// ⌥数字 / ⌃数字 上屏候选的释义。数字键本身仍然选词,所以这里只认「单独的 ⌥」和「单独的 ⌃」——
// 带上 ⌘ 或 ⇧ 的组合是别人的快捷键,输入法不该吃掉。返回 0 表示这个组合不是取释义。
// 1 = 第一条释义,2 = 第二条。
inline int CandidateGlossRequestForModifiers(NSEventModifierFlags modifiers, unichar character)
{
    if (character < '1' || character > '9')
    {
        return 0;
    }
    if (modifiers == NSEventModifierFlagOption)
    {
        return 1;
    }
    return modifiers == NSEventModifierFlagControl ? 2 : 0;
}

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
