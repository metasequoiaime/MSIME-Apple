#include "CandidateRowFit.h"

#include <cassert>
#include <cmath>
#include <numeric>

namespace
{
using msime::mac::CandidateRowItem;
using msime::mac::FitCandidateRowWidths;

double Total(const std::vector<double> &widths)
{
    return std::accumulate(widths.begin(), widths.end(), 0.0);
}

bool Near(double left, double right)
{
    return std::fabs(left - right) < 0.001;
}
} // namespace

int main()
{
    // A row that fits keeps every gloss reservation.
    {
        const std::vector<CandidateRowItem> items{{100.0, 240.0}, {80.0, 200.0}};
        const auto widths = FitCandidateRowWidths(items, 1000.0, 60.0);
        assert(Near(widths[0], 240.0) && Near(widths[1], 200.0));
    }
    // Only the glosses are short of room: the candidates stay whole and the remainder is shared out in
    // proportion to what each gloss asked for.
    {
        const std::vector<CandidateRowItem> items{{100.0, 300.0}, {100.0, 200.0}};
        const auto widths = FitCandidateRowWidths(items, 350.0, 60.0);
        assert(Near(Total(widths), 350.0));
        assert(widths[0] > 100.0 && widths[1] > 100.0);
        assert(Near(widths[0] - 100.0, 2.0 * (widths[1] - 100.0)));
    }
    // The page from the report: one long sentence followed by short candidates, too wide for the screen.
    // The sentence keeps every point it needs and the tail pays for it.
    {
        const std::vector<CandidateRowItem> items{{350.0, 350.0}, {120.0, 248.0}, {90.0, 248.0}, {70.0, 248.0}};
        const auto widths = FitCandidateRowWidths(items, 600.0, 60.0);
        assert(Near(Total(widths), 600.0));
        assert(Near(widths[0], 350.0));
        assert(Near(widths[1], 120.0));
        assert(Near(widths[2], 70.0));
        assert(Near(widths[3], 60.0));
    }
    // No item is squeezed below the floor while an earlier one still has width to give.
    {
        const std::vector<CandidateRowItem> items{{300.0, 300.0}, {300.0, 300.0}};
        const auto widths = FitCandidateRowWidths(items, 400.0, 100.0);
        assert(Near(Total(widths), 400.0));
        assert(Near(widths[0], 300.0) && Near(widths[1], 100.0));
    }
    // Narrower than the floors themselves: nothing can be shown in full, so the squeeze is even again.
    {
        const std::vector<CandidateRowItem> items{{300.0, 300.0}, {300.0, 300.0}, {300.0, 300.0}};
        const auto widths = FitCandidateRowWidths(items, 150.0, 100.0);
        assert(Near(Total(widths), 150.0));
        assert(Near(widths[0], 50.0) && Near(widths[1], 50.0) && Near(widths[2], 50.0));
    }
    // Degenerate input stays in range instead of producing negative frames.
    {
        assert(FitCandidateRowWidths({}, 500.0, 60.0).empty());
        const std::vector<CandidateRowItem> items{{-10.0, -20.0}, {40.0, 10.0}};
        const auto widths = FitCandidateRowWidths(items, 0.0, -5.0);
        assert(Near(widths[0], 0.0) && Near(widths[1], 0.0));
    }
    return 0;
}
