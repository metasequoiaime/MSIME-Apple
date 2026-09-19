#import <Foundation/Foundation.h>
#import <Security/Security.h>

#include <cstring>

namespace {
BOOL TrashIfPresent(NSURL *url, NSString *what, NSError **error) {
    if (!url || ![[NSFileManager defaultManager] fileExistsAtPath:url.path]) return YES;
    NSError *failure = nil;
    if ([[NSFileManager defaultManager] trashItemAtURL:url resultingItemURL:nil error:&failure]) return YES;
    if (error) {
        NSString *reason = failure.localizedDescription.length ? failure.localizedDescription : @"未知错误";
        *error = [NSError errorWithDomain:@"MSIMEUninstall" code:1 userInfo:@{
            NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@未能移到废纸篓：%@", what, reason]
        }];
    }
    return NO;
}

NSURL *PreferencesPlist(NSString *domain) {
    NSURL *library = [[NSFileManager defaultManager] URLForDirectory:NSLibraryDirectory
                                                              inDomain:NSUserDomainMask
                                                     appropriateForURL:nil
                                                                create:NO
                                                                 error:nil];
    if (!library || !domain.length) return nil;
    return [[library URLByAppendingPathComponent:@"Preferences" isDirectory:YES]
        URLByAppendingPathComponent:[domain stringByAppendingPathExtension:@"plist"]];
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
        NSError *failure = nil;
        if (!TrashIfPresent(bundleURL, @"输入法", &failure)) return false;
        if (!remove_user_data) return true;
        if (dataPresent && !TrashIfPresent(userDataURL, @"词库与学习数据", &failure)) return false;
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:domain];
        // cfprefsd may keep the domain file after the in-process removal. Move the
        // file too, so a later launch cannot resurrect credentials or stale settings.
        if (!TrashIfPresent(PreferencesPlist(domain), @"偏好设置", &failure)) return false;
        NSString *service = [domain stringByAppendingString:@".voice"];
        NSDictionary *query = @{ (__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword,
                                 (__bridge id)kSecAttrService : service };
        (void)SecItemDelete((__bridge CFDictionaryRef)query);
        return true;
    }
}
