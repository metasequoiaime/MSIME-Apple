#import "MSIMEClientSession.h"
#include "msime_client.h"
#include <cassert>

// Explicit integration test: pass the lock-verified desktop resource directory.
// Active and staged user data are always created beneath a fresh temporary root.
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc != 2) { fputs("usage: snapshot-activation-test <desktop-resources>\n", stderr); return 2; }
        NSString *resources = [NSString stringWithUTF8String:argv[1]];
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSString *staging = [root stringByAppendingPathComponent:@"staging"];
        assert([NSFileManager.defaultManager createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:nil]);
        __block NSError *error = nil;
        __block NSDictionary *preparedHost = nil;
        dispatch_sync(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            preparedHost = [MSIMEClientSession prepareHostWithResourcesDirectory:resources stateRoot:[root stringByAppendingPathComponent:@"active"] error:&error];
        });
        assert(preparedHost && !error);
        NSMutableDictionary *options = [preparedHost mutableCopy];
        NSMutableDictionary *preferences = [options[@"preferences"] mutableCopy];
        preferences[@"learning"] = @NO;
        options[@"preferences"] = preferences;
        MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
        assert(session && !error && [session setFocused:YES error:&error]);
        for (NSNumber *enabled in @[@YES, @NO]) {
            assert([session setDedicatedEnglishEnabled:enabled.boolValue error:&error] && !error);
            uint64_t oldSession = [[session viewWithError:&error][@"session"] unsignedLongLongValue];
            NSString *version = [MSIMEClientSession snapshotVersionForOptions:options error:&error];
            assert(version && !error);
            NSDictionary *record = @{@"type":@"overlay", @"deleted":@NO,
                @"data":@{@"kind":@"english", @"code":@"msimesnapshotfixture", @"word":@"msimesnapshotfixture", @"weight":@10000, @"user_inserted":@YES}};
            __block NSDictionary *prepared = nil;
            dispatch_sync(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                __block BOOL sent = NO;
                prepared = [MSIMEClientSession prepareSnapshotRequest:@{@"options":options, @"staging_root":staging, @"expected_version":version, @"records":@1}
                    nextRecord:^NSDictionary *(NSError **readerError) {
                        (void)readerError;
                        if (sent) return nil;
                        sent = YES;
                        return record;
                    } error:&error];
            });
            assert(prepared && !error && [prepared[@"source_version"] isEqual:version]);
            __block NSUInteger notifications = 0;
            id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEClientSessionDidReplaceSnapshotNotification object:session queue:nil usingBlock:^(NSNotification *note) {
                assert(note.object == session && NSThread.isMainThread);
                assert([[session viewWithError:nil][@"dedicated_english"] isEqual:enabled]);
                ++notifications;
            }];
            BOOL activated = [MSIMEClientSession applySnapshotHandle:[prepared[@"handle"] unsignedLongLongValue] expectedVersion:version error:&error];
            if (!activated) NSLog(@"Synthetic snapshot activation failed: %@", error.localizedDescription);
            assert(activated);
            assert(!error && notifications == 1);
            [NSNotificationCenter.defaultCenter removeObserver:observer];
            NSDictionary *view = [session viewWithError:&error];
            assert([view[@"session"] unsignedLongLongValue] != oldSession && [view[@"editing_text"] length] == 0);
            assert([view[@"dedicated_english"] isEqual:enabled]);
            assert([session setFocused:YES error:&error]);
            if (enabled.boolValue) {
                NSString *text = @"msimesnapshotfixture";
                for (NSUInteger i = 0; i < text.length; ++i) assert([session typeASCII:[text characterAtIndex:i] shift:NO error:&error]);
                assert([[[session viewWithError:&error][@"candidates"] firstObject][@"text"] isEqual:text]);
                assert([[session command:MSIME_COMMIT_CANDIDATE error:&error][@"commit"] isEqual:text]);
            }
        }
        assert([session closeWithError:&error] && !error);
        assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
        puts("Packaged snapshot activation, English mode retention and imported candidate commit passed");
    }
    return 0;
}
