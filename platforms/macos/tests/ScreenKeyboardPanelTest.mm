#import "../ScreenKeyboardPanel.h"
#import <Carbon/Carbon.h>
#include <cassert>
#include <vector>

static NSButton *Key(NSPanel *panel, NSUInteger index) {
    NSString *identifier = [NSString stringWithFormat:@"MSIMEScreenKeyboardKey%lu", (unsigned long)index];
    for (NSView *view in panel.contentView.subviews)
        if ([view.accessibilityIdentifier isEqualToString:identifier]) return (NSButton *)view;
    assert(false);
    return nil;
}
static void Press(NSPanel *panel, NSUInteger index) {
    NSButton *button = Key(panel, index);
    [NSApp sendAction:button.action to:button.target from:button];
}
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        __block unsigned short lastCode = 65535;
        __block NSEventModifierFlags lastFlags = 0;
        __block NSUInteger sends = 0;
        __block BOOL accepted = YES;
        MSIMEScreenKeyboardPanel *panel = [[MSIMEScreenKeyboardPanel alloc] initWithKeySender:^BOOL(unsigned short code, NSEventModifierFlags flags) {
            ++sends; lastCode = code; lastFlags = flags; return accepted;
        }];
        assert(!panel.canBecomeKeyWindow && !panel.canBecomeMainWindow);
        assert((panel.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0);
        const std::vector<unsigned short> codes = {
            50,18,19,20,21,23,22,26,28,25,29,27,24,51,
            48,12,13,14,15,17,16,32,34,31,35,33,30,42,
            57,0,1,2,3,5,4,38,40,37,41,39,36,
            56,6,7,8,9,11,45,46,43,47,44,56,
            59,55,58,49,58,55,117,59
        };
        assert(codes.size() == 61);
        for (NSUInteger i = 0; i < codes.size(); ++i) {
            NSButton *button = Key(panel, i);
            assert(button && button.accessibilityLabel.length > 0);
            const NSUInteger previous = sends;
            Press(panel, i);
            if (codes[i] == 57 || codes[i] == 56 || codes[i] == 59 || codes[i] == 55 || codes[i] == 58) {
                assert(sends == previous && button.state == NSControlStateValueOn);
                Press(panel, i); // Reset before checking next key.
            } else assert(sends == previous + 1 && lastCode == codes[i] && lastFlags == 0);
        }
        Press(panel, 41); // Left Shift also lights right Shift.
        assert(Key(panel, 52).state == NSControlStateValueOn);
        assert([Key(panel, 15).title isEqualToString:@"Q"]);
        Press(panel, 15);
        assert(lastCode == kVK_ANSI_Q && lastFlags == NSEventModifierFlagShift);
        assert(Key(panel, 41).state == NSControlStateValueOff && Key(panel, 52).state == NSControlStateValueOff);
        Press(panel, 28); // Caps remains sticky across letters, not punctuation.
        Press(panel, 29);
        assert(lastCode == kVK_ANSI_A && lastFlags == NSEventModifierFlagShift); // A has valid keycode zero.
        Press(panel, 39);
        assert(lastFlags == 0);
        Press(panel, 28);
        Press(panel, 53); Press(panel, 54); Press(panel, 55);
        assert(Key(panel, 60).state == NSControlStateValueOn && Key(panel, 58).state == NSControlStateValueOn && Key(panel, 57).state == NSControlStateValueOn);
        Press(panel, 29);
        assert(lastFlags == (NSEventModifierFlagControl | NSEventModifierFlagCommand | NSEventModifierFlagOption));
        for (NSUInteger index : {1u,2u,3u,4u,5u,6u,7u,8u,9u,10u,13u,14u,40u,56u,59u}) {
            Press(panel, 41);
            Press(panel, index);
            assert(lastFlags == 0 && Key(panel, 41).state == NSControlStateValueOff);
        }
        accepted = NO;
        Press(panel, 41); Press(panel, 29);
        assert(Key(panel, 41).state == NSControlStateValueOn); // Failed posting must not consume Shift.
        accepted = YES;
        Press(panel, 29);
        assert(Key(panel, 41).state == NSControlStateValueOff);

        for (NSValue *size in @[[NSValue valueWithSize:NSMakeSize(1100,400)], [NSValue valueWithSize:NSMakeSize(800,300)]]) {
            [panel setContentSize:size.sizeValue];
            [panel.contentView layoutSubtreeIfNeeded];
            NSUInteger index = 0;
            CGFloat previousBottom = 0;
            for (NSUInteger count : {14u,14u,13u,12u,8u}) {
                CGFloat right = 0;
                CGFloat bottom = 0;
                for (NSUInteger item = 0; item < count; ++item) {
                    NSRect rect = Key(panel, index++).frame;
                    assert(NSMinX(rect) >= right && NSMinY(rect) >= previousBottom);
                    assert(NSMaxX(rect) <= panel.contentView.bounds.size.width && NSMaxY(rect) <= panel.contentView.bounds.size.height);
                    assert(rect.size.width > 0 && rect.size.height > 0);
                    right = NSMaxX(rect); bottom = NSMaxY(rect);
                }
                previousBottom = bottom;
            }
            assert(Key(panel, 56).frame.size.width > 5 * Key(panel, 53).frame.size.width);
        }
        const NSUInteger beforeClose = sends;
        [NSApp sendAction:NSSelectorFromString(@"closeKeyboard:") to:panel from:nil];
        assert(!panel.visible && sends == beforeClose);
        for (NSUInteger i : {28u,41u,52u,53u,54u,55u,57u,58u,60u}) assert(Key(panel, i).state == NSControlStateValueOff);
        // Exhaustive Shift/Caps/Control/Command/Option combinations, starting from a clean panel state.
        for (NSUInteger mask = 0; mask < 32; ++mask) {
            for (NSUInteger keyIndex : {29u,39u,1u,56u}) {
                [NSApp sendAction:NSSelectorFromString(@"closeKeyboard:") to:panel from:nil];
                const NSUInteger toggles[] = {41,28,53,54,55};
                for (NSUInteger bit = 0; bit < 5; ++bit) if (mask & (1u << bit)) Press(panel, toggles[bit]);
                NSEventModifierFlags expected = 0;
                if (mask & 1 || (keyIndex == 29 && (mask & 2))) expected |= NSEventModifierFlagShift;
                if (mask & 4) expected |= NSEventModifierFlagControl;
                if (mask & 8) expected |= NSEventModifierFlagCommand;
                if (mask & 16) expected |= NSEventModifierFlagOption;
                if (keyIndex == 1 || keyIndex == 56) expected = 0;
                Press(panel, keyIndex);
                assert(lastCode == codes[keyIndex] && lastFlags == expected);
                assert(Key(panel, 41).state == NSControlStateValueOff);
            }
        }
    }
}
