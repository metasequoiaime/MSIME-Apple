#import <AppKit/AppKit.h>
#include <sys/types.h>

typedef BOOL (^MSIMEScreenKeyboardSender)(unsigned short keyCode, NSEventModifierFlags flags);
typedef pid_t (^MSIMEScreenKeyboardTargetProvider)(void);

// The panel never becomes the input target. Tests supply a sender without posting events.
@interface MSIMEScreenKeyboardPanel : NSPanel
+ (instancetype)sharedPanel;
- (instancetype)initWithKeySender:(MSIMEScreenKeyboardSender)sender;
- (instancetype)initWithKeySender:(MSIMEScreenKeyboardSender)sender
                    targetProvider:(MSIMEScreenKeyboardTargetProvider)targetProvider;
- (void)showKeyboard;
- (void)applyThemePreferences:(NSDictionary *)preferences;
@end
