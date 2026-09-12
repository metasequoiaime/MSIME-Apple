#import "TranslationSettingsWindow.h"
#import "MSIMEClientSession.h"

static NSArray *TranslationLanguages() { return @[@"en", @"fr", @"ja", @"es", @"ru", @"de", @"ko"]; }

@implementation MSIMETranslationSettingsWindow {
    NSString *_directory;
    NSDictionary *_snapshot;
    void (^_saved)(NSDictionary *);
    NSButton *_enabled, *_custom, *_reveal, *_save, *_reload;
    NSPopUpButton *_target;
    NSTextField *_endpoint, *_plainKey, *_status;
    NSSecureTextField *_key;
    NSButton *_tencent, *_revealTencent;
    NSTextField *_secretId, *_plainTencentKey, *_region;
    NSSecureTextField *_tencentKey;
    BOOL _busy, _saving;
    NSUInteger _epoch;
}
- (instancetype)initWithDirectory:(NSString *)directory saved:(void (^)(NSDictionary *))saved {
    if ((self = [super initWithWindow:nil])) { _directory = [directory copy]; _saved = [saved copy]; }
    return self;
}
- (void)loadWindow {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 570, 650)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    window.title = @"候选翻译设置"; window.delegate = self; self.window = window;
    _enabled = [NSButton checkboxWithTitle:@"显示候选释义" target:self action:@selector(updateControls:)];
    _target = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_target addItemsWithTitles:@[@"英语", @"法语", @"日语", @"西班牙语", @"俄语", @"德语", @"韩语"]];
    _custom = [NSButton checkboxWithTitle:@"启用自定义 DeepLX 翻译服务" target:self action:@selector(updateControls:)];
    _endpoint = [NSTextField textFieldWithString:@""]; _endpoint.placeholderString = @"https://example.com/translate";
    _key = [[NSSecureTextField alloc] initWithFrame:NSZeroRect]; _key.placeholderString = @"留空表示不鉴权";
    _plainKey = [NSTextField textFieldWithString:@""]; _plainKey.hidden = YES;
    _plainKey.allowsEditingTextAttributes = NO;
    _reveal = [NSButton checkboxWithTitle:@"显示 API Key" target:self action:@selector(revealKey:)];
    NSStackView *keys = [NSStackView stackViewWithViews:@[_key, _plainKey, _reveal]];
    keys.orientation = NSUserInterfaceLayoutOrientationVertical; keys.alignment = NSLayoutAttributeLeading;
    _tencent = [NSButton checkboxWithTitle:@"启用腾讯云翻译（自定义服务关闭时）" target:self action:@selector(updateControls:)];
    _secretId = [NSTextField textFieldWithString:@""]; _secretId.placeholderString = @"AKID...";
    _tencentKey = [[NSSecureTextField alloc] initWithFrame:NSZeroRect]; _tencentKey.placeholderString = @"SecretKey";
    _plainTencentKey = [NSTextField textFieldWithString:@""]; _plainTencentKey.hidden = YES;
    _plainTencentKey.allowsEditingTextAttributes = NO;
    _revealTencent = [NSButton checkboxWithTitle:@"显示 SecretKey" target:self action:@selector(revealTencentKey:)];
    _region = [NSTextField textFieldWithString:@""]; _region.placeholderString = @"ap-guangzhou（默认）";
    NSStackView *tencentKeys = [NSStackView stackViewWithViews:@[_tencentKey, _plainTencentKey, _revealTencent]];
    tencentKeys.orientation = NSUserInterfaceLayoutOrientationVertical; tencentKeys.alignment = NSLayoutAttributeLeading;
    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[[NSTextField labelWithString:@"候选释义"], _enabled],
        @[[NSTextField labelWithString:@"中文候选目标语言"], _target],
        @[[NSTextField labelWithString:@"翻译服务"], _custom],
        @[[NSTextField labelWithString:@"完整 POST 接口地址"], _endpoint],
        @[[NSTextField labelWithString:@"Bearer API Key（可选）"], keys],
        @[[NSTextField labelWithString:@"腾讯云服务"], _tencent],
        @[[NSTextField labelWithString:@"SecretId"], _secretId],
        @[[NSTextField labelWithString:@"SecretKey"], tencentKeys],
        @[[NSTextField labelWithString:@"腾讯云区域"], _region]]];
    grid.rowSpacing = 14;
    for (NSTextField *field in @[_endpoint, _key, _plainKey, _secretId, _tencentKey, _plainTencentKey, _region])
        [field.widthAnchor constraintEqualToConstant:310].active = YES;
    NSTextField *notice = [NSTextField wrappingLabelWithString:@"英文候选译为中文，英语目标优先查本地词库。自定义服务优先，未命中候选会发送到所填地址（建议 HTTPS）；关闭自定义服务后可使用腾讯云。腾讯云须填写 SecretId 和 SecretKey。凭据仅保存在本机配置文件，不参与云端设置同步。关闭两个在线服务仍保留离线释义。"];
    _status = [NSTextField wrappingLabelWithString:@""];
    _save = [NSButton buttonWithTitle:@"保存" target:self action:@selector(save:)];
    _reload = [NSButton buttonWithTitle:@"重新加载（放弃编辑）" target:self action:@selector(reload:)];
    NSStackView *buttons = [NSStackView stackViewWithViews:@[_reload, _save]];
    NSStackView *stack = [NSStackView stackViewWithViews:@[grid, notice, _status, buttons]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical; stack.alignment = NSLayoutAttributeLeading; stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO; [window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[[stack.leadingAnchor constraintEqualToAnchor:window.contentView.leadingAnchor constant:20],
        [stack.trailingAnchor constraintEqualToAnchor:window.contentView.trailingAnchor constant:-20],
        [stack.topAnchor constraintEqualToAnchor:window.contentView.topAnchor constant:20]]];
    [window center]; [self updateControls:nil];
}
- (void)showWindow:(id)sender {
    if (!self.window) [self loadWindow];
    [super showWindow:sender]; [self reload:nil];
}
- (void)updateControls:(id)sender {
    (void)sender;
    BOOL ready = !_busy && _snapshot != nil;
    _enabled.enabled = ready; _custom.enabled = ready;
    _target.enabled = ready && _enabled.state == NSControlStateValueOn;
    BOOL custom = ready && _custom.state == NSControlStateValueOn;
    _endpoint.enabled = custom; _key.enabled = custom; _plainKey.enabled = custom; _reveal.enabled = custom;
    _tencent.enabled = ready && !custom;
    BOOL tencent = ready && !custom && _tencent.state == NSControlStateValueOn;
    _secretId.enabled = tencent; _tencentKey.enabled = tencent; _plainTencentKey.enabled = tencent;
    _revealTencent.enabled = tencent; _region.enabled = tencent;
    _save.enabled = ready; _reload.enabled = !_busy;
}
- (void)revealKey:(id)sender {
    (void)sender;
    [self.window makeFirstResponder:nil];
    BOOL reveal = _reveal.state == NSControlStateValueOn;
    if (reveal) { _plainKey.stringValue = _key.stringValue; _key.stringValue = @""; }
    else { _key.stringValue = _plainKey.stringValue; _plainKey.stringValue = @""; }
    _plainKey.hidden = !reveal; _key.hidden = reveal;
}
- (void)reload:(id)sender {
    (void)sender;
    if (_busy) return;
    if (!_directory.isAbsolutePath) { _status.stringValue = @"请先激活水杉输入法以加载本机配置。"; return; }
    _busy = YES; _snapshot = nil; _key.stringValue = @""; _plainKey.stringValue = @"";
    _secretId.stringValue = @""; _tencentKey.stringValue = @""; _plainTencentKey.stringValue = @"";
    _status.stringValue = @"正在加载…"; [self updateControls:nil];
    NSUInteger epoch = ++_epoch;
    NSString *directory = _directory;
    __weak MSIMETranslationSettingsWindow *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *snapshot = [MSIMEClientSession loadPreferencesInDirectory:directory error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMETranslationSettingsWindow *current = weakSelf;
            if (!current || current->_epoch != epoch) return;
            current->_busy = NO; current->_snapshot = snapshot;
            NSDictionary *preferences = snapshot[@"preferences"], *custom = preferences[@"custom_translation"];
            if (snapshot) {
                current->_enabled.state = [preferences[@"candidate_translations"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
                NSUInteger index = [TranslationLanguages() indexOfObject:preferences[@"translation_target_language"] ?: @"en"];
                [current->_target selectItemAtIndex:index == NSNotFound ? 0 : index];
                current->_custom.state = [custom[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
                current->_endpoint.stringValue = custom[@"endpoint"] ?: @"";
                current->_key.stringValue = custom[@"api_key"] ?: @"";
                current->_plainKey.hidden = YES; current->_key.hidden = NO; current->_reveal.state = NSControlStateValueOff;
                NSDictionary *tencent = preferences[@"tencent_tmt"];
                current->_tencent.state = [tencent[@"enabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
                current->_secretId.stringValue = tencent[@"secret_id"] ?: @"";
                current->_tencentKey.stringValue = tencent[@"secret_key"] ?: @"";
                current->_region.stringValue = tencent[@"region"] ?: @"ap-guangzhou";
                current->_plainTencentKey.hidden = YES; current->_tencentKey.hidden = NO;
                current->_revealTencent.state = NSControlStateValueOff;
            }
            current->_status.stringValue = snapshot ? @"修改后点击保存。" : @"加载失败；未修改任何设置。";
            [current updateControls:nil];
        });
    });
}
- (void)save:(id)sender {
    (void)sender;
    if (_busy || !_snapshot) return;
    [self.window makeFirstResponder:nil];
    NSString *key = _reveal.state == NSControlStateValueOn ? _plainKey.stringValue : _key.stringValue;
    NSDictionary *custom = @{@"enabled":@(_custom.state == NSControlStateValueOn), @"endpoint":_endpoint.stringValue, @"api_key":key};
    // Use the same descriptor validation as runtime even for disabled drafts.
    if ([custom[@"enabled"] boolValue]) {
        NSDictionary *request = [MSIMEClientSession customTranslationHTTPRequest:@{@"config":custom,
            @"text":@"validation", @"source_language":@"en", @"target_language":@"zh"} error:nil];
        NSURLComponents *url = [NSURLComponents componentsWithString:_endpoint.stringValue];
        if (!request || !url.host.length || url.user || url.password || url.fragment ||
            [_endpoint.stringValue rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
            _status.stringValue = @"请输入有效的 HTTP(S) 完整接口地址和不含控制字符的 API Key。"; return;
        }
    }
    NSMutableDictionary *preferences = [_snapshot[@"preferences"] mutableCopy];
    preferences[@"custom_translation"] = custom;
    preferences[@"tencent_tmt"] = @{@"enabled":@(_tencent.state == NSControlStateValueOn),
        @"secret_id":_secretId.stringValue, @"secret_key":_revealTencent.state == NSControlStateValueOn ? _plainTencentKey.stringValue : _tencentKey.stringValue,
        @"region":_region.stringValue};
    preferences[@"candidate_translations"] = @(_enabled.state == NSControlStateValueOn);
    preferences[@"translation_target_language"] = TranslationLanguages()[_target.indexOfSelectedItem];
    NSMutableDictionary *snapshot = [_snapshot mutableCopy]; snapshot[@"preferences"] = preferences;
    uint64_t revision = [_snapshot[@"revision"] unsignedLongLongValue];
    _busy = YES; _saving = YES; _status.stringValue = @"正在保存…"; [self updateControls:nil];
    NSUInteger epoch = ++_epoch;
    NSString *directory = _directory;
    __weak MSIMETranslationSettingsWindow *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSDictionary *saved = [MSIMEClientSession savePreferencesInDirectory:directory expectedRevision:revision snapshot:snapshot error:nil];
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMETranslationSettingsWindow *current = weakSelf;
            if (!current || current->_epoch != epoch) return;
            current->_busy = NO; current->_saving = NO;
            if (saved) { current->_snapshot = saved; if (current->_saved) current->_saved(saved[@"preferences"]); }
            current->_status.stringValue = saved ? @"已保存到本机配置。" : @"保存失败或配置已被其他窗口更新；请重新加载后再试。";
            [current updateControls:nil];
        });
    });
}
- (BOOL)windowShouldClose:(NSWindow *)sender { (void)sender; return !_saving; }
- (void)windowWillClose:(NSNotification *)notification {
    (void)notification; ++_epoch; _busy = NO; _saving = NO; _snapshot = nil;
    _key.stringValue = @""; _plainKey.stringValue = @""; _endpoint.stringValue = @"";
    _secretId.stringValue = @""; _tencentKey.stringValue = @""; _plainTencentKey.stringValue = @"";
}
- (void)revealTencentKey:(id)sender {
    (void)sender;
    [self.window makeFirstResponder:nil];
    BOOL reveal = _revealTencent.state == NSControlStateValueOn;
    if (reveal) { _plainTencentKey.stringValue = _tencentKey.stringValue; _tencentKey.stringValue = @""; }
    else { _tencentKey.stringValue = _plainTencentKey.stringValue; _plainTencentKey.stringValue = @""; }
    _plainTencentKey.hidden = !reveal; _tencentKey.hidden = reveal;
}
@end
