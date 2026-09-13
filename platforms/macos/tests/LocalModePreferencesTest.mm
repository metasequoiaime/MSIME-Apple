#import "../AppearancePreferences.h"
#import "MSIMEClientSession.h"
#include "msime_client.h"
#include <cassert>

int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *suite = [@"msime.local-modes." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSUserDefaults *defaults = [[NSUserDefaults alloc] initWithSuiteName:suite];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        MSIMEAppearancePreferences *prefs = [[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:[NSURL fileURLWithPath:root]];
        NSDictionary *base = @{@"local_modes": @{@"unicode": @NO, @"future_field": @42}, @"untouched": @7};
        assert([[prefs sharedPreferencesByMerging:base][@"local_modes"] isEqual:base[@"local_modes"]]);
        __block NSUInteger changes = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEAppearanceDidChangeNotification object:prefs queue:nil usingBlock:^(NSNotification *note) { (void)note; ++changes; }];
        [prefs applySharedLocalModes:@{@"unicode": @NO}];
        assert(![prefs localModeEnabled:@"unicode"] && changes == 0);
        assert([defaults objectForKey:@"MSIMEClientLocalModes"] == nil);
        [prefs applySharedAssistancePreferences:@{@"fuzzy_pinyin": @{@"enabled": @NO, @"rules": @[@"z-zh", @"an-ang"]}}];
        assert(!prefs.fuzzyPinyinEnabled && [prefs fuzzyPinyinRuleEnabled:@"z-zh"] && ![prefs fuzzyPinyinRuleEnabled:@"c-ch"]);
        [prefs applySharedLocalModes:@{@"unicode": @1}];
        assert(![prefs localModeEnabled:@"unicode"]);
        NSScrollView *scroll = (id)prefs.window.contentView.subviews.firstObject;
        NSGridView *grid = (id)scroll.documentView;
        NSMutableDictionary<NSString *, NSButton *> *buttons = [NSMutableDictionary dictionary];
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSControl *control = (id)[grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if ([control isKindOfClass:NSControl.class] && control.action == NSSelectorFromString(@"localModeChanged:")) buttons[control.identifier] = (id)control;
        }
        assert(buttons.count == 8);
        NSButton *fuzzy = nil;
        NSMutableDictionary<NSString *, NSButton *> *fuzzyRules = [NSMutableDictionary dictionary];
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSControl *control = (id)[grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if (![control isKindOfClass:NSControl.class]) continue;
            if (control.action == @selector(fuzzyPinyinChanged:)) fuzzy = (id)control;
            if (control.action == @selector(fuzzyPinyinRuleChanged:)) fuzzyRules[control.identifier] = (id)control;
        }
        assert(fuzzy != nil && fuzzyRules.count == 11 && !fuzzyRules[@"z-zh"].enabled);
        fuzzy.state = NSControlStateValueOn;
        [NSApp sendAction:fuzzy.action to:fuzzy.target from:fuzzy];
        assert(prefs.fuzzyPinyinEnabled && fuzzyRules[@"z-zh"].enabled);
        fuzzyRules[@"z-zh"].state = NSControlStateValueOff;
        [NSApp sendAction:fuzzyRules[@"z-zh"].action to:fuzzyRules[@"z-zh"].target from:fuzzyRules[@"z-zh"]];
        assert(![prefs fuzzyPinyinRuleEnabled:@"z-zh"] && [prefs fuzzyPinyinRuleEnabled:@"an-ang"]);
        assert([[prefs sharedPreferencesByMerging:base][@"fuzzy_pinyin"][@"enabled"] isEqual:@YES]);
        assert([[prefs sharedPreferencesByMerging:base][@"fuzzy_pinyin"][@"rules"] isEqual:@[@"an-ang"]]);
        for (NSString *mode in @[@"unicode", @"date_time", @"quick_phrase", @"emoji", @"kaomoji", @"super_jianpin", @"temporary_english", @"temporary_japanese"]) {
            NSButton *button = buttons[mode];
            assert(button && [prefs localModeEnabled:mode] == ![mode isEqual:@"unicode"]);
            NSUInteger before = changes;
            button.state = NSControlStateValueOff;
            [NSApp sendAction:button.action to:button.target from:button];
            assert(changes == before + 1 && ![prefs localModeEnabled:mode]);
            assert(![[[MSIMEAppearancePreferences alloc] initWithDefaults:defaults skinsRoot:prefs.skinsRoot] localModeEnabled:mode]);
            assert([[prefs sharedPreferencesByMerging:base][@"local_modes"][mode] isEqual:@NO]);
            button.state = NSControlStateValueOn;
            [NSApp sendAction:button.action to:button.target from:button];
            assert([prefs localModeEnabled:mode]);
        }
        assert([[prefs sharedPreferencesByMerging:base][@"local_modes"][@"future_field"] isEqual:@42]);
        [prefs applySharedLocalModes:@{@"unicode": @NO}];
        assert(buttons[@"unicode"].state == NSControlStateValueOff);
        assert([[prefs sharedPreferencesByMerging:base][@"local_modes"][@"unicode"] isEqual:@NO]);
        [prefs setLocalMode:@"unicode" enabled:YES];
        NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"quanpin", @"candidate_page_size": @5, @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
        for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
            options[name] = path;
        }
        NSError *error = nil;
        MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
        assert(session && !error && [session setFocused:YES error:&error]);
        NSDictionary *shared = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert(shared && !error);
        NSUInteger revision = 0;
        NSArray<NSArray<NSString *> *> *modes = @[@[@"unicode", @"U"], @[@"date_time", @"T"],
            @[@"quick_phrase", @"K"], @[@"emoji", @"E"], @[@"kaomoji", @"M"],
            @[@"super_jianpin", @"J"], @[@"temporary_english", @"Y"], @[@"temporary_japanese", @"R"]];
        for (NSString *scheme in @[@"quanpin", @"shuangpin"]) {
            prefs.inputScheme = scheme;
            NSDictionary *(^snapshot)(NSUInteger) = ^(NSUInteger nextRevision) {
                return @{@"format_version": @1, @"revision": @(nextRevision),
                    @"preferences": [prefs sharedPreferencesByMerging:shared[@"preferences"]]};
            };
            for (NSArray<NSString *> *entry in modes) {
                NSString *mode = entry[0];
                uint8_t trigger = (uint8_t)[entry[1] characterAtIndex:0];
                // Build each revision explicitly so both schemes exercise the same session.
                NSDictionary *enabled = snapshot(++revision);
                assert([[session updatePreferencesSnapshot:enabled error:&error][@"deferred"] isEqual:@NO]);
                NSDictionary *before = [session typeASCII:trigger shift:YES error:&error][@"view"];
                assert([before[@"local_mode"] isEqual:mode]);
                assert([before[@"scheme"] isEqual:[scheme isEqual:@"quanpin"] ? @0 : @1]);
                buttons[mode].state = NSControlStateValueOff;
                [NSApp sendAction:buttons[mode].action to:buttons[mode].target from:buttons[mode]];
                NSDictionary *disabled = snapshot(++revision);
                assert([[session updatePreferencesSnapshot:disabled error:&error][@"deferred"] isEqual:@YES]);
                assert([[session viewWithError:&error][@"editing_text"] isEqual:before[@"editing_text"]]);
                assert([[session viewWithError:&error][@"local_mode"] isEqual:mode]);
                assert([session command:MSIME_CANCEL error:&error]);
                assert([[session updatePreferencesSnapshot:disabled error:&error][@"deferred"] isEqual:@NO]);
                assert(![[session typeASCII:trigger shift:YES error:&error][@"view"][@"local_mode"] isEqual:mode]);
                assert([session command:MSIME_CANCEL error:&error]);
                buttons[mode].state = NSControlStateValueOn;
                [NSApp sendAction:buttons[mode].action to:buttons[mode].target from:buttons[mode]];
                NSDictionary *restored = snapshot(++revision);
                assert([[session updatePreferencesSnapshot:restored error:&error][@"deferred"] isEqual:@NO]);
                assert([[session typeASCII:trigger shift:YES error:&error][@"view"][@"local_mode"] isEqual:mode]);
                assert([session command:MSIME_CANCEL error:&error]);
            }
        }
        assert([session closeWithError:&error] && !error);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
    }
}
