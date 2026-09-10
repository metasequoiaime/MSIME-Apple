#import "../src/FloatingToolbarPanel.h"

#import <AppKit/AppKit.h>

#include <cmath>
#include <stdexcept>

@interface FloatingToolbarTestDelegate : NSObject <MetasequoiaFloatingToolbarDelegate>
@property(nonatomic) BOOL toggledInputMode;
@property(nonatomic) BOOL toggledPunctuation;
@property(nonatomic) BOOL toggledFullWidth;
@property(nonatomic) BOOL toggledTraditionalOutput;
@property(nonatomic) BOOL openedCharacterPalette;
@property(nonatomic) BOOL openedSettings;
@property(nonatomic, strong) MetasequoiaFloatingToolbarPanel *ownedPanel;
@property(nonatomic) BOOL checkedForUpdates;
@property(nonatomic) BOOL openedWebsite;
@property(nonatomic) BOOL hidToolbar;
@end

@implementation FloatingToolbarTestDelegate
- (void)floatingToolbarDidRequestToggleInputMode:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.toggledInputMode = YES;
}

- (void)floatingToolbarDidRequestTogglePunctuation:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.toggledPunctuation = YES;
}

- (void)floatingToolbarDidRequestToggleFullWidth:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.toggledFullWidth = YES;
}

- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.toggledTraditionalOutput = YES;
}

- (void)floatingToolbarDidRequestOpenSettings:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.openedSettings = YES;
}

- (void)floatingToolbarDidRequestOpenCharacterPalette:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.openedCharacterPalette = YES;
}

- (void)floatingToolbarDidRequestCheckForUpdates:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.checkedForUpdates = YES;
}

- (void)floatingToolbarDidRequestOpenWebsite:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.openedWebsite = YES;
}

- (void)floatingToolbarDidRequestHide:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    self.hidToolbar = YES;
}

- (void)dealloc
{
    // Mirrors MetasequoiaInputController, which releases the toolbar while it is being deallocated.
    [self.ownedPanel deactivateForDelegate:self];
}
@end

namespace
{
void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

bool NearlyEqual(CGFloat first, CGFloat second)
{
    return std::abs(first - second) < 0.01;
}

NSButton *FindButton(NSView *view, NSString *identifier)
{
    if ([view isKindOfClass:[NSButton class]] && [view.accessibilityIdentifier isEqualToString:identifier])
    {
        return (NSButton *)view;
    }
    for (NSView *subview in view.subviews)
    {
        NSButton *match = FindButton(subview, identifier);
        if (match != nil)
        {
            return match;
        }
    }
    return nil;
}
} // namespace

int main()
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSRect visibleFrame = NSMakeRect(100.0, 80.0, 1200.0, 800.0);
        NSRect defaultFrame = MetasequoiaFloatingToolbarFrame(NSMakeRect(0.0, 0.0, 272.0, 44.0), visibleFrame, NO);
        require(NearlyEqual(NSWidth(defaultFrame), 272.0) && NearlyEqual(NSHeight(defaultFrame), 44.0) &&
                    NearlyEqual(NSMaxX(defaultFrame), NSMaxX(visibleFrame) - 20.0) &&
                    NearlyEqual(NSMinY(defaultFrame), NSMinY(visibleFrame) + 20.0),
                "The floating toolbar did not use its expected size and lower-right safe area.");

        NSRect restoredFrame =
            MetasequoiaFloatingToolbarFrame(NSMakeRect(-300.0, 2000.0, 272.0, 44.0), visibleFrame, YES);
        require(NSMinX(restoredFrame) >= NSMinX(visibleFrame) + 12.0 &&
                    NSMaxX(restoredFrame) <= NSMaxX(visibleFrame) - 12.0 &&
                    NSMinY(restoredFrame) >= NSMinY(visibleFrame) + 12.0 &&
                    NSMaxY(restoredFrame) <= NSMaxY(visibleFrame) - 12.0,
                "A restored floating-toolbar frame was not clamped into the visible screen.");

        MetasequoiaFloatingToolbarPanel *panel = [[MetasequoiaFloatingToolbarPanel alloc] init];
        require((panel.styleMask & NSWindowStyleMaskNonactivatingPanel) != 0,
                "The floating toolbar would activate the input-method process when clicked.");
        require(panel.level == NSStatusWindowLevel && panel.movableByWindowBackground && panel.hasShadow &&
                    !panel.opaque,
                "The floating toolbar did not use the expected native floating-panel behavior.");
        require([panel.frameAutosaveName isEqualToString:@"MetasequoiaFloatingToolbarFrame"],
                "The floating toolbar did not remember its dragged position.");

        FloatingToolbarTestDelegate *firstDelegate = [[FloatingToolbarTestDelegate alloc] init];
        FloatingToolbarTestDelegate *secondDelegate = [[FloatingToolbarTestDelegate alloc] init];
        panel.toolbarDelegate = firstDelegate;
        [panel updateEnglishInputMode:NO
                  chinesePunctuationEnabled:YES
                           fullWidthEnabled:NO
            traditionalChineseOutputEnabled:NO];

        NSButton *inputModeButton = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarInputMode");
        NSButton *punctuationButton = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarPunctuation");
        NSButton *fullWidthButton = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarFullWidth");
        NSButton *traditionalOutputButton =
            FindButton(panel.contentView, @"MetasequoiaFloatingToolbarTraditionalOutput");
        NSButton *settingsButton = FindButton(panel.contentView, @"MetasequoiaFloatingToolbarSettings");
        require(inputModeButton != nil && punctuationButton != nil && fullWidthButton != nil &&
                    traditionalOutputButton != nil && settingsButton != nil,
                "The floating toolbar did not expose all five supported actions.");
        require(settingsButton.action == @selector(showUtilityMenu:) &&
                    [settingsButton.accessibilityLabel isEqualToString:@"打开水杉输入法工具菜单"],
                "The toolbar gear did not expose the native utility menu.");
        require([inputModeButton.title isEqualToString:@"中"] &&
                    [inputModeButton.accessibilityLabel isEqualToString:@"切换到英文输入"] &&
                    [punctuationButton.title isEqualToString:@"。"] && [fullWidthButton.title isEqualToString:@"半"] &&
                    [traditionalOutputButton.title isEqualToString:@"简"] &&
                    [traditionalOutputButton.accessibilityLabel isEqualToString:@"切换到繁体输出"],
                "The floating toolbar did not reflect the active input states.");

        [panel updateJapaneseScheme:YES englishMode:NO];
        require([inputModeButton.title isEqualToString:@"日"], "Japanese toolbar label was missing.");
        [panel updateJapaneseScheme:YES englishMode:YES];
        require([inputModeButton.accessibilityLabel isEqualToString:@"切换到日语输入"], "English toggle lost Japanese return target.");
        [panel updateJapaneseScheme:NO englishMode:NO];
        [inputModeButton performClick:nil];
        [punctuationButton performClick:nil];
        [fullWidthButton performClick:nil];
        [traditionalOutputButton performClick:nil];
        require(firstDelegate.toggledInputMode && firstDelegate.toggledPunctuation && firstDelegate.toggledFullWidth &&
                    firstDelegate.toggledTraditionalOutput,
                "The floating toolbar did not forward every state action to its active input controller.");

        NSMenu *utilityMenu = CreateMetasequoiaFloatingToolbarUtilityMenu(panel);
        require(utilityMenu.numberOfItems == 7 && [[utilityMenu itemAtIndex:0].title isEqualToString:@"表情与符号…"] &&
                    [[utilityMenu itemAtIndex:1].title isEqualToString:@"打开设置…"] &&
                    [[utilityMenu itemAtIndex:2].title isEqualToString:@"检查更新…"] &&
                    [utilityMenu itemAtIndex:3].separatorItem &&
                    [[utilityMenu itemAtIndex:4].title isEqualToString:@"访问 msime.app"] &&
                    [utilityMenu itemAtIndex:5].separatorItem &&
                    [[utilityMenu itemAtIndex:6].title isEqualToString:@"隐藏悬浮状态栏"],
                "The toolbar utility menu did not expose the expected native actions.");
        // performActionForItemAtIndex: dispatches without validating, so it happily fires an item
        // AppKit would have greyed out for the user. Ask the menu to update itself first and
        // require every real item to survive that: 隐藏悬浮状态栏 was dead in the shipped build
        // because NSWindow's own -validateMenuItem: vetoed it, and this test still passed.
        [utilityMenu update];
        for (NSInteger index = 0; index < utilityMenu.numberOfItems; ++index)
        {
            NSMenuItem *item = [utilityMenu itemAtIndex:index];
            require(item.separatorItem || item.isEnabled,
                    "A toolbar utility menu item is disabled and cannot be clicked.");
        }
        [utilityMenu performActionForItemAtIndex:0];
        [utilityMenu performActionForItemAtIndex:1];
        [utilityMenu performActionForItemAtIndex:2];
        [utilityMenu performActionForItemAtIndex:4];
        [utilityMenu performActionForItemAtIndex:6];
        require(firstDelegate.openedCharacterPalette && firstDelegate.openedSettings &&
                    firstDelegate.checkedForUpdates && firstDelegate.openedWebsite && firstDelegate.hidToolbar,
                "The toolbar utility menu did not forward every action to its active input controller.");

        [panel updateEnglishInputMode:YES
                  chinesePunctuationEnabled:NO
                           fullWidthEnabled:YES
            traditionalChineseOutputEnabled:YES];
        require([inputModeButton.title isEqualToString:@"英"] && [punctuationButton.title isEqualToString:@"."] &&
                    [fullWidthButton.title isEqualToString:@"全"] &&
                    [traditionalOutputButton.title isEqualToString:@"繁"],
                "The floating toolbar did not refresh after input preferences changed.");

        [panel activateForDelegate:firstDelegate visible:YES];
        [panel activateForDelegate:secondDelegate visible:YES];
        [panel setVisible:NO forDelegate:firstDelegate];
        require(panel.visible && panel.toolbarDelegate == secondDelegate,
                "An old input controller changed the toolbar owned by the newly active controller.");
        [panel setVisible:NO forDelegate:secondDelegate];
        require(!panel.visible && panel.toolbarDelegate == secondDelegate,
                "Hiding the toolbar released its active input controller.");
        [panel setVisible:YES forDelegate:secondDelegate];
        require(panel.visible && panel.toolbarDelegate == secondDelegate,
                "The active input controller could not show its toolbar again.");
        NSRect screenFrame = (panel.screen != nil ? panel.screen : NSScreen.mainScreen).visibleFrame;
        NSRect draggedFrame = panel.frame;
        draggedFrame.origin = NSMakePoint(NSMinX(screenFrame) + 2.0, NSMinY(screenFrame) + 2.0);
        [panel setFrame:draggedFrame display:NO];
        [panel setVisible:YES forDelegate:secondDelegate];
        require(NSEqualRects(panel.frame, draggedFrame),
                "Refreshing a visible floating toolbar moved it away from where the user placed it.");
        require([inputModeButton.toolTip isEqualToString:inputModeButton.accessibilityLabel] &&
                    [settingsButton.toolTip isEqualToString:settingsButton.accessibilityLabel],
                "The floating toolbar buttons did not expose their action as a tooltip.");
        [panel deactivateForDelegate:secondDelegate];
        require(!panel.visible && panel.toolbarDelegate == nil,
                "The active input controller did not release and hide the floating toolbar.");
        @autoreleasepool
        {
            FloatingToolbarTestDelegate *dyingDelegate = [[FloatingToolbarTestDelegate alloc] init];
            dyingDelegate.ownedPanel = panel;
            [panel activateForDelegate:dyingDelegate visible:YES];
            require(panel.visible && panel.toolbarDelegate == dyingDelegate,
                    "The floating toolbar did not accept a new input controller.");
        }
        require(!panel.visible && panel.toolbarDelegate == nil,
                "A deallocated input controller left the floating toolbar on screen.");

        // Every panel above is still alive and still owns the autosave name, so AppKit can flush their frames over the
        // seeded value at any point and the restored panel would read a position this test never wrote. Release the
        // name first so the panel constructed below is the only claimant, which is also how the real process is
        // configured.
        [panel setFrameAutosaveName:@""];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        NSString *savedFrameKey = @"NSWindow Frame MetasequoiaFloatingToolbarFrame";
        id previousSavedFrame = [defaults objectForKey:savedFrameKey];
        [defaults removeObjectForKey:savedFrameKey];
        NSScreen *restoreScreen = panel.screen != nil ? panel.screen : NSScreen.mainScreen;
        NSRect restoreVisibleFrame =
            restoreScreen != nil ? restoreScreen.visibleFrame : NSMakeRect(0.0, 0.0, 1200.0, 800.0);
        // Serializing through a panel writes exactly the string AppKit itself stores for that frame, so the test does
        // not depend on the private layout of the saved-frame default. Its natural size is also the toolbar's real
        // size, which changes whenever a button is added; MetasequoiaFloatingToolbarFrame forces the restored frame
        // back to that size, so a hardcoded width here would move the origin and fail for a reason that has nothing to
        // do with restoration.
        MetasequoiaFloatingToolbarPanel *savingPanel = [[MetasequoiaFloatingToolbarPanel alloc] init];
        NSSize toolbarSize = savingPanel.frame.size;
        NSRect savedFrame = NSMakeRect(std::round(NSMaxX(restoreVisibleFrame) - toolbarSize.width - 60.0),
                                       std::round(NSMaxY(restoreVisibleFrame) - toolbarSize.height - 60.0),
                                       toolbarSize.width, toolbarSize.height);
        [savingPanel setFrame:savedFrame display:NO];
        NSString *savedFrameDescriptor = savingPanel.stringWithSavedFrame;
        [savingPanel setFrameAutosaveName:@""];
        [defaults setObject:savedFrameDescriptor forKey:savedFrameKey];

        MetasequoiaFloatingToolbarPanel *restoredPanel = [[MetasequoiaFloatingToolbarPanel alloc] init];
        FloatingToolbarTestDelegate *restoredDelegate = [[FloatingToolbarTestDelegate alloc] init];
        [restoredPanel activateForDelegate:restoredDelegate visible:YES];
        require(NearlyEqual(NSMinX(restoredPanel.frame), NSMinX(savedFrame)) &&
                    NearlyEqual(NSMinY(restoredPanel.frame), NSMinY(savedFrame)),
                "A relaunched floating toolbar did not reopen at the position saved by the previous session.");
        [restoredPanel deactivateForDelegate:restoredDelegate];

        if (previousSavedFrame != nil)
        {
            [defaults setObject:previousSavedFrame forKey:savedFrameKey];
        }
        else
        {
            [defaults removeObjectForKey:savedFrameKey];
        }
    }
    return 0;
}
