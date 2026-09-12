#import "ScreenKeyboardPanel.h"
#import <Carbon/Carbon.h>
#import <CoreGraphics/CoreGraphics.h>
#include <algorithm>
#include <vector>

namespace {
struct Key {
    const char *normal;
    const char *shifted;
    double weight;
    unsigned short code;
    NSEventModifierFlags modifier = 0;
};
// Windows baseline: 04a8df56f86312474a069f4335a1b58da7afaa9e,
// server/src/keyboard-panel/KeyboardPanel.cpp. macOS uses ANSI hardware key codes.
const std::vector<std::vector<Key>> &Rows() {
    static const std::vector<std::vector<Key>> rows = {
        {{"`","~",1,kVK_ANSI_Grave},{"1","!",1,kVK_ANSI_1},{"2","@",1,kVK_ANSI_2},
         {"3","#",1,kVK_ANSI_3},{"4","$",1,kVK_ANSI_4},{"5","%",1,kVK_ANSI_5},
         {"6","^",1,kVK_ANSI_6},{"7","&",1,kVK_ANSI_7},{"8","*",1,kVK_ANSI_8},
         {"9","(",1,kVK_ANSI_9},{"0",")",1,kVK_ANSI_0},{"-","_",1,kVK_ANSI_Minus},
         {"=","+",1,kVK_ANSI_Equal},{"Backspace","",1.9,kVK_Delete}},
        {{"Tab","",1.5,kVK_Tab},{"q","Q",1,kVK_ANSI_Q},{"w","W",1,kVK_ANSI_W},
         {"e","E",1,kVK_ANSI_E},{"r","R",1,kVK_ANSI_R},{"t","T",1,kVK_ANSI_T},
         {"y","Y",1,kVK_ANSI_Y},{"u","U",1,kVK_ANSI_U},{"i","I",1,kVK_ANSI_I},
         {"o","O",1,kVK_ANSI_O},{"p","P",1,kVK_ANSI_P},{"[","{",1,kVK_ANSI_LeftBracket},
         {"]","}",1,kVK_ANSI_RightBracket},{"\\","|",1.4,kVK_ANSI_Backslash}},
        {{"Caps Lock","",1.85,kVK_CapsLock,NSEventModifierFlagCapsLock},
         {"a","A",1,kVK_ANSI_A},{"s","S",1,kVK_ANSI_S},{"d","D",1,kVK_ANSI_D},
         {"f","F",1,kVK_ANSI_F},{"g","G",1,kVK_ANSI_G},{"h","H",1,kVK_ANSI_H},
         {"j","J",1,kVK_ANSI_J},{"k","K",1,kVK_ANSI_K},{"l","L",1,kVK_ANSI_L},
         {";",":",1,kVK_ANSI_Semicolon},{"'","\"",1,kVK_ANSI_Quote},{"Enter","",2,kVK_Return}},
        {{"Shift","",2.35,kVK_Shift,NSEventModifierFlagShift},
         {"z","Z",1,kVK_ANSI_Z},{"x","X",1,kVK_ANSI_X},{"c","C",1,kVK_ANSI_C},
         {"v","V",1,kVK_ANSI_V},{"b","B",1,kVK_ANSI_B},{"n","N",1,kVK_ANSI_N},
         {"m","M",1,kVK_ANSI_M},{",","<",1,kVK_ANSI_Comma},{".",">",1,kVK_ANSI_Period},
         {"/","?",1,kVK_ANSI_Slash},{"Shift","",2.15,kVK_Shift,NSEventModifierFlagShift}},
        {{"Ctrl","",1.25,kVK_Control,NSEventModifierFlagControl},
         {"Command","",1.25,kVK_Command,NSEventModifierFlagCommand},
         {"Option","",1.25,kVK_Option,NSEventModifierFlagOption},{"Space"," ",6.7,kVK_Space},
         {"Option","",1.25,kVK_Option,NSEventModifierFlagOption},
         {"Command","",1.25,kVK_Command,NSEventModifierFlagCommand},{"Del","",1.25,kVK_ForwardDelete},
         {"Ctrl","",1.25,kVK_Control,NSEventModifierFlagControl}}
    };
    return rows;
}
bool Letter(const Key &key) { return key.normal[0] >= 'a' && key.normal[0] <= 'z' && key.normal[1] == '\0'; }
bool CommitKey(const Key &key) {
    return (key.normal[0] >= '0' && key.normal[0] <= '9' && key.normal[1] == '\0') ||
        key.code == kVK_Space || key.code == kVK_Return || key.code == kVK_Tab ||
        key.code == kVK_Delete || key.code == kVK_ForwardDelete;
}
BOOL PostKey(unsigned short code, NSEventModifierFlags flags) {
    // Permission prompts can change focus. Never send the pending key after prompting.
    if (!CGPreflightPostEventAccess()) { CGRequestPostEventAccess(); return NO; }
    NSRunningApplication *target = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!target || target.processIdentifier == NSProcessInfo.processInfo.processIdentifier) return NO;
    CGEventRef down = CGEventCreateKeyboardEvent(nullptr, code, true);
    CGEventRef up = CGEventCreateKeyboardEvent(nullptr, code, false);
    if (!down || !up) {
        if (down) CFRelease(down);
        if (up) CFRelease(up);
        return NO;
    }
    CGEventFlags eventFlags = 0;
    if (flags & NSEventModifierFlagShift) eventFlags |= kCGEventFlagMaskShift;
    if (flags & NSEventModifierFlagControl) eventFlags |= kCGEventFlagMaskControl;
    if (flags & NSEventModifierFlagOption) eventFlags |= kCGEventFlagMaskAlternate;
    if (flags & NSEventModifierFlagCommand) eventFlags |= kCGEventFlagMaskCommand;
    CGEventSetFlags(down, eventFlags);
    CGEventSetFlags(up, eventFlags);
    // Pin delivery to the foreground process sampled for this click, not a cached old client.
    CGEventPostToPid(target.processIdentifier, down);
    CGEventPostToPid(target.processIdentifier, up);
    CFRelease(down);
    CFRelease(up);
    return YES;
}
}

@interface MSIMEScreenKeyboardContent : NSView
@property(nonatomic, copy) void (^layoutKeys)(NSSize);
@end
@implementation MSIMEScreenKeyboardContent
- (BOOL)isFlipped { return YES; }
- (void)layout { [super layout]; if (self.layoutKeys) self.layoutKeys(self.bounds.size); }
@end

@implementation MSIMEScreenKeyboardPanel {
    MSIMEScreenKeyboardSender _sender;
    NSMutableArray<NSButton *> *_buttons;
    std::vector<Key> _keys;
    NSEventModifierFlags _modifiers;
    NSTextField *_status;
}
+ (instancetype)sharedPanel {
    static MSIMEScreenKeyboardPanel *panel;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ panel = [[self alloc] init]; });
    return panel;
}
- (instancetype)init { return [self initWithKeySender:^BOOL(unsigned short code, NSEventModifierFlags flags) { return PostKey(code, flags); }]; }
- (instancetype)initWithKeySender:(MSIMEScreenKeyboardSender)sender {
    self = [super initWithContentRect:NSMakeRect(0, 0, 1100, 400)
        styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    if (!self) return nil;
    _sender = [sender copy];
    _buttons = [NSMutableArray new];
    self.releasedWhenClosed = NO;
    self.level = NSFloatingWindowLevel;
    self.hidesOnDeactivate = NO;
    self.movableByWindowBackground = YES;
    self.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary;
    MSIMEScreenKeyboardContent *content = [[MSIMEScreenKeyboardContent alloc] initWithFrame:NSMakeRect(0, 0, 1100, 400)];
    content.wantsLayer = YES;
    self.contentView = content;
    _status = [NSTextField labelWithString:@"水杉屏幕键盘"];
    _status.frame = NSMakeRect(10, 4, 950, 20);
    _status.autoresizingMask = NSViewWidthSizable;
    [content addSubview:_status];
    NSButton *close = [NSButton buttonWithTitle:@"×" target:self action:@selector(closeKeyboard:)];
    close.accessibilityLabel = @"关闭屏幕键盘";
    close.frame = NSMakeRect(1066, 2, 28, 24);
    close.autoresizingMask = NSViewMinXMargin;
    [content addSubview:close];
    for (const auto &row : Rows()) for (const Key &key : row) {
        NSButton *button = [NSButton buttonWithTitle:@(key.normal) target:self action:@selector(pressKey:)];
        button.tag = _keys.size();
        button.accessibilityIdentifier = [NSString stringWithFormat:@"MSIMEScreenKeyboardKey%ld", (long)button.tag];
        button.accessibilityLabel = @(key.normal);
        button.font = [NSFont systemFontOfSize:14];
        button.bezelStyle = NSBezelStyleRegularSquare;
        button.buttonType = NSButtonTypePushOnPushOff;
        [_buttons addObject:button];
        _keys.push_back(key);
        [content addSubview:button];
    }
    __weak MSIMEScreenKeyboardPanel *weakSelf = self;
    content.layoutKeys = ^(NSSize size) { [weakSelf layoutKeys:size]; };
    [self layoutKeys:content.bounds.size];
    return self;
}
- (BOOL)canBecomeKeyWindow { return NO; }
- (BOOL)canBecomeMainWindow { return NO; }
- (void)layoutKeys:(NSSize)size {
    NSUInteger index = 0;
    const double height = std::max(1.0, (size.height - 28.0 - 7.0 - 16.0) / 5.0);
    NSUInteger rowIndex = 0;
    for (const auto &row : Rows()) {
        double weight = 0;
        for (const auto &key : row) weight += key.weight;
        const double available = std::max(1.0, size.width - 14.0 - 4.0 * (row.size() - 1));
        double x = 7;
        for (const auto &key : row) {
            double width = available * key.weight / weight;
            _buttons[index++].frame = NSMakeRect(x, 28 + rowIndex * (height + 4), width, height);
            x += width + 4;
        }
        ++rowIndex;
    }
}
- (void)refreshKeys {
    const bool shift = (_modifiers & NSEventModifierFlagShift) != 0;
    const bool caps = (_modifiers & NSEventModifierFlagCapsLock) != 0;
    for (NSUInteger index = 0; index < _keys.size(); ++index) {
        const Key &key = _keys[index];
        const bool shifted = shift || (Letter(key) && caps != shift);
        _buttons[index].title = @(shifted && key.shifted[0] ? key.shifted : key.normal);
        _buttons[index].state = key.modifier && (_modifiers & key.modifier) ? NSControlStateValueOn : NSControlStateValueOff;
    }
}
- (void)pressKey:(NSButton *)button {
    if (button.tag < 0 || (NSUInteger)button.tag >= _keys.size() || _buttons[button.tag] != button) return;
    const Key &key = _keys[button.tag];
    if (key.modifier) _modifiers ^= key.modifier;
    else {
        NSEventModifierFlags flags = _modifiers & ~NSEventModifierFlagCapsLock;
        if (Letter(key) && (_modifiers & NSEventModifierFlagCapsLock)) flags |= NSEventModifierFlagShift;
        if (CommitKey(key)) flags = 0; // Preserve Engine candidate selection with sticky modifiers.
        if (_sender && _sender(key.code, flags)) {
            _modifiers &= ~NSEventModifierFlagShift;
            _status.stringValue = @"水杉屏幕键盘";
        } else _status.stringValue = @"未发送：请检查辅助功能权限，并聚焦输入窗口后重试";
    }
    [self refreshKeys];
}
- (void)closeKeyboard:(id)sender { (void)sender; _modifiers = 0; [self refreshKeys]; [self orderOut:nil]; }
- (void)showKeyboard {
    if (!self.visible) {
        NSRect visible = (NSScreen.mainScreen ?: NSScreen.screens.firstObject).visibleFrame;
        if (!NSIsEmptyRect(visible)) {
            const NSSize size = NSMakeSize(std::min(1100.0, visible.size.width), std::min(400.0, visible.size.height));
            [self setFrame:NSMakeRect(NSMidX(visible) - size.width / 2, NSMinY(visible), size.width, size.height) display:NO];
        }
    }
    [self orderFrontRegardless];
}
@end
