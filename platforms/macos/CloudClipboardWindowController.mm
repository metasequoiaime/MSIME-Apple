#import "CloudClipboardWindowController.h"
#import "CloudClipboardClient.h"
@implementation MSIMECloudClipboardWindowController { NSString *_token; NSTextView *_editor; }
+ (instancetype)sharedController { static MSIMECloudClipboardWindowController *c; static dispatch_once_t once; dispatch_once(&once, ^{ c=[self new]; }); return c; }
- (void)showWithToken:(NSString *)token { _token=[token copy]; if(!self.window){self.window=[[NSWindow alloc]initWithContentRect:NSMakeRect(0,0,480,260) styleMask:(NSWindowStyleMaskTitled|NSWindowStyleMaskClosable) backing:NSBackingStoreBuffered defer:NO];self.window.title=@"云剪贴板";} _editor=[[NSTextView alloc]initWithFrame:NSMakeRect(20,70,440,130)]; NSButton *upload=[NSButton buttonWithTitle:@"上传明确选择的文本" target:self action:@selector(upload:)];upload.frame=NSMakeRect(20,25,180,32);NSView*v=[NSView new];v.frame=NSMakeRect(0,0,480,260);[v addSubview:_editor];[v addSubview:upload];self.window.contentView=v;[self.window center];[self showWindow:nil];[NSApp activateIgnoringOtherApps:YES]; }
- (void)upload:(id)sender { (void)sender; NSString *text=_editor.string; if(!text.length||text.length>4000)return; MSIMEAddCloudClipboard(text,_token,^(__unused NSData*d,NSInteger status,__unused NSError*e){ if(status>=200&&status<300) self->_editor.string=@""; }); }
@end
