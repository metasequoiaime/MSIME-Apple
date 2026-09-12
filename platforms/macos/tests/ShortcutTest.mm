#import "../InputController.mm"
#import "../InputSourceRegistration.h"
#import "../SkinSettingsView.h"
#include <cassert>
#include <fstream>
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
        @"selectChineseMode:", @"selectEnglishMode:", @"",
        @"selectSimplifiedOutput:", @"selectTraditionalOutput:", @"",
        @"openCharacterPalette:", @"showEmoji:", @"showScreenKeyboard:",
        @"showAppearance:", @"showDictionary:", @"showAccount:",
        @"showCloudClipboard:", @"showHandwriting:", @"prepareDictionary:", @"",
        @"checkForUpdates:", @"openWebsite:", @"toggleVoiceInput:", @"showVoiceSettings:"
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
@property(nonatomic, copy) NSDictionary *nextTransition;
@property(nonatomic) NSUInteger asciiCalls;
@property(nonatomic) uint8_t lastASCII;
@property(nonatomic) BOOL lastShift;
@property(nonatomic) uint8_t requestedPageSize;
@property(nonatomic) BOOL failFinish;
@property(nonatomic) NSUInteger focusCalls;
@property(nonatomic) BOOL chinesePunctuation;
@property(nonatomic) NSUInteger punctuationCalls;
@property(nonatomic, copy) NSDictionary *finishTransition;
@end
@implementation ShortcutSession
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
    return nil;
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
    [controller snapshotSessionReplaced:[NSNotification notificationWithName:@"synthetic" object:session]];
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
    assert([controller handleEvent:ModeKey(4, chord, NO) client:client]);
    assert(!appearance.fullWidthInput);
    assert([controller handleEvent:ModeKey(4, chord, YES) client:client]);
    assert(!appearance.fullWidthInput);
    assert([controller handleEvent:ModeKey(4, chord, NO) client:client]);
    assert(appearance.fullWidthInput && session.asciiCalls == 0);
    for (NSEventModifierFlags extra : {NSEventModifierFlagCommand, NSEventModifierFlagControl}) {
        assert(![controller handleEvent:ModeKey(4, chord | extra, NO) client:client]);
        assert(appearance.fullWidthInput);
    }
    appearance.englishMode = YES;
    assert(![controller handleEvent:ModeKey(4, chord, NO) client:client]);
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
    assert([[menu itemAtIndex:6].title isEqual:@"表情与符号…"]);
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
    for (NSUInteger mask = 1; mask < 8; ++mask) {
        NSEventModifierFlags flags = NSEventModifierFlagShift;
        if (mask & 1) flags |= NSEventModifierFlagCommand;
        if (mask & 2) flags |= NSEventModifierFlagControl;
        if (mask & 4) flags |= NSEventModifierFlagOption;
        assert(![controller handleEvent:ModeKey(49, flags, NO) client:client]);
        assert(!appearance.englishMode);
    }
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

int main() {
    assert(!MSIMEShouldRegisterInputSource(1, nullptr));
    const char *registerArguments[] = {"test", "--register-input-source"};
    assert(MSIMEShouldRegisterInputSource(2, registerArguments));
    @autoreleasepool {
        [NSApplication sharedApplication];
        TestSharedInputPreferences();
        TestIndependentAssistancePreferences();
        TestSharedPunctuation();
        TestPageSizeCache();
        NSString *suite = [@"app.msime.test.appearance." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        MSIMEAppearancePreferences *appearance = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults];
        assert(!appearance.vertical && appearance.fontSize == 18);
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
        [controller setValue:@{@"candidates": @[@{@"text": @"测试", @"highlighted": @YES}]} forKey:@"view"];
        [controller renderCandidates];
        assert(layoutPanel.requestedVisible);
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
        NSMutableDictionary *scriptView = [@{@"scheme": @0, @"local_mode": @"none", @"session": @1, @"generation": @20, @"editing_text": @"hanyu", @"caret_position": @5, @"candidates": @[@{@"text": @"汉语", @"highlighted": @YES, @"id": @{@"session": @1, @"generation": @20, @"index": @0}}]} mutableCopy];
        [controller setValue:[scriptView copy] forKey:@"view"];
        NSDictionary *preserved = [[controller valueForKey:@"view"] copy];
        [controller selectTraditionalOutput:nil];
        [controller appearanceChanged:nil];
        assert([controller.menu itemAtIndex:4].state == NSControlStateValueOn);
        assert([[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:appearance.skinsRoot] traditionalOutput]);
        MSIMECandidateButton *scriptButton = PageButton(layoutPanel.contentView, 0);
        assert([scriptButton.toolTip isEqual:@"漢語"] && [scriptButton.title containsString:@"漢語"]);
        assert([scriptButton.candidateID isEqual:scriptView[@"candidates"][0][@"id"]]);
        assert([[controller valueForKey:@"view"] isEqual:preserved]);
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
        assert([controller.menu itemAtIndex:3].state == NSControlStateValueOn);
        [controller apply:@{@"commit": @"汉语", @"commit_context": @{@"scheme": @0, @"local_mode": @"none"}, @"view": @{@"editing_text": @"", @"candidates": @[]}}];
        assert([client.committed isEqual:@"汉语"]);
        TestInputMode(defaults, appearance);
        TestFullWidth(defaults, appearance);
        TestPunctuation(defaults, appearance);
        TestKeymap(defaults, appearance);
        Method fontMethod = class_getClassMethod(NSFont.class, @selector(monospacedSystemFontOfSize:weight:));
        assert(fontMethod);
        originalMonospacedFont = method_setImplementation(fontMethod, (IMP)MissingKeyFont);
        TestKeymap(defaults, appearance);
        method_setImplementation(fontMethod, originalMonospacedFont);
        assert(missingKeyFontCalls > 0);
        [defaults removePersistentDomainForName:suite];
    }
    return 0;
}
