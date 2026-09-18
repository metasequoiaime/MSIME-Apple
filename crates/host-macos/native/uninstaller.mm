#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <cstring>

namespace {
BOOL TrashIfPresent(NSURL *url) {
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return YES;
    return [[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:nil error:nil];
}
}

extern "C" bool msime_macos_uninstall_input_source(const char *bundle_path,
                                                     const char *user_data_path,
                                                     const char *preferences_domain,
                                                     bool remove_user_data) {
    if (!bundle_path || !preferences_domain) return false;
    @autoreleasepool {
        NSString *bundle = [NSString stringWithUTF8String:bundle_path];
        NSString *userData = user_data_path ? [NSString stringWithUTF8String:user_data_path] : nil;
        NSString *domain = [NSString stringWithUTF8String:preferences_domain];
        if (!bundle || !domain) return false;
        NSURL *bundleURL = [NSURL fileURLWithPath:bundle isDirectory:YES];
        NSURL *userDataURL = userData.length ? [NSURL fileURLWithPath:userData isDirectory:YES] : nil;
        BOOL bundlePresent = [[NSFileManager defaultManager] fileExistsAtPath:bundleURL.path];
        BOOL dataPresent = userDataURL && [[NSFileManager defaultManager] fileExistsAtPath:userDataURL.path];
        if (!bundlePresent && !(remove_user_data && dataPresent)) return false;
        // The bundle is the first mutation. A failed move leaves all user data intact.
        if (!TrashIfPresent(bundleURL)) return false;
        if (!remove_user_data) return true;
        if (dataPresent && !TrashIfPresent(userDataURL)) return false;
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domain];
        NSString *service = [domain stringByAppendingString:@".voice"];
        NSDictionary *query = @{ (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecAttrService : service };
        (void)SecItemDelete((__bridge CFDictionaryRef)query);
        return true;
    }
}
