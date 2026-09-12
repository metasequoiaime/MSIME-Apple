#import "../TranslationSettingsWindow.h"
#import "MSIMEClientSession.h"
#include <cassert>

@interface MSIMETranslationSettingsWindow (TestActions)
- (void)save:(id)sender;
- (void)reload:(id)sender;
- (void)revealKey:(id)sender;
- (void)revealTencentKey:(id)sender;
- (void)updateControls:(id)sender;
- (void)providerChanged:(id)sender;
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
        NSButton *enabled = [window valueForKey:@"enabled"], *reveal = [window valueForKey:@"reveal"];
        NSPopUpButton *provider = [window valueForKey:@"provider"];
        NSGridView *grid = [window valueForKey:@"grid"];
        NSTextField *endpoint = [window valueForKey:@"endpoint"], *plain = [window valueForKey:@"plainKey"];
        NSSecureTextField *key = [window valueForKey:@"key"];
        NSPopUpButton *target = [window valueForKey:@"target"];
        NSButton *tencent = [window valueForKey:@"tencent"], *revealTencent = [window valueForKey:@"revealTencent"];
        NSTextField *secretId = [window valueForKey:@"secretId"], *region = [window valueForKey:@"region"], *plainTencent = [window valueForKey:@"plainTencentKey"];
        NSSecureTextField *tencentKey = [window valueForKey:@"tencentKey"];
        assert([tencentKey isKindOfClass:NSSecureTextField.class] && !tencentKey.hidden && plainTencent.hidden);
        assert(tencent.state == NSControlStateValueOn && secretId.enabled && [region.stringValue isEqual:@"ap-guangzhou"]);
        secretId.stringValue = @"AKIDsynthetic"; tencentKey.stringValue = @"synthetic-tencent";
        assert([key isKindOfClass:NSSecureTextField.class] && !key.hidden && plain.hidden);
        assert(target.numberOfItems == 7 && provider.indexOfSelectedItem == 0 && !endpoint.enabled);
        assert(([provider.itemTitles isEqual:@[@"腾讯云", @"自定义 DeepLX"]]));
        assert([grid rowAtIndex:3].hidden && ![grid rowAtIndex:6].hidden);
        [provider selectItemAtIndex:1]; [window providerChanged:nil];
        assert(![grid rowAtIndex:3].hidden && [grid rowAtIndex:6].hidden);
        assert(endpoint.enabled && key.enabled);
        assert(!tencent.enabled && !secretId.enabled && !tencentKey.enabled && !region.enabled);
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
        assert([stored[@"preferences"][@"tencent_tmt"][@"secret_key"] isEqual:@"synthetic-tencent"]);
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
        assert(provider.indexOfSelectedItem == 1 && ![grid rowAtIndex:3].hidden && [grid rowAtIndex:6].hidden);
        enabled.state = NSControlStateValueOff; [provider selectItemAtIndex:0];
        [window providerChanged:nil]; assert(!target.enabled && !endpoint.enabled);
        [window save:nil]; Wait(window); assert(saves == 2);
        stored = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert([stored[@"preferences"][@"candidate_page_size"] isEqual:@7]);
        assert([stored[@"preferences"][@"candidate_translations"] isEqual:@NO]);
        assert([stored[@"preferences"][@"custom_translation"][@"enabled"] isEqual:@NO]);
        assert([stored[@"preferences"][@"custom_translation"][@"api_key"] isEqual:@"synthetic-edited"]);
        assert(tencent.enabled && secretId.enabled && tencentKey.enabled);
        revealTencent.state = NSControlStateValueOn; [window revealTencentKey:nil];
        assert(tencentKey.hidden && !plainTencent.hidden && !tencentKey.stringValue.length);
        assert([plainTencent.stringValue isEqual:@"synthetic-tencent"]);
        [provider selectItemAtIndex:1]; [window providerChanged:nil];
        assert(revealTencent.state == NSControlStateValueOff && !plainTencent.stringValue.length);
        assert([tencentKey.stringValue isEqual:@"synthetic-tencent"] && ![grid rowAtIndex:3].hidden);
        reveal.state = NSControlStateValueOn; [window revealKey:nil];
        [provider selectItemAtIndex:0]; [window providerChanged:nil];
        assert(reveal.state == NSControlStateValueOff && !plain.stringValue.length);
        assert([key.stringValue isEqual:@"synthetic-edited"] && [grid rowAtIndex:3].hidden);
        revealTencent.state = NSControlStateValueOn; [window revealTencentKey:nil];
        plainTencent.stringValue = @"synthetic-tencent-edited"; region.stringValue = @"ap-shanghai";
        [window save:nil]; Wait(window); assert(saves == 3);
        stored = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert([stored[@"preferences"][@"tencent_tmt"][@"secret_key"] isEqual:@"synthetic-tencent-edited"]);
        assert([stored[@"preferences"][@"tencent_tmt"][@"region"] isEqual:@"ap-shanghai"]);
        revealTencent.state = NSControlStateValueOff; [window revealTencentKey:nil];
        assert(!plainTencent.stringValue.length && [tencentKey.stringValue isEqual:@"synthetic-tencent-edited"]);
        // Shared validation rejects malformed drafts without changing stored settings.
        region.stringValue = @"invalid\nregion"; [window save:nil]; Wait(window); assert(saves == 3);
        assert([[MSIMEClientSession loadPreferencesInDirectory:root error:&error][@"revision"] isEqual:stored[@"revision"]]);
        [window reload:nil]; Wait(window);
        assert([region.stringValue isEqual:@"ap-shanghai"] && !tencentKey.hidden && plainTencent.hidden);
        assert(provider.indexOfSelectedItem == 0 && [grid rowAtIndex:3].hidden && ![grid rowAtIndex:6].hidden);
        // A concurrent edit also protects Tencent drafts through the same CAS revision.
        other = [stored mutableCopy]; otherPreferences = [stored[@"preferences"] mutableCopy];
        otherPreferences[@"candidate_page_size"] = @8; other[@"preferences"] = otherPreferences;
        assert([MSIMEClientSession savePreferencesInDirectory:root expectedRevision:[stored[@"revision"] unsignedLongLongValue] snapshot:other error:&error]);
        secretId.stringValue = @"AKIDchanged"; [window save:nil]; Wait(window); assert(saves == 3);
        [window reload:nil]; Wait(window); assert([secretId.stringValue isEqual:@"AKIDsynthetic"]);
        tencent.state = NSControlStateValueOff; [window updateControls:nil];
        assert(!secretId.enabled && !tencentKey.enabled && !region.enabled);
        [window save:nil]; Wait(window); assert(saves == 4);
        stored = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
        assert([stored[@"preferences"][@"tencent_tmt"][@"enabled"] isEqual:@NO]);
        assert([stored[@"preferences"][@"tencent_tmt"][@"secret_key"] isEqual:@"synthetic-tencent-edited"]);
        assert([stored[@"preferences"][@"candidate_page_size"] isEqual:@8]);
        [window.window.contentView layoutSubtreeIfNeeded];
        NSView *stack = window.window.contentView.subviews.firstObject;
        assert(NSMinY(stack.frame) >= 0 && NSMaxY(stack.frame) <= NSHeight(window.window.contentView.bounds));
        assert(NSMinX(stack.frame) >= 0 && NSMaxX(stack.frame) <= NSWidth(window.window.contentView.bounds));
        for (NSView *field in @[secretId, tencentKey, region, tencent]) {
            NSRect rect = [field convertRect:field.bounds toView:window.window.contentView];
            assert(NSMinX(rect) >= 0 && NSMaxX(rect) <= NSWidth(window.window.contentView.bounds));
            assert(NSMinY(rect) >= 0 && NSMaxY(rect) <= NSHeight(window.window.contentView.bounds));
        }
        [window close];
        assert(!key.stringValue.length && !plain.stringValue.length && ![window valueForKey:@"snapshot"]);
        assert(!secretId.stringValue.length && !tencentKey.stringValue.length && !plainTencent.stringValue.length);
        [window showWindow:nil]; [window close];
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        assert(!key.stringValue.length && ![window valueForKey:@"snapshot"]);
        assert(!secretId.stringValue.length && !tencentKey.stringValue.length && !plainTencent.stringValue.length);
        // Real Apple -> C -> Rust disk roundtrip, outside the main input thread.
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            assert(!NSThread.isMainThread);
            NSError *failure = nil;
            NSDictionary *write = @{@"directory":root, @"action":@"remember", @"target_language":@"en", @"generation":@19,
                @"items":@[@{@"text":@"Hello", @"direction":@"english_to_chinese", @"translation":@"你好"}]};
            NSDictionary *saved = [MSIMEClientSession learnedTranslationRequest:write error:&failure];
            assert(saved && !failure && [saved[@"saved"] isEqual:@1]);
            NSDictionary *read = @{@"directory":root, @"action":@"lookup", @"target_language":@"en", @"generation":@20,
                @"items":@[@{@"text":@"HELLO", @"direction":@"english_to_chinese"}]};
            NSDictionary *found = [MSIMEClientSession learnedTranslationRequest:read error:&failure];
            assert(found && !failure && [found[@"generation"] isEqual:@20]);
            assert(([found[@"translations"] isEqual:@[@{@"text":@"HELLO", @"translation":@"你好"}]]));
            NSMutableDictionary *bad = [read mutableCopy]; bad[@"directory"] = @"relative";
            assert(![MSIMEClientSession learnedTranslationRequest:bad error:&failure] && failure);
            dispatch_semaphore_signal(done);
        });
        assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC)) == 0);
        assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
    }
    return 0;
}
