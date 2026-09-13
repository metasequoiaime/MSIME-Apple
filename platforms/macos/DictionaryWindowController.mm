#import "DictionaryWindowController.h"
#import "MSIMEClientSession.h"
#import "ClientDictionaryRuntime.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

@interface MSIMEDictionaryWindowController ()
@property(nonatomic, copy) NSDictionary *options;
@property(nonatomic, strong) NSTextView *content;
@property(nonatomic) NSUInteger offset;
@property(nonatomic, strong) NSButton *previous;
@property(nonatomic, strong) NSButton *next;
@property(nonatomic, strong) NSTextField *pageLabel;
@property(nonatomic, strong) NSPopUpButton *kind;
@property(nonatomic, strong) NSPopUpButton *format;
@property(nonatomic, strong) NSButton *importButton;
@property(nonatomic, strong) NSButton *exportButton;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, copy) NSString *runtimeError;
@end
@implementation MSIMEDictionaryWindowController
- (instancetype)initWithOptions:(NSDictionary *)options {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 620, 500) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (self) {
        _options = [options copy];
        NSError *error = nil;
        if (![[MSIMEDictionaryRuntime alloc] initWithHostOptions:_options error:&error]) _runtimeError = error.localizedDescription ?: @"词典运行目录配置无效";
        window.title = @"个人词典"; window.releasedWhenClosed = NO; [self loadWindow];
    }
    return self;
}
- (void)loadWindow {
    _kind = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSArray<NSString *> *item in @[@[@"拼音词库", @"pinyin"], @[@"五笔词库", @"wubi"], @[@"快捷短语", @"quick_phrase"], @[@"英文词库", @"english"]]) {
        [_kind addItemWithTitle:item[0]];
        _kind.lastItem.representedObject = item[1];
    }
    _kind.translatesAutoresizingMaskIntoConstraints = NO;
    _format = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSArray<NSString *> *item in @[@[@"标准 TSV", @"standard"], @[@"Windows TSV", @"windows"], @[@"Rime userdb / dict.yaml", @"rime"], @[@"汉字自动注音（仅导入）", @"hans"]]) {
        [_format addItemWithTitle:item[0]];
        _format.lastItem.representedObject = item[1];
    }
    _format.translatesAutoresizingMaskIntoConstraints = NO;
    NSButton *refresh = [NSButton buttonWithTitle:@"刷新" target:self action:@selector(refresh:)];
    refresh.translatesAutoresizingMaskIntoConstraints = NO;
    _importButton = [NSButton buttonWithTitle:@"导入…" target:self action:@selector(importFile:)];
    _importButton.translatesAutoresizingMaskIntoConstraints = NO;
    _exportButton = [NSButton buttonWithTitle:@"导出…" target:self action:@selector(exportFile:)];
    _exportButton.translatesAutoresizingMaskIntoConstraints = NO;
    _previous = [NSButton buttonWithTitle:@"上一页" target:self action:@selector(previousPage:)];
    _next = [NSButton buttonWithTitle:@"下一页" target:self action:@selector(nextPage:)];
    _previous.translatesAutoresizingMaskIntoConstraints = _next.translatesAutoresizingMaskIntoConstraints = NO;
    _pageLabel = [NSTextField labelWithString:@"第 1 页"]; _pageLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _status = [NSTextField labelWithString:@""]; _status.translatesAutoresizingMaskIntoConstraints = NO;
    _content = [[NSTextView alloc] initWithFrame:NSZeroRect];
    _content.editable = NO; _content.font = [NSFont systemFontOfSize:13]; _content.translatesAutoresizingMaskIntoConstraints = NO;
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.hasVerticalScroller = YES; scroll.documentView = _content; scroll.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:_kind]; [self.window.contentView addSubview:_format]; [self.window.contentView addSubview:refresh]; [self.window.contentView addSubview:_importButton]; [self.window.contentView addSubview:_exportButton]; [self.window.contentView addSubview:_previous]; [self.window.contentView addSubview:_next]; [self.window.contentView addSubview:_pageLabel]; [self.window.contentView addSubview:_status]; [self.window.contentView addSubview:scroll];
    [NSLayoutConstraint activateConstraints:@[[_kind.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:12], [_kind.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:12], [_format.topAnchor constraintEqualToAnchor:_kind.topAnchor], [_format.leadingAnchor constraintEqualToAnchor:_kind.trailingAnchor constant:8], [refresh.topAnchor constraintEqualToAnchor:_kind.topAnchor], [refresh.leadingAnchor constraintEqualToAnchor:_format.trailingAnchor constant:8], [_importButton.topAnchor constraintEqualToAnchor:_kind.topAnchor], [_importButton.leadingAnchor constraintEqualToAnchor:refresh.trailingAnchor constant:8], [_exportButton.topAnchor constraintEqualToAnchor:_kind.topAnchor], [_exportButton.leadingAnchor constraintEqualToAnchor:_importButton.trailingAnchor constant:8], [_exportButton.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-12], [_next.topAnchor constraintEqualToAnchor:_kind.bottomAnchor constant:8], [_next.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-12], [_previous.topAnchor constraintEqualToAnchor:_next.topAnchor], [_previous.trailingAnchor constraintEqualToAnchor:_next.leadingAnchor constant:-8], [_pageLabel.centerYAnchor constraintEqualToAnchor:_next.centerYAnchor], [_pageLabel.trailingAnchor constraintEqualToAnchor:_previous.leadingAnchor constant:-12], [_status.topAnchor constraintEqualToAnchor:_next.bottomAnchor constant:8], [_status.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:12], [_status.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-12], [scroll.topAnchor constraintEqualToAnchor:_status.bottomAnchor constant:8], [scroll.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:12], [scroll.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-12], [scroll.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-12]]];
    [self refresh:nil];
}
- (NSString *)selectedKind { return self.kind.selectedItem.representedObject ?: @"pinyin"; }
- (NSString *)selectedFormat { return self.format.selectedItem.representedObject ?: @"standard"; }
- (void)showMessage:(NSString *)message {
    self.status.stringValue = message.length ? message : @"操作失败";
}
- (void)refresh:(id)sender {
    (void)sender;
    NSUInteger offset = self.offset;
    if (self.runtimeError) { self.content.string = self.runtimeError; self.previous.enabled = NO; self.next.enabled = NO; return; }
    NSDictionary *request = @{ @"options": self.options, @"action": @{ @"operation": @"list", @"offset": @(offset), @"limit": @100 } };
    __weak MSIMEDictionaryWindowController *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSDictionary *result = [MSIMEClientSession dictionaryRequest:request error:&error];
        NSString *message = nil;
        BOOL hasMore = [result[@"has_more"] boolValue];
        if (!result) message = error.localizedDescription ?: @"词典读取失败";
        else {
            NSMutableString *text = [NSMutableString string];
            for (NSDictionary *entry in result[@"entries"]) [text appendFormat:@"%@\t%@\n", entry[@"key"] ?: @"", entry[@"value"] ?: @""];
            message = text.length ? text : @"暂无个人词条";
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEDictionaryWindowController *controller = weakSelf;
            if (controller) { controller.content.string = message; controller.previous.enabled = offset >= 100; controller.next.enabled = hasMore; controller.pageLabel.stringValue = [NSString stringWithFormat:@"第 %lu 页", (unsigned long)(offset / 100 + 1)]; }
        });
    });
}
- (void)importFile:(id)sender {
    (void)sender;
    if (self.runtimeError) { [self showMessage:self.runtimeError]; return; }
    if ([[self selectedFormat] isEqualToString:@"hans"] && ![[self selectedKind] isEqualToString:@"pinyin"]) {
        [self showMessage:@"汉字自动注音格式只支持拼音词库。"];
        return;
    }
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories = NO;
    panel.allowedContentTypes = @[UTTypePlainText, UTTypeTabSeparatedText, UTTypeYAML];
    __weak MSIMEDictionaryWindowController *weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        MSIMEDictionaryWindowController *controller = weakSelf;
        if (!controller) return;
        NSURL *sourceURL = [panel.URL copy];
        NSError *error = nil;
        NSData *data = [NSData dataWithContentsOfURL:sourceURL options:0 error:&error];
        if (!data || data.length == 0 || data.length > 65536) {
            [controller showMessage:@"文件需为不超过 64 KiB 的 UTF-8 文本。"];
            return;
        }
        NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!text || [text rangeOfString:@"\0"].location != NSNotFound) {
            [controller showMessage:@"文件需为不超过 64 KiB 的 UTF-8 文本。"];
            return;
        }
        NSDictionary *request = @{ @"options": controller.options, @"action": @{ @"operation": @"import", @"kind": [controller selectedKind], @"format": [controller selectedFormat], @"text": text, @"request_id": NSUUID.UUID.UUIDString } };
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSError *requestError = nil;
            NSDictionary *result = [MSIMEClientSession dictionaryRequest:request error:&requestError];
            NSString *message = nil;
            if (!result) message = requestError.localizedDescription ?: @"词典导入失败";
            else {
                NSUInteger applied = [result[@"applied"] unsignedIntegerValue];
                NSUInteger failed = [result[@"failed"] unsignedIntegerValue];
                BOOL truncated = [result[@"truncated"] boolValue];
                message = failed || truncated
                    ? [NSString stringWithFormat:@"已导入 %lu 个词条，跳过 %lu 个无效条目%@。", (unsigned long)applied, (unsigned long)failed, truncated ? @"（达到上限）" : @""]
                    : [NSString stringWithFormat:@"已导入 %lu 个词条。", (unsigned long)applied];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf) { [weakSelf showMessage:message]; weakSelf.offset = 0; [weakSelf refresh:nil]; } });
        });
    }];
}
- (void)exportFile:(id)sender {
    (void)sender;
    if (self.runtimeError) { [self showMessage:self.runtimeError]; return; }
    NSString *format = [self selectedFormat];
    if ([format isEqualToString:@"hans"] || [format isEqualToString:@"rime"]) {
        [self showMessage:@"当前格式仅支持导入，请选择标准 TSV 或 Windows TSV。"];
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.allowedContentTypes = @[UTTypeTabSeparatedText];
    panel.nameFieldStringValue = [NSString stringWithFormat:@"msime-%@.tsv", [self selectedKind]];
    __weak MSIMEDictionaryWindowController *weakSelf = self;
    [panel beginWithCompletionHandler:^(NSModalResponse response) {
        if (response != NSModalResponseOK || !panel.URL) return;
        MSIMEDictionaryWindowController *controller = weakSelf;
        if (!controller) return;
        NSURL *destinationURL = [panel.URL copy];
        NSDictionary *options = controller.options;
        NSString *kind = [controller selectedKind];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            NSMutableString *text = [NSMutableString string];
            NSUInteger offset = 0;
            BOOL hasMore = YES;
            NSString *message = nil;
            while (hasMore && offset <= 1000000) {
                NSDictionary *request = @{ @"options": options, @"action": @{ @"operation": @"export", @"kind": kind, @"format": format, @"offset": @(offset), @"limit": @1000 } };
                NSError *error = nil;
                NSDictionary *result = [MSIMEClientSession dictionaryRequest:request error:&error];
                if (!result) { message = error.localizedDescription ?: @"词典导出失败"; break; }
                NSString *chunk = [result[@"text"] isKindOfClass:NSString.class] ? result[@"text"] : @"";
                [text appendString:chunk];
                NSUInteger count = 0;
                for (NSString *line in [chunk componentsSeparatedByString:@"\n"]) if (line.length) ++count;
                hasMore = [result[@"has_more"] boolValue];
                if (hasMore && count == 0) { message = @"词典导出返回了无效分页。"; break; }
                offset += count;
            }
            if (!message && hasMore) message = @"词典导出超过了支持的条目上限。";
            if (!message) {
                NSError *error = nil;
                NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
                if (![data writeToURL:destinationURL options:NSDataWritingAtomic error:&error]) message = error.localizedDescription ?: @"词典文件写入失败";
                else message = [NSString stringWithFormat:@"已导出至 %@。", destinationURL.lastPathComponent];
            }
            dispatch_async(dispatch_get_main_queue(), ^{ if (weakSelf) [weakSelf showMessage:message]; });
        });
    }];
}
- (void)previousPage:(id)sender { (void)sender; if (_offset >= 100) { _offset -= 100; [self refresh:nil]; } }
- (void)nextPage:(id)sender { (void)sender; _offset += 100; [self refresh:nil]; }
@end
