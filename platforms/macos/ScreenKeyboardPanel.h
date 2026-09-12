#import <AppKit/AppKit.h>

typedef BOOL (^MSIMEScreenKeyboardSender)(unsigned short keyCode, NSEventModifierFlags flags);

// The panel never becomes the input target. Tests supply a sender without posting events.
@interface MSIMEScreenKeyboardPanel : NSPanel
+ (instancetype)sharedPanel;
- (instancetype)initWithKeySender:(MSIMEScreenKeyboardSender)sender;
- (void)showKeyboard;
@end
