#import "AccountWindowController.h"
#import "AccountKeychain.h"
@implementation MSIMEAccountWindowController
+ (instancetype)sharedController { static MSIMEAccountWindowController *c; static dispatch_once_t once; dispatch_once(&once, ^{ c = [[self alloc] initWithWindow:nil]; }); return c; }
- (void)showForAccountID:(NSString *)accountID { if (!self.window) { self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,420,180) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO]; self.window.title = @"水杉账户"; } NSError *e=nil; NSString *token=MSIMEKeychainToken(accountID,&e); NSTextField *label=[[NSTextField alloc] initWithFrame:NSMakeRect(24,70,372,70)]; label.editable=NO; label.bezeled=NO; label.drawsBackground=NO; label.stringValue=token.length ? [NSString stringWithFormat:@"账户 %@\n已保存授权凭据，可用于云词库。",accountID] : @"尚未找到该账户的授权凭据。"; self.window.contentView=label; [self.window center]; [self showWindow:nil]; [NSApp activateIgnoringOtherApps:YES]; }
@end
