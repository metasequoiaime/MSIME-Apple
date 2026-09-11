#import "ShuangpinKeymapPanel.h"
#include <cassert>
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        for (NSString *profile in @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"]) {
            NSArray *rows = MetasequoiaShuangpinKeymapRows(profile);
            assert(rows.count == 3);
            assert([rows[0] count] == 10);
            assert(MetasequoiaShuangpinZeroInitialText(profile).length > 8);
            MetasequoiaShuangpinKeymapPanel *panel = [MetasequoiaShuangpinKeymapPanel new];
            [panel setProfileName:profile];
            assert(panel.styleMask & NSWindowStyleMaskNonactivatingPanel);
            assert(panel.ignoresMouseEvents);
            NSString *before = panel.contentView.accessibilityValue;
            [panel updateHighlightedKey:@"q"];
            assert(![panel.contentView.accessibilityValue isEqual:before]);
            [panel updateHighlightedKey:@""];
            assert([panel.contentView.accessibilityValue isEqual:before]);
            [panel close];
        }
        assert([MetasequoiaShuangpinKeymapRows(@"invalid") isEqual:MetasequoiaShuangpinKeymapRows(@"xiaohe")]);
        assert(![MetasequoiaShuangpinKeymapRows(@"microsoft") isEqual:MetasequoiaShuangpinKeymapRows(@"xiaohe")]);
        NSRect screen = NSMakeRect(-1440, 0, 1440, 900);
        NSRect frame = MetasequoiaShuangpinKeymapPanelFrame(NSMakeRect(-10, 1, 1, 20), NSMakeSize(620, 203), 80, screen);
        assert(NSContainsRect(screen, frame));
        assert(MetasequoiaShouldShowShuangpinKeymap(YES, YES, YES));
        assert(!MetasequoiaShouldShowShuangpinKeymap(NO, YES, YES));
        assert(!MetasequoiaShouldShowShuangpinKeymap(YES, YES, NO));
    }
}
