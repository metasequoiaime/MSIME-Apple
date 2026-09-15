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

// 候选行上「待上屏的那一列」:0 是候选词本身,1 是目标语言的释义,2 是第二语言的释义。Tab 在这几列
// 之间循环,⇧Tab 反向;没有释义的列直接跳过,所以一条释义都没有时 Tab 停在 0,不会变成一个按了没反应
// 又悄悄改了上屏内容的键。
inline int NextArmedGlossColumn(int current, bool hasPrimary, bool hasSecondary, bool backwards)
{
    int columns[3] = {0, 0, 0};
    int count = 1;
    if (hasPrimary)
    {
        columns[count++] = 1;
    }
    if (hasSecondary)
    {
        columns[count++] = 2;
    }
    int position = 0;
    for (int index = 0; index < count; ++index)
    {
        if (columns[index] == current)
        {
            position = index;
            break;
        }
    }
    const int next = (position + (backwards ? count - 1 : 1)) % count;
    return columns[next];
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
