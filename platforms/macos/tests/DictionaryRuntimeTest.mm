#import "../ClientDictionaryRuntime.h"
#import "../../../shared/apple/MSIMEClientSession.h"
#include <cassert>

int main() {
    @autoreleasepool {
        NSDictionary *valid = @{@"resources": @"/tmp/resources", @"user_data": @"/tmp/user", @"cache": @"/tmp/cache", @"dictionaries": @"/tmp/dictionaries"};
        NSError *error = nil;
        MSIMEDictionaryRuntime *runtime = [[MSIMEDictionaryRuntime alloc] initWithHostOptions:valid error:&error];
        assert(runtime && !error);
        assert([runtime.resourcesDirectory.path isEqual:@"/tmp/resources"]);
        assert([runtime.userDataDirectory.path isEqual:@"/tmp/user"]);
        assert([runtime.cacheDirectory.path isEqual:@"/tmp/cache"]);
        assert([runtime.dictionariesDirectory.path isEqual:@"/tmp/dictionaries"]);
        NSMutableDictionary *missing = [valid mutableCopy]; [missing removeObjectForKey:@"cache"];
        error = nil; assert(![[MSIMEDictionaryRuntime alloc] initWithHostOptions:missing error:&error] && error);
        NSMutableDictionary *relative = [valid mutableCopy]; relative[@"resources"] = @"relative";
        error = nil; assert(![[MSIMEDictionaryRuntime alloc] initWithHostOptions:relative error:&error] && error);
        for (NSString *key in valid) {
            for (id invalid in @[@"relative", @"", @42, NSNull.null]) {
                NSMutableDictionary *options = [valid mutableCopy];
                options[key] = invalid;
                error = nil;
                assert(![[MSIMEDictionaryRuntime alloc] initWithHostOptions:options error:&error]);
                assert([error.domain isEqual:@"app.msime.client.dictionary-runtime"]);
            }
        }

        // Exercise the actual host API on a private fixture, never a user's dictionary.
        NSURL *fixture = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];
        assert([NSFileManager.defaultManager createDirectoryAtURL:fixture
            withIntermediateDirectories:YES attributes:nil error:&error]);
        __block NSUInteger completions = 0;
        __block BOOL returned = NO;
        [MSIMEDictionaryRuntime prepareResourcesDirectory:
            [fixture URLByAppendingPathComponent:@"missing-resources"].path
            stateRoot:[fixture URLByAppendingPathComponent:@"state"].path
            completion:^(NSDictionary *options, NSError *failure) {
                assert(NSThread.isMainThread);
                assert(returned);
                assert(!options && failure);
                completions++;
            }];
        returned = YES;
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (!completions && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(completions == 1);
        NSError *discardError = nil;
        assert(![MSIMEClientSession discardSnapshotHandle:UINT64_MAX error:&discardError]);
        assert(discardError != nil);
        assert([NSFileManager.defaultManager removeItemAtURL:fixture error:nil]);
    }
    return 0;
}
