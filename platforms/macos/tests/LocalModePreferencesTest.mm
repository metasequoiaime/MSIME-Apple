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
        [prefs applySharedLocalModes:@{@"unicode": @1}];
        assert(![prefs localModeEnabled:@"unicode"]);
        NSScrollView *scroll = (id)prefs.window.contentView.subviews.firstObject;
        NSGridView *grid = (id)scroll.documentView;
        NSMutableDictionary<NSString *, NSButton *> *buttons = [NSMutableDictionary dictionary];
        for (NSInteger row = 0; row < grid.numberOfRows; ++row) {
            NSControl *control = (id)[grid cellAtColumnIndex:1 rowIndex:row].contentView;
            if (control.action == NSSelectorFromString(@"localModeChanged:")) buttons[control.identifier] = (id)control;
        }
        assert(buttons.count == 8);
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
        assert([[[session typeASCII:'U' shift:YES error:&error][@"view"] objectForKey:@"local_mode"] isEqual:@"unicode"]);
        [prefs setLocalMode:@"unicode" enabled:NO];
        NSDictionary *shared = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert(shared && !error);
        NSDictionary *snapshot = @{@"format_version": @1, @"revision": @1,
            @"preferences": [prefs sharedPreferencesByMerging:shared[@"preferences"]]};
        assert([[session updatePreferencesSnapshot:snapshot error:&error][@"deferred"] isEqual:@YES]);
        assert([[session viewWithError:&error][@"local_mode"] isEqual:@"unicode"]);
        assert([session command:MSIME_CANCEL error:&error]);
        assert([[session updatePreferencesSnapshot:snapshot error:&error][@"deferred"] isEqual:@NO]);
        assert(![[session typeASCII:'U' shift:YES error:&error][@"view"][@"local_mode"] isEqual:@"unicode"]);
        assert([session command:MSIME_CANCEL error:&error]);
        buttons[@"unicode"].state = NSControlStateValueOn;
        [NSApp sendAction:buttons[@"unicode"].action to:buttons[@"unicode"].target from:buttons[@"unicode"]];
        NSDictionary *restored = @{@"format_version": @1, @"revision": @2,
            @"preferences": [prefs sharedPreferencesByMerging:shared[@"preferences"]]};
        assert([[session updatePreferencesSnapshot:restored error:&error][@"deferred"] isEqual:@NO]);
        assert([[session typeASCII:'U' shift:YES error:&error][@"view"][@"local_mode"] isEqual:@"unicode"]);
        assert([session closeWithError:&error] && !error);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        [defaults removePersistentDomainForName:suite];
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
    }
}
