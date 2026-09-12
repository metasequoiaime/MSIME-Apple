#import "AISettingsWindow.h"
#import "MSIMEClientSession.h"
#import "AISettingsSnapshot.h"

static BOOL SafeAIEndpoint(NSString *value) {
    NSURLComponents *url = [NSURLComponents componentsWithString:value ?: @""];
    return ([url.scheme.lowercaseString isEqualToString:@"http"] || [url.scheme.lowercaseString isEqualToString:@"https"]) && url.host.length && !url.user.length && !url.password.length && !url.fragment.length;
}

@implementation MSIMEAISettingsWindow {
    NSString *_directory;
    void (^_saved)(NSDictionary *);
    NSDictionary *_snapshot;
    NSButton *_enabled;
    NSPopUpButton *_provider;
    NSTextField *_model, *_endpoint, *_limit, *_status;
    NSArray<NSTextField *> *_prompts;
}

- (instancetype)initWithDirectory:(NSString *)directory saved:(void (^)(NSDictionary *))saved {
    if ((self = [super initWithWindow:nil])) { _directory = [directory copy]; _saved = [saved copy]; }
    return self;
}

- (void)loadWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 600, 620) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title = @"AI 联想设置"; self.window = window;
    _enabled = [NSButton checkboxWithTitle:@"启用 AI 联想" target:nil action:nil];
    _provider = [[NSPopUpButton alloc] initWithFrame:NSZeroRect]; [_provider addItemsWithTitles:@[@"DeepSeek", @"OpenAI", @"SiliconFlow", @"Groq"]];
    _model = [NSTextField textFieldWithString:@""]; _endpoint = [NSTextField textFieldWithString:@""]; _limit = [NSTextField textFieldWithString:@"3"];
    NSMutableArray *prompts = [NSMutableArray array]; for (NSUInteger i = 0; i < 4; ++i) [prompts addObject:[NSTextField textFieldWithString:@""]]; _prompts = prompts;
    NSGridView *grid = [NSGridView gridViewWithViews:@[@[[NSTextField labelWithString:@"状态"], _enabled], @[[NSTextField labelWithString:@"提供商"], _provider], @[[NSTextField labelWithString:@"模型"], _model], @[[NSTextField labelWithString:@"接口地址"], _endpoint], @[[NSTextField labelWithString:@"候选数量"], _limit], @[[NSTextField labelWithString:@"默认提示词"], _prompts[0]], @[[NSTextField labelWithString:@"自定义提示词 1"], _prompts[1]], @[[NSTextField labelWithString:@"自定义提示词 2"], _prompts[2]], @[[NSTextField labelWithString:@"自定义提示词 3"], _prompts[3]]]];
    grid.rowSpacing = 12; for (NSView *view in @[_model, _endpoint, _limit, _prompts[0], _prompts[1], _prompts[2], _prompts[3]]) { view.translatesAutoresizingMaskIntoConstraints = NO; [view.widthAnchor constraintEqualToConstant:390].active = YES; }
    _status = [NSTextField wrappingLabelWithString:@""]; NSButton *save = [NSButton buttonWithTitle:@"保存" target:self action:@selector(save:)]; NSButton *reload = [NSButton buttonWithTitle:@"重新加载" target:self action:@selector(reload:)];
    NSStackView *stack = [NSStackView stackViewWithViews:@[grid, _status, [NSStackView stackViewWithViews:@[reload, save]]]]; stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.spacing = 16; stack.translatesAutoresizingMaskIntoConstraints = NO; [window.contentView addSubview:stack]; [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20], [stack.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20], [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20]]]; [window center];
}
- (void)showWindow:(id)sender { if (!self.window) [self loadWindow]; [super showWindow:sender]; [self reload:nil]; }
- (void)reload:(id)sender { (void)sender; if (!_directory.isAbsolutePath) { _status.stringValue = @"请先激活输入法。"; return; } _snapshot = [MSIMEClientSession loadPreferencesInDirectory:_directory error:nil]; NSDictionary *ai = _snapshot[@"preferences"][@"ai_assistant"]; _enabled.state = [ai[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff; NSArray *providers = @[@"deepseek", @"openai", @"siliconflow", @"groq"]; NSUInteger index = [providers indexOfObject:ai[@"provider"]]; [_provider selectItemAtIndex:index == NSNotFound ? 0 : index]; _model.stringValue = ai[@"model"] ?: @""; _endpoint.stringValue = ai[@"endpoint"] ?: @""; _limit.stringValue = [ai[@"candidate_limit"] stringValue] ?: @"3"; for (NSUInteger i = 0; i < 4; ++i) _prompts[i].stringValue = ai[i ? [NSString stringWithFormat:@"prompt_custom_%lu", (unsigned long)i] : @"prompt"] ?: @""; _status.stringValue = _snapshot ? @"修改后点击保存。" : @"加载失败。"; }
- (void)save:(id)sender { (void)sender; if (!_snapshot) return; NSInteger limit = _limit.integerValue; if (limit < 1 || limit > 10) { _status.stringValue = @"候选数量必须为 1～10。"; return; } if (_enabled.state == NSControlStateValueOn && !SafeAIEndpoint(_endpoint.stringValue)) { _status.stringValue = @"启用 AI 时请输入有效的 HTTP(S) 接口地址。"; return; } NSArray *providers = @[@"deepseek", @"openai", @"siliconflow", @"groq"]; NSDictionary *edits = @{ @"enabled": @(_enabled.state == NSControlStateValueOn), @"provider": providers[_provider.indexOfSelectedItem], @"model": _model.stringValue, @"endpoint": _endpoint.stringValue, @"candidate_limit": @(limit), @"prompt": _prompts[0].stringValue, @"prompt_custom_1": _prompts[1].stringValue, @"prompt_custom_2": _prompts[2].stringValue, @"prompt_custom_3": _prompts[3].stringValue }; NSMutableDictionary *snapshot = [_snapshot mutableCopy]; snapshot[@"preferences"] = MSIMEAISettingsMerge(_snapshot[@"preferences"], edits); NSDictionary *saved = [MSIMEClientSession savePreferencesInDirectory:_directory expectedRevision:[_snapshot[@"revision"] unsignedLongLongValue] snapshot:snapshot error:nil]; if (saved) { _snapshot = saved; _status.stringValue = @"已保存。"; if (_saved) _saved(saved[@"preferences"]); } else _status.stringValue = @"保存失败，请重新加载。"; }
@end
