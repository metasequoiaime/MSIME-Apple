#pragma once

#include <algorithm>
#include <cstddef>
#include <vector>

namespace msime::mac
{
// A horizontal candidate row wider than the screen used to be scaled down uniformly, which cut the sentence
// at the head of the page by the same factor as the single-character candidates at its tail. The head is the
// candidate the user is reading and the one most likely to be chosen, so the row now gives up space in the
// order it can afford to lose it: the gloss reservations first, then width from the last candidate forward,
// each down to a floor that still shows its selection number. Width the leading candidates need to print
// their text in full is the last thing to go.
struct CandidateRowItem
{
    // Selection number, gap, candidate text and padding - what the item needs to print the candidate in full.
    double textWidth = 0.0;
    // textWidth raised to whatever the gloss drawn under the candidate asks for. Values below textWidth are
    // treated as textWidth: a gloss never shrinks the candidate above it.
    double preferredWidth = 0.0;
};

// Widths in row order, summing to at most availableWidth whenever the floors allow it.
inline std::vector<double> FitCandidateRowWidths(const std::vector<CandidateRowItem> &items, double availableWidth,
                                                 double minimumWidth)
{
    const std::size_t count = items.size();
    std::vector<double> widths(count, 0.0);
    if (count == 0)
        return widths;
    const double available = std::max<double>(availableWidth, 0.0);
    std::vector<double> preferred(count, 0.0);
    double textTotal = 0.0;
    double preferredTotal = 0.0;
    for (std::size_t index = 0; index < count; ++index)
    {
        widths[index] = std::max<double>(items[index].textWidth, 0.0);
        preferred[index] = std::max(widths[index], items[index].preferredWidth);
        textTotal += widths[index];
        preferredTotal += preferred[index];
    }
    if (preferredTotal <= available)
        return preferred;
    if (textTotal < available)
    {
        // Room for every candidate but not for every gloss. Share what is left in proportion to what each
        // gloss asked for, so one wide gloss cannot take the space the others need.
        const double share = (available - textTotal) / (preferredTotal - textTotal);
        for (std::size_t index = 0; index < count; ++index)
            widths[index] += (preferred[index] - widths[index]) * share;
        return widths;
    }
    double deficit = textTotal - available;
    const double floorWidth = std::max<double>(minimumWidth, 0.0);
    for (std::size_t index = count; index-- > 0 && deficit > 0.0;)
    {
        const double floored = std::min(widths[index], floorWidth);
        const double release = std::min(widths[index] - floored, deficit);
        widths[index] -= release;
        deficit -= release;
    }
    if (deficit > 0.0)
    {
        // Narrower than the floors themselves - a tiny screen, or a page of long sentences. Nothing can be
        // shown in full here, so fall back to squeezing every item by the same factor.
        double flooredTotal = 0.0;
        for (double width : widths)
            flooredTotal += width;
        const double scale = flooredTotal > 0.0 ? available / flooredTotal : 0.0;
        for (double &width : widths)
            width = width * scale;
    }
    return widths;
}
} // namespace msime::mac
