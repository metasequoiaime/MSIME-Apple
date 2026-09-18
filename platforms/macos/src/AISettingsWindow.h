#import <AppKit/AppKit.h>
@interface MSIMEAISettingsWindow : NSWindowController
- (instancetype)initWithDirectory:(NSString *)directory saved:(void (^)(NSDictionary *))saved;
@end
