#import "../src/InputModeHUDPanel.h"

#import <AppKit/AppKit.h>

#include <cstdio>
#include <initializer_list>
#include <stdexcept>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

constexpr CGFloat kWidth = 100.0;
constexpr CGFloat kHeight = 56.0;
} // namespace

int main()
{
    @autoreleasepool
    {
        try
        {
            Require([MetasequoiaInputModeHUDText(YES) isEqualToString:@"英"] &&
                        [MetasequoiaInputModeHUDText(NO) isEqualToString:@"中"],
                    "The badge did not name the mode it was switched to.");

            const NSRect screen = NSMakeRect(0.0, 0.0, 1440.0, 900.0);
            const NSSize panel = NSMakeSize(kWidth, kHeight);

            // A caret in open screen puts the badge under it, centred on it.
            const NSRect caret = NSMakeRect(700.0, 500.0, 2.0, 20.0);
            const NSRect under = MetasequoiaInputModeHUDFrame(caret, panel, screen);
            Require(NSMaxY(under) < NSMinY(caret), "The badge covered the line being typed.");
            Require(std::abs(NSMidX(under) - NSMidX(caret)) < 0.5, "The badge was not centred on the caret.");
            Require(NSWidth(under) == kWidth && NSHeight(under) == kHeight, "The badge changed size.");

            // No room underneath: it goes above rather than off the bottom of the screen.
            const NSRect lowCaret = NSMakeRect(700.0, 12.0, 2.0, 20.0);
            const NSRect above = MetasequoiaInputModeHUDFrame(lowCaret, panel, screen);
            Require(NSMinY(above) > NSMaxY(lowCaret), "A caret near the bottom edge pushed the badge off-screen.");

            // Edges: the badge stays inside the visible frame whichever side the caret hugs.
            for (const NSRect edgeCaret : {NSMakeRect(-40.0, 500.0, 2.0, 20.0), NSMakeRect(1480.0, 500.0, 2.0, 20.0),
                                           NSMakeRect(700.0, 1200.0, 2.0, 20.0)})
            {
                const NSRect frame = MetasequoiaInputModeHUDFrame(edgeCaret, panel, screen);
                Require(NSMinX(frame) >= NSMinX(screen) && NSMaxX(frame) <= NSMaxX(screen) &&
                            NSMinY(frame) >= NSMinY(screen) && NSMaxY(frame) <= NSMaxY(screen),
                        "The badge left the screen following a caret at its edge.");
            }

            // A client that reports no caret -- zeroes, or a height of nothing -- still gets a badge,
            // in the lower middle rather than pinned to a corner.
            Require(!MetasequoiaIsUsableCaretRect(NSZeroRect) &&
                        !MetasequoiaIsUsableCaretRect(NSMakeRect(10.0, 10.0, 2.0, 0.0)) &&
                        MetasequoiaIsUsableCaretRect(NSMakeRect(10.0, 10.0, 2.0, 18.0)),
                    "An unusable caret rectangle was taken for a usable one.");
            const NSRect fallback = MetasequoiaInputModeHUDFrame(NSZeroRect, panel, screen);
            Require(std::abs(NSMidX(fallback) - NSMidX(screen)) < 0.5 && NSMinY(fallback) > NSMinY(screen) &&
                        NSMidY(fallback) < NSMidY(screen),
                    "A caretless client did not get the badge in the lower middle of the screen.");

            // The panel itself takes neither focus nor clicks: it appears over whatever is being
            // typed into, and must not interrupt it.
            MetasequoiaInputModeHUDPanel *hud = [MetasequoiaInputModeHUDPanel sharedPanel];
            Require(hud == [MetasequoiaInputModeHUDPanel sharedPanel], "The badge was not shared.");
            Require(hud.ignoresMouseEvents && hud.floatingPanel && hud.becomesKeyOnlyIfNeeded && !hud.opaque,
                    "The badge could take focus or swallow a click.");
            Require(hud.displayedText == nil, "The badge was on screen before anything switched.");
            [hud showEnglishInputMode:YES nearCaretRect:NSMakeRect(700.0, 500.0, 2.0, 20.0)];
            Require([hud.displayedText isEqualToString:@"英"], "Switching to English did not show 英.");
            [hud showEnglishInputMode:NO nearCaretRect:NSMakeRect(700.0, 500.0, 2.0, 20.0)];
            Require([hud.displayedText isEqualToString:@"中"], "Switching back did not replace the badge text.");

            // The badge wears the product's own green with ink that reads on it, rather than a
            // system HUD material that says nothing about which input method spoke.
            NSColor *forest = [MetasequoiaForestColor() colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            NSColor *ink = [MetasequoiaOnForestColor() colorUsingColorSpace:[NSColorSpace sRGBColorSpace]];
            Require(forest != nil && ink != nil, "The theme colours did not resolve.");
            Require(std::abs(forest.greenComponent - forest.redComponent) > 0.1 &&
                        forest.greenComponent > forest.blueComponent,
                    "The badge background was not the forest green.");
            const CGFloat contrast = std::abs(ink.brightnessComponent - forest.brightnessComponent);
            Require(contrast > 0.4, "The badge text would not read against its background.");
            // The logo is a bundle resource, so a test binary has none to find and the badge falls
            // back to the character alone rather than reserving an empty slot for it.
            Require(hud.showsLogo == ([[NSBundle bundleForClass:[MetasequoiaInputModeHUDPanel class]]
                                          imageForResource:@"MetasequoiaIMEMenuIcon"] != nil),
                    "The badge disagreed with the bundle about whether it has a logo.");
            [hud orderOut:nil];
        }
        catch (const std::exception &error)
        {
            std::fprintf(stderr, "%s\n", error.what());
            return 1;
        }
    }
    return 0;
}
