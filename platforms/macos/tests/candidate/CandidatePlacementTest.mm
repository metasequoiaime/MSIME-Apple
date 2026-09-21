#import <AppKit/AppKit.h>
#import "../../src/candidate/CandidatePlacement.h"

#include <cassert>
#include <cmath>

// Where the candidate window goes, and when the caret it is told about is worth using at all.
//
// Both decisions are made here and nowhere else, and both fail in ways that are obvious to a user
// and invisible to every other test: a window a few points off screen, or one parked at the origin
// of the main display while the user types in the corner of a second one.
int main()
{
    @autoreleasepool
    {
        // A 1600x1000 display whose visible area starts below the menu bar, and a second one to the
        // left of it with negative coordinates - the ordinary two-display arrangement on this
        // platform, and the one that catches an implementation reaching for absolute zero.
        const NSRect screen = NSMakeRect(0, 0, 1600, 1000);
        const NSRect left = NSMakeRect(-1440, 200, 1440, 900);
        const NSSize panel = NSMakeSize(320, 120);

        // The ordinary case: under the caret, four points clear of it, left edge aligned.
        const NSRect caret = NSMakeRect(400, 600, 2, 18);
        const NSPoint under = MSIMECandidateOrigin(caret, panel, screen);
        assert(under.x == 400);
        assert(under.y == 600 - 120 - 4);

        // Near the bottom of the display there is no room underneath, so it flips above the caret -
        // above the whole caret, not above its baseline, or it would cover the line being typed.
        const NSRect low = NSMakeRect(400, 40, 2, 18);
        const NSPoint flipped = MSIMECandidateOrigin(low, panel, screen);
        assert(flipped.y == NSMaxY(low) + 4);
        assert(flipped.y >= NSMinY(screen));

        // Against the right edge the window stops at the edge rather than hanging off it.
        const NSRect right = NSMakeRect(1500, 600, 2, 18);
        assert(MSIMECandidateOrigin(right, panel, screen).x == 1600 - 320);

        // Against the left edge of a display that starts at a negative x, the clamp is that
        // display's edge. Clamping to zero would drag the window onto the main display.
        const NSRect far = NSMakeRect(-1430, 800, 2, 18);
        const NSPoint negative = MSIMECandidateOrigin(far, panel, left);
        assert(negative.x == -1430);
        const NSRect beyond = NSMakeRect(-1500, 800, 2, 18);
        assert(MSIMECandidateOrigin(beyond, panel, left).x == NSMinX(left));

        // A window wider than the display it is on: the inner clamp keeps the left edge on the
        // display instead of producing a right-hand clamp that is further left than the left one.
        const NSSize wide = NSMakeSize(2000, 120);
        assert(MSIMECandidateOrigin(caret, wide, screen).x == NSMinX(screen));
        // Same for a window taller than the display.
        const NSSize tall = NSMakeSize(320, 2000);
        assert(MSIMECandidateOrigin(caret, tall, screen).y == NSMinY(screen));

        // A caret at the very top still leaves the window inside the visible area after the flip.
        const NSRect top = NSMakeRect(400, 995, 2, 18);
        const NSPoint high = MSIMECandidateOrigin(top, panel, screen);
        assert(high.y >= NSMinY(screen) && high.y + panel.height <= NSMaxY(screen));

        // What counts as a caret worth positioning against. A zero-height rect is what a client
        // that does not implement the caret query returns, and NaN is what an arithmetic failure
        // upstream produces; both would otherwise park the window somewhere arbitrary.
        assert(MSIMEValidCaret(caret));
        assert(MSIMEValidCaret(far));
        assert(!MSIMEValidCaret(NSMakeRect(400, 600, 2, 0)));
        assert(!MSIMEValidCaret(NSMakeRect(400, 600, 2, -18)));
        assert(!MSIMEValidCaret(NSMakeRect(NAN, 600, 2, 18)));
        assert(!MSIMEValidCaret(NSMakeRect(400, NAN, 2, 18)));
        assert(!MSIMEValidCaret(NSMakeRect(400, 600, NAN, 18)));
        assert(!MSIMEValidCaret(NSMakeRect(400, 600, 2, NAN)));
        assert(!MSIMEValidCaret(NSMakeRect(INFINITY, 600, 2, 18)));
        // A zero-width caret is ordinary - an insertion point has no width.
        assert(MSIMEValidCaret(NSMakeRect(400, 600, 0, 18)));
    }
    return 0;
}
