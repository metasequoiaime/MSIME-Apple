#import "AccountWindowController.h"
#import "AccountAuthClient.h"
#import "AccountSessionManager.h"
#import "AccountKeychain.h"

@implementation MSIMEAccountWindowController {
    NSString *_accountID;
}

+ (instancetype)sharedController {
    static MSIMEAccountWindowController *controller;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ controller = [[self alloc] initWithWindow:nil]; });
    return controller;
}

- (void)showForAccountID:(NSString *)accountID {
    _accountID = [accountID copy];
    if (!self.window) {
        self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 180)
                                                   styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
                                                     backing:NSBackingStoreBuffered defer:NO];
        self.window.title = @"水杉账户";
    }
    NSString *token = [[MSIMEAccountSessionManager sharedManager] accessTokenForAccountID:accountID];
    NSTextField *label = [[NSTextField alloc] initWithFrame:NSMakeRect(24, 90, 372, 50)];
    label.editable = NO; label.bezeled = NO; label.drawsBackground = NO;
    label.stringValue = token.length ? [NSString stringWithFormat:@"账户 %@\n已保存授权凭据。", accountID] : @"尚未找到授权凭据。";
    NSButton *login = [[NSButton alloc] initWithFrame:NSMakeRect(24, 35, 100, 32)];
    login.title = @"登录"; login.bezelStyle = NSBezelStyleRounded; login.target = self; login.action = @selector(login:);
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 180)]; [view addSubview:label]; [view addSubview:login]; self.window.contentView = view;
    [self.window center]; [self showWindow:nil]; [NSApp activateIgnoringOtherApps:YES];
}

- (void)login:(id)sender { (void)sender; MSIMEAuthChallenge(nil, ^(NSData *data, NSInteger status, NSError *error) { if (status < 200 || status >= 300 || error) return; NSDictionary *challenge = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil]; NSString *value = challenge[@"challenge"]; if (![value isKindOfClass:NSString.class]) return; NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = @"输入登录凭据"; NSSecureTextField *field = [[NSSecureTextField alloc] initWithFrame:NSMakeRect(0, 0, 260, 24)]; alert.accessoryView = field; [alert addButtonWithTitle:@"登录"]; [alert addButtonWithTitle:@"取消"]; if ([alert runModal] != NSAlertFirstButtonReturn) return; MSIMEAuthLogin(value, field.stringValue, nil, ^(NSData *result, NSInteger resultStatus, NSError *resultError) { if (resultStatus < 200 || resultStatus >= 300 || resultError) return; NSDictionary *tokens = [NSJSONSerialization JSONObjectWithData:result options:0 error:nil]; NSString *access = tokens[@"access_token"]; if ([access isKindOfClass:NSString.class]) { NSError *storeError = nil; MSIMEStoreKeychainToken(self->_accountID, access, &storeError); } }); }); }
@end
