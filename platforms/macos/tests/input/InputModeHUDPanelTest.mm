#import "../../src/input/InputModeHUDPanel.h"
#import <AppKit/AppKit.h>
#include <cmath>
#include <cstdio>
#include <initializer_list>
#include <stdexcept>

namespace {
void Require(bool condition, const char *message) { if (!condition) throw std::runtime_error(message); }
}

int main() {
    @autoreleasepool {
        try {
            Require([MSIMEInputModeHUDText(YES) isEqualToString:@"英"] && [MSIMEInputModeHUDText(NO) isEqualToString:@"中"], "HUD text mismatch");
            const NSRect screen = NSMakeRect(0, 0, 1440, 900);
            const NSSize panel = NSMakeSize(100, 56);
            const NSRect caret = NSMakeRect(700, 500, 2, 20);
            const NSRect under = MSIMEInputModeHUDFrame(caret, panel, screen);
            Require(NSMaxY(under) < NSMinY(caret) && std::abs(NSMidX(under) - NSMidX(caret)) < 0.5, "HUD did not stay below caret");
            const NSRect low = MSIMEInputModeHUDFrame(NSMakeRect(700, 12, 2, 20), panel, screen);
            Require(NSMinY(low) > NSMaxY(NSMakeRect(700, 12, 2, 20)), "HUD did not move above low caret");
            for (const NSRect edge : {NSMakeRect(-40, 500, 2, 20), NSMakeRect(1480, 500, 2, 20), NSMakeRect(700, 1200, 2, 20)}) {
                NSRect frame = MSIMEInputModeHUDFrame(edge, panel, screen);
                Require(NSMinX(frame) >= NSMinX(screen) && NSMaxX(frame) <= NSMaxX(screen) && NSMinY(frame) >= NSMinY(screen) && NSMaxY(frame) <= NSMaxY(screen), "HUD escaped screen");
            }
            Require(!MSIMEInputModeHUDUsableCaretRect(NSZeroRect) && !MSIMEInputModeHUDUsableCaretRect(NSMakeRect(0, 0, 1, 0)) && MSIMEInputModeHUDUsableCaretRect(caret), "caret validation mismatch");
            MSIMEInputModeHUDPanel *hud = MSIMEInputModeHUDPanel.sharedPanel;
            Require(hud == MSIMEInputModeHUDPanel.sharedPanel && hud.ignoresMouseEvents && hud.floatingPanel && !hud.opaque, "HUD panel contract mismatch");
            Require(hud.displayedText == nil, "HUD was visible before use");
            [hud showEnglishInputMode:YES nearCaretRect:caret];
            Require([hud.displayedText isEqualToString:@"英"], "English HUD missing");
            [hud showEnglishInputMode:NO nearCaretRect:caret];
            Require([hud.displayedText isEqualToString:@"中"], "Chinese HUD missing");
            [hud orderOut:nil];
        } catch (const std::exception &error) { std::fprintf(stderr, "%s\n", error.what()); return 1; }
    }
    return 0;
}
