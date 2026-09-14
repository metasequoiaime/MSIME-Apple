#import "MSIMEClientSession.h"
#include <cassert>

int main() {
    @autoreleasepool {
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"quanpin", @"candidate_page_size": @5, @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
        for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
            NSString *path = [root stringByAppendingPathComponent:name];
            assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
            options[name] = path;
        }
        NSError *error = nil;
        MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
        assert(session && !error);
        uint64_t first = [[session startVoiceWithError:&error][@"generation"] unsignedLongLongValue];
        assert(first > 0 && !error);
        assert(![session applyVoiceText:@"" generation:first error:&error] && !error);
        NSDictionary *result = [session applyVoiceText:@"synthetic voice result" generation:first error:&error];
        assert([result[@"commit"] isEqual:@"synthetic voice result"] && !error);
        assert([result[@"view"] isKindOfClass:NSDictionary.class]);
        assert(![session applyVoiceText:@"duplicate" generation:first error:&error] && !error);
        uint64_t second = [[session startVoiceWithError:&error][@"generation"] unsignedLongLongValue];
        assert(second > first);
        assert([session cancelVoiceWithError:&error] && !error);
        assert(![session applyVoiceText:@"cancelled" generation:second error:&error] && !error);
        uint64_t third = [[session startVoiceWithError:&error][@"generation"] unsignedLongLongValue];
        assert(third > second);
        assert(![session applyVoiceText:@"stale" generation:first error:&error] && !error);
        assert([[[session applyVoiceText:@"synthetic successor" generation:third error:&error] objectForKey:@"commit"] isEqual:@"synthetic successor"]);
        assert([session closeWithError:&error] && !error);
        assert([NSFileManager.defaultManager removeItemAtPath:root error:&error] && !error);
    }
}
