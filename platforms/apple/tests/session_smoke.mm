#import "MSIMEClientSession.h"
#include "msime_client.h"
#include <cassert>
#include <initializer_list>

int main() {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"quanpin", @"candidate_page_size": @5, @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
        for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            BOOL created = [[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil];
            assert(created);
            options[name] = path;
        }
        NSError *error = nil;
        MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
        assert(session && !error);
        assert([session setFocused:YES error:&error]);
        assert([session typeASCII:'U' shift:YES error:&error]);
        for (uint8_t key : {'4', 'e', '2', 'd'}) assert([session typeASCII:key shift:NO error:&error]);
        NSDictionary *result = [session command:MSIME_COMMIT_CANDIDATE error:&error];
        assert([result[@"commit"] isEqual:@"中"]);
        __block BOOL rejected = NO;
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_DEFAULT, 0), ^{
            NSError *threadError = nil;
            rejected = ![session viewWithError:&threadError] && threadError != nil;
            dispatch_semaphore_signal(done);
        });
        assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        assert(rejected);
        assert([session closeWithError:&error]);
        assert(![session viewWithError:&error]);
        assert(error);
        [[NSFileManager defaultManager] removeItemAtPath:root error:nil];
        puts("Apple Foundation consumer: input, commit, thread and lifetime checks passed");
    }
    return 0;
}
