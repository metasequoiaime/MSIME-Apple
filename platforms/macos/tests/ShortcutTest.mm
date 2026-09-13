#import "../InputController.mm"
#import "../InputSourceRegistration.h"
#import "../SkinSettingsView.h"
#include <cassert>
#include <fstream>
#include <sqlite3.h>
#import <objc/runtime.h>

static NSUInteger missingKeyFontCalls;
static IMP originalMonospacedFont;
static NSFont *MissingKeyFont(id cls, SEL selector, CGFloat size, NSFontWeight weight) {
    if (size == 11.0 && weight == NSFontWeightBold) {
        ++missingKeyFontCalls;
        return nil;
    }
    return ((NSFont *(*)(id, SEL, CGFloat, NSFontWeight))originalMonospacedFont)(cls, selector, size, weight);
}

static NSControl *PreferenceControl(MSIMEAppearancePreferences *preferences, SEL action) {
    NSScrollView *scroll = (id)preferences.window.contentView.subviews.firstObject;
    assert([scroll isKindOfClass:NSScrollView.class]);
    NSGridView *grid = (id)scroll.documentView;
    for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
        NSView *view = [grid cellAtColumnIndex:1 rowIndex:row].contentView;
        if ([view isKindOfClass:NSControl.class] && [(NSControl *)view action] == action) return (id)view;
    }
    assert(false && "Missing preference action");
    return nil;
}

static void CheckMenu(NSMenu *menu, id controller) {
    NSArray<NSString *> *actions = @[
        @"selectChineseMode:", @"selectEnglishMode:", @"toggleDedicatedEnglishMode:", @"",
        @"selectSimplifiedOutput:", @"selectTraditionalOutput:", @"",
        @"openCharacterPalette:", @"showEmoji:", @"showScreenKeyboard:",
        @"showAppearance:", @"showDictionary:", @"showAccount:",
        @"showCloudClipboard:", @"showHandwriting:", @"prepareDictionary:", @"",
        @"checkForUpdates:", @"openWebsite:", @"showHelp:", @"showAbout:", @"showFeedback:", @"toggleVoiceInput:", @"showVoiceSettings:"
    ];
    assert(menu.numberOfItems == (NSInteger)actions.count && !menu.autoenablesItems);
    for (NSUInteger index = 0; index < actions.count; ++index) {
        NSMenuItem *item = [menu itemAtIndex:index];
        if (actions[index].length == 0) assert(item.separatorItem);
        else {
            assert(item.action == NSSelectorFromString(actions[index]));
            assert(item.target == controller && [controller respondsToSelector:item.action]);
        }
    }
}

@interface ShortcutSession : NSObject
@property(nonatomic) uint32_t lastCommand;
@property(nonatomic) NSUInteger edgeCalls;
@property(nonatomic) uint8_t lastEdge;
@property(nonatomic) uint64_t edgeGeneration;
@property(nonatomic) NSUInteger edgeIndex;
@property(nonatomic) NSUInteger selectCalls;
@property(nonatomic) uint64_t selectedGeneration;
@property(nonatomic) NSUInteger selectedIndex;
@property(nonatomic) NSUInteger maintenanceCalls;
@property(nonatomic) NSInteger maintenanceAction;
@property(nonatomic) NSUInteger englishCandidateCalls;
@property(nonatomic) BOOL dedicatedEnglish;
@property(nonatomic, copy) NSDictionary *nextTransition;
@property(nonatomic) NSUInteger asciiCalls;
@property(nonatomic) uint8_t lastASCII;
@property(nonatomic) BOOL lastShift;
@property(nonatomic) uint8_t requestedPageSize;
@property(nonatomic) BOOL failFinish;
@property(nonatomic) NSUInteger focusCalls;
@property(nonatomic) BOOL chinesePunctuation;
@property(nonatomic) NSUInteger punctuationCalls;
@property(nonatomic, copy) NSDictionary *punctuationView;
@property(nonatomic) BOOL fullwidth;
@property(nonatomic) NSUInteger widthCalls;
@property(nonatomic, copy) NSDictionary *finishTransition;
@end
@implementation ShortcutSession
- (NSDictionary *)translationQueryWithError:(NSError **)error { (void)error; return nil; }
- (NSDictionary *)onlineQueryWithError:(NSError **)error { (void)error; return nil; }
- (NSDictionary *)setCharacterWidthFull:(BOOL)fullwidth error:(NSError **)error {
    (void)error; self.fullwidth = fullwidth; ++self.widthCalls; return nil;
}
- (NSDictionary *)viewWithError:(NSError **)error {
    (void)error;
    return @{@"focused":@NO, @"editing_text":@"", @"candidates":@[], @"dedicated_english":@(self.dedicatedEnglish)};
}
- (NSDictionary *)setDedicatedEnglishEnabled:(BOOL)enabled error:(NSError **)error {
    (void)error; ++self.englishCandidateCalls; self.dedicatedEnglish = enabled;
    return @{@"focused":@YES, @"editing_text":@"", @"preedit":@"", @"candidates":@[], @"dedicated_english":@(enabled)};
}
- (NSDictionary *)pinGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error {
    (void)error; ++self.maintenanceCalls; self.maintenanceAction = 0; self.selectedGeneration = generation; self.selectedIndex = index; return nil;
}
- (NSDictionary *)removeGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error {
    (void)error; ++self.maintenanceCalls; self.maintenanceAction = 1; self.selectedGeneration = generation; self.selectedIndex = index; return nil;
}
- (NSDictionary *)clearPositionGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error {
    (void)error; ++self.maintenanceCalls; self.maintenanceAction = 2; self.selectedGeneration = generation; self.selectedIndex = index; return nil;
}
- (NSDictionary *)fixGeneration:(uint64_t)generation index:(NSUInteger)index position:(uint8_t)position error:(NSError **)error {
    (void)error; ++self.maintenanceCalls; self.maintenanceAction = 10 + position; self.selectedGeneration = generation; self.selectedIndex = index; return nil;
}
- (NSDictionary *)selectGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error {
    (void)error; ++self.selectCalls; self.selectedGeneration = generation; self.selectedIndex = index;
    return nil;
}
- (NSDictionary *)selectEdgeGeneration:(uint64_t)generation index:(NSUInteger)index edge:(uint8_t)edge error:(NSError **)error {
    (void)error; ++self.edgeCalls; self.lastEdge = edge; self.edgeGeneration = generation; self.edgeIndex = index;
    return self.nextTransition;
}
- (NSDictionary *)setChinesePunctuationEnabled:(BOOL)enabled error:(NSError **)error {
    (void)error;
    self.chinesePunctuation = enabled;
    ++self.punctuationCalls;
    return self.punctuationView;
}
- (NSDictionary *)setFocused:(BOOL)focused error:(NSError **)error {
    (void)error;
    ++self.focusCalls;
    return @{@"handled": @NO, @"commit": NSNull.null, @"view": @{@"focused": @(focused), @"editing_text": @"", @"candidates": @[]}};
}
- (NSDictionary *)setCandidatePageSize:(uint8_t)size error:(NSError **)error {
    (void)error;
    self.requestedPageSize = size;
    return nil;
}
- (NSDictionary *)typeASCII:(uint8_t)ascii shift:(BOOL)shift error:(NSError **)error {
    (void)error;
    ++self.asciiCalls;
    self.lastASCII = ascii;
    self.lastShift = shift;
    return self.nextTransition;
}
- (NSDictionary *)command:(uint32_t)command error:(NSError **)error {
    (void)error;
    self.lastCommand = command;
    if (self.failFinish && command == MSIME_FINISH_COMPOSITION) return nil;
    if (self.finishTransition && command == MSIME_FINISH_COMPOSITION) return self.finishTransition;
    if (self.nextTransition) return self.nextTransition;
    return @{@"handled": @YES, @"commit": @"测试", @"view": @{@"editing_text": @"", @"caret_position": @0, @"candidates": @[]}};
}
@end

@interface ShortcutClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@property(nonatomic) NSRect caret;
@property(nonatomic, strong) NSMutableArray<NSString *> *insertions;
@end
@implementation ShortcutClient
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect {
    (void)index;
    *rect = self.caret;
    return @{};
}
- (void)insertText:(id)text replacementRange:(NSRange)range {
    (void)range;
    self.committed = text;
    [self.insertions addObject:text];
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)range {
    (void)selection;
    (void)range;
    self.marked = text;
}
@end

@interface TestCandidatePanel : NSObject
@property(nonatomic, getter=isVisible) BOOL visible;
@end
@implementation TestCandidatePanel
- (void)orderOut:(id)sender { (void)sender; self.visible = NO; }
@end

@interface HiddenCandidatePanel : MSIMECandidatePanel
@property(nonatomic) BOOL requestedVisible;
@end
@implementation HiddenCandidatePanel
- (BOOL)isVisible { return self.requestedVisible; }
- (void)orderFrontRegardless { self.requestedVisible = YES; }
- (void)orderOut:(id)sender { (void)sender; self.requestedVisible = NO; }
@end

@interface ModeController : MSIMEInputController
@property(nonatomic) NSUInteger preparationCalls;
@property(nonatomic) NSUInteger paletteCalls;
@end
@implementation ModeController
- (void)prepareSession {
    ++self.preparationCalls;
    if ([self valueForKey:@"session"]) [super prepareSession];
}
- (void)showSystemCharacterPalette { ++self.paletteCalls; }
@end

static NSEvent *ModeKey(unsigned short code, NSEventModifierFlags flags, BOOL repeat) {
    return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:code == 49 ? @" " : @"a" charactersIgnoringModifiers:code == 49 ? @" " : @"a" isARepeat:repeat keyCode:code];
}

@interface HiddenKeymapPanel : MSIMEShuangpinKeymapPanel
@property(nonatomic) BOOL requestedVisible;
@property(nonatomic) CGFloat clearance;
@end
@implementation HiddenKeymapPanel
- (void)showNearCaretRect:(NSRect)rect candidateClearance:(CGFloat)clearance {
    (void)rect; self.requestedVisible = YES; self.clearance = clearance;
}
- (void)orderOut:(id)sender { (void)sender; self.requestedVisible = NO; }
@end

@interface SuccessfulPageSession : ShortcutSession
@property(nonatomic) NSUInteger pageSizeCalls;
@end
@implementation SuccessfulPageSession
- (NSDictionary *)setCandidatePageSize:(uint8_t)size error:(NSError **)error {
    (void)error;
    self.requestedPageSize = size;
    ++self.pageSizeCalls;
    return @{@"view": @{@"editing_text": @"", @"candidates": @[]}};
}
@end

static void TestPageSizeCache() {
    NSString *suite = [@"msime.page-cache." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    ModeController *controller = [ModeController alloc];
    SuccessfulPageSession *session = [SuccessfulPageSession new];
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:session forKey:@"session"];
    [controller syncPageSize];
    [controller syncPageSize];
    assert(session.pageSizeCalls == 1 && session.requestedPageSize == 9);
    [controller applySharedToolbarPreferences:@{@"candidate_page_size": @5}];
    // The shared snapshot changed Engine independently; a local return to 9
    // must not be skipped just because the last direct request was also 9.
    prefs.pageSize = 9;
    [controller syncPageSize];
    assert(session.pageSizeCalls == 2 && session.requestedPageSize == 9);
    [controller applySharedToolbarPreferences:@{@"candidate_page_size": @9}];
    [controller syncPageSize];
    assert(session.pageSizeCalls == 2);
    ShortcutClient *client = [ShortcutClient new];
    client.marked = @"synthetic";
    [controller setValue:client forKey:@"activeClient"];
    HiddenKeymapPanel *keymap = [[HiddenKeymapPanel alloc] init];
    keymap.requestedVisible = YES;
    [controller setValue:keymap forKey:@"keymapPanel"];
    HiddenCandidatePanel *panel = [[HiddenCandidatePanel alloc] init];
    panel.requestedVisible = YES;
    [controller setValue:panel forKey:@"panel"];
    [controller snapshotSessionReplaced:[NSNotification notificationWithName:@"synthetic" object:[NSObject new]]];
    [controller syncPageSize];
    assert(session.pageSizeCalls == 2 && [client.marked isEqual:@"synthetic"] && keymap.requestedVisible && panel.requestedVisible);
    session.dedicatedEnglish = YES;
    [controller snapshotSessionReplaced:[NSNotification notificationWithName:@"synthetic" object:session]];
    assert([[[controller valueForKey:@"view"] objectForKey:@"dedicated_english"] isEqual:@YES]);
    assert(client.marked.length == 0 && client.committed == nil && !keymap.requestedVisible && !panel.requestedVisible);
    assert([[controller valueForKey:@"focusPending"] boolValue]);
    [controller syncPageSize];
    assert(session.pageSizeCalls == 3 && session.requestedPageSize == 9);
    [controller prepareSession];
    assert(session.focusCalls == 1 && ![[controller valueForKey:@"focusPending"] boolValue]);
    [defaults removePersistentDomainForName:suite];
}

static void TestSharedPunctuation() {
    NSString *suite = [@"msime.punctuation." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    ModeController *controller = [ModeController alloc];
    MSIMEFloatingToolbarPanel *toolbar = [[MSIMEFloatingToolbarPanel alloc] init];
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:toolbar forKey:@"toolbar"];
    NSButton *toggle = (id)PreferenceControl(prefs, @selector(punctuationChanged:));
    NSButton *toolbarToggle = [toolbar valueForKey:@"punctuationButton"];
    __block NSUInteger saves = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    for (NSNumber *enabled in @[@NO, @YES, @NO]) {
        [controller applySharedToolbarPreferences:@{@"chinese_punctuation": enabled}];
        assert(prefs.chinesePunctuation == enabled.boolValue && toggle.state == (enabled.boolValue ? NSControlStateValueOn : NSControlStateValueOff));
        assert([toolbarToggle.title isEqual:enabled.boolValue ? @"。" : @"."]);
        assert([toolbarToggle.accessibilityLabel isEqual:enabled.boolValue ? @"切换到西文标点" : @"切换到中文标点"]);
        assert([[prefs sharedPreferencesByMerging:@{}][@"chinese_punctuation"] isEqual:enabled] && saves == 0);
    }
    assert([defaults objectForKey:@"MSIMEClientChinesePunctuation"] == nil);
    for (id invalid in @[NSNull.null, @1, @"true"]) {
        [controller applySharedToolbarPreferences:@{@"chinese_punctuation": invalid}];
        assert(!prefs.chinesePunctuation && [toolbarToggle.title isEqual:@"."] && saves == 0);
    }
    [controller floatingToolbarDidRequestTogglePunctuation:toolbar];
    assert(prefs.chinesePunctuation && toggle.state == NSControlStateValueOn && [toolbarToggle.title isEqual:@"。"] && saves == 1);
    MSIMEAppearancePreferences *reopened = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(reopened.chinesePunctuation);
    [controller applySharedToolbarPreferences:@{@"chinese_punctuation": @NO}];
    assert(!prefs.chinesePunctuation && saves == 1);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [defaults removePersistentDomainForName:suite];
}

static void TestSharedTraditionalOutput() {
    NSString *suite = [@"msime.traditional." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    ModeController *controller = [ModeController alloc];
    MSIMEFloatingToolbarPanel *toolbar = [[MSIMEFloatingToolbarPanel alloc] init];
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:toolbar forKey:@"toolbar"];
    NSButton *toggle = [toolbar valueForKey:@"traditionalOutputButton"];
    __block NSUInteger saves = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    assert(!prefs.traditionalOutput);
    assert(![prefs sharedPreferencesByMerging:@{}][@"traditional_chinese_output"]);
    assert([[prefs sharedPreferencesByMerging:@{@"traditional_chinese_output":@YES}][@"traditional_chinese_output"] isEqual:@YES]);
    for (NSNumber *enabled in @[@YES, @NO, @YES]) {
        [controller applySharedToolbarPreferences:@{@"traditional_chinese_output":enabled}];
        assert(prefs.traditionalOutput == enabled.boolValue && saves == 0);
        assert([toggle.title isEqual:enabled.boolValue ? @"繁" : @"简"]);
        assert([controller.menu itemAtIndex:enabled.boolValue ? 5 : 4].state == NSControlStateValueOn);
        assert([[prefs cloudSettingsSnapshot][@"platform.macos.traditional_chinese_output"] isEqual:enabled]);
    }
    assert([defaults objectForKey:@"MSIMEClientTraditionalOutput"] == nil);
    for (id invalid in @[NSNull.null, @1, @"true"]) {
        [controller applySharedToolbarPreferences:@{@"traditional_chinese_output":invalid}];
        assert(prefs.traditionalOutput && saves == 0);
    }
    [controller selectSimplifiedOutput:nil];
    assert(!prefs.traditionalOutput && saves == 1);
    assert([[prefs sharedPreferencesByMerging:@{}][@"traditional_chinese_output"] isEqual:@NO]);
    [controller applySharedToolbarPreferences:@{@"traditional_chinese_output":@YES}];
    assert(prefs.traditionalOutput && saves == 1);
    assert([[prefs sharedPreferencesByMerging:@{}][@"traditional_chinese_output"] isEqual:@YES]);
    NSMutableDictionary *cloud = [[prefs cloudSettingsSnapshot] mutableCopy];
    cloud[@"platform.macos.traditional_chinese_output"] = @NO;
    assert([prefs applyCloudSettingsSnapshot:cloud]);
    assert(!prefs.traditionalOutput && saves == 2);
    assert([[prefs sharedPreferencesByMerging:@{}][@"traditional_chinese_output"] isEqual:@NO]);
    [controller selectTraditionalOutput:nil];
    assert(prefs.traditionalOutput && saves == 3);
    assert([[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults] traditionalOutput]);

    // Persist through the actual shared store, then consume it with fresh local defaults.
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSError *error = nil;
    NSDictionary *snapshot = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(snapshot && !error);
    NSDictionary *saved = [MSIMEClientSession savePreferencesInDirectory:root expectedRevision:[snapshot[@"revision"] unsignedLongLongValue]
        snapshot:@{@"format_version":@1, @"revision":snapshot[@"revision"], @"preferences":[prefs sharedPreferencesByMerging:snapshot[@"preferences"]]} error:&error];
    assert(saved && !error);
    NSDictionary *loaded = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(loaded && !error && [loaded[@"preferences"][@"traditional_chinese_output"] isEqual:@YES]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [defaults removePersistentDomainForName:suite];
    MSIMEAppearancePreferences *fresh = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(!fresh.traditionalOutput);
    [fresh applySharedInputPreferences:loaded[@"preferences"]];
    assert(fresh.traditionalOutput);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
}

static void TestIndependentAssistancePreferences() {
    NSString *suite = [@"msime.assistance." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    [defaults setBool:NO forKey:@"MSIMEClientHelpcodeEnabled"];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(!prefs.quanpinHelpcodeEnabled && !prefs.shuangpinHelpcodeEnabled);
    ModeController *controller = [ModeController alloc];
    [controller setValue:prefs forKey:@"appearance"];
    NSButton *quanpin = (id)PreferenceControl(prefs, @selector(quanpinHelpcodeChanged:));
    NSButton *shuangpin = (id)PreferenceControl(prefs, @selector(shuangpinHelpcodeChanged:));
    NSButton *autocorrect = (id)PreferenceControl(prefs, @selector(transpositionChanged:));
    __block NSUInteger saves = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    NSDictionary *shared = @{@"autocorrect": @NO, @"quanpin_helpcode": @{@"enabled": @YES, @"auto_display": @NO}, @"shuangpin_helpcode": @{@"enabled": @NO, @"future_field": @7}};
    [controller applySharedToolbarPreferences:shared];
    assert(prefs.quanpinHelpcodeEnabled && !prefs.shuangpinHelpcodeEnabled && !prefs.autocorrect && saves == 0);
    assert(quanpin.state == NSControlStateValueOn && shuangpin.state == NSControlStateValueOff && autocorrect.state == NSControlStateValueOff);
    for (NSString *key in shared) assert([[prefs sharedPreferencesByMerging:shared][key] isEqual:shared[key]]);
    [controller applySharedToolbarPreferences:@{@"autocorrect": @1, @"quanpin_helpcode": @{@"enabled": @0}, @"shuangpin_helpcode": NSNull.null}];
    assert(prefs.quanpinHelpcodeEnabled && !prefs.shuangpinHelpcodeEnabled && !prefs.autocorrect && saves == 0);
    quanpin.state = NSControlStateValueOff;
    [NSApp sendAction:quanpin.action to:quanpin.target from:quanpin];
    assert(!prefs.quanpinHelpcodeEnabled && !prefs.shuangpinHelpcodeEnabled && saves == 1);
    shuangpin.state = NSControlStateValueOn;
    [NSApp sendAction:shuangpin.action to:shuangpin.target from:shuangpin];
    prefs.autocorrect = YES;
    assert(!prefs.quanpinHelpcodeEnabled && prefs.shuangpinHelpcodeEnabled && prefs.autocorrect && saves == 3);
    MSIMEAppearancePreferences *reopened = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(!reopened.quanpinHelpcodeEnabled && reopened.shuangpinHelpcodeEnabled && reopened.autocorrect);
    NSDictionary *edited = [prefs sharedPreferencesByMerging:shared];
    assert([edited[@"quanpin_helpcode"][@"enabled"] isEqual:@NO] && [edited[@"shuangpin_helpcode"][@"enabled"] isEqual:@YES]);
    assert([edited[@"quanpin_helpcode"][@"auto_display"] isEqual:@NO] && [edited[@"shuangpin_helpcode"][@"future_field"] isEqual:@7]);
    [controller applySharedToolbarPreferences:shared];
    assert(prefs.quanpinHelpcodeEnabled && !prefs.shuangpinHelpcodeEnabled && !prefs.autocorrect && saves == 3);
    NSScrollView *scroll = (id)prefs.window.contentView.subviews.firstObject;
    NSGridView *grid = (id)scroll.documentView;
    NSMutableDictionary *schemaControls = [NSMutableDictionary dictionary];
    NSMutableDictionary *displayControls = [NSMutableDictionary dictionary];
    for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
        NSControl *control = (id)[grid cellAtColumnIndex:1 rowIndex:row].contentView;
        if ([control isKindOfClass:NSControl.class] && control.action == @selector(helpcodeSchemaChanged:)) schemaControls[control.identifier] = control;
        if ([control isKindOfClass:NSControl.class] && control.action == @selector(helpcodeDisplayChanged:)) displayControls[control.identifier] = control;
    }
    assert(schemaControls.count == 2 && displayControls.count == 2);
    NSDictionary *options = @{@"quanpin_helpcode": @{@"schema": @"shouyou2_0", @"show_in_candidate_window": @NO}, @"shuangpin_helpcode": @{@"schema": @"xiaohe", @"show_in_candidate_window": @YES}};
    [prefs applySharedAssistancePreferences:options];
    assert(saves == 3 && [defaults objectForKey:@"MSIMEClientHelpcodeOptions"] == nil);
    assert([(NSPopUpButton *)schemaControls[@"quanpin"] indexOfSelectedItem] == 2);
    assert([(NSButton *)displayControls[@"quanpin"] state] == NSControlStateValueOff);
    for (NSString *scheme in @[@"quanpin", @"shuangpin"]) {
        NSPopUpButton *schemas = schemaControls[scheme];
        NSButton *display = displayControls[scheme];
        NSArray *identifiers = @[@"lantian", @"ziranma", @"shouyou2_0", @"shouyouplus", @"xiaohe"];
        assert(([schemas.itemTitles isEqual:@[@"蓝天小雨点", @"自然码", @"首右2.0", @"首右plus", @"小鹤"]]));
        for (NSUInteger index = 0; index < identifiers.count; ++index) {
            [schemas selectItemAtIndex:index];
            [NSApp sendAction:schemas.action to:schemas.target from:schemas];
            display.state = index % 2 ? NSControlStateValueOn : NSControlStateValueOff;
            [NSApp sendAction:display.action to:display.target from:display];
            NSDictionary *merged = [prefs sharedPreferencesByMerging:options][[scheme stringByAppendingString:@"_helpcode"]];
            assert([merged[@"schema"] isEqual:identifiers[index]] && [merged[@"show_in_candidate_window"] boolValue] == (index % 2 == 1));
            MSIMEAppearancePreferences *restored = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert([[restored helpcodeOptionsForScheme:scheme][@"schema"] isEqual:identifiers[index]]);
            assert([[restored helpcodeOptionsForScheme:scheme][@"show_in_candidate_window"] boolValue] == (index % 2 == 1));
        }
    }
    NSUInteger beforeRefresh = saves;
    [prefs applySharedAssistancePreferences:options];
    [prefs applySharedAssistancePreferences:@{@"quanpin_helpcode": @{@"schema": @"invalid", @"show_in_candidate_window": @1}}];
    assert(saves == beforeRefresh);
    assert([[prefs helpcodeOptionsForScheme:@"quanpin"] isEqual:options[@"quanpin_helpcode"]]);
    assert([[prefs helpcodeOptionsForScheme:@"shuangpin"] isEqual:options[@"shuangpin_helpcode"]]);
    NSButton *neighbor = (id)PreferenceControl(prefs, @selector(neighborChanged:));
    [prefs applySharedAssistancePreferences:@{@"autocorrect": @NO, @"quanpin": @{@"autocorrect_transposition": @YES, @"autocorrect_neighbor": @NO}}];
    assert(autocorrect.state == NSControlStateValueOn && neighbor.state == NSControlStateValueOff);
    assert(prefs.autocorrectTransposition && !prefs.autocorrectNeighbor);
    autocorrect.state = NSControlStateValueOff;
    [NSApp sendAction:autocorrect.action to:autocorrect.target from:autocorrect];
    neighbor.state = NSControlStateValueOn;
    [NSApp sendAction:neighbor.action to:neighbor.target from:neighbor];
    MSIMEAppearancePreferences *correctionRestored = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(!correctionRestored.autocorrectTransposition && correctionRestored.autocorrectNeighbor);
    NSDictionary *correctionMerged = [prefs sharedPreferencesByMerging:@{@"quanpin": @{@"future": @7}}][@"quanpin"];
    assert([correctionMerged[@"autocorrect_transposition"] isEqual:@NO] && [correctionMerged[@"autocorrect_neighbor"] isEqual:@YES] && [correctionMerged[@"future"] isEqual:@7]);
    NSUInteger beforeCorrectionRefresh = saves;
    [prefs applySharedAssistancePreferences:@{@"autocorrect": @NO, @"quanpin": @{}}];
    assert(!prefs.autocorrectTransposition && !prefs.autocorrectNeighbor && saves == beforeCorrectionRefresh);
    assert([prefs sharedPreferencesByMerging:@{}][@"quanpin"][@"autocorrect_neighbor"] == NSNull.null);
    [prefs applySharedAssistancePreferences:@{@"quanpin": @{@"autocorrect_neighbor": @1}}];
    assert(!prefs.autocorrectNeighbor);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [defaults removePersistentDomainForName:suite];
}

static void TestSharedInputPreferences() {
    NSString *suite = [@"msime.shared-input." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    prefs.inputScheme = @"quanpin";
    prefs.shuangpinProfile = @"xiaohe";
    prefs.shuangpinPreeditUsesRaw = YES;
    ModeController *controller = [ModeController alloc];
    [controller setValue:prefs forKey:@"appearance"];
    __block NSUInteger saves = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    NSDictionary *shared = @{@"scheme": @"shuangpin", @"shuangpin_profile": @"microsoft", @"shuangpin_preedit_uses_raw": @NO};
    [controller applySharedToolbarPreferences:shared];
    assert([prefs.inputScheme isEqual:@"shuangpin"] && [prefs.shuangpinProfile isEqual:@"microsoft"] && !prefs.shuangpinPreeditUsesRaw);
    NSPopUpButton *scheme = (id)PreferenceControl(prefs, @selector(schemeChanged:));
    NSPopUpButton *profile = (id)PreferenceControl(prefs, @selector(profileChanged:));
    NSPopUpButton *preedit = (id)PreferenceControl(prefs, @selector(preeditChanged:));
    assert(scheme.indexOfSelectedItem == 1 && profile.indexOfSelectedItem == 3 && preedit.indexOfSelectedItem == 0);
    assert(saves == 0);
    assert([[defaults stringForKey:@"MSIMEClientInputScheme"] isEqual:@"quanpin"]);
    for (NSString *key in shared) assert([[prefs sharedPreferencesByMerging:shared][key] isEqual:shared[key]]);
    [controller applySharedToolbarPreferences:@{@"scheme": NSNull.null, @"shuangpin_profile": @42, @"shuangpin_preedit_uses_raw": @1}];
    [controller applySharedToolbarPreferences:@{}];
    assert([prefs.inputScheme isEqual:@"shuangpin"] && [prefs.shuangpinProfile isEqual:@"microsoft"] && !prefs.shuangpinPreeditUsesRaw && saves == 0);
    [scheme selectItemAtIndex:2];
    [NSApp sendAction:scheme.action to:scheme.target from:scheme];
    [profile selectItemAtIndex:2];
    [NSApp sendAction:profile.action to:profile.target from:profile];
    [preedit selectItemAtIndex:1];
    [NSApp sendAction:preedit.action to:preedit.target from:preedit];
    NSDictionary *edited = [prefs sharedPreferencesByMerging:shared];
    assert([edited[@"scheme"] isEqual:@"wubi"] && [edited[@"shuangpin_profile"] isEqual:@"shoudao"] && [edited[@"shuangpin_preedit_uses_raw"] isEqual:@YES] && saves == 3);
    [controller applySharedToolbarPreferences:shared];
    assert(scheme.indexOfSelectedItem == 1 && profile.indexOfSelectedItem == 3 && preedit.indexOfSelectedItem == 0 && saves == 3);
    NSPopUpButton *layout = (id)PreferenceControl(prefs, @selector(layoutChanged:));
    NSPopUpButton *font = (id)PreferenceControl(prefs, @selector(fontChanged:));
    NSPopUpButton *page = (id)PreferenceControl(prefs, @selector(pageSizeChanged:));
    for (NSUInteger size = 12; size <= 32; ++size) {
        for (NSUInteger count = 1; count <= 9; ++count) {
            NSDictionary *candidate = @{@"candidate_layout": count % 2 ? @"vertical" : @"horizontal", @"candidate_font_size": @(size), @"candidate_page_size": @(count)};
            [controller applySharedToolbarPreferences:candidate];
            assert(prefs.vertical == (count % 2 == 1) && prefs.fontSize == size && prefs.pageSize == count);
            assert(layout.indexOfSelectedItem == (NSInteger)(count % 2) && font.indexOfSelectedItem == (NSInteger)size - 12 && page.indexOfSelectedItem == (NSInteger)count - 1);
            for (NSString *key in candidate) assert([[prefs sharedPreferencesByMerging:candidate][key] isEqual:candidate[key]]);
        }
    }
    assert(saves == 3 && [defaults objectForKey:@"MSIMEClientCandidateFontSize"] == nil);
    for (id invalid in @[NSNull.null, @YES, @0, @99, @1.5, @"18"]) {
        [controller applySharedToolbarPreferences:@{@"candidate_layout": invalid, @"candidate_font_size": invalid, @"candidate_page_size": invalid}];
        assert(prefs.vertical && prefs.fontSize == 32 && prefs.pageSize == 9 && saves == 3);
    }
    [layout selectItemAtIndex:0];
    [NSApp sendAction:layout.action to:layout.target from:layout];
    [font selectItemAtIndex:1];
    [NSApp sendAction:font.action to:font.target from:font];
    [page selectItemAtIndex:1];
    [NSApp sendAction:page.action to:page.target from:page];
    assert(!prefs.vertical && prefs.fontSize == 13 && prefs.pageSize == 2 && saves == 6);
    NSDictionary *candidateEdited = [prefs sharedPreferencesByMerging:@{}];
    assert([candidateEdited[@"candidate_layout"] isEqual:@"horizontal"] && [candidateEdited[@"candidate_font_size"] isEqual:@13] && [candidateEdited[@"candidate_page_size"] isEqual:@2]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [defaults removePersistentDomainForName:suite];
}

static void TestKeymap(NSUserDefaults *defaults, MSIMEAppearancePreferences *appearance) {
    NSPopUpButton *profiles = (id)PreferenceControl(appearance, @selector(profileChanged:));
    NSArray *identifiers = @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"];
    NSArray *titles = @[@"小鹤双拼", @"自然码双拼", @"首道双拼", @"微软双拼"];
    assert([profiles.itemTitles isEqual:titles]);
    for (NSUInteger index = 0; index < identifiers.count; ++index) {
        [profiles selectItemAtIndex:index];
        assert([NSApp sendAction:profiles.action to:profiles.target from:profiles]);
        assert([appearance.shuangpinProfile isEqual:identifiers[index]]);
        MSIMEAppearancePreferences *restored = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot];
        assert([restored.shuangpinProfile isEqual:identifiers[index]]);
        NSPopUpButton *restoredProfiles = (id)PreferenceControl(restored, @selector(profileChanged:));
        assert([restoredProfiles.titleOfSelectedItem isEqual:titles[index]]);
    }
    assert(!appearance.shuangpinKeymap);
    NSButton *toggle = (id)PreferenceControl(appearance, @selector(keymapChanged:));
    toggle.state = NSControlStateValueOn;
    [NSApp sendAction:toggle.action to:toggle.target from:toggle];
    assert(appearance.shuangpinKeymap);
    assert([[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] shuangpinKeymap]);
    HiddenKeymapPanel *panel = [[HiddenKeymapPanel alloc] init];
    assert(panel.ignoresMouseEvents && panel.floatingPanel);
    for (NSString *profile in @[@"xiaohe", @"ziranma", @"shoudao", @"microsoft"]) {
        NSArray *rows = MSIMEShuangpinKeymapRows(profile);
        assert(rows.count == 3 && [rows[0] count] == 10 && [rows[2] count] == 7);
        assert([rows[1] count] == ([profile isEqual:@"microsoft"] ? 10 : 9));
        [panel setProfileName:profile];
        [panel.contentView layoutSubtreeIfNeeded];
        assert([panel.contentView.accessibilityLabel containsString:@"键位提示"]);
        assert([MSIMEShuangpinZeroInitialText(profile) containsString:@"零声母"]);
        if ([profile isEqual:@"microsoft"]) {
            assert([rows[1][9][@"key"] isEqual:@";"]);
            assert([rows[1][9][@"codes"] containsString:@"ing"]);
        }
        [panel updateHighlightedKey:@"a"];
        assert([panel.contentView.accessibilityValue containsString:@"当前按键 A"]);
        for (NSAppearanceName theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            panel.contentView.appearance = [NSAppearance appearanceNamed:theme];
            NSBitmapImageRep *bitmap = [panel.contentView bitmapImageRepForCachingDisplayInRect:panel.contentView.bounds];
            assert(bitmap != nil);
            [panel.contentView cacheDisplayInRect:panel.contentView.bounds toBitmapImageRep:bitmap];
            assert(bitmap.pixelsWide >= 620 && bitmap.pixelsHigh >= 203);
            NSString *directory = NSProcessInfo.processInfo.environment[@"MSIME_KEYMAP_SNAPSHOT_DIR"];
            if (directory) {
                NSString *file = [directory stringByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.png", profile, theme]];
                assert([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:file atomically:YES]);
            }
        }
        [panel updateHighlightedKey:@""];
        assert(![panel.contentView.accessibilityValue containsString:@"当前按键"]);
    }
    NSRect frame = MSIMEShuangpinKeymapPanelFrame(NSMakeRect(30, 400, 1, 20), NSMakeSize(620, 203), 60, NSMakeRect(0, 0, 1000, 800));
    assert(frame.origin.x == 30 && frame.origin.y == 129);
    frame = MSIMEShuangpinKeymapPanelFrame(NSMakeRect(990, 20, 1, 20), NSMakeSize(620, 203), 60, NSMakeRect(0, 0, 1000, 800));
    assert(frame.origin.x == 364 && frame.origin.y == 108);
    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    client.caret = NSMakeRect(20, 400, 1, 20);
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:panel forKey:@"keymapPanel"];
    [controller setValue:[ShortcutSession new] forKey:@"session"];
    NSDictionary *view = @{@"scheme": @1, @"local_mode": @"none", @"dedicated_english": @NO, @"shuangpin_profile": @"microsoft", @"editing_text": @"b;", @"preedit": @"bing", @"candidates": @[]};
    [controller setValue:view forKey:@"view"];
    [controller updateKeymapPanel];
    assert(panel.requestedVisible && [panel.contentView.accessibilityValue containsString:@"当前按键 ;"]);
    assert(panel.clearance == (appearance.vertical ? 24 : appearance.fontSize + 42));
    NSMutableDictionary *withCandidates = [view mutableCopy];
    withCandidates[@"candidates"] = @[@{@"text": @"合成"}];
    [controller setValue:withCandidates forKey:@"view"];
    appearance.showsCandidatePreedit = NO;
    [controller updateKeymapPanel];
    CGFloat hiddenClearance = panel.clearance;
    appearance.showsCandidatePreedit = YES;
    [controller updateKeymapPanel];
    assert(panel.clearance > hiddenClearance);
    NSUInteger savedFontSize = appearance.fontSize;
    BOOL savedVertical = appearance.vertical;
    NSString *savedFamily = appearance.fontFamily;
    appearance.fontFamily = @"Helvetica";
    appearance.fontSize = 32;
    appearance.vertical = YES;
    appearance.showsCandidatePreedit = NO;
    [controller updateKeymapPanel];
    NSFont *clearanceFont = [appearance candidateFontOfSize:32];
    CGFloat measuredHeight = ceil([@"合成" sizeWithAttributes:@{NSFontAttributeName:clearanceFont}].height);
    assert(panel.clearance >= measuredHeight + 12 + 24);
    appearance.fontSize = savedFontSize;
    appearance.fontFamily = savedFamily;
    appearance.vertical = savedVertical;
    appearance.showsCandidatePreedit = YES;
    for (NSString *display in @[@"b;", @"bing", @""]) {
        NSMutableDictionary *next = [view mutableCopy];
        next[@"preedit"] = display;
        [controller setValue:next forKey:@"view"];
        [controller updateKeymapPanel];
        assert(panel.requestedVisible && [panel.contentView.accessibilityValue containsString:@"当前按键 ;"]);
    }
    for (id mode in @[@"unicode", @"date_time", @"quick_phrase", @"emoji", @"kaomoji", @"super_jianpin", @"temporary_english", @"temporary_japanese", @"unknown", @"", NSNull.null, @1]) {
        NSMutableDictionary *next = [view mutableCopy];
        next[@"local_mode"] = mode;
        [controller setValue:next forKey:@"view"];
        [controller updateKeymapPanel];
        assert(!panel.requestedVisible);
        [controller setValue:view forKey:@"view"];
        [controller updateKeymapPanel];
        assert(panel.requestedVisible && [panel.contentView.accessibilityValue containsString:@"当前按键 ;"]);
    }
    NSMutableDictionary *missingMode = [view mutableCopy];
    missingMode[@"dedicated_english"] = @YES;
    [controller setValue:missingMode forKey:@"view"];
    [controller updateKeymapPanel];
    assert(!panel.requestedVisible);
    [controller setValue:view forKey:@"view"];
    [controller updateKeymapPanel];
    assert(panel.requestedVisible);
    missingMode[@"dedicated_english"] = @NO;
    [missingMode removeObjectForKey:@"local_mode"];
    [controller setValue:missingMode forKey:@"view"];
    [controller updateKeymapPanel];
    assert(!panel.requestedVisible);
    for (NSDictionary *excluded in @[@{}, @{@"scheme": @0}, @{@"scheme": @3}, @{@"editing_text": @""}, @{@"editing_text": NSNull.null}, @{@"editing_text": @42}, @{@"shuangpin_profile": @""}]) {
        NSMutableDictionary *next = [view mutableCopy];
        [next addEntriesFromDictionary:excluded];
        if (!excluded.count) [next removeObjectForKey:@"scheme"];
        [controller setValue:next forKey:@"view"];
        [controller updateKeymapPanel];
        assert(!panel.requestedVisible);
    }
    [controller setValue:view forKey:@"view"];
    client.caret = NSZeroRect;
    [controller updateKeymapPanel];
    assert(!panel.requestedVisible);
    client.caret = NSMakeRect(20, 400, 1, 20);
    appearance.englishMode = YES;
    [controller updateKeymapPanel];
    assert(!panel.requestedVisible);
    appearance.englishMode = NO;
    appearance.shuangpinKeymap = NO;
    [controller updateKeymapPanel];
    assert(!panel.requestedVisible && toggle.state == NSControlStateValueOff);
}

static void TestPunctuation(NSUserDefaults *defaults, MSIMEAppearancePreferences *appearance) {
    assert(appearance.chinesePunctuation);
    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    [controller setValue:@{@"editing_text": @"test", @"candidates": @[]} forKey:@"view"];
    const BOOL english = appearance.englishMode;
    const BOOL fullWidth = appearance.fullWidthInput;
    const BOOL traditional = appearance.traditionalOutput;
    session.failFinish = YES;
    [controller floatingToolbarDidRequestTogglePunctuation:nil];
    assert(appearance.chinesePunctuation && session.punctuationCalls == 0);
    session.failFinish = NO;
    [controller floatingToolbarDidRequestTogglePunctuation:nil];
    assert(session.lastCommand == MSIME_FINISH_COMPOSITION);
    assert([client.committed isEqual:@"测试"]);
    assert(!appearance.chinesePunctuation && !session.chinesePunctuation);
    assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] chinesePunctuation]);
    session.chinesePunctuation = YES;
    [controller prepareSession];
    assert(!session.chinesePunctuation);
    assert(appearance.englishMode == english && appearance.fullWidthInput == fullWidth && appearance.traditionalOutput == traditional);
    [controller floatingToolbarDidRequestTogglePunctuation:nil];
    assert(appearance.chinesePunctuation && session.chinesePunctuation);
    NSEvent *(^toggleEvent)(unsigned short, NSEventModifierFlags, BOOL) = ^NSEvent *(unsigned short key, NSEventModifierFlags flags, BOOL repeat) {
        return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags timestamp:0 windowNumber:0 context:nil characters:@"." charactersIgnoringModifiers:@"." isARepeat:repeat keyCode:key];
    };
    NSEvent *toggle = toggleEvent(47, NSEventModifierFlagControl, NO);
    [controller setValue:@{@"editing_text":@"test", @"candidates":@[]} forKey:@"view"];
    session.failFinish = YES;
    NSUInteger calls = session.punctuationCalls;
    assert([controller handleEvent:toggle client:client]);
    assert(appearance.chinesePunctuation && session.punctuationCalls == calls);
    session.failFinish = NO;
    assert([controller handleEvent:toggle client:client]);
    assert(!appearance.chinesePunctuation && !session.chinesePunctuation && session.punctuationCalls > calls);
    assert(session.lastCommand == MSIME_FINISH_COMPOSITION && [client.committed isEqual:@"测试"]);
    assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] chinesePunctuation]);
    calls = session.punctuationCalls;
    assert([controller handleEvent:toggleEvent(47, NSEventModifierFlagControl, YES) client:client]);
    assert(!appearance.chinesePunctuation && session.punctuationCalls == calls);
    for (NSNumber *flags in @[@0, @(NSEventModifierFlagCommand), @(NSEventModifierFlagControl | NSEventModifierFlagShift), @(NSEventModifierFlagControl | NSEventModifierFlagOption), @(NSEventModifierFlagControl | NSEventModifierFlagCommand)])
        assert(!MSIMEPunctuationToggle(toggleEvent(47, flags.unsignedIntegerValue, NO)));
    assert(!MSIMEPunctuationToggle(toggleEvent(65, NSEventModifierFlagControl, NO))); // Keypad decimal.
    // The punctuation preference can be changed while English passthrough is active.
    appearance.englishMode = YES;
    assert([controller handleEvent:toggle client:client]);
    assert(appearance.englishMode && appearance.chinesePunctuation && session.chinesePunctuation);
    appearance.englishMode = english;
    assert(appearance.fullWidthInput == fullWidth && appearance.traditionalOutput == traditional);
    // The punctuation API returns a bare View, not {view: ...} like key input.
    NSDictionary *punctuationView = @{@"session":@9, @"generation":@4, @"focused":@YES,
        @"editing_text":@"nini", @"preedit":@"ni'ni", @"caret_position":@2,
        @"dedicated_english":@YES, @"candidates":@[]};
    session.punctuationView = punctuationView;
    NSString *previousCommit = client.committed;
    session.lastCommand = UINT32_MAX;
    [controller syncPunctuation];
    assert([[controller valueForKey:@"view"] isEqual:punctuationView]);
    assert([client.marked isEqual:@"ni'ni"] && [client.committed isEqual:previousCommit]);
    assert(session.lastCommand == UINT32_MAX);
    session.punctuationView = nil;
    [controller syncPunctuation];
    assert([[controller valueForKey:@"view"] isEqual:punctuationView]);
}

static void TestCharacterSetShortcut(NSUserDefaults *defaults, MSIMEAppearancePreferences *appearance) {
    assert(appearance.characterSetShortcut);
    NSDictionary *keys = @{@"toggle_character_set_ctrl_shift_f":@NO, @"switch_language_shift":@NO};
    assert([[appearance sharedPreferencesByMerging:@{@"keybindings":keys}][@"keybindings"] isEqual:keys]);
    assert(![appearance sharedPreferencesByMerging:@{}][@"keybindings"]);
    [appearance applySharedInputPreferences:@{@"keybindings":keys}];
    assert(!appearance.characterSetShortcut);
    [appearance applySharedInputPreferences:@{@"keybindings":@{@"toggle_character_set_ctrl_shift_f":@"invalid"}}];
    [appearance applySharedInputPreferences:@{@"keybindings":@"invalid"}];
    assert(!appearance.characterSetShortcut);
    NSButton *button = (id)PreferenceControl(appearance, NSSelectorFromString(@"characterSetShortcutChanged:"));
    assert(button.state == NSControlStateValueOff);
    button.state = NSControlStateValueOn;
    [NSApp sendAction:button.action to:button.target from:button];
    assert(appearance.characterSetShortcut);
    NSDictionary *merged = [appearance sharedPreferencesByMerging:@{@"keybindings":keys}];
    assert(([merged[@"keybindings"] isEqual:@{@"toggle_character_set_ctrl_shift_f":@YES, @"switch_language_shift":@NO}]));
    NSDictionary *patch = [appearance sharedPreferencesByMerging:@{}];
    assert([patch[@"keybindings"] isEqual:@{@"toggle_character_set_ctrl_shift_f":@YES}]);
    assert([MSIMEMergePreferenceSnapshot(@{@"keybindings":keys}, patch)[@"keybindings"] isEqual:merged[@"keybindings"]]);

    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    NSDictionary *view = @{@"editing_text":@"test", @"candidates":@[]};
    [controller setValue:view forKey:@"view"];
    const BOOL english = appearance.englishMode, traditional = appearance.traditionalOutput;
    const BOOL fullWidth = appearance.fullWidthInput, punctuation = appearance.chinesePunctuation;
    appearance.englishMode = NO;
    session.lastCommand = UINT32_MAX;
    NSEventModifierFlags flags = NSEventModifierFlagControl | NSEventModifierFlagShift;
    assert([controller handleEvent:ModeKey(3, flags, NO) client:client]);
    assert(appearance.traditionalOutput != traditional);
    assert([controller handleEvent:ModeKey(3, flags, YES) client:client]);
    assert(appearance.traditionalOutput != traditional);
    assert([[controller valueForKey:@"view"] isEqual:view]);
    assert(session.lastCommand == UINT32_MAX && client.committed == nil);
    assert([controller handleEvent:ModeKey(3, flags | NSEventModifierFlagCapsLock, NO) client:client]);
    assert(appearance.traditionalOutput == traditional);
    appearance.englishMode = YES;
    assert([controller handleEvent:ModeKey(3, flags, NO) client:client]);
    assert(appearance.traditionalOutput == traditional && appearance.englishMode);
    for (NSUInteger mask = 0; mask < 16; ++mask) {
        NSEventModifierFlags mods = (mask & 1 ? NSEventModifierFlagControl : 0) |
            (mask & 2 ? NSEventModifierFlagShift : 0) | (mask & 4 ? NSEventModifierFlagOption : 0) |
            (mask & 8 ? NSEventModifierFlagCommand : 0);
        assert([controller handleEvent:ModeKey(3, mods, NO) client:client] == (mask == 3));
        assert(appearance.traditionalOutput == traditional);
    }
    assert(![controller handleEvent:ModeKey(2, flags, NO) client:client]);
    [appearance applySharedInputPreferences:@{@"keybindings":keys}];
    assert(![controller handleEvent:ModeKey(3, flags, NO) client:client]);
    appearance.characterSetShortcut = NO;
    assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] characterSetShortcut]);
    appearance.characterSetShortcut = YES;
    appearance.englishMode = english;
    assert(appearance.fullWidthInput == fullWidth && appearance.chinesePunctuation == punctuation);
}

static void TestDedicatedEnglish(MSIMEAppearancePreferences *appearance) {
    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    [controller setValue:@{@"editing_text":@"test", @"candidates":@[]} forKey:@"view"];
    NSEventModifierFlags flags = NSEventModifierFlagControl | NSEventModifierFlagShift;
    session.failFinish = YES;
    assert([controller handleEvent:ModeKey(14, flags, NO) client:client]);
    assert(session.englishCandidateCalls == 0);
    session.failFinish = NO;
    assert([controller handleEvent:ModeKey(14, flags, NO) client:client]);
    assert(session.dedicatedEnglish && session.englishCandidateCalls == 1 && !appearance.englishMode);
    assert([client.committed isEqual:@"测试"]);
    assert([[[controller menu] itemAtIndex:2] state] == NSControlStateValueOn);
    assert([[[controller menu] itemAtIndex:0] state] == NSControlStateValueOff);
    assert([controller handleEvent:ModeKey(14, flags, YES) client:client]);
    assert(session.englishCandidateCalls == 1);
    [controller selectChineseMode:nil];
    assert(!session.dedicatedEnglish && !appearance.englishMode);
    appearance.englishMode = YES;
    assert([controller handleEvent:ModeKey(14, flags, NO) client:client]);
    assert(session.dedicatedEnglish && !appearance.englishMode);
    assert([controller handleEvent:ModeKey(14, flags, NO) client:client]);
    assert(!session.dedicatedEnglish && !appearance.englishMode);
    NSUInteger calls = session.englishCandidateCalls;
    for (NSNumber *extra in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagOption)]) {
        [controller handleEvent:ModeKey(14, flags | extra.unsignedIntegerValue, NO) client:client];
        assert(session.englishCandidateCalls == calls);
    }
}

static void TestFullWidth(NSUserDefaults *defaults, MSIMEAppearancePreferences *appearance) {
    assert(!appearance.fullWidthInput);
    NSButton *control = (id)PreferenceControl(appearance, @selector(fullWidthChanged:));
    control.state = NSControlStateValueOn;
    [NSApp sendAction:control.action to:control.target from:control];
    assert(appearance.fullWidthInput);
    assert([[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] fullWidthInput]);
    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    const NSEventModifierFlags chord = NSEventModifierFlagOption | NSEventModifierFlagShift;
    [controller prepareSession];
    assert(session.fullwidth && session.widthCalls > 0);
    assert([controller handleEvent:ModeKey(4, chord, NO) client:client]);
    assert(!appearance.fullWidthInput);
    assert([controller handleEvent:ModeKey(4, chord, YES) client:client]);
    assert(!appearance.fullWidthInput);
    assert([controller handleEvent:ModeKey(4, chord, NO) client:client]);
    assert(appearance.fullWidthInput && session.asciiCalls == 0);
    const NSEventModifierFlags windowsChord = NSEventModifierFlagControl | NSEventModifierFlagShift;
    assert([controller handleEvent:ModeKey(49, windowsChord, NO) client:client]);
    assert(!appearance.fullWidthInput);
    [controller appearanceChanged:nil];
    assert(!session.fullwidth);
    NSUInteger widthCalls = session.widthCalls;
    assert([controller handleEvent:ModeKey(49, windowsChord, YES) client:client]);
    assert(!appearance.fullWidthInput && session.widthCalls == widthCalls);
    assert([controller handleEvent:ModeKey(49, windowsChord, NO) client:client]);
    [controller appearanceChanged:nil];
    assert(appearance.fullWidthInput && session.fullwidth);
    for (NSEventModifierFlags extra : {NSEventModifierFlagCommand, NSEventModifierFlagOption})
        assert(!msime::mac::IsFullWidthInputToggle(49, windowsChord | extra));
    for (NSEventModifierFlags extra : {NSEventModifierFlagCommand, NSEventModifierFlagControl}) {
        assert(![controller handleEvent:ModeKey(4, chord | extra, NO) client:client]);
        assert(appearance.fullWidthInput);
    }
    appearance.englishMode = YES;
    assert(![controller handleEvent:ModeKey(4, chord, NO) client:client]);
    assert([controller handleEvent:ModeKey(49, windowsChord, NO) client:client]);
    assert(!appearance.fullWidthInput && appearance.englishMode);
    assert([controller handleEvent:ModeKey(49, windowsChord, NO) client:client]);
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(appearance.fullWidthInput);
    appearance.englishMode = NO;
    NSDictionary *idle = @{@"handled": @NO, @"view": @{@"editing_text": @"", @"candidates": @[]}};
    session.nextTransition = idle;
    for (unichar character = 32; character <= 126; ++character) {
        NSString *text = [NSString stringWithCharacters:&character length:1];
        NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:character == 32 ? 49 : 0];
        assert([controller handleEvent:key client:client]);
        assert(client.committed.length == 1);
        assert([client.committed characterAtIndex:0] == (character == 32 ? 0x3000 : character + 0xFEE0));
    }
    client.committed = nil;
    session.nextTransition = @{@"handled": @YES, @"view": @{@"editing_text": @"a", @"candidates": @[]}};
    NSUInteger calls = session.asciiCalls;
    assert([controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(session.asciiCalls == calls + 1 && client.committed == nil && [client.marked isEqual:@"a"]);
    session.nextTransition = @{@"handled": @NO, @"view": @{@"editing_text": @"a", @"candidates": @[]}};
    session.failFinish = YES;
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(client.committed == nil);
    session.failFinish = NO;
    // A partial finish must not insert the fallback inside the remaining composition.
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(client.committed == nil);
    session.finishTransition = @{@"handled": @YES, @"commit": @"测试", @"view": @{@"editing_text": @"", @"candidates": @[]}};
    client.insertions = [NSMutableArray array];
    assert([controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert([client.committed isEqual:@"ａ"] && client.marked.length == 0);
    assert(([client.insertions isEqual:@[@"测试", @"ａ"]]));
    session.nextTransition = idle;
    for (NSString *text in @[@"\t", @"汉", @"😀"]) {
        NSEvent *key = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:text charactersIgnoringModifiers:text isARepeat:NO keyCode:0];
        client.committed = nil;
        assert(![controller handleEvent:key client:client]);
        assert(client.committed == nil);
    }
    session.nextTransition = nil;
    client.committed = nil;
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(client.committed == nil);
    session.nextTransition = idle;
    appearance.fullWidthInput = NO;
    client.committed = nil;
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(client.committed == nil && control.state == NSControlStateValueOff);
}

static NSEvent *TapEvent(NSEventType type, unsigned short key, NSEventModifierFlags flags, double time) {
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:time windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key];
}

static NSUInteger baseDeactivationCalls;
static void RecordBaseDeactivation(id object, SEL selector, id sender) {
    (void)object; (void)selector; (void)sender; ++baseDeactivationCalls;
}

@interface DeactivationToolbar : NSObject
@property(nonatomic) NSUInteger calls;
@end
@implementation DeactivationToolbar
- (void)deactivateForDelegate:(id)delegate { (void)delegate; ++self.calls; }
@end

static void TestStaleClientDeactivation() {
    NSString *suite = [@"msime.deactivation." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    ModeController *controller = [ModeController alloc];
    ShortcutClient *oldClient = [ShortcutClient new], *current = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    TestCandidatePanel *panel = [TestCandidatePanel new], *keymap = [TestCandidatePanel new];
    DeactivationToolbar *toolbar = [DeactivationToolbar new];
    NSTimer *timer = [NSTimer timerWithTimeInterval:1 repeats:YES block:^(NSTimer *unused) { (void)unused; }];
    NSDictionary *view = @{@"focused":@YES, @"editing_text":@"test", @"candidates":@[]};
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:current forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    [controller setValue:panel forKey:@"panel"];
    [controller setValue:keymap forKey:@"keymapPanel"];
    [controller setValue:toolbar forKey:@"toolbar"];
    [controller setValue:timer forKey:@"preferencesTimer"];
    [controller setValue:view forKey:@"view"];
    panel.visible = keymap.visible = YES;
    current.marked = @"test";
    // Isolate superclass IPC in this controller test, while recording whether
    // stale callbacks reach it. Actual installed IMK delivery is a separate gate.
    Method base = class_getInstanceMethod(IMKInputController.class, @selector(deactivateServer:));
    assert(base);
    baseDeactivationCalls = 0;
    IMP original = method_setImplementation(base, (IMP)RecordBaseDeactivation);
    auto down = TapEvent(NSEventTypeFlagsChanged, 56, NSEventModifierFlagShift, 1.0);
    auto up = TapEvent(NSEventTypeFlagsChanged, 56, 0, 1.1);
    assert(![controller handleEvent:down client:current]);
    for (id stale in @[oldClient, NSNull.null]) {
        [controller deactivateServer:stale == NSNull.null ? nil : stale];
        assert([controller valueForKey:@"activeClient"] == current);
        assert([[controller valueForKey:@"view"] isEqual:view]);
        assert([current.marked isEqual:@"test"] && current.committed == nil);
        assert(panel.visible && keymap.visible && timer.valid);
        assert(session.focusCalls == 0 && toolbar.calls == 0 && baseDeactivationCalls == 0);
    }
    // The current client's pending tap must survive an unrelated deactivation.
    assert([controller handleEvent:up client:current] && prefs.englishMode);
    assert([current.committed isEqual:@"测试"]);
    panel.visible = keymap.visible = YES;
    [controller deactivateServer:current];
    assert([controller valueForKey:@"activeClient"] == nil);
    assert([controller valueForKey:@"preferencesTimer"] == nil && !timer.valid);
    assert(!panel.visible && !keymap.visible && current.marked.length == 0);
    assert(session.focusCalls == 1 && toolbar.calls == 1 && baseDeactivationCalls == 1);
    [controller deactivateServer:current];
    assert(session.focusCalls == 1 && toolbar.calls == 1 && baseDeactivationCalls == 1);
    method_setImplementation(base, original);
    [defaults removePersistentDomainForName:suite];
}

@interface ControlledPreferenceRead : NSObject
@property(nonatomic, strong) dispatch_semaphore_t started;
@property(nonatomic, strong) dispatch_semaphore_t released;
@property(nonatomic, copy) NSDictionary *snapshot;
@end
@implementation ControlledPreferenceRead
- (instancetype)init {
    self = [super init];
    if (self) { _started = dispatch_semaphore_create(0); _released = dispatch_semaphore_create(0); }
    return self;
}
@end

@interface AsyncPreferenceSession : ShortcutSession
@property(nonatomic) NSUInteger updates;
@end
@implementation AsyncPreferenceSession
- (NSDictionary *)updatePreferencesSnapshot:(NSDictionary *)snapshot error:(NSError **)error {
    (void)snapshot; (void)error; ++self.updates;
    return @{@"view":@{@"focused":@YES, @"editing_text":@"", @"candidates":@[]}};
}
@end

@interface AsyncPreferencesController : ModeController
@property(nonatomic, copy) NSArray<ControlledPreferenceRead *> *reads;
@property(nonatomic) NSUInteger readCalls;
@property(nonatomic) NSUInteger completions;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *appliedPreferences;
@end
@implementation AsyncPreferencesController
- (NSDictionary *)readPreferencesSnapshotInDirectory:(NSString *)directory error:(NSError **)error {
    (void)directory; (void)error;
    assert(!NSThread.isMainThread);
    ControlledPreferenceRead *read;
    @synchronized(self) { assert(self.readCalls < self.reads.count); read = self.reads[self.readCalls++]; }
    dispatch_semaphore_signal(read.started);
    assert(dispatch_semaphore_wait(read.released, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    return read.snapshot;
}
- (void)completePreferenceLoad:(NSDictionary *)snapshot error:(NSError *)error generation:(uint64_t)generation
                       session:(MSIMEClientSession *)session client:(id)client {
    assert(NSThread.isMainThread);
    [super completePreferenceLoad:snapshot error:error generation:generation session:session client:client];
    ++self.completions;
}
- (void)applySharedToolbarPreferences:(NSDictionary *)preferences {
    [self.appliedPreferences addObject:preferences];
    [super applySharedToolbarPreferences:preferences];
}
@end

static void WaitForPreferenceCompletions(AsyncPreferencesController *controller, NSUInteger count) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (controller.completions < count && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(controller.completions == count);
}

static void TestPreferenceClientGeneration() {
    for (NSNumber *returnToFirst in @[@NO, @YES]) {
        NSString *suite = [@"msime.preference-focus." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        prefs.englishMode = YES;
        AsyncPreferencesController *controller = [AsyncPreferencesController alloc];
        ShortcutClient *first = [ShortcutClient new], *second = [ShortcutClient new];
        AsyncPreferenceSession *session = returnToFirst.boolValue ? [AsyncPreferenceSession new] : nil;
        NSMutableArray *reads = [NSMutableArray array];
        for (NSNumber *enabled in @[@NO, @YES, @NO]) {
            ControlledPreferenceRead *read = [ControlledPreferenceRead new];
            read.snapshot = @{@"preferences":@{@"chinese_punctuation":enabled}};
            [reads addObject:read];
        }
        controller.reads = reads;
        controller.appliedPreferences = [NSMutableArray array];
        [controller setValue:prefs forKey:@"appearance"];
        [controller setValue:first forKey:@"activeClient"];
        [controller setValue:session forKey:@"session"];
        [controller setValue:@"/synthetic-preferences" forKey:@"preferencesDirectory"];
        [controller reloadPreferences];
        assert(dispatch_semaphore_wait(controller.reads[0].started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
        NSEvent *release = TapEvent(NSEventTypeFlagsChanged, 56, 0, 1);
        assert(![controller handleEvent:release client:second]);
        if (returnToFirst.boolValue) assert(![controller handleEvent:release client:first]);
        [controller reloadPreferences];
        assert(dispatch_semaphore_wait(controller.reads[1].started, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
        dispatch_semaphore_signal(controller.reads[0].released);
        WaitForPreferenceCompletions(controller, 1);
        assert(controller.appliedPreferences.count == 0 && session.updates == 0);
        // Completing the old request must not release the newer request's gate.
        [controller reloadPreferences];
        dispatch_semaphore_signal(controller.reads[1].released);
        WaitForPreferenceCompletions(controller, 2);
        assert(controller.readCalls == 2 && controller.appliedPreferences.count == 1);
        assert([controller.appliedPreferences[0][@"chinese_punctuation"] isEqual:@YES]);
        assert(session.updates == (session ? 1 : 0));
        dispatch_semaphore_signal(controller.reads[2].released);
        [controller reloadPreferences];
        WaitForPreferenceCompletions(controller, 3);
        assert(controller.appliedPreferences.count == 2 && !prefs.chinesePunctuation);
        assert(session.updates == (session ? 2 : 0));
        [defaults removePersistentDomainForName:suite];
    }
}

static void TestModifierTaps() {
    for (NSNumber *key in @[@56, @60, @59, @62]) {
        const auto code = key.unsignedShortValue;
        const auto flag = code == 56 || code == 60 ? NSEventModifierFlagShift : NSEventModifierFlagControl;
        auto down = TapEvent(NSEventTypeFlagsChanged, code, flag, 1.0);
        auto up = TapEvent(NSEventTypeFlagsChanged, code, 0, 1.1);
        MSIMEModifierTap tap;
        assert(!tap.observe(up, true, true)); // A release after focus acquisition cannot toggle.
        assert(!tap.observe(down, true, true));
        assert(tap.observe(up, true, true));
        assert(!tap.observe(up, true, true));
        for (double time : {1.5, 2.0, 0.9}) {
            tap.reset();
            assert(!tap.observe(down, true, true));
            assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, code, 0, time), true, true));
        }
        tap.reset();
        assert(!tap.observe(down, false, false));
        assert(!tap.observe(up, true, true)); // Enabling while held does not arm.
        assert(!tap.observe(down, true, true));
        assert(!tap.observe(up, false, false));
        tap.reset();
        assert(!tap.observe(down, true, true));
        tap.reset();
        assert(!tap.observe(up, true, true));
        for (auto other : {NSEventModifierFlagCommand, NSEventModifierFlagOption, NSEventModifierFlagFunction,
                          flag == NSEventModifierFlagShift ? NSEventModifierFlagControl : NSEventModifierFlagShift}) {
            tap.reset();
            assert(!tap.observe(down, true, true));
            assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, 55, flag | other, 1.02), true, true));
            assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, 55, flag, 1.04), true, true));
            assert(!tap.observe(up, true, true));
        }
        // A held non-modifier and typing while held cancel.
        tap.reset();
        assert(!tap.observe(TapEvent(NSEventTypeKeyDown, 0, 0, 0.9), true, true));
        assert(!tap.observe(down, true, true));
        assert(!tap.observe(up, true, true));
        assert(!tap.observe(TapEvent(NSEventTypeKeyUp, 0, 0, 1.2), true, true));
        assert(!tap.observe(down, true, true));
        assert(tap.observe(up, true, true));
        assert(!tap.observe(down, true, true));
        assert(!tap.observe(TapEvent(NSEventTypeKeyDown, 0, flag, 1.02), true, true));
        assert(!tap.observe(TapEvent(NSEventTypeKeyUp, 0, flag, 1.04), true, true));
        assert(!tap.observe(up, true, true));
        assert(!tap.observe(down, true, true));
        unsigned short otherSide = code == 56 ? 60 : code == 60 ? 56 : code == 59 ? 62 : 59;
        assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, otherSide, flag, 1.02), true, true));
        assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, otherSide, flag, 1.04), true, true));
        assert(tap.observe(up, true, true));
        assert(!tap.observe(down, true, true));
        assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, otherSide, flag, 1.02), true, true));
        assert(!tap.observe(TapEvent(NSEventTypeFlagsChanged, code, flag, 1.04), true, true));
        assert(tap.observe(TapEvent(NSEventTypeFlagsChanged, otherSide, 0, 1.1), true, true));
    }

    NSString *suite = [@"msime.modifier-taps." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(prefs.shiftTapShortcut && !prefs.controlTapShortcut);
    assert(![prefs sharedPreferencesByMerging:@{}][@"keybindings"]);
    NSDictionary *keys = @{@"switch_language_shift":@NO, @"switch_language_ctrl":@YES, @"switch_language_ctrl_alt_space":@NO};
    [prefs applySharedInputPreferences:@{@"keybindings":keys}];
    assert(!prefs.shiftTapShortcut && prefs.controlTapShortcut);
    assert([[prefs sharedPreferencesByMerging:@{@"keybindings":keys}][@"keybindings"] isEqual:keys]);
    [prefs applySharedInputPreferences:@{@"keybindings":@{@"switch_language_shift":@1, @"switch_language_ctrl":@"false"}}];
    assert(!prefs.shiftTapShortcut && prefs.controlTapShortcut);
    NSButton *shift = (id)PreferenceControl(prefs, NSSelectorFromString(@"shiftTapShortcutChanged:"));
    NSButton *control = (id)PreferenceControl(prefs, NSSelectorFromString(@"controlTapShortcutChanged:"));
    assert(shift.state == NSControlStateValueOff && control.state == NSControlStateValueOn);
    shift.state = NSControlStateValueOn;
    assert([NSApp sendAction:shift.action to:shift.target from:shift]);
    control.state = NSControlStateValueOff;
    assert([NSApp sendAction:control.action to:control.target from:control]);
    MSIMEAppearancePreferences *reopened = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(reopened.shiftTapShortcut && !reopened.controlTapShortcut);
    NSDictionary *merged = [MSIMEMergePreferenceSnapshot(@{@"keybindings":keys}, [prefs sharedPreferencesByMerging:@{}]) objectForKey:@"keybindings"];
    assert(([merged isEqual:@{@"switch_language_shift":@YES, @"switch_language_ctrl":@NO, @"switch_language_ctrl_alt_space":@NO}]));

    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    assert([controller recognizedEvents:client] == (NSEventMaskKeyDown | NSEventMaskKeyUp | NSEventMaskFlagsChanged));
    auto down = TapEvent(NSEventTypeFlagsChanged, 56, NSEventModifierFlagShift, 1.0);
    auto up = TapEvent(NSEventTypeFlagsChanged, 56, 0, 1.1);
    session.failFinish = YES;
    assert(![controller handleEvent:down client:client]);
    assert([controller handleEvent:up client:client]);
    assert(!prefs.englishMode);
    session.failFinish = NO;
    assert(![controller handleEvent:down client:client]);
    assert([controller handleEvent:up client:client]);
    assert(prefs.englishMode && [client.committed isEqual:@"测试"]);
    assert(![controller handleEvent:down client:client]);
    assert([controller handleEvent:up client:client]);
    assert(!prefs.englishMode);
    assert(![controller handleEvent:down client:client]);
    ShortcutClient *other = [ShortcutClient new];
    assert(![controller handleEvent:up client:other]);
    assert(!prefs.englishMode);
    prefs.controlTapShortcut = YES;
    assert(![controller handleEvent:TapEvent(NSEventTypeFlagsChanged, 62, NSEventModifierFlagControl, 2.0) client:other]);
    assert([controller handleEvent:TapEvent(NSEventTypeFlagsChanged, 62, 0, 2.1) client:other]);
    assert(prefs.englishMode);
    assert(![controller handleEvent:TapEvent(NSEventTypeKeyUp, 0, 0, 2.2) client:other]);
    assert(![controller handleEvent:down client:other]);
    [controller snapshotSessionReplaced:[NSNotification notificationWithName:@"synthetic" object:session]];
    assert(![controller handleEvent:up client:other] && prefs.englishMode);
    assert(![controller handleEvent:down client:other]);
    assert(![controller handleEvent:up client:nil]);
    assert(![controller handleEvent:up client:other] && prefs.englishMode);
    [defaults removePersistentDomainForName:suite];
}

@interface ApplicationShortcutClient : ShortcutClient
@property(nonatomic, copy) NSString *bundleIdentifier;
@end
@implementation ApplicationShortcutClient
@end

static NSDictionary *monitoredSource;
static NSUInteger monitoredSourceReads;
static TISInputSourceRef CopyMonitoredSource() {
    ++monitoredSourceReads;
    return monitoredSource ? (TISInputSourceRef)CFBridgingRetain(monitoredSource) : nullptr;
}
static void *MonitoredSourceProperty(TISInputSourceRef source, CFStringRef key) {
    return (__bridge void *)((__bridge NSDictionary *)source)[(__bridge NSString *)key];
}

static void TestInputSourceModeReset() {
    NSString *suite = [@"msime.source-reset." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    [prefs activateInputModeForApplication:@"org.example.fixture"];
    prefs.englishMode = YES; // Keep an independent per-app choice.
    prefs.imeModeScope = @"global";
    [prefs activateInputModeForApplication:@"org.example.fixture"];
    prefs.englishMode = YES;
    NSNotificationCenter *center = [NSNotificationCenter new];
    NSString *bundleKey = (__bridge NSString *)kTISPropertyBundleID;
    NSString *sourceKey = (__bridge NSString *)kTISPropertyInputSourceID;
    NSString *notification = (__bridge NSString *)kTISNotifySelectedKeyboardInputSourceChanged;
    NSString *own = @"org.example.input-method";
    __block NSUInteger resets = 0, saves = 0;
    id saveObserver = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    MSIMEInputSourceMonitor *monitor = [[MSIMEInputSourceMonitor alloc] initWithCenter:center bundleIdentifier:own
        copySource:CopyMonitoredSource propertyGetter:MonitoredSourceProperty switchedAway:^{ assert(NSThread.isMainThread); ++resets; [prefs resetGlobalInputMode]; }];
    assert(monitor);
    for (NSDictionary *source in @[@{}, @{sourceKey:@42}, @{bundleKey:own}, @{sourceKey:own},
                                   @{sourceKey:[own stringByAppendingString:@".mode"]}]) {
        monitoredSource = source;
        [center postNotificationName:notification object:nil];
        assert(resets == 0 && prefs.englishMode && saves == 0);
    }
    monitoredSource = nil;
    [center postNotificationName:notification object:nil];
    assert(resets == 0 && prefs.englishMode);
    for (NSDictionary *source in @[@{bundleKey:@"org.example.other-input"},
                                   @{sourceKey:@"com.apple.keylayout.US"},
                                   @{sourceKey:[own stringByAppendingString:@"-other"]}]) {
        prefs.englishMode = YES;
        NSUInteger beforeSaves = saves, beforeResets = resets;
        monitoredSource = source;
        [center postNotificationName:notification object:nil];
        assert(resets == beforeResets + 1 && !prefs.englishMode && saves == beforeSaves);
    }
    prefs.defaultImeMode = @"english";
    prefs.englishMode = NO;
    [center postNotificationName:notification object:nil];
    assert(prefs.englishMode); // Reset follows the configured default, not hardcoded Chinese.
    prefs.imeModeScope = @"app";
    [prefs activateInputModeForApplication:@"org.example.fixture"];
    assert(prefs.englishMode); // A source change did not erase the separate app choice.
    NSUInteger before = resets;
    // A delayed background notification must re-read the selected source on
    // the main thread, not reset from an obsolete source captured at receipt.
    dispatch_semaphore_t posted = dispatch_semaphore_create(0);
    NSUInteger reads = monitoredSourceReads;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        [center postNotificationName:notification object:nil];
        dispatch_semaphore_signal(posted);
    });
    assert(dispatch_semaphore_wait(posted, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)) == 0);
    monitoredSource = @{bundleKey:own};
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1];
    while (monitoredSourceReads == reads && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(monitoredSourceReads > reads && resets == before);
    monitoredSource = @{sourceKey:@"com.apple.keylayout.US"};
    [monitor stop];
    [center postNotificationName:notification object:nil];
    assert(resets == before);
    __weak MSIMEInputSourceMonitor *weakMonitor = monitor;
    monitor = nil;
    assert(weakMonitor == nil);
    [NSNotificationCenter.defaultCenter removeObserver:saveObserver];
    [defaults removePersistentDomainForName:suite];
    monitoredSource = nil;
}

static void TestInputModePolicy() {
    NSString *suite = [@"msime.mode-policy." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert([prefs.defaultImeMode isEqual:@"chinese"] && [prefs.imeModeScope isEqual:@"app"]);
    assert(![prefs sharedPreferencesByMerging:@{}][@"default_ime_mode"]);
    NSDictionary *shared = @{@"default_ime_mode":@"english", @"ime_mode_scope":@"global"};
    assert([[prefs sharedPreferencesByMerging:shared][@"default_ime_mode"] isEqual:@"english"]);
    [prefs applySharedInputPreferences:shared];
    assert([prefs.defaultImeMode isEqual:@"english"] && [prefs.imeModeScope isEqual:@"global"]);
    [prefs applySharedInputPreferences:@{@"default_ime_mode":@YES, @"ime_mode_scope":@"invalid"}];
    assert([prefs.defaultImeMode isEqual:@"english"] && [prefs.imeModeScope isEqual:@"global"]);
    NSPopUpButton *mode = (id)PreferenceControl(prefs, NSSelectorFromString(@"defaultImeModeChanged:"));
    NSPopUpButton *scope = (id)PreferenceControl(prefs, NSSelectorFromString(@"imeModeScopeChanged:"));
    assert(mode.indexOfSelectedItem == 1 && scope.indexOfSelectedItem == 1);
    [mode selectItemAtIndex:0];
    assert([NSApp sendAction:mode.action to:mode.target from:mode]);
    [scope selectItemAtIndex:0];
    assert([NSApp sendAction:scope.action to:scope.target from:scope]);
    MSIMEAppearancePreferences *reopened = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert([reopened.defaultImeMode isEqual:@"chinese"] && [reopened.imeModeScope isEqual:@"app"]);
    NSDictionary *patch = [prefs sharedPreferencesByMerging:@{}];
    assert([patch[@"default_ime_mode"] isEqual:@"chinese"] && [patch[@"ime_mode_scope"] isEqual:@"app"]);
    prefs.defaultImeMode = @"invalid"; prefs.imeModeScope = @"invalid";
    assert([prefs.defaultImeMode isEqual:@"chinese"] && [prefs.imeModeScope isEqual:@"app"]);

    // Before the first key, the initial asynchronous preference load can seed
    // the default; after the first key, refreshes cannot change the active mode.
    [prefs activateInputModeForApplication:@"org.example.fixture-a"];
    [prefs applySharedInputPreferences:@{@"default_ime_mode":@"english"}];
    assert(prefs.englishMode);
    [prefs lockActiveInputMode];
    [prefs applySharedInputPreferences:@{@"default_ime_mode":@"chinese"}];
    assert(prefs.englishMode);
    [prefs activateInputModeForApplication:@"org.example.fixture-b"];
    assert(!prefs.englishMode);
    [prefs lockActiveInputMode];
    [prefs activateInputModeForApplication:@"org.example.fixture-a"];
    assert(prefs.englishMode);
    [prefs applySharedInputPreferences:@{@"ime_mode_scope":@"global"}];
    assert(prefs.englishMode); // Scope changes are deferred to activation.
    [prefs activateInputModeForApplication:@"org.example.fixture-a"];
    assert(!prefs.englishMode);
    prefs.englishMode = YES;
    [prefs activateInputModeForApplication:@"org.example.fixture-b"];
    assert(prefs.englishMode);
    NSMutableDictionary *cloud = [[prefs cloudSettingsSnapshot] mutableCopy];
    assert([cloud[@"platform.macos.english_input_mode"] isEqual:@YES]);
    cloud[@"platform.macos.english_input_mode"] = @NO;
    assert([prefs applyCloudSettingsSnapshot:cloud] && !prefs.englishMode);
    [prefs activateInputModeForApplication:@"org.example.fixture-a"];
    assert(!prefs.englishMode);
    // Per-app choices survive changing scope, but do not leak into fresh preferences.
    prefs.imeModeScope = @"app";
    [prefs activateInputModeForApplication:@"org.example.fixture-a"];
    assert(prefs.englishMode);
    [reopened activateInputModeForApplication:@"org.example.fixture-a"];
    assert(!reopened.englishMode);

    ModeController *controller = [ModeController alloc];
    ShortcutSession *session = [ShortcutSession new];
    ApplicationShortcutClient *a = [ApplicationShortcutClient new], *b = [ApplicationShortcutClient new];
    a.bundleIdentifier = @"org.example.fixture-a"; b.bundleIdentifier = @"org.example.fixture-b";
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:session forKey:@"session"];
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:a]);
    assert(prefs.englishMode && session.asciiCalls == 0);
    [controller handleEvent:ModeKey(0, 0, NO) client:b];
    assert(!prefs.englishMode && session.asciiCalls == 1);
    [prefs applySharedInputPreferences:@{@"default_ime_mode":@"english"}];
    assert(!prefs.englishMode);
    [controller handleEvent:ModeKey(0, 0, NO) client:a];
    assert(prefs.englishMode && session.asciiCalls == 1);
    // App identities are memory-only; no per-app state is exported or persisted.
    assert([defaults objectForKey:a.bundleIdentifier] == nil);
    assert(![prefs sharedPreferencesByMerging:@{}][a.bundleIdentifier]);
    [defaults removePersistentDomainForName:suite];
}

static void TestControlOptionSpace() {
    NSUserDefaults *standardDefaults = NSUserDefaults.standardUserDefaults;
    id previousHoldSpace = [standardDefaults objectForKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
    [standardDefaults setBool:NO forKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
    NSString *suite = [@"msime.control-option-space." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(prefs.controlOptionSpaceShortcut);
    NSDictionary *keys = @{@"switch_language_ctrl_alt_space":@NO, @"switch_language_ctrl":@YES, @"toggle_character_set_ctrl_shift_f":@NO};
    assert([[prefs sharedPreferencesByMerging:@{@"keybindings":keys}][@"keybindings"] isEqual:keys]);
    assert(![prefs sharedPreferencesByMerging:@{}][@"keybindings"]);
    [prefs applySharedInputPreferences:@{@"keybindings":keys}];
    assert(!prefs.controlOptionSpaceShortcut && !prefs.characterSetShortcut);
    for (id invalid in @[NSNull.null, @1, @"true"])
        [prefs applySharedInputPreferences:@{@"keybindings":@{@"switch_language_ctrl_alt_space":invalid}}];
    assert(!prefs.controlOptionSpaceShortcut);
    NSButton *button = (id)PreferenceControl(prefs, NSSelectorFromString(@"controlOptionSpaceShortcutChanged:"));
    assert(button.state == NSControlStateValueOff);
    button.state = NSControlStateValueOn;
    assert([NSApp sendAction:button.action to:button.target from:button]);
    assert(prefs.controlOptionSpaceShortcut && !prefs.characterSetShortcut);
    NSMutableDictionary *expected = [keys mutableCopy];
    expected[@"switch_language_ctrl_alt_space"] = @YES;
    assert([[prefs sharedPreferencesByMerging:@{@"keybindings":keys}][@"keybindings"] isEqual:expected]);
    NSDictionary *patch = [prefs sharedPreferencesByMerging:@{}];
    assert([patch[@"keybindings"] isEqual:@{@"switch_language_ctrl_alt_space":@YES}]);
    assert([MSIMEMergePreferenceSnapshot(@{@"keybindings":keys}, patch)[@"keybindings"] isEqual:expected]);
    assert([[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults] controlOptionSpaceShortcut]);

    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    ShortcutSession *session = [ShortcutSession new];
    TestCandidatePanel *panel = [TestCandidatePanel new];
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    [controller setValue:panel forKey:@"panel"];
    prefs.inputModeShortcut = NO; // Independent from the legacy Shift+Space switch.
    NSEventModifierFlags flags = NSEventModifierFlagControl | NSEventModifierFlagOption;
    session.failFinish = YES;
    panel.visible = YES;
    client.marked = @"test";
    assert([controller handleEvent:ModeKey(49, flags, NO) client:client]);
    assert(!prefs.englishMode && panel.visible && [client.marked isEqual:@"test"]);
    session.failFinish = NO;
    assert([controller handleEvent:ModeKey(49, flags, NO) client:client]);
    assert(prefs.englishMode && !panel.visible && client.marked.length == 0);
    assert(session.lastCommand == MSIME_FINISH_COMPOSITION && [client.committed isEqual:@"测试"]);
    session.lastCommand = UINT32_MAX;
    assert([controller handleEvent:ModeKey(49, flags, YES) client:client]);
    assert(prefs.englishMode && session.lastCommand == UINT32_MAX);
    assert([controller handleEvent:ModeKey(49, flags | NSEventModifierFlagCapsLock, NO) client:client]);
    assert(!prefs.englishMode && session.lastCommand == UINT32_MAX);
    for (NSUInteger mask = 0; mask < 16; ++mask) {
        prefs.englishMode = YES;
        NSEventModifierFlags mods = (mask & 1 ? NSEventModifierFlagControl : 0) |
            (mask & 2 ? NSEventModifierFlagOption : 0) | (mask & 4 ? NSEventModifierFlagShift : 0) |
            (mask & 8 ? NSEventModifierFlagCommand : 0);
        assert([controller handleEvent:ModeKey(49, mods, NO) client:client] == (mask == 3 || mask == 5));
        assert(prefs.englishMode == (mask != 3));
    }
    assert(![controller handleEvent:ModeKey(0, flags, NO) client:client]);
    [prefs applySharedInputPreferences:@{@"keybindings":keys}];
    assert(![controller handleEvent:ModeKey(49, flags, NO) client:client]);
    assert(prefs.englishMode && button.state == NSControlStateValueOff);
    prefs.controlOptionSpaceShortcut = NO;
    assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults] controlOptionSpaceShortcut]);
    [defaults removePersistentDomainForName:suite];
    if (previousHoldSpace) [standardDefaults setObject:previousHoldSpace forKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
    else [standardDefaults removeObjectForKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
}

static void TestInputMode(NSUserDefaults *defaults, MSIMEAppearancePreferences *appearance) {
    assert(!appearance.englishMode && appearance.inputModeShortcut);
    NSButton *shortcut = (id)PreferenceControl(appearance, @selector(inputModeShortcutChanged:));
    shortcut.state = NSControlStateValueOff;
    [NSApp sendAction:shortcut.action to:shortcut.target from:shortcut];
    MSIMEAppearancePreferences *reloaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot];
    assert(!reloaded.inputModeShortcut);
    appearance.inputModeShortcut = YES;
    ModeController *controller = [ModeController alloc];
    ShortcutClient *client = [ShortcutClient new];
    TestCandidatePanel *panel = [TestCandidatePanel new];
    ShortcutSession *session = [ShortcutSession new];
    [controller setValue:appearance forKey:@"appearance"];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:panel forKey:@"panel"];
    [controller setValue:session forKey:@"session"];
    NSMenu *menu = controller.menu;
    CheckMenu(menu, controller);
    assert([menu itemAtIndex:0].state == NSControlStateValueOn);
    assert([menu itemAtIndex:1].state == NSControlStateValueOff);
    assert([[menu itemAtIndex:7].title isEqual:@"表情与符号…"]);
    client.marked = @"ceshi";
    panel.visible = YES;
    [NSApp sendAction:[menu itemAtIndex:1].action to:controller from:[menu itemAtIndex:1]];
    assert(appearance.englishMode && !panel.visible);
    assert([client.committed isEqual:@"测试"] && client.marked.length == 0);
    assert([controller.menu itemAtIndex:1].state == NSControlStateValueOn);
    assert(reloaded.englishMode); // Persistence is shared, not held only in the controller.
    session.lastCommand = UINT32_MAX;
    session.asciiCalls = 0;
    for (NSNumber *flags in @[@0, @(NSEventModifierFlagCommand), @(NSEventModifierFlagOption)]) {
        assert(![controller handleEvent:ModeKey(0, flags.unsignedIntegerValue, NO) client:client]);
    }
    assert(session.lastCommand == UINT32_MAX && session.asciiCalls == 0);
    assert([controller handleEvent:ModeKey(49, NSEventModifierFlagShift, YES) client:client]);
    assert(appearance.englishMode);
    assert([controller handleEvent:ModeKey(49, NSEventModifierFlagShift, NO) client:client]);
    assert(!appearance.englishMode);
    assert([controller handleEvent:ModeKey(49, NSEventModifierFlagShift, YES) client:client]);
    assert(!appearance.englishMode);
    const BOOL beforeWidth = appearance.fullWidthInput;
    for (NSUInteger mask = 1; mask < 8; ++mask) {
        NSEventModifierFlags flags = NSEventModifierFlagShift;
        if (mask & 1) flags |= NSEventModifierFlagCommand;
        if (mask & 2) flags |= NSEventModifierFlagControl;
        if (mask & 4) flags |= NSEventModifierFlagOption;
        assert([controller handleEvent:ModeKey(49, flags, NO) client:client] == (mask == 2));
        assert(!appearance.englishMode);
    }
    appearance.fullWidthInput = beforeWidth;
    appearance.inputModeShortcut = NO;
    [controller handleEvent:ModeKey(49, NSEventModifierFlagShift, NO) client:client];
    assert(!appearance.englishMode && session.lastCommand == MSIME_COMMIT_CANDIDATE);
    appearance.inputModeShortcut = YES;
    session.failFinish = YES;
    panel.visible = YES;
    [controller selectEnglishMode:nil];
    [controller openCharacterPalette:nil];
    assert(!appearance.englishMode && panel.visible && controller.paletteCalls == 0);
    session.failFinish = NO;
    client.marked = @"ceshi";
    client.committed = nil;
    [controller openCharacterPalette:nil];
    assert(controller.paletteCalls == 1 && [client.committed isEqual:@"测试"] && client.marked.length == 0);
    [controller setValue:nil forKey:@"session"];
    [controller selectEnglishMode:nil];
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(controller.preparationCalls == 0);
    [controller handleEvent:ModeKey(49, NSEventModifierFlagShift, NO) client:client];
    assert(!appearance.englishMode && controller.preparationCalls == 0);
    assert(![controller handleEvent:ModeKey(0, 0, NO) client:client]);
    assert(controller.preparationCalls == 1);
    [controller setValue:session forKey:@"session"];
    [controller setValue:@YES forKey:@"focusPending"];
    session.focusCalls = 0;
    [controller handleEvent:ModeKey(0, 0, NO) client:client];
    assert(session.focusCalls == 1);
    [controller handleEvent:ModeKey(0, 0, NO) client:client];
    assert(session.focusCalls == 1);
    appearance.englishMode = NO;
}

static MSIMECandidateButton *PageButton(NSView *content, NSInteger tag) {
    for (NSView *view in content.subviews) {
        if ([view isKindOfClass:MSIMECandidateButton.class] && view.tag == tag) return (id)view;
    }
    return nil;
}

static void TestExternalSkin(MSIMEInputController *controller, HiddenCandidatePanel *panel, NSUserDefaults *defaults) {
    char temporary[] = "/tmp/msime-native-skin-XXXXXX";
    assert(mkdtemp(temporary));
    const std::filesystem::path root(temporary);
    std::filesystem::create_directory(root / "synthetic");
    {
        std::ofstream manifest(root / "synthetic" / "skin.toml");
        manifest << R"toml(schema_version = 1
id = "synthetic"
name = "Synthetic Skin"
version = "1.0"
base = "fluent"
preview = "decoration.png"
[supports]
layouts = ["horizontal", "vertical"]
themes = ["dark", "light"]
[candidate_window]
min_width_dip = 240
[candidate_window.decoration]
top_inset_dip = 48
width_dip = 120
[candidate.light]
surface = "#fff7fa"
selected = "#111111"
show_selected_bar = false
[candidate.dark]
surface = "#121314"
selected = "#ffffff"
show_selected_bar = true
)toml";
        assert(manifest.good());
    }
    NSBitmapImageRep *image = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:nullptr pixelsWide:4 pixelsHigh:4 bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
    for (NSInteger y = 0; y < 4; ++y) for (NSInteger x = 0; x < 4; ++x) {
        unsigned char *pixel = image.bitmapData + y * image.bytesPerRow + x * 4;
        pixel[0] = 255; pixel[1] = 0; pixel[2] = 0; pixel[3] = 255;
    }
    image = [image bitmapImageRepByRetaggingWithColorSpace:NSColorSpace.sRGBColorSpace];
    assert(image);
    assert([[image representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:@((root / "synthetic" / "decoration.png").c_str()) atomically:YES]);
    MSIMEAppearancePreferences *external = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:[NSURL fileURLWithPath:@(root.c_str()) isDirectory:YES]];
    NSPopUpButton *control = (id)PreferenceControl(external, @selector(skinChanged:));
    assert(control.numberOfItems == 5 && [control.lastItem.title isEqual:@"Synthetic Skin"]);
    [control selectItemAtIndex:4];
    [NSApp sendAction:control.action to:control.target from:control];
    assert([external.skinID isEqual:@"synthetic"] && external.decorationImage);
    MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:external.skinsRoot];
    assert([loaded.skinID isEqual:@"synthetic"] && [loaded resolvedSkinForDark:NO].id == "synthetic");
    NSDictionary *before = [[controller valueForKey:@"view"] copy];
    [controller setValue:external forKey:@"appearance"];
    MSIMEFloatingToolbarPanel *toolbar = [MSIMEFloatingToolbarPanel new];
    [toolbar setFrameAutosaveName:@""];
    [controller setValue:toolbar forKey:@"toolbar"];
    MetasequoiaSkinSettingsView *cards = (id)[external skinCatalogController].window.contentView.subviews.firstObject;
    NSArray<NSSwitch *> *skinSwitches = [cards valueForKey:@"switches"];
    assert([skinSwitches.lastObject.identifier isEqual:@"synthetic"]);
    [NSNotificationCenter.defaultCenter addObserver:controller selector:@selector(appearanceChanged:)
                                              name:MSIMEAppearanceDidChangeNotification object:external];
    [NSApp sendAction:skinSwitches.firstObject.action to:skinSwitches.firstObject.target from:skinSwitches.firstObject];
    assert([external.skinID isEqual:@"fluent"] && !external.decorationImage);
    [NSApp sendAction:skinSwitches.lastObject.action to:skinSwitches.lastObject.target from:skinSwitches.lastObject];
    assert([external.skinID isEqual:@"synthetic"] && external.decorationImage);
    assert([control.selectedItem.representedObject isEqual:@"synthetic"]);
    assert([panel.contentView.subviews.lastObject isKindOfClass:NSImageView.class]);
    assert([[controller valueForKey:@"view"] isEqual:before]);
    [NSNotificationCenter.defaultCenter removeObserver:controller name:MSIMEAppearanceDidChangeNotification object:external];
    for (NSNumber *vertical in @[@NO, @YES]) {
        external.vertical = vertical.boolValue;
        for (NSString *theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
            panel.appearance = [NSAppearance appearanceNamed:theme];
            [controller appearanceChanged:nil];
            [toolbar applyThemePreferences:@{@"theme": [theme isEqual:NSAppearanceNameDarkAqua] ? @"dark" : @"light"}];
            NSColor *toolbarFill = [[toolbar valueForKey:@"chrome"] valueForKey:@"fillColor"];
            assert([toolbarFill isEqual:SkinColor([external resolvedSkinForDark:[theme isEqual:NSAppearanceNameDarkAqua]].tokens.surface)]);
            MSIMECandidateChromeView *chrome = (id)panel.contentView;
            NSImageView *decoration = (id)chrome.subviews.lastObject;
            assert([decoration isKindOfClass:NSImageView.class] && decoration.image);
            assert(panel.frame.size.width >= 240);
            assert(decoration.frame.size.width == 120 && decoration.frame.size.height == 48);
            assert(NSMaxX(decoration.frame) == chrome.bounds.size.width && NSMaxY(decoration.frame) == chrome.bounds.size.height);
            MSIMECandidateButton *first = PageButton(chrome, 0);
            assert(NSMaxY(first.frame) <= NSMinY(decoration.frame));
            assert(first.showSelectedBar == [theme isEqual:NSAppearanceNameDarkAqua]);
            const auto tokens = [external resolvedSkinForDark:[theme isEqual:NSAppearanceNameDarkAqua]].tokens;
            assert([chrome.fillColor isEqual:SkinColor(tokens.surface)]);
            assert([first.titleColor isEqual:SkinColor(tokens.selectedText)]);
            NSBitmapImageRep *bitmap = [chrome bitmapImageRepForCachingDisplayInRect:chrome.bounds];
            [chrome cacheDisplayInRect:chrome.bounds toBitmapImageRep:bitmap];
            assert(bitmap && [[controller valueForKey:@"view"] isEqual:before]);
        }
    }
    // No disk reads while typing/rendering: removal takes effect only on explicit reload.
    std::filesystem::remove_all(root / "synthetic");
    [controller renderCandidates];
    assert([external resolvedSkinForDark:NO].id == "synthetic" && external.decorationImage);
    NSButton *reload = (id)PreferenceControl(external, @selector(reloadSkinsFromButton:));
    [NSApp sendAction:reload.action to:reload.target from:reload];
    assert([external.skinID isEqual:@"synthetic"]);
    assert([external resolvedSkinForDark:NO].id == "fluent" && !external.decorationImage);
    assert(control.numberOfItems == 4 && [control.selectedItem.representedObject isEqual:@"fluent"]);
    [controller appearanceChanged:nil];
    for (NSView *view in panel.contentView.subviews) assert(![view isKindOfClass:NSImageView.class]);
    panel.appearance = nil;
    std::filesystem::remove_all(root);
}

@interface CloudShortcutSession : ShortcutSession
@property(nonatomic, copy) NSDictionary *query;
@property(nonatomic) NSUInteger cloudApplications;
@end
@implementation CloudShortcutSession
- (NSDictionary *)onlineQueryWithError:(NSError **)error { (void)error; return self.query; }
- (NSDictionary *)applyCloudResponse:(NSData *)body query:(NSDictionary *)query error:(NSError **)error {
    (void)body; (void)error;
    assert([query isEqual:self.query] && NSThread.isMainThread);
    ++self.cloudApplications;
    NSMutableDictionary *updated = [self.query mutableCopy];
    updated[@"generation"] = @([updated[@"generation"] unsignedLongLongValue] + 1);
    self.query = updated;
    return @{@"applied":@YES, @"view":@{@"focused":@YES, @"preedit":@"synthetic", @"editing_text":@"synthetic", @"caret_position":@0, @"candidates":@[]}};
}
@end
@interface ControlledCloudRequest : MSIMECloudCandidateRequest
@property(nonatomic, copy) void (^reply)(NSData *);
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL cancelled;
@end
@implementation ControlledCloudRequest
- (void)start { self.started = YES; }
- (void)cancel { self.cancelled = YES; }
@end
@interface CloudShortcutController : ModeController
@property(nonatomic, strong) NSMutableArray<ControlledCloudRequest *> *requests;
@end
@implementation CloudShortcutController
- (MSIMECloudCandidateRequest *)cloudRequestForURL:(NSURL *)url completion:(void (^)(NSData *))completion {
    assert([url.host isEqual:@"inputtools.google.com"]);
    ControlledCloudRequest *request = [ControlledCloudRequest new];
    request.reply = completion;
    [self.requests addObject:request];
    return request;
}
- (void)renderCandidates {} // Keep the test independent of real panel placement.
@end

static void TestCloudCandidateScheduling() {
    CloudShortcutController *controller = [CloudShortcutController alloc];
    controller.requests = [NSMutableArray array];
    CloudShortcutSession *session = [CloudShortcutSession new];
    session.query = @{@"scheme":@0, @"generation":@1, @"identity":@"synthetic", @"query_text":@"nihao", @"cache_key":@"nihao", @"pinyin_segments":@[@"ni", @"hao"], @"cloud_eligible":@YES, @"ai_eligible":@NO, @"cloud_candidates":@YES, @"session_id":@1};
    ShortcutClient *client = [ShortcutClient new], *other = [ShortcutClient new];
    [controller setValue:session forKey:@"session"];
    [controller setValue:client forKey:@"activeClient"];
    [controller synchronizeCloudCandidates];
    NSTimer *timer = [controller valueForKey:@"cloudTimer"];
    assert(timer && timer.fireDate.timeIntervalSinceNow > 0.4 && controller.requests.count == 0);
    [controller synchronizeCloudCandidates];
    assert([controller valueForKey:@"cloudTimer"] == timer);
    [timer fire]; [timer invalidate];
    ControlledCloudRequest *first = controller.requests.lastObject;
    assert(first.started && controller.requests.count == 1);
    NSData *body = [@"synthetic" dataUsingEncoding:NSUTF8StringEncoding];
    first.reply(body);
    assert(session.cloudApplications == 1 && client.committed == nil && [client.marked isEqual:@"synthetic"]);
    assert([controller valueForKey:@"cloudTimer"] == nil); // No response-triggered request loop.
    [controller cancelCloudCandidates];
    [controller synchronizeCloudCandidates];
    timer = [controller valueForKey:@"cloudTimer"];
    [timer fire]; [timer invalidate];
    ControlledCloudRequest *stale = controller.requests.lastObject;
    [controller setValue:other forKey:@"activeClient"];
    stale.reply(body);
    assert(session.cloudApplications == 1);
    [controller cancelCloudCandidates];
    assert(stale.cancelled);
    [controller setValue:client forKey:@"activeClient"];
    [controller synchronizeCloudCandidates];
    timer = [controller valueForKey:@"cloudTimer"];
    [timer fire]; [timer invalidate];
    stale.reply(body); // A -> B -> A must still reject the old response.
    assert(session.cloudApplications == 1);
    ControlledCloudRequest *disabled = controller.requests.lastObject;
    NSMutableDictionary *query = [session.query mutableCopy];
    query[@"cloud_candidates"] = @NO;
    session.query = query;
    disabled.reply(body); // Recheck permission even before the next synchronization.
    assert(session.cloudApplications == 1);
    [controller synchronizeCloudCandidates];
    assert(disabled.cancelled && [controller valueForKey:@"cloudTimer"] == nil);
    query[@"cloud_candidates"] = @YES;
    session.query = query;
    [controller synchronizeCloudCandidates];
    timer = [controller valueForKey:@"cloudTimer"];
    session.query = nil; // Composition cancelled before debounce expires.
    [timer fire]; [timer invalidate];
    assert(controller.requests.count == 3);
    [controller cancelCloudCandidates];
    session.query = query;
    [controller synchronizeCloudCandidates];
    NSTimer *oldTimer = [controller valueForKey:@"cloudTimer"];
    NSMutableDictionary *newQuery = [query mutableCopy];
    newQuery[@"generation"] = @99;
    session.query = newQuery;
    [controller synchronizeCloudCandidates];
    assert(!oldTimer.valid);
    timer = [controller valueForKey:@"cloudTimer"];
    assert(timer != oldTimer);
    [timer fire]; [timer invalidate];
    ControlledCloudRequest *replaced = controller.requests.lastObject;
    [controller setValue:[CloudShortcutSession new] forKey:@"session"];
    replaced.reply(body);
    assert(session.cloudApplications == 1);
    [controller setValue:session forKey:@"session"];
    [controller snapshotSessionReplaced:[NSNotification notificationWithName:MSIMEClientSessionDidReplaceSnapshotNotification object:session]];
    assert(replaced.cancelled);
    replaced.reply(body);
    assert(session.cloudApplications == 1);
    [controller synchronizeCloudCandidates];
    assert([controller valueForKey:@"cloudTimer"] == nil);
    [controller setValue:@NO forKey:@"focusPending"];
    [controller synchronizeCloudCandidates];
    timer = [controller valueForKey:@"cloudTimer"];
    [timer fire]; [timer invalidate];
    ControlledCloudRequest *blurred = controller.requests.lastObject;
    Method base = class_getInstanceMethod(IMKInputController.class, @selector(deactivateServer:));
    IMP original = method_setImplementation(base, (IMP)RecordBaseDeactivation);
    [controller deactivateServer:other];
    assert(!blurred.cancelled);
    session.query = nil;
    [controller deactivateServer:client];
    assert(blurred.cancelled && [controller valueForKey:@"activeClient"] == nil);
    blurred.reply(body);
    assert(session.cloudApplications == 1);
    method_setImplementation(base, original);
}

static void TestAiCandidateEngineDelivery() {
    NSError *bridgeError = nil;
    NSDictionary *descriptor = [MSIMEClientSession aiHTTPRequest:@{
        @"config":@{@"enabled":@YES, @"provider":@"deepseek", @"endpoint":@"https://synthetic.invalid/chat", @"model":@"synthetic",
            @"token":@"synthetic-secret", @"candidate_limit":@3, @"prompt_id":@"custom_2", @"prompt_custom_2":@"synthetic prompt"},
        @"input":@{@"segmented_pinyin":@[@"ni", @"hao"], @"context":@"", @"candidate_limit":@3}} error:&bridgeError];
    assert(descriptor && !bridgeError && [descriptor[@"timeout_ms"] isEqual:@8000]);
    assert([descriptor[@"headers"][@"Authorization"] isEqual:@"Bearer synthetic-secret"]);
    assert([descriptor[@"body"][@"thinking"][@"type"] isEqual:@"disabled"]);
    NSData *response = [NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"message":@{@"content":
        @"{\"candidates\":[{\"text\":\"合成候选甲\"},{\"text\":\"合成候选乙\"}]}"}}]} options:0 error:nil];
    NSArray *parsed = [MSIMEClientSession parseAIResponse:response limit:3 error:&bridgeError];
    assert(!bridgeError && parsed.count == 2);
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableDictionary *options = [@{@"api_version":@1, @"preferences":@{@"scheme":@"quanpin", @"learning":@NO,
        @"candidate_page_size":@5, @"chinese_punctuation":@YES,
        @"ai_assistant":@{@"enabled":@YES, @"provider":@"openai", @"candidate_limit":@3}}} mutableCopy];
    for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
        options[name] = path;
    }
    NSError *error = nil;
    MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
    assert(session && !error);
    [session setFocused:YES error:&error];
    for (char byte : std::string("nihaoshijie")) [session typeASCII:byte shift:NO error:&error];
    NSDictionary *query = [session onlineQueryWithError:&error];
    assert(!error && [query[@"ai_eligible"] boolValue]);
    NSDictionary *applied = [session applyOnlineCandidates:parsed source:1 query:query error:&error];
    assert(!error && [applied[@"applied"] boolValue]);
    NSArray *candidates = applied[@"view"][@"candidates"];
    assert(candidates.count >= 2 && [candidates[0][@"text"] isEqual:@"合成候选甲"] && [candidates[1][@"text"] isEqual:@"合成候选乙"]);
    assert([candidates[0][@"source"] isEqual:@3] && [candidates[1][@"source"] isEqual:@3]);
    assert([applied[@"view"][@"editing_text"] isEqual:@"nihaoshijie"]);
    [session typeASCII:'a' shift:NO error:&error];
    applied = [session applyOnlineCandidates:@[@"过期候选"] source:1 query:query error:&error];
    assert(!error && ![applied[@"applied"] boolValue]);
    query = [session onlineQueryWithError:&error];
    applied = [session applyOnlineCandidates:@[@"甲", @"乙", @"丙", @"丁"] source:1 query:query error:&error];
    assert(!error && ![applied[@"applied"] boolValue]); // Configured limit, not just ABI limit.
    assert(![session applyOnlineCandidates:(id)@[@1] source:1 query:query error:&error] && error);
    error = nil;
    assert(![session applyOnlineCandidates:@[@"合成"] source:2 query:query error:&error] && error);
    error = nil;
    NSString *oversized = [@"x" stringByPaddingToLength:4097 withString:@"x" startingAtIndex:0];
    assert(![session applyOnlineCandidates:@[oversized] source:1 query:query error:&error] && error);
    error = nil;
    NSMutableDictionary *largeQuery = [query mutableCopy];
    largeQuery[@"synthetic"] = [@"x" stringByPaddingToLength:16385 withString:@"x" startingAtIndex:0];
    assert(![session applyOnlineCandidates:@[@"合成"] source:1 query:largeQuery error:&error] && error);
    error = nil;
    applied = [session applyOnlineCandidates:@[] source:1 query:query error:&error];
    assert(!error && ![applied[@"applied"] boolValue]);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
}
static void TestCloudCandidateEngineDelivery() {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableDictionary *options = [@{@"api_version":@1, @"preferences":@{@"scheme":@"quanpin", @"candidate_page_size":@5, @"chinese_punctuation":@YES, @"cloud_candidates":@YES, @"learning":@NO}} mutableCopy];
    for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
        options[name] = path;
    }
    NSError *error = nil;
    MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
    assert(session && !error);
    CloudShortcutController *controller = [CloudShortcutController alloc];
    controller.requests = [NSMutableArray array];
    ShortcutClient *client = [ShortcutClient new];
    [controller setValue:session forKey:@"session"];
    [controller setValue:client forKey:@"activeClient"];
    [controller apply:[session setFocused:YES error:&error]];
    for (char byte : std::string("nihao")) [controller apply:[session typeASCII:byte shift:NO error:&error]];
    assert(!error && controller.requests.count == 0);
    NSTimer *timer = [controller valueForKey:@"cloudTimer"];
    assert(timer);
    [timer fire]; [timer invalidate];
    assert(controller.requests.count == 1);
    controller.requests.lastObject.reply([@"[\"SUCCESS\", [[\"nihao\", [\"云端测试候选\"]]]]" dataUsingEncoding:NSUTF8StringEncoding]);
    NSDictionary *view = [session viewWithError:&error];
    assert(!error && [view[@"editing_text"] isEqual:@"nihao"]);
    assert([view[@"candidates"][0][@"text"] isEqual:@"云端测试候选"]);
    assert([view[@"candidates"][0][@"source"] isEqual:@2]);
    assert([CandidateDisplay(view[@"candidates"][0], NO) isEqual:@"云端测试候选 ☁️"]);
    assert(client.committed == nil && [controller valueForKey:@"cloudTimer"] == nil);
    // Add a synthetic packaged glossary, then exercise the actual background path.
    sqlite3 *glossDatabase = nullptr;
    assert(sqlite3_open([[options[@"resources"] stringByAppendingPathComponent:@"english.db"] fileSystemRepresentation], &glossDatabase) == SQLITE_OK);
    assert(sqlite3_exec(glossDatabase, "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);"
        "CREATE TABLE en_zh_glosses(english TEXT PRIMARY KEY,chinese_gloss TEXT NOT NULL);"
        "CREATE TABLE zh_en_glosses(chinese TEXT PRIMARY KEY,english_gloss TEXT NOT NULL);"
        "INSERT INTO zh_en_glosses VALUES('云端测试候选','synthetic glossary');", nullptr, nullptr, nullptr) == SQLITE_OK);
    assert(sqlite3_close(glossDatabase) == SQLITE_OK);
    [controller cancelCandidateGloss];
    [controller synchronizeCandidateGloss];
    NSDate *glossDeadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (![[session viewWithError:nil][@"candidates"][0][@"translation"] isEqual:@"synthetic glossary"] && glossDeadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert([[session viewWithError:nil][@"candidates"][0][@"translation"] isEqual:@"synthetic glossary"]);
    [controller applySharedToolbarPreferences:@{@"candidate_translations":@NO}];
    assert(![controller currentGlossRequest]);
    assert(![session viewWithError:nil][@"candidates"][0][@"translation"]);
    [controller apply:[session command:MSIME_COMMIT_CANDIDATE error:&error]];
    assert(!error && [client.committed isEqual:@"云端测试候选"] && client.marked.length == 0);
    assert([controller valueForKey:@"cloudTimer"] == nil);
    [controller cancelCloudCandidates];
    assert([session closeWithError:&error] && !error);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
}

static void TestCloudCandidatePreference() {
    NSString *suite = [@"msime.cloud.preference." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    NSButton *toggle = (id)PreferenceControl(prefs, @selector(cloudCandidatesChanged:));
    assert(prefs.cloudCandidates && toggle.state == NSControlStateValueOn);
    assert([toggle.title containsString:@"Google"]);
    assert(![prefs sharedPreferencesByMerging:@{}][@"cloud_candidates"]);
    assert([[prefs sharedPreferencesByMerging:@{@"cloud_candidates":@NO}][@"cloud_candidates"] isEqual:@NO]);
    __block NSUInteger saves = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    [prefs applySharedInputPreferences:@{@"cloud_candidates":@NO}];
    assert(!prefs.cloudCandidates && toggle.state == NSControlStateValueOff && saves == 0);
    for (id invalid in @[NSNull.null, @1, @"true"]) [prefs applySharedInputPreferences:@{@"cloud_candidates":invalid}];
    assert(!prefs.cloudCandidates && saves == 0);
    assert([defaults objectForKey:@"MSIMEClientCloudCandidates"] == nil);
    toggle.state = NSControlStateValueOn;
    [NSApp sendAction:toggle.action to:toggle.target from:toggle];
    assert(prefs.cloudCandidates && saves == 1);
    assert([[prefs sharedPreferencesByMerging:@{}][@"cloud_candidates"] isEqual:@YES]);
    CloudShortcutController *controller = [CloudShortcutController alloc];
    controller.requests = [NSMutableArray array];
    CloudShortcutSession *session = [CloudShortcutSession new];
    session.query = @{@"scheme":@0, @"generation":@1, @"identity":@"synthetic", @"query_text":@"nihao", @"cache_key":@"nihao", @"pinyin_segments":@[@"ni", @"hao"], @"cloud_eligible":@YES, @"ai_eligible":@NO, @"cloud_candidates":@YES, @"session_id":@1};
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:session forKey:@"session"];
    [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
    [controller synchronizeCloudCandidates];
    NSTimer *timer = [controller valueForKey:@"cloudTimer"];
    [timer fire]; [timer invalidate];
    assert(controller.requests.count == 1);
    ControlledCloudRequest *request = controller.requests.lastObject;
    toggle.state = NSControlStateValueOff;
    [NSApp sendAction:toggle.action to:toggle.target from:toggle];
    // Guard even before the notification handler runs or shared storage is saved.
    request.reply([@"synthetic" dataUsingEncoding:NSUTF8StringEncoding]);
    assert(session.cloudApplications == 0 && !prefs.cloudCandidates && saves == 2);
    [controller appearanceChanged:nil];
    assert(request.cancelled && [controller valueForKey:@"cloudTimer"] == nil);
    [controller synchronizeCloudCandidates];
    assert([controller valueForKey:@"cloudTimer"] == nil);
    assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults] cloudCandidates]);
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSError *error = nil;
    NSDictionary *snapshot = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(snapshot && !error);
    NSDictionary *merged = [prefs sharedPreferencesByMerging:snapshot[@"preferences"]];
    assert([merged[@"cloud_candidates"] isEqual:@NO]);
    assert([merged[@"ai_assistant"] isEqual:snapshot[@"preferences"][@"ai_assistant"]]);
    assert(([MSIMEClientSession savePreferencesInDirectory:root expectedRevision:[snapshot[@"revision"] unsignedLongLongValue]
        snapshot:@{@"format_version":@1, @"revision":snapshot[@"revision"], @"preferences":merged} error:&error] && !error));
    NSDictionary *loaded = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(loaded && !error && [loaded[@"preferences"][@"cloud_candidates"] isEqual:@NO]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [defaults removePersistentDomainForName:suite];
    MSIMEAppearancePreferences *fresh = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(fresh.cloudCandidates);
    [fresh applySharedInputPreferences:loaded[@"preferences"]];
    assert(!fresh.cloudCandidates);
    [controller cancelCloudCandidates];
    [prefs.window close];
    assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
}

@interface GlossSession : ShortcutSession
@property(nonatomic) NSUInteger applications;
@property(nonatomic) NSUInteger clears;
@property(nonatomic) BOOL enabled;
@property(nonatomic, copy) NSString *targetLanguage;
@property(nonatomic, copy) NSString *localMode;
@property(nonatomic) NSUInteger scheme;
@end
@implementation GlossSession
- (NSDictionary *)translationQueryWithError:(NSError **)error { (void)error; return self.enabled ? @{@"generation":@1, @"target_language":self.targetLanguage ?: @"en"} : nil; }
- (NSDictionary *)viewWithError:(NSError **)error { (void)error; return @{@"generation":@1, @"scheme":@(self.scheme), @"local_mode":self.localMode ?: @"none", @"candidates":@[@{@"text":@"hello", @"source":@4}]}; }
- (NSDictionary *)hostOptions { return @{@"resources":@"/synthetic"}; }
- (NSDictionary *)applyTranslations:(NSArray *)translations generation:(uint64_t)generation error:(NSError **)error {
    (void)error; assert(NSThread.isMainThread && generation == 1 && translations.count <= 1);
    if (translations.count) ++self.applications; else ++self.clears;
    return @{@"applied":@YES, @"view":[self viewWithError:nil]};
}
@end
@interface GlossController : CloudShortcutController
@property(nonatomic, strong) dispatch_semaphore_t started;
@property(nonatomic, strong) dispatch_semaphore_t released;
@property(nonatomic) NSUInteger lookups;
@end
@implementation GlossController
- (NSDictionary *)readCandidateGloss:(NSDictionary *)request resources:(NSString *)resources {
    assert(!NSThread.isMainThread && [resources isEqual:@"/synthetic"]);
    ++self.lookups;
    dispatch_semaphore_signal(self.started);
    assert(dispatch_semaphore_wait(self.released, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    return @{@"generation":request[@"generation"], @"translations":@[@{@"text":@"hello", @"translation":@"测试释义"}]};
}
@end
@interface CustomTranslationSession : GlossSession
@property(nonatomic, copy) NSDictionary *custom;
@property(nonatomic, copy) NSDictionary *tencent;
@property(nonatomic, copy) NSArray *page;
@property(nonatomic, copy) NSArray *delivered;
@property(nonatomic) uint64_t generation;
@property(nonatomic) BOOL offline;
@end
@implementation CustomTranslationSession
- (NSDictionary *)translationQueryWithError:(NSError **)error {
    (void)error;
    return self.enabled ? @{@"generation":@(self.generation), @"target_language":self.targetLanguage ?: @"en",
        @"custom_translation":self.custom ?: @{}, @"tencent_tmt":self.tencent ?: @{}} : nil;
}
- (NSDictionary *)viewWithError:(NSError **)error {
    (void)error;
    return @{@"generation":@(self.generation), @"scheme":@(self.scheme), @"local_mode":self.localMode ?: @"none", @"candidates":self.page ?: @[]};
}
- (NSDictionary *)hostOptions { return self.offline ? @{@"resources":@"/synthetic"} : @{}; }
- (NSDictionary *)applyTranslations:(NSArray *)translations generation:(uint64_t)generation error:(NSError **)error {
    (void)error;
    assert(NSThread.isMainThread && generation == self.generation);
    self.delivered = translations;
    return @{@"applied":@YES, @"view":[self viewWithError:nil]};
}
@end
@interface ControlledTranslationBatch : MSIMECustomTranslationBatch
@property(nonatomic, copy) void (^reply)(NSArray *);
@property(nonatomic, copy) NSArray *items;
@property(nonatomic, copy) NSDictionary *tencentConfig;
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL cancelled;
@end
@implementation ControlledTranslationBatch
- (void)start { assert(!self.started); self.started = YES; }
- (void)cancel { self.cancelled = YES; }
@end
@interface CustomTranslationController : CloudShortcutController
@property(nonatomic, strong) NSMutableArray<ControlledTranslationBatch *> *batches;
@property(nonatomic) BOOL useRealDelay;
@end
@implementation CustomTranslationController
- (NSTimer *)customTranslationTimerWithBlock:(void (^)(NSTimer *))block {
    if (self.useRealDelay) return [super customTranslationTimerWithBlock:block];
    block(nil); return nil;
}
- (MSIMECustomTranslationBatch *)customBatchForItems:(NSArray<NSDictionary *> *)items completion:(void (^)(NSArray<NSDictionary *> *))completion {
    ControlledTranslationBatch *batch = [ControlledTranslationBatch new];
    batch.reply = completion;
    batch.items = items;
    [self.batches addObject:batch];
    return batch;
}
- (NSDictionary *)readCandidateGloss:(NSDictionary *)request resources:(NSString *)resources {
    assert(!NSThread.isMainThread && [resources isEqual:@"/synthetic"]);
    return @{@"generation":request[@"generation"], @"translations":@[@{@"text":@"Hello", @"translation":@"本地释义"}]};
}
- (MSIMECustomTranslationBatch *)tencentBatchForItems:(NSArray<NSDictionary *> *)items config:(NSDictionary *)config
                                         completion:(void (^)(NSArray<NSDictionary *> *))completion {
    ControlledTranslationBatch *batch = (ControlledTranslationBatch *)[self customBatchForItems:items completion:completion];
    batch.tencentConfig = config;
    return batch;
}
@end
static NSDictionary *TencentConfig() {
    return @{@"enabled":@YES, @"secret_id":@"AKIDsynthetic", @"secret_key":@"synthetic", @"region":@"ap-guangzhou"};
}
static void WaitForGloss(CustomTranslationController *controller) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (![controller valueForKey:@"glossResults"] && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert([controller valueForKey:@"glossResults"]);
}
static void TestLearnedGlossRuntime() {
    [[MSIMETranslationCache sharedCache] clear];
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    CustomTranslationController *writer = [CustomTranslationController alloc]; writer.batches = [NSMutableArray array];
    CustomTranslationSession *session = [CustomTranslationSession new];
    session.enabled = YES; session.generation = 1; session.targetLanguage = @"en"; session.tencent = TencentConfig();
    session.page = @[@{@"text":@"Hello", @"source":@4}, @{@"text":@"测试", @"source":@0}];
    [writer setValue:session forKey:@"session"]; [writer setValue:[ShortcutClient new] forKey:@"activeClient"];
    [writer setValue:root forKey:@"preferencesDirectory"];
    [writer synchronizeCandidateGloss]; WaitForGloss(writer);
    [writer synchronizeCustomTranslations];
    assert(writer.batches.count == 1);
    writer.batches[0].reply(@[@{@"text":@"Hello", @"translation":@"学习释义"}, @{@"text":@"测试", @"translation":@"test"}]);
    dispatch_sync([MSIMEInputController learnedTranslationQueue], ^{});
    [writer cancelCandidateTranslations]; [[MSIMETranslationCache sharedCache] clear];
    // A new controller with both providers absent reuses the persisted glosses.
    CustomTranslationController *reader = [CustomTranslationController alloc]; reader.batches = [NSMutableArray array];
    session.tencent = nil; session.generation++;
    [reader setValue:session forKey:@"session"]; [reader setValue:[ShortcutClient new] forKey:@"activeClient"];
    [reader setValue:root forKey:@"preferencesDirectory"];
    [reader synchronizeCandidateGloss]; WaitForGloss(reader);
    assert(reader.batches.count == 0 && session.delivered.count == 2);
    assert([session.delivered[0][@"translation"] isEqual:@"学习释义"]);
    // Learned glossary entries override packaged values, matching Engine.
    [reader cancelCandidateTranslations]; session.offline = YES;
    [reader synchronizeCandidateGloss]; WaitForGloss(reader);
    assert(([session.delivered isEqual:@[@{@"text":@"Hello", @"translation":@"学习释义"}, @{@"text":@"测试", @"translation":@"test"}]]));
    [reader cancelCandidateTranslations]; session.offline = NO;
    [reader setValue:[root stringByAppendingPathComponent:@"another-profile"] forKey:@"preferencesDirectory"];
    [reader synchronizeCandidateGloss]; WaitForGloss(reader);
    assert(session.delivered.count == 0); // User directories cannot share learned words.
    [reader cancelCandidateTranslations]; [reader setValue:root forKey:@"preferencesDirectory"];
    session.targetLanguage = @"fr";
    assert(![reader currentGlossRequest]);
    // A stale online completion must not persist text, even if it is otherwise valid.
    session.targetLanguage = @"en"; session.tencent = TencentConfig();
    session.page = @[@{@"text":@"stale", @"source":@4}];
    [writer synchronizeCandidateGloss]; WaitForGloss(writer); [writer synchronizeCustomTranslations];
    ControlledTranslationBatch *pending = writer.batches.lastObject;
    session.generation++;
    pending.reply(@[@{@"text":@"stale", @"translation":@"不应保存"}]);
    dispatch_sync([MSIMEInputController learnedTranslationQueue], ^{});
    [writer cancelCandidateTranslations];
    session.tencent = nil; session.delivered = @[];
    [reader synchronizeCandidateGloss]; WaitForGloss(reader);
    assert(session.delivered.count == 0);
    [reader cancelCandidateTranslations];
    NSError *error = nil;
    assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
    [[MSIMETranslationCache sharedCache] clear];
}
static void TestTencentCandidateScheduling() {
    [[MSIMETranslationCache sharedCache] clear];
    CustomTranslationController *controller = [CustomTranslationController alloc];
    controller.batches = [NSMutableArray array];
    CustomTranslationSession *session = [CustomTranslationSession new];
    session.enabled = YES; session.generation = 1; session.targetLanguage = @"fr";
    session.tencent = TencentConfig();
    session.page = @[@{@"text":@"Hello", @"source":@4}, @{@"text":@"测试", @"source":@0}, @{@"text":@"smile", @"source":@6}];
    ShortcutClient *client = [ShortcutClient new];
    [controller setValue:session forKey:@"session"]; [controller setValue:client forKey:@"activeClient"];
    [controller applySharedToolbarPreferences:@{@"tencent_tmt":session.tencent}];
    [controller synchronizeCustomTranslations]; [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 1 && controller.batches[0].started);
    ControlledTranslationBatch *first = controller.batches[0];
    assert([first.tencentConfig isEqual:session.tencent] && first.items.count == 2);
    assert(([first.items[0] isEqual:@{@"text":@"Hello", @"key":@"hello", @"source_language":@"en", @"target_language":@"zh"}]));
    assert([first.items[1][@"target_language"] isEqual:@"fr"]);
    NSArray *online = @[@{@"text":@"Hello", @"translation":@"你好"}];
    first.reply(online); assert([session.delivered isEqual:online]);
    session.generation++; [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 1); // Positive and negative cache hits.
    // Custom remains authoritative, including a configured but invalid endpoint.
    session.custom = @{@"enabled":@YES, @"endpoint":@"", @"api_key":@""};
    [controller synchronizeCustomTranslations]; assert(controller.batches.count == 1);
    session.custom = @{@"enabled":@YES, @"endpoint":@"https://provider.invalid", @"api_key":@""};
    [controller synchronizeCustomTranslations]; assert(controller.batches.count == 2);
    assert(!controller.batches.lastObject.tencentConfig && controller.batches.lastObject.items.count == 2);
    controller.batches.lastObject.reply(@[@{@"text":@"Hello", @"translation":@"自定义"}]);
    session.custom = nil; [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 2 && [session.delivered isEqual:online]); // Provider cache isolation.
    for (NSString *field in @[@"secret_id", @"secret_key", @"region"]) {
        NSMutableDictionary *edited = [session.tencent mutableCopy];
        edited[field] = [field isEqual:@"region"] ? @"ap-shanghai" : @"syntheticReplacement";
        [controller applySharedToolbarPreferences:@{@"tencent_tmt":edited}];
        assert(![controller currentCustomTranslationRequest] && session.delivered.count == 0);
        session.tencent = edited;
        NSUInteger before = controller.batches.count;
        [controller synchronizeCustomTranslations];
        assert(controller.batches.count == before + 1 && controller.batches.lastObject.items.count == 2);
        controller.batches.lastObject.reply(online);
    }
    for (NSString *change in @[@"generation", @"page", @"client", @"session", @"focus", @"japanese", @"disabled"]) {
        [[MSIMETranslationCache sharedCache] clear];
        [controller cancelCandidateTranslations]; session.delivered = @[];
        [controller synchronizeCustomTranslations];
        ControlledTranslationBatch *pending = controller.batches.lastObject;
        NSArray *page = session.page;
        if ([change isEqual:@"generation"]) session.generation++;
        if ([change isEqual:@"page"]) session.page = @[];
        if ([change isEqual:@"client"]) [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
        if ([change isEqual:@"session"]) [controller setValue:[CustomTranslationSession new] forKey:@"session"];
        if ([change isEqual:@"focus"]) [controller setValue:@YES forKey:@"focusPending"];
        if ([change isEqual:@"japanese"]) session.localMode = @"temporary_japanese";
        if ([change isEqual:@"disabled"]) session.enabled = NO;
        pending.reply(online); assert(session.delivered.count == 0);
        [controller cancelCandidateTranslations]; assert(pending.cancelled);
        session.page = page; session.localMode = nil; session.enabled = YES;
        [controller setValue:session forKey:@"session"]; [controller setValue:client forKey:@"activeClient"];
        [controller setValue:@NO forKey:@"focusPending"];
    }
    session.targetLanguage = @"en"; session.offline = YES;
    [controller synchronizeCandidateGloss]; [controller synchronizeCustomTranslations];
    assert(![controller currentCustomTranslationRequest]);
    NSUInteger before = controller.batches.count;
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (controller.batches.count == before && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(controller.batches.count == before + 1);
    ControlledTranslationBatch *fallback = controller.batches.lastObject;
    assert(fallback.tencentConfig && fallback.items.count == 1 && [fallback.items[0][@"text"] isEqual:@"测试"]);
    fallback.reply(@[@{@"text":@"测试", @"translation":@"test"}]);
    assert(([session.delivered isEqual:@[@{@"text":@"Hello", @"translation":@"本地释义"}, @{@"text":@"测试", @"translation":@"test"}]]));
    [controller cancelCandidateTranslations]; [[MSIMETranslationCache sharedCache] clear];
    session.offline = NO;
    [controller synchronizeCandidateGloss];
    [controller synchronizeCustomTranslations];
    ControlledTranslationBatch *pending = controller.batches.lastObject;
    assert(pending != fallback && pending.started);
    NSMutableDictionary *disabled = [session.tencent mutableCopy]; disabled[@"enabled"] = @NO;
    [controller applySharedToolbarPreferences:@{@"tencent_tmt":disabled}];
    assert(pending.cancelled && ![controller currentCustomTranslationRequest] && session.delivered.count == 0);
    pending.reply(online); assert(session.delivered.count == 0);
    session.tencent = disabled; assert(![controller currentCustomTranslationRequest]);
    session.tencent = TencentConfig();
    [controller applySharedToolbarPreferences:@{@"tencent_tmt":session.tencent}];
    [controller synchronizeCandidateGloss];
    [controller synchronizeCustomTranslations]; pending = controller.batches.lastObject;
    // Pending custom enablement must block Tencent even before the query updates.
    NSDictionary *custom = @{@"enabled":@YES, @"endpoint":@"https://provider.invalid", @"api_key":@""};
    [controller applySharedToolbarPreferences:@{@"custom_translation":custom}];
    assert(pending.cancelled && ![controller currentCustomTranslationRequest]);
    pending.reply(online); assert(session.delivered.count == 0);
    [controller cancelCandidateTranslations]; [[MSIMETranslationCache sharedCache] clear];
}
static void TestCustomTranslationController() {
    CustomTranslationController *controller = [CustomTranslationController alloc];
    controller.batches = [NSMutableArray array];
    CustomTranslationSession *session = [CustomTranslationSession new];
    session.enabled = YES; session.generation = 1; session.targetLanguage = @"fr";
    session.custom = @{@"enabled":@YES, @"endpoint":@"https://translation.invalid/api", @"api_key":@""};
    session.page = @[@{@"text":@"Hello", @"source":@4}, @{@"text":@"测试", @"source":@0}, @{@"text":@"smile", @"source":@6}];
    ShortcutClient *client = [ShortcutClient new];
    [controller setValue:client forKey:@"activeClient"];
    [controller setValue:session forKey:@"session"];
    [controller synchronizeCandidateGloss];
    [controller synchronizeCustomTranslations];
    [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 1 && controller.batches[0].started);
    ControlledTranslationBatch *first = controller.batches[0];
    assert(first.items.count == 2);
    assert(([first.items[0][@"request"][@"body"] isEqual:@{@"text":@"hello", @"source_lang":@"EN", @"target_lang":@"ZH"}]));
    assert(([first.items[1][@"request"][@"body"] isEqual:@{@"text":@"测试", @"source_lang":@"ZH", @"target_lang":@"FR"}]));
    NSArray *online = @[@{@"text":@"Hello", @"translation":@"你好"}, @{@"text":@"测试", @"translation":@"essai"}];
    first.reply(online);
    assert([session.delivered isEqual:online] && controller.batches.count == 1);
    // A pending target change cancels work before Engine's applied snapshot changes.
    [controller applySharedToolbarPreferences:@{@"translation_target_language":@"de"}];
    assert(session.delivered.count == 0 && ![controller currentCustomTranslationRequest]);
    first.reply(online);
    assert(session.delivered.count == 0);
    session.targetLanguage = @"de";
    [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 2);
    ControlledTranslationBatch *second = controller.batches.lastObject;
    assert([second.items[1][@"request"][@"body"][@"target_lang"] isEqual:@"DE"]);
    // Candidate identity, generation, client, session, focus and mode guards all
    // reject a callback even before the next synchronization cancels transport.
    for (NSString *change in @[@"generation", @"page", @"client", @"session", @"focus", @"japanese", @"disabled"]) {
        [controller cancelCandidateTranslations];
        [controller synchronizeCustomTranslations];
        ControlledTranslationBatch *batch = controller.batches.lastObject;
        NSArray *page = session.page;
        if ([change isEqual:@"generation"]) session.generation++;
        if ([change isEqual:@"page"]) session.page = @[@{@"text":@"different", @"source":@0}];
        if ([change isEqual:@"client"]) [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
        if ([change isEqual:@"session"]) [controller setValue:[CustomTranslationSession new] forKey:@"session"];
        if ([change isEqual:@"focus"]) [controller setValue:@YES forKey:@"focusPending"];
        if ([change isEqual:@"japanese"]) session.localMode = @"temporary_japanese";
        if ([change isEqual:@"disabled"]) session.enabled = NO;
        batch.reply(online);
        assert(session.delivered.count == 0);
        [controller cancelCandidateTranslations];
        assert(batch.cancelled);
        session.page = page; session.localMode = nil; session.enabled = YES;
        [controller setValue:session forKey:@"session"];
        [controller setValue:client forKey:@"activeClient"];
        [controller setValue:@NO forKey:@"focusPending"];
    }
    [controller synchronizeCustomTranslations];
    ControlledTranslationBatch *pending = controller.batches.lastObject;
    NSDictionary *disabled = @{@"enabled":@NO, @"endpoint":@"https://translation.invalid/api", @"api_key":@""};
    [controller applySharedToolbarPreferences:@{@"custom_translation":disabled}];
    assert(pending.cancelled && ![controller currentCustomTranslationRequest]);
    pending.reply(online);
    assert(session.delivered.count == 0);
    [controller applySharedToolbarPreferences:@{@"custom_translation":session.custom, @"translation_target_language":@"en"}];
    session.targetLanguage = @"en"; session.offline = YES;
    [controller synchronizeCandidateGloss];
    [controller synchronizeCustomTranslations];
    assert(![controller currentCustomTranslationRequest]); // Wait for offline lookup.
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    NSUInteger previous = controller.batches.count;
    while (controller.batches.count == previous && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(controller.batches.count == previous + 1);
    ControlledTranslationBatch *fallback = controller.batches.lastObject;
    assert(fallback.items.count == 1 && [fallback.items[0][@"text"] isEqual:@"测试"]);
    fallback.reply(@[@{@"text":@"测试", @"translation":@"test"}]);
    assert(([session.delivered isEqual:@[@{@"text":@"Hello", @"translation":@"本地释义"}, @{@"text":@"测试", @"translation":@"test"}]]));
    [controller synchronizeCandidateGloss]; [controller synchronizeCustomTranslations];
    assert(controller.batches.lastObject == fallback);
    [controller cancelCandidateTranslations];
    // The native toggle is authoritative even before persistence/notification.
    session.offline = NO;
    [controller synchronizeCandidateGloss]; [controller synchronizeCustomTranslations];
    ControlledTranslationBatch *nativePending = controller.batches.lastObject;
    NSString *suite = [@"msime.custom.translation." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    [controller setValue:prefs forKey:@"appearance"];
    prefs.candidateTranslations = NO;
    assert(![controller currentCustomTranslationRequest]);
    [controller appearanceChanged:nil];
    assert(nativePending.cancelled && session.delivered.count == 0);
    nativePending.reply(online);
    assert(session.delivered.count == 0);
    [prefs.window close];
    [defaults removePersistentDomainForName:suite];
}
static void TestCustomTranslationCacheDelivery() {
    [[MSIMETranslationCache sharedCache] clear];
    CustomTranslationController *controller = [CustomTranslationController alloc];
    controller.batches = [NSMutableArray array];
    CustomTranslationSession *session = [CustomTranslationSession new];
    session.enabled = YES; session.generation = 1; session.targetLanguage = @"fr";
    session.custom = @{@"enabled":@YES, @"endpoint":@"https://cache.invalid/api", @"api_key":@""};
    session.page = @[@{@"text":@"Hello", @"source":@4}];
    [controller setValue:session forKey:@"session"];
    [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
    [controller applySharedToolbarPreferences:@{@"custom_translation":session.custom}];
    [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 1);
    controller.batches[0].reply(@[@{@"text":@"Hello", @"translation":@"你好"}]);
    [controller cancelCandidateTranslations]; session.generation++;
    session.page = @[@{@"text":@"HELLO", @"source":@4}];
    [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 1);
    assert(([session.delivered isEqual:@[@{@"text":@"HELLO", @"translation":@"你好"}]]));
    session.generation++; session.page = @[@{@"text":@"HELLO", @"source":@4}, @{@"text":@"missing", @"source":@4}];
    [controller synchronizeCustomTranslations]; assert(controller.batches.count == 2);
    assert(controller.batches[1].items.count == 1 && [controller.batches[1].items[0][@"text"] isEqual:@"missing"]);
    controller.batches[1].reply(@[]);
    assert(([session.delivered isEqual:@[@{@"text":@"HELLO", @"translation":@"你好"}]]));
    session.generation++; [controller synchronizeCustomTranslations];
    assert(controller.batches.count == 2);
    // A credential edit invalidates failure suppression without putting a key
    // in the cache identity; a subsequent generation may retry immediately.
    session.custom = @{@"enabled":@YES, @"endpoint":@"https://cache.invalid/api", @"api_key":@"synthetic"};
    [controller applySharedToolbarPreferences:@{@"custom_translation":session.custom}];
    [controller synchronizeCustomTranslations]; assert(controller.batches.count == 3);
    controller.batches[2].reply(@[@{@"text":@"missing", @"translation":@"找到"}]);
    session.targetLanguage = @"de"; session.generation++;
    [controller synchronizeCustomTranslations]; assert(controller.batches.count == 4);
    [controller cancelCandidateTranslations];
    [[MSIMETranslationCache sharedCache] clear];
}
static void TestCustomTranslationIdleDelay(BOOL tencent) {
    [[MSIMETranslationCache sharedCache] clear];
    CustomTranslationController *controller = [CustomTranslationController alloc];
    controller.useRealDelay = YES; controller.batches = [NSMutableArray array];
    CustomTranslationSession *session = [CustomTranslationSession new];
    session.enabled = YES; session.generation = 1; session.targetLanguage = @"fr";
    session.custom = @{@"enabled":@YES, @"endpoint":@"https://idle.invalid/api", @"api_key":@""};
    if (tencent) { session.custom = nil; session.tencent = TencentConfig(); }
    session.page = @[@{@"text":@"hello", @"source":@4}];
    [controller setValue:session forKey:@"session"];
    [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
    [controller synchronizeCustomTranslations];
    NSTimer *first = [controller valueForKey:@"customTimer"];
    assert(first.valid && first.fireDate.timeIntervalSinceNow > 0.4 && first.fireDate.timeIntervalSinceNow <= 0.5);
    [controller synchronizeCustomTranslations];
    assert(first == [controller valueForKey:@"customTimer"]);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    assert(controller.batches.count == 0);
    session.generation++; session.page = @[@{@"text":@"newest", @"source":@4}];
    [controller synchronizeCustomTranslations];
    NSTimer *second = [controller valueForKey:@"customTimer"];
    assert(!first.valid && second.valid && second != first);
    [first fire]; assert(controller.batches.count == 0);
    [controller setValue:@YES forKey:@"focusPending"];
    [second fire];
    assert(controller.batches.count == 0 && ![controller valueForKey:@"customTimer"]);
    [controller cancelCandidateTranslations];
    [controller setValue:@NO forKey:@"focusPending"];
    [controller synchronizeCustomTranslations];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (!controller.batches.count && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(controller.batches.count == 1 && [controller.batches[0].items[0][@"text"] isEqual:@"newest"]);
    controller.batches[0].reply(@[@{@"text":@"newest", @"translation":@"最新"}]);
    session.generation++;
    [controller synchronizeCustomTranslations];
    assert(![controller valueForKey:@"customTimer"] && controller.batches.count == 1);
    assert(session.delivered.count == 1); // Cache hits never incur the delay.
    session.generation++; session.page = @[@{@"text":@"cancelled", @"source":@4}];
    [controller synchronizeCustomTranslations];
    NSTimer *cancelled = [controller valueForKey:@"customTimer"];
    [controller cancelCandidateTranslations]; [cancelled fire];
    assert(!cancelled.valid && controller.batches.count == 1);
    [[MSIMETranslationCache sharedCache] clear];
}
static void TestGlossScheduling() {
    GlossController *controller = [GlossController alloc];
    controller.started = dispatch_semaphore_create(0);
    controller.released = dispatch_semaphore_create(0);
    GlossSession *session = [GlossSession new]; session.enabled = YES;
    ShortcutClient *a = [ShortcutClient new], *b = [ShortcutClient new];
    [controller setValue:session forKey:@"session"];
    [controller setValue:a forKey:@"activeClient"];
    [controller synchronizeCandidateGloss];
    assert(dispatch_semaphore_wait(controller.started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    [controller synchronizeCandidateGloss]; // Identical view must not duplicate work.
    [controller cancelCandidateGloss];
    [controller setValue:b forKey:@"activeClient"];
    [controller synchronizeCandidateGloss];
    dispatch_semaphore_signal(controller.released);
    assert(dispatch_semaphore_wait(controller.started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(session.applications == 0);
    dispatch_semaphore_signal(controller.released);
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
    while (session.applications == 0 && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(session.applications == 1 && controller.lookups == 2);
    [controller synchronizeCandidateGloss];
    assert(controller.lookups == 2);
    [controller cancelCandidateGloss];
}

static void TestCandidateTranslationPreference() {
    NSString *suite = [@"msime.gloss.preference." stringByAppendingString:NSUUID.UUID.UUIDString];
    NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
    MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    NSButton *toggle = (id)PreferenceControl(prefs, @selector(candidateTranslationsChanged:));
    assert(prefs.candidateTranslations && toggle.state == NSControlStateValueOn);
    assert(![prefs sharedPreferencesByMerging:@{}][@"candidate_translations"]);
    assert([[prefs sharedPreferencesByMerging:@{@"candidate_translations":@NO}][@"candidate_translations"] isEqual:@NO]);
    __block NSUInteger saves = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++saves; }];
    [prefs applySharedInputPreferences:@{@"candidate_translations":@NO}];
    assert(!prefs.candidateTranslations && toggle.state == NSControlStateValueOff && saves == 0);
    for (id invalid in @[NSNull.null, @1, @"true"]) [prefs applySharedInputPreferences:@{@"candidate_translations":invalid}];
    assert(!prefs.candidateTranslations && saves == 0 && ![defaults objectForKey:@"MSIMEClientCandidateTranslations"]);
    toggle.state = NSControlStateValueOn;
    [NSApp sendAction:toggle.action to:toggle.target from:toggle];
    assert(prefs.candidateTranslations && saves == 1);
    GlossController *controller = [GlossController alloc];
    controller.started = dispatch_semaphore_create(0);
    controller.released = dispatch_semaphore_create(0);
    GlossSession *session = [GlossSession new]; session.enabled = YES;
    [controller setValue:prefs forKey:@"appearance"];
    [controller setValue:session forKey:@"session"];
    [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
    [controller synchronizeCandidateGloss];
    assert(dispatch_semaphore_wait(controller.started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    toggle.state = NSControlStateValueOff;
    [NSApp sendAction:toggle.action to:toggle.target from:toggle];
    assert(![controller currentGlossRequest] && saves == 2);
    [controller appearanceChanged:nil];
    assert(session.clears == 1);
    dispatch_semaphore_signal(controller.released);
    [(NSOperationQueue *)[controller valueForKey:@"glossQueue"] waitUntilAllOperationsAreFinished];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(session.applications == 0);
    assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults] candidateTranslations]);
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSError *error = nil;
    NSDictionary *snapshot = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(snapshot && !error);
    NSDictionary *merged = [prefs sharedPreferencesByMerging:snapshot[@"preferences"]];
    assert([merged[@"candidate_translations"] isEqual:@NO]);
    assert([merged[@"custom_translation"] isEqual:snapshot[@"preferences"][@"custom_translation"]]);
    NSDictionary *saved = [MSIMEClientSession savePreferencesInDirectory:root expectedRevision:[snapshot[@"revision"] unsignedLongLongValue]
        snapshot:@{@"format_version":@1, @"revision":snapshot[@"revision"], @"preferences":merged} error:&error];
    assert(saved && !error);
    NSDictionary *loaded = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(loaded && !error && [loaded[@"preferences"][@"candidate_translations"] isEqual:@NO]);
    [prefs setTranslationPreferencesDirectory:root];
    NSControl *translationEntry = PreferenceControl(prefs, @selector(showTranslationSettings:));
    assert(translationEntry);
    [NSApp sendAction:translationEntry.action to:translationEntry.target from:translationEntry];
    NSWindowController *translationWindow = [prefs valueForKey:@"translationWindow"];
    assert(translationWindow.window.visible);
    [translationWindow close];
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    [defaults removePersistentDomainForName:suite];
    MSIMEAppearancePreferences *fresh = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
    assert(fresh.candidateTranslations);
    [fresh applySharedInputPreferences:loaded[@"preferences"]];
    assert(!fresh.candidateTranslations);
    [prefs.window close];
    [controller cancelCandidateGloss];
    assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
}

static void TestGlossModePolicy() {
    GlossController *controller = [GlossController alloc];
    controller.started = dispatch_semaphore_create(0);
    controller.released = dispatch_semaphore_create(0);
    GlossSession *session = [GlossSession new]; session.enabled = YES;
    [controller setValue:session forKey:@"session"];
    [controller setValue:[ShortcutClient new] forKey:@"activeClient"];
    assert([controller currentGlossRequest]);
    for (NSString *target in @[@"fr", @"ja", @"es", @"ru", @"de", @"ko", @"unknown"]) {
        session.targetLanguage = target;
        assert(![controller currentGlossRequest]);
    }
    session.targetLanguage = @"en";
    session.scheme = 3;
    assert(![controller currentGlossRequest]);
    for (NSNumber *scheme in @[@0, @1]) {
        session.scheme = scheme.unsignedIntegerValue;
        session.localMode = @"temporary_japanese";
        assert(![controller currentGlossRequest]);
    }
    session.localMode = @"none";
    assert([controller currentGlossRequest]);
    [controller synchronizeCandidateGloss];
    assert(dispatch_semaphore_wait(controller.started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    // Requested settings take effect before the Engine applies its deferred snapshot.
    [controller applySharedToolbarPreferences:@{@"translation_target_language":@"fr"}];
    assert(![controller currentGlossRequest] && session.clears == 1);
    dispatch_semaphore_signal(controller.released);
    [(NSOperationQueue *)[controller valueForKey:@"glossQueue"] waitUntilAllOperationsAreFinished];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(session.applications == 0);
    [controller applySharedToolbarPreferences:@{@"translation_target_language":@"en"}];
    assert([controller currentGlossRequest]);
    [controller synchronizeCandidateGloss];
    assert(dispatch_semaphore_wait(controller.started, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
    session.localMode = @"temporary_japanese";
    dispatch_semaphore_signal(controller.released);
    [(NSOperationQueue *)[controller valueForKey:@"glossQueue"] waitUntilAllOperationsAreFinished];
    [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    assert(session.applications == 0);
    [controller cancelCandidateGloss];
}

int main() {
    assert(!MSIMEShouldRegisterInputSource(1, nullptr));
    const char *registerArguments[] = {"test", "--register-input-source"};
    assert(MSIMEShouldRegisterInputSource(2, registerArguments));
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSUserDefaults *standardDefaults = NSUserDefaults.standardUserDefaults;
        id previousVoiceHoldSpace = [standardDefaults objectForKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
        [standardDefaults setBool:NO forKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
        TestCloudCandidateScheduling();
        TestCloudCandidateEngineDelivery();
        TestAiCandidateEngineDelivery();
        TestCloudCandidatePreference();
        TestGlossScheduling();
        TestCustomTranslationController();
        TestCustomTranslationCacheDelivery();
        TestCustomTranslationIdleDelay(NO);
        TestCustomTranslationIdleDelay(YES);
        TestTencentCandidateScheduling();
        TestLearnedGlossRuntime();
        TestCandidateTranslationPreference();
        TestGlossModePolicy();
        TestSharedInputPreferences();
        TestIndependentAssistancePreferences();
        TestSharedPunctuation();
        TestSharedTraditionalOutput();
        TestPageSizeCache();
        NSString *suite = [@"app.msime.test.appearance." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *appearance = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        assert(!appearance.vertical && appearance.fontSize == 18);
        assert(appearance.candidateFollowCursor);
        assert(appearance.pageShortcut == 0);
        assert(appearance.pageSize == 9);
        assert([appearance.skinID isEqual:@"fluent"]);
        appearance.skinID = @"../invalid";
        assert([appearance.skinID isEqual:@"fluent"]);
        appearance.pageSize = 10;
        assert(appearance.pageSize == 9);
        appearance.pageShortcut = 99;
        assert(appearance.pageShortcut == 0);
        appearance.fontSize = 99;
        assert(appearance.fontSize == 18);
        NSPopUpButton *layoutControl = (id)PreferenceControl(appearance, @selector(layoutChanged:));
        NSPopUpButton *fontControl = (id)PreferenceControl(appearance, @selector(fontChanged:));
        NSPopUpButton *shortcutControl = (id)PreferenceControl(appearance, @selector(pageShortcutChanged:));
        NSPopUpButton *sizeControl = (id)PreferenceControl(appearance, @selector(pageSizeChanged:));
        NSPopUpButton *skinControl = (id)PreferenceControl(appearance, @selector(skinChanged:));
        NSButton *followCursorControl = (id)PreferenceControl(appearance, @selector(candidateFollowCursorChanged:));
        assert(followCursorControl.state == NSControlStateValueOn);
        [followCursorControl setState:NSControlStateValueOff];
        [NSApp sendAction:followCursorControl.action to:followCursorControl.target from:followCursorControl];
        assert(!appearance.candidateFollowCursor);
        MSIMEAppearancePreferences *followCursorLoaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        assert(!followCursorLoaded.candidateFollowCursor);
        assert([[[appearance sharedPreferencesByMerging:@{}] objectForKey:@"candidate_follow_cursor"] isEqual:@NO]);
        [appearance applySharedCandidatePreferences:@{@"candidate_follow_cursor": @YES}];
        assert(appearance.candidateFollowCursor);
        assert(([skinControl.itemTitles isEqual:@[@"Fluent", @"微信绿", @"石墨 Graphite", @"杨柳青"]]));
        NSArray<NSString *> *skinIDs = @[@"fluent", @"wechat", @"graphite", @"willow_green"];
        for (NSInteger option = 0; option < 4; ++option) {
            [skinControl selectItemAtIndex:option];
            [NSApp sendAction:skinControl.action to:skinControl.target from:skinControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert([loaded.skinID isEqual:skinIDs[option]]);
        }
        appearance.skinID = @"fluent";
        assert(sizeControl.numberOfItems == 9);
        for (NSInteger option = 0; option < 9; ++option) {
            assert(([sizeControl.itemTitles[option] isEqual:[NSString stringWithFormat:@"%ld 个", option + 1]]));
            [sizeControl selectItemAtIndex:option];
            [NSApp sendAction:sizeControl.action to:sizeControl.target from:sizeControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert(loaded.pageSize == (NSUInteger)option + 1);
        }
        assert(([shortcutControl.itemTitles isEqual:@[@"- / =", @"[ / ]", @"Page Up / Page Down"]]));
        for (NSInteger option = 0; option < 3; ++option) {
            [shortcutControl selectItemAtIndex:option];
            [NSApp sendAction:shortcutControl.action to:shortcutControl.target from:shortcutControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert(loaded.pageShortcut == option);
        }
        appearance.pageShortcut = 0;
        assert(([layoutControl.itemTitles isEqual:@[@"横向排列", @"纵向列表"]]));
        [layoutControl selectItemAtIndex:1];
        [NSApp sendAction:layoutControl.action to:layoutControl.target from:layoutControl];
        assert(fontControl.numberOfItems == 21);
        for (NSInteger option = 0; option < 21; ++option) {
            [fontControl selectItemAtIndex:option];
            [NSApp sendAction:fontControl.action to:fontControl.target from:fontControl];
            MSIMEAppearancePreferences *loaded = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
            assert(loaded.fontSize == (NSUInteger)option + 12);
            assert(([fontControl.titleOfSelectedItem isEqual:[NSString stringWithFormat:@"%ld pt", option + 12]]));
        }
        [fontControl selectItemAtIndex:4];
        [NSApp sendAction:fontControl.action to:fontControl.target from:fontControl];
        MSIMEAppearancePreferences *reopened = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        assert(reopened.vertical && reopened.fontSize == 16);
        appearance.fontSize = 18;
        MSIMECandidatePanel *focusPanel = [[MSIMECandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        assert(!focusPanel.canBecomeKeyWindow && !focusPanel.canBecomeMainWindow);
        MSIMECandidateButton *focusButton = [[MSIMECandidateButton alloc] initWithFrame:NSZeroRect];
        assert(!focusButton.acceptsFirstResponder);
        assert([focusButton acceptsFirstMouse:nil]);
        assert(!MSIMEValidCaret(NSZeroRect));
        assert(!MSIMEValidCaret(NSMakeRect(NAN, 0, 1, 20)));
        assert(!MSIMEValidCaret(NSMakeRect(0, INFINITY, 1, 20)));
        assert(!MSIMEValidCaret(NSMakeRect(0, 0, INFINITY, 20)));
        assert(!MSIMEValidCaret(NSMakeRect(0, 0, 1, -1)));
        assert(MSIMEValidCaret(NSMakeRect(-500, -200, 0, 20)));
        NSRect bounds = NSMakeRect(0, 0, 1000, 800);
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(100, 500, 1, 20), NSMakeSize(200, 100), bounds), NSMakePoint(100, 396)));
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(950, 20, 1, 20), NSMakeSize(200, 100), bounds), NSMakePoint(800, 44)));
        // Oversized content anchors at the visible origin, never outside both edges.
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(950, 20, 1, 20), NSMakeSize(1200, 900), bounds), NSZeroPoint));
        bounds = NSMakeRect(-1000, -800, 1000, 800);
        assert(NSEqualPoints(MSIMECandidateOrigin(NSMakeRect(-50, -780, 1, 20), NSMakeSize(200, 100), bounds), NSMakePoint(-200, -756)));
        // Inject a session and client without registering a system input source.
        MSIMEInputController *controller = [MSIMEInputController alloc];
        ShortcutSession *session = [ShortcutSession new];
        ShortcutClient *client = [ShortcutClient new];
        [controller setValue:session forKey:@"session"];
        [controller setValue:client forKey:@"activeClient"];
        [controller setValue:appearance forKey:@"appearance"];
        [controller syncPageSize];
        assert(session.requestedPageSize == 9);
        appearance.pageSize = 5;
        [controller appearanceChanged:nil];
        assert(session.requestedPageSize == 5);
        for (NSNumber *flags in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagControl), @(NSEventModifierFlagOption)]) {
            session.lastCommand = UINT32_MAX;
            client.committed = nil;
            client.marked = @"ceshi";
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:flags.unsignedIntegerValue timestamp:0 windowNumber:0 context:nil characters:@"a" charactersIgnoringModifiers:@"a" isARepeat:NO keyCode:0];
            assert(![controller handleEvent:event client:client]);
            assert(session.lastCommand == MSIME_FINISH_COMPOSITION);
            assert([client.committed isEqualToString:@"测试"]);
            assert(client.marked.length == 0);
        }
        TestCandidatePanel *panel = [TestCandidatePanel new];
        [controller setValue:panel forKey:@"panel"];
        for (NSNumber *key in @[@123, @124]) {
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            panel.visible = YES;
            session.lastCommand = UINT32_MAX;
            client.committed = nil;
            client.marked = @"ceshi";
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == UINT32_MAX);
            assert(client.committed == nil && [client.marked isEqualToString:@"ceshi"]);
            panel.visible = NO;
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == (key.unsignedShortValue == 123 ? MSIME_MOVE_LEFT : MSIME_MOVE_RIGHT));
        }
        HiddenCandidatePanel *layoutPanel = [[HiddenCandidatePanel alloc] initWithContentRect:NSZeroRect styleMask:NSWindowStyleMaskBorderless | NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
        for (NSNumber *key in @[@115, @119]) {
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            panel.visible = YES;
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == (key.unsignedShortValue == 115 ? MSIME_FIRST_CANDIDATE_ON_PAGE : MSIME_LAST_CANDIDATE_ON_PAGE));
            panel.visible = NO;
            assert([controller handleEvent:event client:client]);
            assert(session.lastCommand == (key.unsignedShortValue == 115 ? MSIME_MOVE_HOME : MSIME_MOVE_END));
        }
        [controller setValue:layoutPanel forKey:@"panel"];
        client.caret = NSMakeRect(NSMidX(NSScreen.mainScreen.visibleFrame), NSMidY(NSScreen.mainScreen.visibleFrame), 1, 20);
        appearance.candidateFollowCursor = NO;
        [controller setValue:@{@"candidates": @[@{@"text": @"测试", @"highlighted": @YES}]} forKey:@"view"];
        [controller renderCandidates];
        assert(layoutPanel.requestedVisible);
        NSPoint anchoredCandidateOrigin = layoutPanel.frame.origin;
        NSRect visibleFrame = NSScreen.mainScreen.visibleFrame;
        client.caret = NSMakeRect(NSMaxX(visibleFrame) - 120, NSMinY(visibleFrame) + 120, 1, 20);
        [controller renderCandidates];
        assert(NSEqualPoints(layoutPanel.frame.origin, anchoredCandidateOrigin));
        appearance.candidateFollowCursor = YES;
        [controller renderCandidates];
        assert(!NSEqualPoints(layoutPanel.frame.origin, anchoredCandidateOrigin));
        CGFloat shortWidth = layoutPanel.frame.size.width;
        [controller setValue:@{@"candidates": @[@{@"text": @"合成候选布局测试文本", @"highlighted": @YES}]} forKey:@"view"];
        [controller renderCandidates];
        assert(layoutPanel.frame.size.width > shortWidth);
        NSButton *rendered = (NSButton *)layoutPanel.contentView.subviews.firstObject;
        assert(rendered.font.pointSize == 18);
        assert([rendered.toolTip isEqualToString:@"合成候选布局测试文本"]);
        assert(rendered.lineBreakMode == NSLineBreakByTruncatingTail);
        client.caret = NSZeroRect;
        [controller renderCandidates];
        assert(!layoutPanel.requestedVisible);
        client.caret = NSMakeRect(NSMidX(NSScreen.mainScreen.visibleFrame), NSMidY(NSScreen.mainScreen.visibleFrame), 1, 20);
        NSMutableDictionary *pageView = [@{@"session": @1, @"generation": @2, @"focused": @YES, @"page": @0, @"page_count": @3, @"editing_text": @"ceshi", @"caret_position": @5, @"candidates": @[@{@"text": @"测试", @"highlighted": @YES}]} mutableCopy];
        [controller setValue:[pageView copy] forKey:@"view"];
        [controller renderCandidates];
        MSIMECandidateButton *previous = (id)PageButton(layoutPanel.contentView, -1);
        MSIMECandidateButton *next = (id)PageButton(layoutPanel.contentView, -2);
        assert(previous && next && !previous.enabled && next.enabled);
        assert([previous.accessibilityLabel isEqual:@"上一页候选"]);
        assert([next.accessibilityLabel isEqual:@"下一页候选"]);
        assert(previous.frame.size.height == 26 && next.frame.size.width == 28);
        // A layout-only render can keep all Engine IDs unchanged. The detached
        // button must still be rejected, just like detached candidate buttons.
        MSIMECandidateButton *oldPageButton = next;
        [controller renderCandidates];
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:oldPageButton];
        assert(session.lastCommand == UINT32_MAX && oldPageButton.superview != layoutPanel.contentView);
        next = (id)PageButton(layoutPanel.contentView, -2);
        NSDictionary *pageIdentity = next.candidateID;
        for (NSString *field in @[@"session", @"generation", @"page", @"page_count", @"focused"]) {
            for (id invalid in @[NSNull.null, @YES, @(-1), @1.5, @"1"]) {
                NSMutableDictionary *bad = [pageView mutableCopy];
                bad[field] = [field isEqual:@"focused"] && [invalid isEqual:@YES] ? @1 : invalid;
                next.candidateID = bad;
                [controller setValue:bad forKey:@"view"];
                session.lastCommand = UINT32_MAX;
                [controller changeCandidatePage:next];
                assert(session.lastCommand == UINT32_MAX);
            }
        }
        for (NSNumber *invalidCount in @[@0, @1]) {
            NSMutableDictionary *bad = [pageView mutableCopy];
            bad[@"page"] = @1; bad[@"page_count"] = invalidCount;
            next.candidateID = bad;
            [controller setValue:bad forKey:@"view"];
            session.lastCommand = UINT32_MAX;
            [controller changeCandidatePage:next];
            assert(session.lastCommand == UINT32_MAX);
        }
        next.candidateID = pageIdentity;
        [controller setValue:[pageView copy] forKey:@"view"];
        pageView[@"page"] = @1;
        session.nextTransition = @{@"handled": @YES, @"commit": NSNull.null, @"view": [pageView copy]};
        client.committed = nil;
        [next performClick:nil];
        assert(session.lastCommand == MSIME_NEXT_PAGE && client.committed == nil);
        assert([client.marked isEqual:@"ceshi"]);
        // A previous page's retained button must not advance the current page.
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:next];
        assert(session.lastCommand == UINT32_MAX);
        previous = (id)PageButton(layoutPanel.contentView, -1);
        next = (id)PageButton(layoutPanel.contentView, -2);
        assert(previous.enabled && next.enabled);
        pageView[@"page"] = @0;
        session.nextTransition = @{@"handled": @YES, @"commit": NSNull.null, @"view": [pageView copy]};
        [previous performClick:nil];
        assert(session.lastCommand == MSIME_PREVIOUS_PAGE);
        for (NSString *changed in @[@"session", @"generation", @"focused"]) {
            [controller setValue:[pageView copy] forKey:@"view"];
            [controller renderCandidates];
            next = (id)PageButton(layoutPanel.contentView, -2);
            NSMutableDictionary *stale = [pageView mutableCopy];
            stale[changed] = [changed isEqual:@"focused"] ? @NO : @99;
            [controller setValue:stale forKey:@"view"];
            session.lastCommand = UINT32_MAX;
            [controller changeCandidatePage:next];
            assert(session.lastCommand == UINT32_MAX);
        }
        pageView[@"page"] = @2;
        [controller setValue:[pageView copy] forKey:@"view"];
        [controller renderCandidates];
        previous = (id)PageButton(layoutPanel.contentView, -1);
        next = (id)PageButton(layoutPanel.contentView, -2);
        assert(previous.enabled && !next.enabled);
        session.lastCommand = UINT32_MAX;
        [controller changeCandidatePage:next];
        assert(session.lastCommand == UINT32_MAX);
        [layoutPanel orderOut:nil];
        [controller changeCandidatePage:previous];
        assert(session.lastCommand == UINT32_MAX);
        pageView[@"page"] = @0;
        pageView[@"page_count"] = @1;
        // The candidate preedit uses Engine display text, independent of candidate font.
        pageView[@"preedit"] = @"ce'shi";
        pageView[@"caret_position"] = @2;
        [controller setValue:pageView forKey:@"view"];
        // Fallback text can be taller than the primary family at the same size.
        appearance.fontFamily = @"Helvetica";
        appearance.fontSize = 32;
        appearance.preeditFontSize = 32;
        appearance.showsCandidatePreedit = YES;
        NSFont *fallbackFont = [appearance candidateFontOfSize:32];
        CGFloat fallbackHeight = ceil([@"合😀" sizeWithAttributes:@{NSFontAttributeName:fallbackFont}].height);
        assert(fallbackHeight > ceil(fallbackFont.ascender - fallbackFont.descender + fallbackFont.leading));
        NSMutableDictionary *fallbackView = [pageView mutableCopy];
        fallbackView[@"preedit"] = @"合😀";
        fallbackView[@"candidates"] = @[@{@"text": @"合😀", @"highlighted": @YES}];
        for (NSNumber *vertical in @[@NO, @YES]) {
            appearance.vertical = vertical.boolValue;
            [controller setValue:fallbackView forKey:@"view"];
            [controller renderCandidates];
            for (NSView *child in layoutPanel.contentView.subviews) {
                if ([child.identifier isEqual:@"candidate-preedit"]) assert(child.frame.size.height >= fallbackHeight + 6);
                if ([child isKindOfClass:MSIMECandidateButton.class]) assert(child.frame.size.height >= fallbackHeight + 12);
            }
        }
        appearance.fontSize = 18;
        [controller setValue:pageView forKey:@"view"];
        NSString *installedFamily = [NSFont fontWithName:@"Menlo" size:18].familyName;
        assert(installedFamily);
        appearance.fontFamily = installedFamily;
        for (NSNumber *vertical in @[@NO, @YES]) {
            appearance.vertical = vertical.boolValue;
            appearance.showsCandidatePreedit = YES;
            appearance.preeditFontSize = 32;
            [controller renderCandidates];
            NSTextField *preeditLabel = nil;
            for (NSView *child in layoutPanel.contentView.subviews)
                if ([child.identifier isEqual:@"candidate-preedit"]) preeditLabel = (id)child;
            assert(preeditLabel && [preeditLabel.stringValue isEqual:@"ce'shi"] && preeditLabel.font.pointSize == 32);
            assert([preeditLabel isKindOfClass:MSIMECandidatePreeditField.class]);
            MSIMECandidatePreeditField *caretLabel = (id)preeditLabel;
            assert(caretLabel.caretIndex == 2 && caretLabel.showsCaret);
            NSRect middleCaret = caretLabel.caretRect;
            assert(!NSIsEmptyRect(middleCaret) && NSContainsRect(caretLabel.bounds, middleCaret));
            NSBitmapImageRep *withCaret = [caretLabel bitmapImageRepForCachingDisplayInRect:caretLabel.bounds];
            [caretLabel cacheDisplayInRect:caretLabel.bounds toBitmapImageRep:withCaret];
            caretLabel.showsCaret = NO;
            assert(NSIsEmptyRect(caretLabel.caretRect));
            NSBitmapImageRep *withoutCaret = [caretLabel bitmapImageRepForCachingDisplayInRect:caretLabel.bounds];
            [caretLabel cacheDisplayInRect:caretLabel.bounds toBitmapImageRep:withoutCaret];
            assert(![[withCaret TIFFRepresentation] isEqual:[withoutCaret TIFFRepresentation]]);
            caretLabel.showsCaret = YES;
            caretLabel.caretIndex = 0;
            assert(NSMinX(caretLabel.caretRect) < NSMinX(middleCaret));
            caretLabel.caretIndex = caretLabel.stringValue.length;
            assert(NSMinX(caretLabel.caretRect) > NSMinX(middleCaret));
            caretLabel.caretIndex = 2;
            assert([preeditLabel.font.familyName isEqual:installedFamily]);
            const auto preeditTokens = [appearance resolvedSkinForDark:NO].tokens;
            layoutPanel.contentView.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
            [controller refreshCandidateSkin];
            assert([preeditLabel.textColor isEqual:SkinColor(preeditTokens.text)]);
            assert([caretLabel.caretColor isEqual:SkinColor(preeditTokens.accent)]);
            assert(NSContainsRect(layoutPanel.contentView.bounds, preeditLabel.frame));
            for (NSView *child in layoutPanel.contentView.subviews)
                if ([child isKindOfClass:MSIMECandidateButton.class]) {
                    assert(!NSIntersectsRect(child.frame, preeditLabel.frame));
                    assert([((NSButton *)child).font.familyName isEqual:installedFamily]);
                }
            CGFloat shownHeight = layoutPanel.frame.size.height;
            appearance.showsCandidatePreedit = NO;
            [controller renderCandidates];
            assert(layoutPanel.frame.size.height < shownHeight);
            for (NSView *child in layoutPanel.contentView.subviews) assert(![child.identifier isEqual:@"candidate-preedit"]);
        }
        appearance.showsCandidatePreedit = YES;
        appearance.preeditFontSize = 16;
        // Long rows scroll rather than truncating away the insertion point.
        MSIMECandidatePreeditField *longPreedit = [MSIMECandidatePreeditField labelWithString:[@"ni'" stringByPaddingToLength:180 withString:@"ni'" startingAtIndex:0]];
        longPreedit.frame = NSMakeRect(0, 0, 80, 28);
        longPreedit.font = [NSFont systemFontOfSize:16];
        longPreedit.showsCaret = YES;
        for (NSNumber *offset in @[@0, @50, @180, @(NSUIntegerMax)]) {
            longPreedit.caretIndex = offset.unsignedIntegerValue;
            assert(NSContainsRect(longPreedit.bounds, longPreedit.caretRect));
        }
        longPreedit.stringValue = @"合😀";
        longPreedit.caretIndex = 3;
        assert(NSContainsRect(longPreedit.bounds, longPreedit.caretRect));
        longPreedit.stringValue = @"";
        assert(NSIsEmptyRect(longPreedit.caretRect));
        longPreedit.stringValue = @"iiii";
        longPreedit.caretIndex = 2;
        CTLineRef slotted = [longPreedit newPreeditLine];
        CGFloat beforeSlot = CTLineGetOffsetForStringIndex(slotted, 2, nullptr);
        CGFloat afterSlot = CTLineGetOffsetForStringIndex(slotted, 3, nullptr);
        assert(fabs(afterSlot - beforeSlot - 2.95) < 0.01);
        assert(fabs(NSMinX(longPreedit.caretRect) - (2 + beforeSlot + 0.85)) < 0.01);
        assert(fabs(NSWidth(longPreedit.caretRect) - 1.25) < 0.01);
        CFRelease(slotted);
        assert([longPreedit.stringValue isEqual:@"iiii"]); // The slot is display-only.
        longPreedit.showsCaret = NO;
        CTLineRef unslotted = [longPreedit newPreeditLine];
        CGFloat unslottedWidth = CTLineGetTypographicBounds(unslotted, nullptr, nullptr, nullptr);
        CFRelease(unslotted);
        longPreedit.showsCaret = YES;
        longPreedit.caretIndex = 4;
        assert(fabs(NSMinX(longPreedit.caretRect) - (2 + unslottedWidth + 1.5)) < 0.01);
        appearance.fontFamily = @"Segoe UI";
        for (id display in @[@"", NSNull.null]) {
            pageView[@"preedit"] = display;
            [controller setValue:pageView forKey:@"view"];
            [controller renderCandidates];
            NSTextField *label = nil;
            for (NSView *child in layoutPanel.contentView.subviews)
                if ([child.identifier isEqual:@"candidate-preedit"]) label = (id)child;
            if (display == NSNull.null) assert([label.stringValue isEqual:@"ceshi"]);
            else assert(label == nil);
        }
        pageView[@"preedit"] = @"ce'shi";
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        assert(PageButton(layoutPanel.contentView, -1) == nil);
        assert(PageButton(layoutPanel.contentView, -2) == nil);
        pageView[@"candidates"] = @[@{@"text": @"测试", @"highlighted": @YES, @"id": @{@"session": @1, @"generation": @2, @"index": @0}}, @{@"text": @"布局", @"highlighted": @NO, @"id": @{@"session": @1, @"generation": @2, @"index": @1}}];
        [controller setValue:pageView forKey:@"view"];
        [controller renderCandidates];
        CGFloat verticalHeight = layoutPanel.frame.size.height;
        MSIMECandidateButton *clickCandidate = (id)PageButton(layoutPanel.contentView, 1);
        assert(clickCandidate);
        const NSEventModifierFlags deleteModifiers = NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagShift;
        NSEvent *(^deleteEvent)(unsigned short, NSEventModifierFlags, BOOL) = ^NSEvent *(unsigned short code, NSEventModifierFlags modifiers, BOOL repeat) {
            return [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifiers timestamp:0 windowNumber:0 context:nil characters:@"!" charactersIgnoringModifiers:@"!" isARepeat:repeat keyCode:code];
        };
        NSArray *digitCodes = @[@18, @19, @20, @21, @23, @22, @26, @28];
        NSMutableDictionary *deleteView = [pageView mutableCopy];
        NSMutableArray *deleteCandidates = [NSMutableArray array];
        for (NSUInteger slot = 0; slot < 8; ++slot)
            [deleteCandidates addObject:@{@"id":@{@"session":@1, @"generation":@2, @"index":@(40 + slot)}, @"text":@"合成测试"}];
        deleteView[@"candidates"] = deleteCandidates;
        [controller setValue:deleteView forKey:@"view"];
        for (NSUInteger slot = 0; slot < 8; ++slot) {
            unsigned short code = [digitCodes[slot] unsignedShortValue];
            NSUInteger calls = session.maintenanceCalls;
            session.lastCommand = UINT32_MAX;
            assert([controller handleEvent:deleteEvent(code, deleteModifiers, NO) client:client]);
            assert(session.maintenanceCalls == calls + 1 && session.maintenanceAction == 1);
            assert(session.selectedGeneration == 2 && session.selectedIndex == 40 + slot && session.lastCommand == UINT32_MAX);
            assert([controller handleEvent:deleteEvent(code, deleteModifiers, YES) client:client]);
            assert(session.maintenanceCalls == calls + 1);
            for (NSNumber *modifiers in @[@(deleteModifiers | NSEventModifierFlagCommand), @(deleteModifiers ^ NSEventModifierFlagControl), @(deleteModifiers ^ NSEventModifierFlagOption), @(deleteModifiers ^ NSEventModifierFlagShift)])
                assert(MSIMECandidateDeletionSlot(deleteEvent(code, modifiers.unsignedIntegerValue, NO)) == NSNotFound);
        }
        for (NSNumber *code in @[@25, @29, @83, @84, @85, @86, @87, @88, @89, @91])
            assert(MSIMECandidateDeletionSlot(deleteEvent(code.unsignedShortValue, deleteModifiers, NO)) == NSNotFound);
        NSUInteger deletionCalls = session.maintenanceCalls;
        for (id invalid in @[NSNull.null, @{}, @{@"id":@{@"session":@1, @"generation":@99, @"index":@0}}]) {
            deleteView[@"candidates"] = @[invalid];
            [controller setValue:deleteView forKey:@"view"];
            assert([controller handleEvent:deleteEvent(18, deleteModifiers, NO) client:client]);
        }
        [controller setValue:pageView forKey:@"view"];
        assert([controller handleEvent:deleteEvent(28, deleteModifiers, NO) client:client]); // Empty slot.
        assert(session.maintenanceCalls == deletionCalls && session.lastCommand == UINT32_MAX);
        NSMenu *candidateMenu = clickCandidate.menu;
        NSEvent *rightClick = [NSEvent mouseEventWithType:NSEventTypeRightMouseDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil eventNumber:1 clickCount:1 pressure:1];
        assert([clickCandidate menuForEvent:rightClick] == candidateMenu);
        assert(candidateMenu.numberOfItems == 3);
        assert([[candidateMenu itemAtIndex:0].title isEqual:@"置顶"]);
        assert([[candidateMenu itemAtIndex:1].title isEqual:@"固定排位"]);
        assert([[candidateMenu itemAtIndex:2].title isEqual:@"删除"]);
        assert([[candidateMenu itemAtIndex:2].keyEquivalent isEqual:@"2"]);
        assert([candidateMenu itemAtIndex:2].keyEquivalentModifierMask == deleteModifiers);
        NSMenu *positionMenu = [candidateMenu itemAtIndex:1].submenu;
        assert(positionMenu.numberOfItems == 7 && [positionMenu itemAtIndex:5].separatorItem);
        NSMutableArray *operations = [NSMutableArray arrayWithObjects:[candidateMenu itemAtIndex:0], [candidateMenu itemAtIndex:2], nil];
        [operations addObjectsFromArray:[positionMenu.itemArray subarrayWithRange:NSMakeRange(0, 5)]];
        [operations addObject:[positionMenu itemAtIndex:6]];
        for (NSMenuItem *operation in operations) {
            NSUInteger calls = session.maintenanceCalls;
            [NSApp sendAction:operation.action to:operation.target from:operation];
            assert(session.maintenanceCalls == calls + 1 && session.maintenanceAction == operation.tag);
            assert(session.selectedGeneration == 2 && session.selectedIndex == 1);
        }
        NSMenuItem *retainedOperation = [candidateMenu itemAtIndex:0];
        NSDictionary *validContext = retainedOperation.representedObject;
        NSUInteger maintenanceCalls = session.maintenanceCalls;
        retainedOperation.enabled = NO;
        [controller candidateMenuAction:retainedOperation];
        retainedOperation.enabled = YES;
        layoutPanel.requestedVisible = NO;
        [controller candidateMenuAction:retainedOperation];
        layoutPanel.requestedVisible = YES;
        for (NSString *field in @[@"session", @"generation", @"focused"]) {
            NSMutableDictionary *stale = [pageView mutableCopy];
            stale[field] = [field isEqual:@"focused"] ? @NO : @99;
            [controller setValue:stale forKey:@"view"];
            [controller candidateMenuAction:retainedOperation];
        }
        [controller setValue:pageView forKey:@"view"];
        for (NSString *field in @[@"session", @"generation", @"index"]) {
            NSMutableDictionary *badID = [validContext[@"id"] mutableCopy];
            [badID removeObjectForKey:field];
            retainedOperation.representedObject = @{@"id":badID, @"render":validContext[@"render"]};
            [controller candidateMenuAction:retainedOperation];
        }
        retainedOperation.representedObject = validContext;
        assert(session.maintenanceCalls == maintenanceCalls);
        for (NSString *text in @[@"中", @"𠀀", @"测试"]) {
            NSMenu *menu = [controller menuForCandidate:@{@"id":clickCandidate.candidateID, @"text":text}];
            assert(menu.numberOfItems == ([text isEqual:@"测试"] ? 3 : 2));
        }
        NSDictionary *validClickID = clickCandidate.candidateID;
        NSUInteger selectedCalls = session.selectCalls;
        [controller selectCandidate:clickCandidate];
        assert(session.selectCalls == selectedCalls + 1 && session.selectedGeneration == 2 && session.selectedIndex == 1);
        for (NSString *field in @[@"session", @"generation", @"index"]) {
            for (id invalid in @[@(-1), @YES, @1.5, @"1", NSNull.null, @"missing"]) {
                NSMutableDictionary *bad = [validClickID mutableCopy];
                bad[field] = invalid;
                if ([invalid isEqual:@"missing"]) [bad removeObjectForKey:field];
                clickCandidate.candidateID = bad;
                [controller selectCandidate:clickCandidate];
                assert(session.selectCalls == selectedCalls + 1);
            }
        }
        clickCandidate.candidateID = validClickID;
        for (NSString *field in @[@"session", @"generation", @"focused"]) {
            NSMutableDictionary *staleView = [pageView mutableCopy];
            staleView[field] = [field isEqual:@"focused"] ? @NO : @99;
            [controller setValue:staleView forKey:@"view"];
            [controller selectCandidate:clickCandidate];
            assert(session.selectCalls == selectedCalls + 1);
        }
        [controller setValue:pageView forKey:@"view"];
        layoutPanel.requestedVisible = NO;
        [controller selectCandidate:clickCandidate];
        assert(session.selectCalls == selectedCalls + 1);
        layoutPanel.requestedVisible = YES;
        clickCandidate.enabled = NO;
        [controller selectCandidate:clickCandidate];
        assert(session.selectCalls == selectedCalls + 1);
        clickCandidate.enabled = YES;
        [controller renderCandidates];
        [controller selectCandidate:clickCandidate];
        assert(session.selectCalls == selectedCalls + 1); // Detached button from an earlier render.
        [controller candidateMenuAction:retainedOperation];
        assert(session.maintenanceCalls == maintenanceCalls);
        appearance.vertical = NO;
        session.lastCommand = UINT32_MAX;
        [controller appearanceChanged:nil];
        assert(session.lastCommand == UINT32_MAX);
        assert(layoutPanel.frame.size.height < verticalHeight);
        NSView *first = layoutPanel.contentView.subviews[0];
        NSView *second = layoutPanel.contentView.subviews[1];
        assert(first.frame.origin.y == second.frame.origin.y);
        assert(NSMaxX(first.frame) == NSMinX(second.frame));
        CGFloat normalHeight = layoutPanel.frame.size.height;
        appearance.fontSize = 20;
        [controller appearanceChanged:nil];
        assert(layoutPanel.frame.size.height > normalHeight);
        // Palette and native drawing coverage: four skins, two layouts and both appearances.
        NSDictionary *preservedView = [[controller valueForKey:@"view"] copy];
        session.lastCommand = UINT32_MAX;
        for (NSString *skinID in skinIDs) {
            appearance.skinID = skinID;
            for (NSNumber *vertical in @[@NO, @YES]) {
                appearance.vertical = vertical.boolValue;
                [controller appearanceChanged:nil];
                for (NSString *theme in @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]) {
                    MSIMECandidateChromeView *chrome = (id)layoutPanel.contentView;
                    chrome.appearance = [NSAppearance appearanceNamed:theme];
                    // Exercise the same callback AppKit uses for a system appearance change.
                    [chrome viewDidChangeEffectiveAppearance];
                    const auto tokens = msime::mac::BuiltInSkinTokens(skinID.UTF8String, [theme isEqual:NSAppearanceNameDarkAqua]);
                    assert([chrome.fillColor isEqual:SkinColor(tokens.surface)]);
                    assert([chrome.strokeColor isEqual:SkinColor(tokens.border)]);
                    assert(chrome.cornerRadius == tokens.radius && chrome.lineWidth == tokens.borderWidth);
                    assert(!chrome.isOpaque && !layoutPanel.isOpaque);
                    MSIMECandidateButton *selected = (id)chrome.subviews[0];
                    MSIMECandidateButton *unselected = (id)chrome.subviews[1];
                    assert(selected.candidateHighlighted && !unselected.candidateHighlighted);
                    assert([selected.candidateID isEqual:preservedView[@"candidates"][0][@"id"]]);
                    assert([unselected.candidateID isEqual:preservedView[@"candidates"][1][@"id"]]);
                    assert([selected.fillColor isEqual:SkinColor(tokens.selected)]);
                    assert([selected.titleColor isEqual:SkinColor(tokens.selectedText)]);
                    assert([unselected.titleColor isEqual:SkinColor(tokens.text)]);
                    appearance.candidateTextColor = @"#1234AB";
                    [controller refreshCandidateSkin];
                    NSColor *override = [appearance candidateTextColorWithDefault:NSColor.blackColor];
                    assert([unselected.titleColor isEqual:override]);
                    assert([selected.titleColor isEqual:SkinColor(tokens.selectedText)]);
                    for (NSView *child in chrome.subviews)
                        if ([child.identifier isEqual:@"candidate-preedit"]) {
                            assert([((NSTextField *)child).textColor isEqual:override]);
                            assert([((MSIMECandidatePreeditField *)child).caretColor isEqual:SkinColor(tokens.accent)]);
                        }
                    appearance.candidateTextColor = nil;
                    [controller refreshCandidateSkin];
                    assert([unselected.titleColor isEqual:SkinColor(tokens.text)]);
                    assert([unselected.numberColor isEqual:SkinColor(tokens.number)]);
                    assert(selected.showSelectedBar == tokens.showSelectedBar);
                    NSBitmapImageRep *bitmap = [chrome bitmapImageRepForCachingDisplayInRect:chrome.bounds];
                    assert(bitmap);
                    [chrome cacheDisplayInRect:chrome.bounds toBitmapImageRep:bitmap];
                    assert(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0);
                    assert([[controller valueForKey:@"view"] isEqual:preservedView]);
                    assert(session.lastCommand == UINT32_MAX);
                    assert(!layoutPanel.canBecomeKeyWindow && !selected.acceptsFirstResponder);
                }
            }
        }
        TestExternalSkin(controller, layoutPanel, defaults);
        [controller setValue:appearance forKey:@"appearance"];
        appearance.vertical = NO;
        appearance.skinID = @"fluent";
        [controller appearanceChanged:nil];
        for (NSNumber *key in @[@123, @124, @125, @126]) {
            layoutPanel.requestedVisible = YES;
            session.lastCommand = UINT32_MAX;
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
            assert([controller handleEvent:event client:client]);
            uint32_t expected = key.unsignedShortValue == 123 ? MSIME_PREVIOUS_CANDIDATE : key.unsignedShortValue == 124 ? MSIME_NEXT_CANDIDATE : UINT32_MAX;
            assert(session.lastCommand == expected);
        }
        CheckMenu([controller menu], controller);
        for (NSInteger option = 0; option < 3; ++option) {
            appearance.pageShortcut = option;
            NSArray *plain = @[@"-", @"=", @"[", @"]"];
            NSArray *shifted = @[@"_", @"+", @"{", @"}"];
            for (NSUInteger i = 0; i < plain.count; ++i) {
                for (NSNumber *visible in @[@NO, @YES]) {
                    for (NSNumber *shift in @[@NO, @YES]) {
                        layoutPanel.requestedVisible = visible.boolValue;
                        session.lastCommand = UINT32_MAX;
                        session.asciiCalls = 0;
                        NSString *characters = shift.boolValue ? shifted[i] : plain[i];
                        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:shift.boolValue ? NSEventModifierFlagShift : 0 timestamp:0 windowNumber:0 context:nil characters:characters charactersIgnoringModifiers:plain[i] isARepeat:NO keyCode:0];
                        assert([controller handleEvent:event client:client]);
                        BOOL paging = visible.boolValue && !shift.boolValue && ((option == 0 && i < 2) || (option == 1 && i >= 2));
                        if (paging) {
                            assert(session.lastCommand == (i % 2 == 0 ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE));
                            assert(session.asciiCalls == 0);
                        } else {
                            assert(session.lastCommand == UINT32_MAX && session.asciiCalls == 1);
                            assert(session.lastASCII == [characters characterAtIndex:0] && session.lastShift == shift.boolValue);
                        }
                    }
                }
            }
            for (NSNumber *key in @[@116, @121]) {
                layoutPanel.requestedVisible = YES;
                NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:key.unsignedShortValue];
                assert([controller handleEvent:event client:client]);
                assert(session.lastCommand == (key.unsignedShortValue == 116 ? MSIME_PREVIOUS_PAGE : MSIME_NEXT_PAGE));
            }
        }
        appearance.pageShortcut = 0;
        for (NSNumber *modifier in @[@(NSEventModifierFlagCommand), @(NSEventModifierFlagControl), @(NSEventModifierFlagOption)]) {
            layoutPanel.requestedVisible = YES;
            NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:modifier.unsignedIntegerValue timestamp:0 windowNumber:0 context:nil characters:@"=" charactersIgnoringModifiers:@"=" isARepeat:NO keyCode:0];
            assert(![controller handleEvent:event client:client]);
            assert(session.lastCommand == MSIME_FINISH_COMPOSITION);
        }
        NSDictionary *beforeWordView = [controller valueForKey:@"view"];
        NSDictionary *beforeWordTransition = session.nextTransition;
        for (NSString *keys in @[@"brackets", @"minus_equal"]) {
            [appearance setNavigation:keys enabled:NO];
            [appearance setWordCharacterEnabled:YES keys:keys];
            for (NSUInteger edge = 0; edge < 2; ++edge) {
                NSDictionary *edgeView = @{@"session": @71, @"generation": @72, @"focused": @YES, @"editing_text": @"synthetic",
                    @"candidates": @[@{@"text": @"合成", @"highlighted": @YES, @"id": @{@"session": @71, @"generation": @72, @"index": @8}}]};
                [controller setValue:edgeView forKey:@"view"];
                layoutPanel.requestedVisible = YES;
                NSString *character = [keys isEqual:@"brackets"] ? (edge ? @"]" : @"[") : (edge ? @"=" : @"-");
                NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:character charactersIgnoringModifiers:character isARepeat:NO keyCode:0];
                NSUInteger calls = session.edgeCalls;
                session.nextTransition = @{@"handled": @NO, @"commit": NSNull.null, @"view": edgeView};
                assert([controller handleEvent:event client:client]);
                assert(session.edgeCalls == calls + 1 && session.lastEdge == edge && session.edgeGeneration == 72 && session.edgeIndex == 8);
                for (NSString *field in @[@"session", @"generation", @"index"]) {
                    for (id invalid in @[@(-1), @YES, @1.5, @"8", NSNull.null, @"missing"]) {
                        NSMutableDictionary *badID = [@{@"session": @71, @"generation": @72, @"index": @8} mutableCopy];
                        badID[field] = invalid;
                        if ([invalid isEqual:@"missing"]) [badID removeObjectForKey:field];
                        NSMutableDictionary *badView = [edgeView mutableCopy];
                        badView[@"candidates"] = @[@{@"text": @"合成", @"highlighted": @YES, @"id": badID}];
                        [controller setValue:badView forKey:@"view"];
                        layoutPanel.requestedVisible = YES;
                        NSUInteger before = session.edgeCalls;
                        assert([controller handleEvent:event client:client] && session.edgeCalls == before);
                    }
                }
                for (NSString *field in @[@"session", @"generation", @"focused"]) {
                    NSMutableDictionary *staleView = [edgeView mutableCopy];
                    staleView[field] = [field isEqual:@"focused"] ? @NO : @99;
                    [controller setValue:staleView forKey:@"view"];
                    layoutPanel.requestedVisible = YES;
                    NSUInteger before = session.edgeCalls;
                    assert([controller handleEvent:event client:client] && session.edgeCalls == before);
                }
            }
            [appearance setWordCharacterEnabled:NO keys:keys];
        }
        [controller setValue:beforeWordView forKey:@"view"];
        session.nextTransition = beforeWordTransition;
        appearance.pageShortcut = 0;
        for (NSArray *entry in @[@[@"comma_period", @",", @0, @(MSIME_PREVIOUS_PAGE)],
                                 @[@"comma_period", @".", @0, @(MSIME_NEXT_PAGE)],
                                 @[@"tab", @"\t", @48, @(MSIME_NEXT_PAGE)],
                                 @[@"page_up_down", @"", @121, @(MSIME_NEXT_PAGE)],
                                 @[@"arrows", @"", @125, @(MSIME_NEXT_CANDIDATE)]]) {
            for (NSNumber *enabled in @[@NO, @YES]) {
                [appearance applySharedCandidatePreferences:@{@"navigation": @{entry[0]:enabled}}];
                layoutPanel.requestedVisible = YES;
                appearance.vertical = YES;
                session.lastCommand = UINT32_MAX;
                session.asciiCalls = 0;
                NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0 windowNumber:0 context:nil characters:entry[1] charactersIgnoringModifiers:entry[1] isARepeat:NO keyCode:[entry[2] unsignedShortValue]];
                BOOL handled = [controller handleEvent:event client:client];
                if (enabled.boolValue) assert(handled && session.lastCommand == [entry[3] unsignedIntValue]);
                else {
                    assert(session.lastCommand == UINT32_MAX);
                    if ([entry[2] unsignedShortValue] != 0) assert(!handled);
                    else assert(session.asciiCalls == 1);
                }
            }
        }
        layoutPanel.requestedVisible = YES;
        NSEvent *reverseTab = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:0 context:nil characters:@"\t" charactersIgnoringModifiers:@"\t" isARepeat:NO keyCode:48];
        assert([controller handleEvent:reverseTab client:client] && session.lastCommand == MSIME_PREVIOUS_PAGE);
        layoutPanel.requestedVisible = NO;
        session.lastCommand = UINT32_MAX;
        assert(![controller handleEvent:reverseTab client:client] && session.lastCommand == UINT32_MAX);
        // Script selection changes only native display/commit strings, not Engine state or IDs.
        assert(!appearance.traditionalOutput);
        assert([MSIMEChineseOutputString(@"汉语", YES) isEqual:@"漢語"]);
        assert([MSIMEChineseOutputString(@"汉语", NO) isEqual:@"汉语"]);
        assert([CandidateDisplay(@{@"text": @"汉语", @"annotation": @"(aB)"}, YES) isEqual:@"漢語(aB)"]);
        assert([CandidateDisplay(@{@"text": @"汉语", @"annotation": NSNull.null}, NO) isEqual:@"汉语"]);
        assert(([CandidateDisplay(@{@"text":@"汉语", @"corrected":@YES, @"annotation":@"(aB)", @"source":@2}, YES) isEqual:@"漢語*(aB) ☁️"]));
        for (id corrected in @[@NO, @1, @"true", NSNull.null])
            assert(([CandidateDisplay(@{@"text":@"汉语", @"corrected":corrected}, NO) isEqual:@"汉语"]));
        for (id source in @[@0, @1, @4, @255, @(-1), @YES, @2.0, @"2", NSNull.null])
            assert(([CandidateDisplay(@{@"text":@"汉语", @"source":source}, NO) isEqual:@"汉语"]));
        assert(([CandidateDisplay(@{@"text":@"汉语", @"annotation":@"(aB)", @"source":@2}, YES) isEqual:@"漢語(aB) ☁️"]));
        assert(([CandidateDisplay(@{@"text":@"汉语", @"annotation":@"(aB)", @"source":@3}, NO) isEqual:@"汉语(aB) 🤖"]));
        NSMutableDictionary *scriptView = [@{@"scheme": @0, @"local_mode": @"none", @"session": @1, @"generation": @20, @"editing_text": @"hanyu", @"caret_position": @5, @"candidates": @[@{@"text": @"汉语", @"highlighted": @YES, @"id": @{@"session": @1, @"generation": @20, @"index": @0}}]} mutableCopy];
        [controller setValue:[scriptView copy] forKey:@"view"];
        NSDictionary *preserved = [[controller valueForKey:@"view"] copy];
        [controller selectTraditionalOutput:nil];
        [controller appearanceChanged:nil];
        assert([controller.menu itemAtIndex:5].state == NSControlStateValueOn);
        assert([[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] traditionalOutput]);
        MSIMECandidateButton *scriptButton = PageButton(layoutPanel.contentView, 0);
        assert([scriptButton.toolTip isEqual:@"漢語"] && [scriptButton.title containsString:@"漢語"]);
        assert([scriptButton.candidateID isEqual:scriptView[@"candidates"][0][@"id"]]);
        assert([[controller valueForKey:@"view"] isEqual:preserved]);
        for (NSNumber *traditional in @[@NO, @YES]) {
            [controller applySharedToolbarPreferences:@{@"traditional_chinese_output":traditional}];
            [controller renderCandidates];
            scriptButton = PageButton(layoutPanel.contentView, 0);
            assert([scriptButton.toolTip isEqual:traditional.boolValue ? @"漢語" : @"汉语"]);
            assert([scriptButton.candidateID isEqual:scriptView[@"candidates"][0][@"id"]]);
            assert([[controller valueForKey:@"view"] isEqual:preserved]);
        }
        NSMutableDictionary *annotated = [scriptView mutableCopy];
        NSMutableDictionary *word = [scriptView[@"candidates"][0] mutableCopy];
        word[@"annotation"] = @"(aB)";
        annotated[@"candidates"] = @[word];
        [controller setValue:annotated forKey:@"view"];
        [controller renderCandidates];
        scriptButton = PageButton(layoutPanel.contentView, 0);
        assert([scriptButton.title containsString:@"漢語(aB)"]);
        assert([scriptButton.toolTip isEqual:@"漢語(aB)"]);
        assert([scriptButton.candidateID isEqual:word[@"id"]]);
        assert([word[@"text"] isEqual:@"汉语"]);
        for (NSNumber *vertical in @[@NO, @YES]) {
            appearance.vertical = vertical.boolValue;
            [controller renderCandidates];
            NSSize originalSize = PageButton(layoutPanel.contentView, 0).frame.size;
            word[@"translation"] = @"synthetic glossary";
            [controller renderCandidates];
            MSIMECandidateButton *translated = PageButton(layoutPanel.contentView, 0);
            assert([translated.translation isEqual:@"synthetic glossary"] && translated.translationBelow == !vertical.boolValue);
            assert(fabs(translated.translationFont.pointSize - translated.font.pointSize * 0.78) < 0.01);
            assert([translated.toolTip containsString:@"\nsynthetic glossary"] && [translated.candidateID isEqual:word[@"id"]]);
            assert(vertical.boolValue ? translated.frame.size.width > originalSize.width : translated.frame.size.height > originalSize.height);
            NSBitmapImageRep *bitmap = [translated bitmapImageRepForCachingDisplayInRect:translated.bounds];
            assert(bitmap);
            [translated cacheDisplayInRect:translated.bounds toBitmapImageRep:bitmap];
            [word removeObjectForKey:@"translation"];
        }
        word[@"corrected"] = @YES;
        NSUInteger fixedCase = 0;
        for (id fixed in @[@0, @1, @5, @(-1), @256, @YES, @1.0, @"1", NSNull.null]) {
            word[@"fixed_position"] = fixed;
            const BOOL valid = fixedCase == 1 || fixedCase == 2;
            ++fixedCase;
            for (NSNumber *highlighted in @[@NO, @YES]) {
                word[@"highlighted"] = highlighted;
                [controller renderCandidates];
                scriptButton = PageButton(layoutPanel.contentView, 0);
                assert(scriptButton.candidateFixed == valid);
                assert([scriptButton.title containsString:@"漢語*(aB)"] && [scriptButton.candidateID isEqual:word[@"id"]]);
                if (valid) {
                    NSColor *color = [scriptButton.titleColor colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
                    assert(fabs(color.redComponent - 55.0/255) < 0.001 && fabs(color.greenComponent - 154.0/255) < 0.001 && fabs(color.blueComponent - 211.0/255) < 0.001);
                    [controller refreshCandidateSkin];
                    assert([scriptButton.titleColor isEqual:color]);
                }
                assert([word[@"text"] isEqual:@"汉语"]);
            }
        }
        [word removeObjectForKey:@"corrected"];
        [word removeObjectForKey:@"fixed_position"];
        for (NSNumber *source in @[@2, @3]) {
            word[@"source"] = source;
            NSDictionary *unchanged = [word copy];
            for (NSNumber *vertical in @[@NO, @YES]) {
                appearance.vertical = vertical.boolValue;
                [controller renderCandidates];
                scriptButton = PageButton(layoutPanel.contentView, 0);
                NSString *expected = source.integerValue == 2 ? @"漢語(aB) ☁️" : @"漢語(aB) 🤖";
                assert([scriptButton.title containsString:expected] && [scriptButton.toolTip isEqual:expected]);
                assert([scriptButton.candidateID isEqual:word[@"id"]] && [word isEqual:unchanged]);
                assert(scriptButton.frame.size.width > 0 && scriptButton.frame.size.height > 0);
            }
        }
        NSUInteger contextIndex = 0;
        for (NSDictionary *context in @[@{@"scheme": @0, @"local_mode": @"none"}, @{@"scheme": @1, @"local_mode": @"quick_phrase"}, @{@"scheme": @3, @"local_mode": @"none"}, @{@"scheme": @0, @"local_mode": @"unicode"}, @{@"scheme": @0, @"local_mode": @"temporary_japanese"}, @{@"scheme": @1, @"local_mode": @"temporary_japanese"}, @{}]) {
            BOOL convert = contextIndex++ < 2;
            assert(MSIMEScriptConversionApplies(context) == convert);
            NSMutableDictionary *candidateView = [scriptView mutableCopy];
            [candidateView addEntriesFromDictionary:context];
            if (context.count == 0) [candidateView removeObjectForKey:@"scheme"];
            [controller setValue:candidateView forKey:@"view"];
            [controller renderCandidates];
            scriptButton = PageButton(layoutPanel.contentView, 0);
            assert([scriptButton.toolTip isEqual:convert ? @"漢語" : @"汉语"]);
            // Post-commit view has already reset its mode and may have applied another scheme.
            NSDictionary *transition = @{@"handled": @YES, @"commit": @"汉语", @"commit_context": context, @"view": @{@"scheme": @0, @"local_mode": @"none", @"editing_text": @"", @"candidates": @[]}};
            [controller apply:transition];
            assert([client.committed isEqual:convert ? @"漢語" : @"汉语"]);
            assert([transition[@"commit"] isEqual:@"汉语"]);
        }
        NSMutableDictionary *japaneseView = [scriptView mutableCopy];
        japaneseView[@"local_mode"] = @"temporary_japanese";
        japaneseView[@"candidates"] = @[@{@"text": @"日本国", @"highlighted": @YES, @"id": word[@"id"]}];
        [controller setValue:japaneseView forKey:@"view"];
        [controller renderCandidates];
        assert([PageButton(layoutPanel.contentView, 0).toolTip isEqual:@"日本国"]);
        assert([PageButton(layoutPanel.contentView, 0).candidateID isEqual:word[@"id"]]);
        [controller apply:@{@"commit": @"日本国", @"commit_context": @{@"scheme": @0, @"local_mode": @"temporary_japanese"},
                            @"view": @{@"scheme": @0, @"local_mode": @"none", @"editing_text": @"", @"candidates": @[]}}];
        assert([client.committed isEqual:@"日本国"]);
        [controller selectSimplifiedOutput:nil];
        assert([controller.menu itemAtIndex:4].state == NSControlStateValueOn);
        [controller apply:@{@"commit": @"汉语", @"commit_context": @{@"scheme": @0, @"local_mode": @"none"}, @"view": @{@"editing_text": @"", @"candidates": @[]}}];
        assert([client.committed isEqual:@"汉语"]);
        TestInputMode(defaults, appearance);
        TestControlOptionSpace();
        TestInputModePolicy();
        TestInputSourceModeReset();
        TestModifierTaps();
        TestStaleClientDeactivation();
        TestPreferenceClientGeneration();
        TestFullWidth(defaults, appearance);
        TestPunctuation(defaults, appearance);
        TestCharacterSetShortcut(defaults, appearance);
        TestDedicatedEnglish(appearance);
        TestKeymap(defaults, appearance);
        Method fontMethod = class_getClassMethod(NSFont.class, @selector(monospacedSystemFontOfSize:weight:));
        assert(fontMethod);
        originalMonospacedFont = method_setImplementation(fontMethod, (IMP)MissingKeyFont);
        TestKeymap(defaults, appearance);
        method_setImplementation(fontMethod, originalMonospacedFont);
        assert(missingKeyFontCalls > 0);
        [defaults removePersistentDomainForName:suite];
        if (previousVoiceHoldSpace) [standardDefaults setObject:previousVoiceHoldSpace forKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
        else [standardDefaults removeObjectForKey:@"MSIMEClientVoiceHotkeyHoldSpace"];
    }
    return 0;
}
