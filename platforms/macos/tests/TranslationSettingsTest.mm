#import "../TranslationSettingsWindow.h"
#import "MSIMEClientSession.h"
#include <cassert>

@interface MSIMETranslationSettingsWindow (TestActions)
- (void)save:(id)sender;
- (void)reload:(id)sender;
- (void)revealKey:(id)sender;
- (void)updateControls:(id)sender;
@end
static void Wait(MSIMETranslationSettingsWindow *window) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while ([[window valueForKey:@"busy"] boolValue] && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(![[window valueForKey:@"busy"] boolValue]);
}
int main() {
    @autoreleasepool {
        [NSApplication sharedApplication];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSError *error = nil;
        NSDictionary *initial = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert(initial && !error);
        __block NSUInteger saves = 0;
        MSIMETranslationSettingsWindow *window = [[MSIMETranslationSettingsWindow alloc] initWithDirectory:root saved:^(NSDictionary *preferences) {
            assert(NSThread.isMainThread && [preferences[@"custom_translation"] isKindOfClass:NSDictionary.class]); ++saves;
        }];
        [window showWindow:nil]; Wait(window);
        NSButton *custom = [window valueForKey:@"custom"], *enabled = [window valueForKey:@"enabled"], *reveal = [window valueForKey:@"reveal"];
        NSTextField *endpoint = [window valueForKey:@"endpoint"], *plain = [window valueForKey:@"plainKey"];
        NSSecureTextField *key = [window valueForKey:@"key"];
        NSPopUpButton *target = [window valueForKey:@"target"];
        assert([key isKindOfClass:NSSecureTextField.class] && !key.hidden && plain.hidden);
        assert(target.numberOfItems == 7 && custom.state == NSControlStateValueOff && !endpoint.enabled);
        custom.state = NSControlStateValueOn; [window updateControls:nil];
        assert(endpoint.enabled && key.enabled);
        endpoint.stringValue = @"file:///synthetic";
        [window save:nil];
        assert(saves == 0 && ![[window valueForKey:@"busy"] boolValue]);
        endpoint.stringValue = @"https://translation.invalid/api"; key.stringValue = @"synthetic";
        reveal.state = NSControlStateValueOn; [window revealKey:nil];
        assert(key.hidden && !plain.hidden && !key.stringValue.length && [plain.stringValue isEqual:@"synthetic"]);
        plain.stringValue = @"synthetic-edited";
        reveal.state = NSControlStateValueOff; [window revealKey:nil];
        assert([key.stringValue isEqual:@"synthetic-edited"] && !plain.stringValue.length);
        [target selectItemAtIndex:1];
        [window save:nil]; Wait(window);
        assert(saves == 1);
        NSDictionary *stored = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert(stored && !error);
        assert([stored[@"preferences"][@"translation_target_language"] isEqual:@"fr"]);
        assert([stored[@"preferences"][@"custom_translation"][@"api_key"] isEqual:@"synthetic-edited"]);
        assert([stored[@"preferences"][@"custom_translation"][@"enabled"] isEqual:@YES]);
        assert([stored[@"preferences"][@"cloud_candidates"] isEqual:initial[@"preferences"][@"cloud_candidates"]]);
        // A different writer advances the revision; stale drafts cannot overwrite it.
        NSMutableDictionary *other = [stored mutableCopy], *otherPreferences = [stored[@"preferences"] mutableCopy];
        otherPreferences[@"candidate_page_size"] = @7; other[@"preferences"] = otherPreferences;
        assert([MSIMEClientSession savePreferencesInDirectory:root expectedRevision:[stored[@"revision"] unsignedLongLongValue] snapshot:other error:&error] && !error);
        endpoint.stringValue = @"https://changed.invalid/api";
        [window save:nil]; Wait(window);
        assert(saves == 1);
        [window reload:nil]; Wait(window);
        assert([endpoint.stringValue isEqual:@"https://translation.invalid/api"]);
        enabled.state = NSControlStateValueOff; custom.state = NSControlStateValueOff;
        [window updateControls:nil]; assert(!target.enabled && !endpoint.enabled);
        [window save:nil]; Wait(window); assert(saves == 2);
        stored = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert([stored[@"preferences"][@"candidate_page_size"] isEqual:@7]);
        assert([stored[@"preferences"][@"candidate_translations"] isEqual:@NO]);
        assert([stored[@"preferences"][@"custom_translation"][@"enabled"] isEqual:@NO]);
        assert([stored[@"preferences"][@"custom_translation"][@"api_key"] isEqual:@"synthetic-edited"]);
        [window.window.contentView layoutSubtreeIfNeeded];
        NSView *stack = window.window.contentView.subviews.firstObject;
        assert(NSMinY(stack.frame) >= 0 && NSMaxY(stack.frame) <= NSHeight(window.window.contentView.bounds));
        [window close];
        assert(!key.stringValue.length && !plain.stringValue.length && ![window valueForKey:@"snapshot"]);
        [window showWindow:nil]; [window close];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        assert(!key.stringValue.length && ![window valueForKey:@"snapshot"]);
        assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
    }
    return 0;
}
