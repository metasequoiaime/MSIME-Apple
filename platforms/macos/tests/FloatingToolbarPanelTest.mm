#import "../FloatingToolbarPanel.h"
#import <AppKit/AppKit.h>
#include <cassert>
#include <cmath>

@interface ToolbarDelegate : NSObject <MetasequoiaFloatingToolbarDelegate>
@property(nonatomic) NSUInteger calls;
@end
@implementation ToolbarDelegate
- (void)floatingToolbarDidRequestToggleInputMode:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestTogglePunctuation:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestToggleFullWidth:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestOpenCharacterPalette:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestOpenSettings:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestCheckForUpdates:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestOpenWebsite:(id)x { (void)x; _calls++; }
- (void)floatingToolbarDidRequestHide:(id)x { (void)x; _calls++; }
@end

static NSButton *Button(NSView *view, NSString *identifier)
{
    if ([view isKindOfClass:NSButton.class] && [view.accessibilityIdentifier isEqual:identifier]) return (NSButton *)view;
    for (NSView *child in view.subviews) if (NSButton *found = Button(child, identifier)) return found;
    return nil;
}

int main()
{
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSRect visible = NSMakeRect(100, 80, 1200, 800);
        NSRect frame = MetasequoiaFloatingToolbarFrame(NSMakeRect(0, 0, 272, 44), visible, NO);
        assert(std::abs(NSMaxX(frame) - NSMaxX(visible) + 20) < .01);
        assert(std::abs(NSMinY(frame) - NSMinY(visible) - 20) < .01);
        NSRect clamped = MetasequoiaFloatingToolbarFrame(NSMakeRect(-300, 2000, 272, 44), visible, YES);
        assert(NSMinX(clamped) >= NSMinX(visible) + 12 && NSMaxX(clamped) <= NSMaxX(visible) - 12);
        MetasequoiaFloatingToolbarPanel *panel = [MetasequoiaFloatingToolbarPanel new];
        assert((panel.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0);
        ToolbarDelegate *delegate = [ToolbarDelegate new]; panel.toolbarDelegate = delegate;
        [panel updateEnglishInputMode:NO chinesePunctuationEnabled:YES fullWidthEnabled:NO traditionalChineseOutputEnabled:NO];
        NSButton *input = Button(panel.contentView, @"MetasequoiaFloatingToolbarInputMode");
        NSButton *punctuation = Button(panel.contentView, @"MetasequoiaFloatingToolbarPunctuation");
        NSButton *full = Button(panel.contentView, @"MetasequoiaFloatingToolbarFullWidth");
        NSButton *traditional = Button(panel.contentView, @"MetasequoiaFloatingToolbarTraditionalOutput");
        assert(input && punctuation && full && traditional);
        assert([input.title isEqual:@"中"] && [punctuation.title isEqual:@"。"] && [full.title isEqual:@"半"] && [traditional.title isEqual:@"简"]);
        [input performClick:nil]; [punctuation performClick:nil]; [full performClick:nil]; [traditional performClick:nil];
        assert(delegate.calls == 4);
        NSMenu *menu = CreateMetasequoiaFloatingToolbarUtilityMenu(panel);
        assert(menu.numberOfItems == 7 && menu.itemArray[3].separatorItem && menu.itemArray[5].separatorItem);
        [panel deactivateForDelegate:delegate];
    }
    return 0;
}
