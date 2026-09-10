#import "../DictionaryRuntime.h"
#include <cassert>

int main() {
    @autoreleasepool {
        NSDictionary *valid = @{@"resources": @"/tmp/resources", @"user_data": @"/tmp/user", @"cache": @"/tmp/cache", @"dictionaries": @"/tmp/dictionaries"};
        NSError *error = nil;
        MSIMEDictionaryRuntime *runtime = [[MSIMEDictionaryRuntime alloc] initWithHostOptions:valid error:&error];
        assert(runtime && !error);
        assert([runtime.resourcesDirectory.path isEqual:@"/tmp/resources"]);
        NSMutableDictionary *missing = [valid mutableCopy]; [missing removeObjectForKey:@"cache"];
        error = nil; assert(![[MSIMEDictionaryRuntime alloc] initWithHostOptions:missing error:&error] && error);
        NSMutableDictionary *relative = [valid mutableCopy]; relative[@"resources"] = @"relative";
        error = nil; assert(![[MSIMEDictionaryRuntime alloc] initWithHostOptions:relative error:&error] && error);
    }
    return 0;
}
