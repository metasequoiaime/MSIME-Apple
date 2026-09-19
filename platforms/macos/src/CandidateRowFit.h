#pragma once

#include <algorithm>
#include <cstddef>
#include <vector>

namespace metasequoia::mac
{
// A horizontal row wider than the screen used to be scaled down by a single factor, which cut the sentence at
// the head of the page by the same proportion as the one-character candidates at its tail. A page holding a
// sentence is worth more as one readable sentence than as nine equally shortened stubs, so the row now shows
// candidates at the width their text needs and stops when the next one no longer fits: fewer candidates, each
// of them whole. Whatever is left over after that goes back to the glosses.
struct CandidateRowItem
{
    // Selection number, gap, candidate text and padding - what the item needs to print the candidate in full.
    double textWidth = 0.0;
    // textWidth raised to whatever the glosses stacked under the candidate ask for. Values below textWidth are
    // treated as textWidth: a gloss never shrinks the candidate above it.
    double preferredWidth = 0.0;
};

// Widths in row order, summing to at most availableWidth. A candidate the row has no room for gets 0.0 and is
// not drawn; the zeroes are always a suffix, so the first one ends the row. The head candidate is always shown,
// truncated only if it alone is wider than the whole row.
inline std::vector<double> FitCandidateRowWidths(const std::vector<CandidateRowItem> &items, double availableWidth)
{
    const std::size_t count = items.size();
    std::vector<double> widths(count, 0.0);
    if (count == 0)
        return widths;
    const double available = std::max<double>(availableWidth, 0.0);
    std::vector<double> text(count, 0.0);
    std::vector<double> preferred(count, 0.0);
    double preferredTotal = 0.0;
    for (std::size_t index = 0; index < count; ++index)
    {
        text[index] = std::max<double>(items[index].textWidth, 0.0);
        preferred[index] = std::max(text[index], items[index].preferredWidth);
        preferredTotal += preferred[index];
    }
    if (preferredTotal <= available)
        return preferred;
    std::size_t visible = 0;
    double textTotal = 0.0;
    while (visible < count && textTotal + text[visible] <= available)
        textTotal += text[visible++];
    if (visible == 0)
    {
        // Even the first candidate is wider than the row. Give it everything and let the button truncate it;
        // dropping it instead would leave the page with nothing to select.
        widths[0] = available;
        return widths;
    }
    double glossNeed = 0.0;
    for (std::size_t index = 0; index < visible; ++index)
    {
        widths[index] = text[index];
        glossNeed += preferred[index] - text[index];
    }
    if (glossNeed > 0.0)
    {
        // Room for these candidates but not for every gloss under them. Share what is left in proportion to
        // what each gloss asked for, so one wide gloss cannot take the space the others need.
        const double share = std::min(1.0, (available - textTotal) / glossNeed);
        for (std::size_t index = 0; index < visible; ++index)
            widths[index] += (preferred[index] - text[index]) * share;
    }
    return widths;
}
} // namespace metasequoia::mac
