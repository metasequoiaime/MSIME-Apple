#import "DictionaryWindowController.h"
#import "MSIMEClientSession.h"

@interface MSIMEDictionaryWindowController ()
@property(nonatomic, copy) NSDictionary *options;
@property(nonatomic, strong) NSTextView *content;
@end
@implementation MSIMEDictionaryWindowController
- (instancetype)initWithOptions:(NSDictionary *)options {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 420) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) { _options = [options copy]; window.title = @"个人词典"; window.releasedWhenClosed = NO; [self loadWindow]; }
    return self;
}
- (void)loadWindow {
    NSButton *refresh = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(refresh:)];
    refresh.translatesAutoresizingMaskIntoConstraints = NO;
    _content = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _content.editable = NO; _content.font = [NSFont systemFontOfSize:13]; _content.translatesAutoresizingMaskIntoConstraints = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES; scroll.documentView = _content; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:refresh]; [self.window.contentView addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[refresh.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:12], [refresh.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-12], [scroll.topAnchor constraintEqualToAnchor:refresh.bottomAnchor constant:8], [scroll.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:12], [scroll.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-12], [scroll.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-12]]];
    [self refresh:nil];
}
- (void)refresh:(id)sender {
    (void)sender;
    NSDictionary *request = @{ @"options": self.options, @"action": @{ @"operation": @"list", @"offset": @0, @"limit": @100 } };
    __weak MSIMEDictionaryWindowController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSDictionary *result = [MSIMEClientSession dictionaryRequest:request error:&error];
        NSString *message = nil;
        if (!result) message = error.localizedDescription ?: @"词典读取失败";
        else {
            NSMutableString *text = [NSMutableString string];
            for (NSDictionary *entry in result[@"entries"]) [text appendFormat:@"%@\t%@\n", entry[@"key"] ?: @"", entry[@"value"] ?: @""];
            message = text.length ? text : @"暂无个人词条";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEDictionaryWindowController *controller = weakSelf;
            if (controller) controller.content.string = message;
        });
    });
}
@end
