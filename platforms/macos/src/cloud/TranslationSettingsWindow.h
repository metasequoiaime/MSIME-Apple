#import <AppKit/AppKit.h>

/// Explicit local-only editing; no translation request is sent by this window.
@interface MSIMETranslationSettingsWindow : NSWindowController <NSWindowDelegate>
- (instancetype)initWithDirectory:(NSString *)directory saved:(void (^)(NSDictionary *preferences))saved;
@end
