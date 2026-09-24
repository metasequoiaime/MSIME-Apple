#import <Foundation/Foundation.h>

#include "../../src/settings/RuntimeOptionsRefresh.h"

#include <stdexcept>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

int refreshCalls = 0;

char *CountingRefresh(const uint8_t *, size_t)
{
    ++refreshCalls;
    return nullptr;
}

NSData *Write(NSString *path, id document)
{
    NSData *data = [NSJSONSerialization dataWithJSONObject:document options:NSJSONWritingPrettyPrinted error:nil];
    Require([data writeToFile:path atomically:YES], "Cannot write a fixture options file.");
    return data;
}

NSDictionary *StaleLayout(NSString *root)
{
    NSString *state = [root stringByAppendingPathComponent:@"state"];
    return @{
        @"api_version" : @1,
        @"resources" : [root stringByAppendingPathComponent:@"missing-resources"],
        @"user_data" : [state stringByAppendingPathComponent:@"user"],
        @"cache" : [state stringByAppendingPathComponent:@"cache"],
        @"dictionaries" : [state stringByAppendingPathComponent:@"user/dictionaries/previous-generation"],
        @"preferences_directory" : state,
        @"online_provider_socket" : @"/synthetic/provider.sock",
    };
}
} // namespace

int main()
{
    @autoreleasepool
    {
        NSFileManager *files = NSFileManager.defaultManager;
        NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        Require([files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil],
                "Cannot create the fixture directory.");

        NSString *missing = [root stringByAppendingPathComponent:@"missing/runtime-options.json"];
        Require(MSIMERefreshRuntimeOptionsWith(missing, nil, msime_client_refresh_host) == MSIMERuntimeOptionsRefreshFailed,
                "A missing options file was not reported as a failed refresh.");
        Require(MSIMERefreshRuntimeOptionsWith(@"runtime-options.json", nil, msime_client_refresh_host) ==
                    MSIMERuntimeOptionsRefreshFailed,
                "A relative options path was accepted.");

        NSString *stale = [root stringByAppendingPathComponent:@"stale.json"];
        NSData *staleBytes = Write(stale, StaleLayout(root));
        Require(MSIMERefreshRuntimeOptionsWith(stale, nil, msime_client_refresh_host) == MSIMERuntimeOptionsRefreshFailed,
                "A stale generation whose resources cannot be verified did not report failure.");
        Require([[NSData dataWithContentsOfFile:stale] isEqualToData:staleBytes],
                "A failed refresh modified the options file.");

        NSString *link = [root stringByAppendingPathComponent:@"linked.json"];
        Require([files createSymbolicLinkAtPath:link withDestinationPath:stale error:nil], "Cannot create the fixture symlink.");
        Require(MSIMERefreshRuntimeOptionsWith(link, nil, msime_client_refresh_host) == MSIMERuntimeOptionsRefreshCurrent,
                "A symlinked options file was not left alone.");
        Require([[NSData dataWithContentsOfFile:stale] isEqualToData:staleBytes],
                "Refreshing through a symlink modified its target.");
        NSDictionary *linkAttributes = [files attributesOfItemAtPath:link error:nil];
        Require([linkAttributes[NSFileType] isEqual:NSFileTypeSymbolicLink], "The symlink was replaced by a file.");

        NSString *foreign = [root stringByAppendingPathComponent:@"foreign.json"];
        NSData *foreignBytes = Write(foreign, @{
            @"api_version" : @1,
            @"resources" : @"/synthetic/resources",
            @"dictionaries" : @"/synthetic/elsewhere/dictionaries",
        });
        Require(MSIMERefreshRuntimeOptionsWith(foreign, nil, msime_client_refresh_host) == MSIMERuntimeOptionsRefreshCurrent,
                "A document outside the prepared layout was not left alone.");
        Require([[NSData dataWithContentsOfFile:foreign] isEqualToData:foreignBytes],
                "A document outside the prepared layout was rewritten.");

        NSString *bundle = [root stringByAppendingPathComponent:@"Metasequoia.app"];
        NSString *embedded = [bundle stringByAppendingPathComponent:@"Contents/Resources/runtime-options.json"];
        Require([files createDirectoryAtPath:embedded.stringByDeletingLastPathComponent withIntermediateDirectories:YES
                                  attributes:nil error:nil],
                "Cannot create the fixture bundle.");
        NSData *embeddedBytes = Write(embedded, StaleLayout(root));
        Require(MSIMERefreshRuntimeOptionsWith(embedded, bundle, CountingRefresh) == MSIMERuntimeOptionsRefreshCurrent,
                "Options inside the main bundle were not skipped.");
        Require(MSIMERefreshRuntimeOptionsWith([bundle stringByAppendingPathComponent:@"Contents/../Contents/Resources/runtime-options.json"],
                                               bundle, CountingRefresh) == MSIMERuntimeOptionsRefreshCurrent,
                "A non-standardized path inside the main bundle was not skipped.");
        Require(refreshCalls == 0, "The Host API was called for options inside the main bundle.");
        Require([[NSData dataWithContentsOfFile:embedded] isEqualToData:embeddedBytes],
                "Options inside the main bundle were modified.");

        NSString *sibling = [root stringByAppendingPathComponent:@"Metasequoia.app-data/runtime-options.json"];
        Require(MSIMERefreshRuntimeOptionsWith(sibling, bundle, CountingRefresh) == MSIMERuntimeOptionsRefreshFailed &&
                    refreshCalls == 1,
                "A path that only shares the bundle path as a string prefix was treated as inside the bundle.");

        [files removeItemAtPath:root error:nil];
    }
    return 0;
}
