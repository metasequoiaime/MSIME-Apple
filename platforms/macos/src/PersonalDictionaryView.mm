#import "PersonalDictionaryView.h"

#import "PersonalDictionaryStore.h"
#import "PreferencesWindowController.h"

#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

namespace
{
// 一页 50 条。引擎允许到 1000,但这块面板只有十来行高,一次取回一屏之外的东西只是让翻页失去意义。
constexpr NSUInteger kPageSize = 50;

NSTextField *FieldWithPlaceholder(NSString *placeholder)
{
    NSTextField *field = [NSTextField textFieldWithString:@""];
    field.placeholderString = placeholder;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    [field.widthAnchor constraintEqualToConstant:260.0].active = YES;
    return field;
}

NSTextField *EditorLabel(NSString *text)
{
    NSTextField *label = [NSTextField labelWithString:text];
    label.alignment = NSTextAlignmentRight;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    [label.widthAnchor constraintEqualToConstant:64.0].active = YES;
    return label;
}
} // namespace

@interface MetasequoiaPersonalDictionaryView () <NSTableViewDataSource, NSTableViewDelegate>
@end

@implementation MetasequoiaPersonalDictionaryView
{
    NSTableView *_table;
    NSTextField *_statusLabel;
    NSButton *_addButton;
    NSButton *_editButton;
    NSButton *_removeButton;
    NSButton *_exportButton;
    NSButton *_previousButton;
    NSButton *_nextButton;
    NSArray<MetasequoiaPersonalDictionaryEntry *> *_entries;
    NSUInteger _offset;
    BOOL _hasMore;
    // 加词表单同一时刻只会开一张,控件留成 ivar,类别一变就能直接改提示,不用把 block 挂到按钮上。
    NSPopUpButton *_editorKindButton;
    NSTextField *_editorKeyField;
    NSTextField *_editorHintLabel;
}

- (instancetype)initWithFrame:(NSRect)frameRect
{
    self = [super initWithFrame:frameRect];
    if (self == nil)
    {
        return nil;
    }
    _entries = @[];
    _offset = 0;
    _hasMore = NO;
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.accessibilityLabel = @"用户词库";

    _table = [[NSTableView alloc] initWithFrame:NSZeroRect];
    _table.dataSource = self;
    _table.delegate = self;
    _table.usesAlternatingRowBackgroundColors = YES;
    _table.allowsMultipleSelection = NO;
    _table.rowHeight = 22.0;
    _table.accessibilityLabel = @"用户词库列表";
    NSArray<NSArray *> *columns = @[
        @[ @"kind", @"类别", @70.0 ], @[ @"key", @"编码", @170.0 ], @[ @"value", @"词条", @220.0 ],
        @[ @"weight", @"权重", @80.0 ]
    ];
    for (NSArray *definition in columns)
    {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:definition[0]];
        column.title = definition[1];
        column.width = [definition[2] doubleValue];
        [_table addTableColumn:column];
    }

    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = _table;
    [scroll.heightAnchor constraintEqualToConstant:240.0].active = YES;

    _addButton = [NSButton buttonWithTitle:@"新增…" target:self action:@selector(addEntry:)];
    _editButton = [NSButton buttonWithTitle:@"编辑…" target:self action:@selector(editEntry:)];
    _removeButton = [NSButton buttonWithTitle:@"删除" target:self action:@selector(removeEntry:)];
    _exportButton = [NSButton buttonWithTitle:@"导出…" target:self action:@selector(exportEntries:)];
    _previousButton = [NSButton buttonWithTitle:@"上一页" target:self action:@selector(showPreviousPage:)];
    _nextButton = [NSButton buttonWithTitle:@"下一页" target:self action:@selector(showNextPage:)];
    for (NSButton *button in @[ _addButton, _editButton, _removeButton, _exportButton, _previousButton, _nextButton ])
    {
        button.bezelStyle = NSBezelStyleRounded;
        button.accessibilityLabel = button.title;
    }
    _removeButton.hasDestructiveAction = YES;

    _statusLabel = [NSTextField labelWithString:@""];
    _statusLabel.textColor = [NSColor secondaryLabelColor];
    _statusLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _statusLabel.accessibilityLabel = @"用户词库状态";
    _statusLabel.maximumNumberOfLines = 2;

    NSStackView *actions = [NSStackView
        stackViewWithViews:@[ _addButton, _editButton, _removeButton, _exportButton, _previousButton, _nextButton ]];
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.spacing = 8.0;
    actions.translatesAutoresizingMaskIntoConstraints = NO;

    NSStackView *stack = [NSStackView stackViewWithViews:@[ scroll, actions, _statusLabel ]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 10.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [stack.topAnchor constraintEqualToAnchor:self.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:self.bottomAnchor],
        [scroll.widthAnchor constraintEqualToAnchor:stack.widthAnchor],
    ]];
    // 按钮的初始状态不依赖装载:没有选中行就不该能改能删,哪怕列表还没读过。
    [self updateButtons];
    // 这里不查库:设置窗口一次把所有页都建出来,在构造里读词库等于把一次磁盘 IO 加到「打开设置」上。
    // 列表由控制器在切到这一页时装载,顺带解决了另一个问题 —— 窗口是常驻的,不重新读的话,打字新造
    // 的词在已经开过一次的设置窗里永远看不到。
    return self;
}

- (void)reload
{
    NSError *error = nil;
    BOOL hasMore = NO;
    NSArray<MetasequoiaPersonalDictionaryEntry *> *entries =
        [MetasequoiaPersonalDictionaryStore entriesAtOffset:_offset limit:kPageSize hasMore:&hasMore error:&error];
    if (entries == nil)
    {
        _entries = @[];
        _hasMore = NO;
        _statusLabel.stringValue = @"读取用户词库失败。";
        _statusLabel.textColor = [NSColor systemRedColor];
        _statusLabel.toolTip = error.localizedDescription;
    }
    else
    {
        _entries = entries;
        _hasMore = hasMore;
        _statusLabel.textColor = [NSColor secondaryLabelColor];
        _statusLabel.toolTip = nil;
        if (entries.count == 0 && _offset == 0)
        {
            _statusLabel.stringValue = @"还没有用户词条。打字时新造的词，以及在这里新增的词，都会出现在这份列表里。";
        }
        else
        {
            _statusLabel.stringValue =
                [NSString stringWithFormat:@"第 %lu–%lu 条%@", (unsigned long)(_offset + 1),
                                           (unsigned long)(_offset + entries.count), hasMore ? @"，还有更多" : @""];
        }
    }
    [_table reloadData];
    [self updateButtons];
}

- (void)updateButtons
{
    const BOOL hasSelection = _table.selectedRow >= 0 && _table.selectedRow < (NSInteger)_entries.count;
    _editButton.enabled = hasSelection;
    _removeButton.enabled = hasSelection;
    _previousButton.enabled = _offset > 0;
    _nextButton.enabled = _hasMore;
}

- (nullable MetasequoiaPersonalDictionaryEntry *)selectedEntry
{
    const NSInteger row = _table.selectedRow;
    return row >= 0 && row < (NSInteger)_entries.count ? _entries[row] : nil;
}

#pragma mark - 表格

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    (void)tableView;
    return (NSInteger)_entries.count;
}

- (nullable NSView *)tableView:(NSTableView *)tableView
            viewForTableColumn:(nullable NSTableColumn *)tableColumn
                           row:(NSInteger)row
{
    (void)tableView;
    if (row < 0 || row >= (NSInteger)_entries.count || tableColumn == nil)
    {
        return nil;
    }
    MetasequoiaPersonalDictionaryEntry *entry = _entries[row];
    NSString *text = @"";
    if ([tableColumn.identifier isEqualToString:@"kind"])
    {
        text = MetasequoiaPersonalDictionaryKindTitle(entry.kind);
    }
    else if ([tableColumn.identifier isEqualToString:@"key"])
    {
        text = entry.key;
    }
    else if ([tableColumn.identifier isEqualToString:@"value"])
    {
        text = entry.value;
    }
    else if ([tableColumn.identifier isEqualToString:@"weight"])
    {
        text = [NSString stringWithFormat:@"%lld", entry.weight];
    }
    NSTextField *cell = [NSTextField labelWithString:text];
    cell.lineBreakMode = NSLineBreakByTruncatingTail;
    return cell;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    (void)notification;
    [self updateButtons];
}

#pragma mark - 翻页

- (void)showPreviousPage:(id)sender
{
    (void)sender;
    _offset = _offset > kPageSize ? _offset - kPageSize : 0;
    [self reload];
}

- (void)showNextPage:(id)sender
{
    (void)sender;
    if (!_hasMore)
    {
        return;
    }
    _offset += kPageSize;
    [self reload];
}

#pragma mark - 编辑

// 加词和改词共用一张表单。引擎对每一类的编码写法要求不同,所以类别一变,提示也跟着变。
- (void)presentEditorForEntry:(nullable MetasequoiaPersonalDictionaryEntry *)existing
{
    NSWindow *host = self.window;
    if (host == nil)
    {
        return;
    }
    _editorKindButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    for (NSInteger kind = MetasequoiaPersonalDictionaryKindPinyin; kind <= MetasequoiaPersonalDictionaryKindEnglish;
         ++kind)
    {
        [_editorKindButton
            addItemWithTitle:MetasequoiaPersonalDictionaryKindTitle((MetasequoiaPersonalDictionaryKind)kind)];
    }
    _editorKindButton.translatesAutoresizingMaskIntoConstraints = NO;
    _editorKindButton.accessibilityLabel = @"词条类别";
    _editorKindButton.target = self;
    _editorKindButton.action = @selector(editorKindChanged:);
    [_editorKindButton.widthAnchor constraintEqualToConstant:260.0].active = YES;
    _editorKeyField = FieldWithPlaceholder(@"");
    _editorKeyField.accessibilityLabel = @"词条编码";
    NSTextField *valueField = FieldWithPlaceholder(@"上屏的内容");
    valueField.accessibilityLabel = @"词条内容";
    _editorHintLabel = [NSTextField labelWithString:@""];
    _editorHintLabel.font = [NSFont systemFontOfSize:NSFont.smallSystemFontSize];
    _editorHintLabel.textColor = [NSColor secondaryLabelColor];
    _editorHintLabel.translatesAutoresizingMaskIntoConstraints = NO;

    if (existing != nil)
    {
        [_editorKindButton selectItemAtIndex:existing.kind];
        _editorKeyField.stringValue = existing.key;
        valueField.stringValue = existing.value;
    }
    [self editorKindChanged:_editorKindButton];

    NSGridView *grid = [NSGridView gridViewWithViews:@[
        @[ EditorLabel(@"类别"), _editorKindButton ], @[ EditorLabel(@"编码"), _editorKeyField ],
        @[ [NSGridCell emptyContentView], _editorHintLabel ], @[ EditorLabel(@"词条"), valueField ]
    ]];
    grid.rowSpacing = 8.0;
    grid.columnSpacing = 10.0;
    [grid layoutSubtreeIfNeeded];
    grid.frame = NSMakeRect(0.0, 0.0, grid.fittingSize.width, grid.fittingSize.height);

    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = existing != nil ? @"编辑词条" : @"新增词条";
    alert.informativeText = @"编码是打字时输入的内容，词条是上屏的内容。";
    alert.accessoryView = grid;
    [alert addButtonWithTitle:existing != nil ? @"保存" : @"添加"];
    [alert addButtonWithTitle:@"取消"];
    [alert beginSheetModalForWindow:host
                  completionHandler:^(NSModalResponse response) {
                    if (response != NSAlertFirstButtonReturn)
                    {
                        return;
                    }
                    MetasequoiaPersonalDictionaryEntry *entry = [MetasequoiaPersonalDictionaryEntry
                        entryWithKind:(MetasequoiaPersonalDictionaryKind)self->_editorKindButton.indexOfSelectedItem
                                  key:self->_editorKeyField.stringValue
                                value:valueField.stringValue
                               weight:existing != nil ? existing.weight : 100000];
                    [self commitEntry:entry replacing:existing];
                  }];
}

- (void)editorKindChanged:(id)sender
{
    (void)sender;
    const MetasequoiaPersonalDictionaryKind kind =
        (MetasequoiaPersonalDictionaryKind)_editorKindButton.indexOfSelectedItem;
    NSString *hint = MetasequoiaPersonalDictionaryKindKeyHint(kind);
    _editorHintLabel.stringValue = hint;
    _editorKeyField.placeholderString = hint;
}

- (void)commitEntry:(MetasequoiaPersonalDictionaryEntry *)entry
          replacing:(nullable MetasequoiaPersonalDictionaryEntry *)existing
{
    NSError *error = nil;
    if (![MetasequoiaPersonalDictionaryStore validateEntry:entry error:&error])
    {
        [self reportFailure:@"这条词条不符合词库的格式要求。" error:error];
        return;
    }
    // 写库前先让输入会话停下来:引擎的候选和查询缓存是按会话建的,不重建就会继续答出旧结果。
    [self quiesceInputSessions];
    const BOOL written = existing != nil
                             ? [MetasequoiaPersonalDictionaryStore replaceEntry:existing withEntry:entry error:&error]
                             : [MetasequoiaPersonalDictionaryStore addEntry:entry error:&error];
    if (!written)
    {
        [self reportFailure:existing != nil ? @"词条未能保存。" : @"词条未能添加。" error:error];
        return;
    }
    [self reload];
}

- (void)addEntry:(id)sender
{
    (void)sender;
    [self presentEditorForEntry:nil];
}

- (void)editEntry:(id)sender
{
    (void)sender;
    MetasequoiaPersonalDictionaryEntry *entry = [self selectedEntry];
    if (entry != nil)
    {
        [self presentEditorForEntry:entry];
    }
}

- (void)removeEntry:(id)sender
{
    (void)sender;
    MetasequoiaPersonalDictionaryEntry *entry = [self selectedEntry];
    NSWindow *host = self.window;
    if (entry == nil || host == nil)
    {
        return;
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.alertStyle = NSAlertStyleWarning;
    alert.messageText = [NSString stringWithFormat:@"删除「%@」？", entry.value];
    alert.informativeText = @"这条词条会从用户词库里移除，无法撤销。打字时重新造出同一个词会再次被记住。";
    [alert addButtonWithTitle:@"取消"];
    [alert addButtonWithTitle:@"删除"];
    alert.buttons[0].keyEquivalent = @"\r";
    alert.buttons[1].keyEquivalent = @"";
    alert.buttons[1].hasDestructiveAction = YES;
    [alert beginSheetModalForWindow:host
                  completionHandler:^(NSModalResponse response) {
                    if (response != NSAlertSecondButtonReturn)
                    {
                        return;
                    }
                    [self quiesceInputSessions];
                    NSError *error = nil;
                    if (![MetasequoiaPersonalDictionaryStore removeEntry:entry error:&error])
                    {
                        [self reportFailure:@"词条未能删除。" error:error];
                        return;
                    }
                    [self reload];
                  }];
}

#pragma mark - 导出

- (void)exportEntries:(id)sender
{
    (void)sender;
    NSWindow *host = self.window;
    if (host == nil)
    {
        return;
    }
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = @"水杉用户词库.txt";
    panel.allowedContentTypes = @[ UTTypePlainText ];
    [panel beginSheetModalForWindow:host
                  completionHandler:^(NSModalResponse response) {
                    if (response != NSModalResponseOK || panel.URL == nil)
                    {
                        return;
                    }
                    [self writeExportTo:panel.URL];
                  }];
}

- (void)writeExportTo:(NSURL *)destination
{
    NSMutableString *text = [NSMutableString stringWithString:@"# 类别\t编码\t词条\t权重\n"];
    NSUInteger offset = 0;
    BOOL hasMore = YES;
    while (hasMore)
    {
        NSError *error = nil;
        NSArray<MetasequoiaPersonalDictionaryEntry *> *page =
            [MetasequoiaPersonalDictionaryStore entriesAtOffset:offset limit:1000 hasMore:&hasMore error:&error];
        if (page == nil)
        {
            [self reportFailure:@"读取用户词库失败，导出未完成。" error:error];
            return;
        }
        for (MetasequoiaPersonalDictionaryEntry *entry in page)
        {
            [text appendFormat:@"%@\t%@\t%@\t%lld\n", MetasequoiaPersonalDictionaryKindTitle(entry.kind), entry.key,
                               entry.value, entry.weight];
        }
        if (page.count == 0)
        {
            break;
        }
        offset += page.count;
    }
    NSError *error = nil;
    if (![text writeToURL:destination atomically:YES encoding:NSUTF8StringEncoding error:&error])
    {
        [self reportFailure:@"导出文件未能写入。" error:error];
        return;
    }
    _statusLabel.stringValue = [NSString stringWithFormat:@"已导出到 %@", destination.lastPathComponent];
    _statusLabel.textColor = [NSColor systemGreenColor];
    _statusLabel.toolTip = nil;
}

#pragma mark - 杂项

- (void)quiesceInputSessions
{
    // 设置窗通常和输入法在同一个进程(输入菜单开的那条路),但 open-settings.sh 会另起一个进程,那时
    // 本地通知到不了正在打字的那个实例,所以两个通知中心都发。
    [NSNotificationCenter.defaultCenter postNotificationName:MetasequoiaWillResetLearnedDataNotification object:nil];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:MetasequoiaWillResetLearnedDataNotification
                                                                 object:nil
                                                               userInfo:nil
                                                     deliverImmediately:YES];
}

- (void)reportFailure:(NSString *)message error:(nullable NSError *)error
{
    _statusLabel.stringValue = message;
    _statusLabel.textColor = [NSColor systemRedColor];
    // 引擎给的理由是英文一句话,放进 tooltip 而不是丢掉 —— 「不符合格式」不告诉人哪里不符合等于没说。
    _statusLabel.toolTip = error.localizedDescription;
}

@end
