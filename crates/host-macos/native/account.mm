#import <Foundation/Foundation.h>
#import <Security/Security.h>

static NSDictionary *MSIMEAccountQuery(void) {
    return @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"app.msime.backend.account",
        (__bridge id)kSecAttrAccount: @"https://api.msime.app",
    };
}

// Returns 1 when found, 0 when absent, and -1 for a keychain failure.
int msime_macos_account_load(uint8_t *buffer, size_t capacity, size_t *length) {
    if (!buffer || !length || capacity == 0) return -1;
    NSMutableDictionary *query = [MSIMEAccountQuery() mutableCopy];
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status == errSecItemNotFound) return 0;
    if (status != errSecSuccess || !result || ![(__bridge id)result isKindOfClass:[NSData class]]) {
        if (result) CFRelease(result);
        return -1;
    }
    NSData *data = (__bridge NSData *)result;
    if (data.length > capacity) {
        CFRelease(result);
        return -1;
    }
    [data getBytes:buffer length:data.length];
    *length = data.length;
    CFRelease(result);
    return 1;
}

bool msime_macos_account_save(const uint8_t *bytes, size_t length) {
    if (!bytes || length == 0 || length > 1024 * 1024) return false;
    NSData *data = [NSData dataWithBytes:bytes length:length];
    NSDictionary *attributes = @{
        (__bridge id)kSecValueData: data,
        (__bridge id)kSecAttrAccessible: (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    };
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)MSIMEAccountQuery(),
                                    (__bridge CFDictionaryRef)attributes);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *item = [MSIMEAccountQuery() mutableCopy];
        [item addEntriesFromDictionary:attributes];
        status = SecItemAdd((__bridge CFDictionaryRef)item, NULL);
    }
    return status == errSecSuccess;
}

bool msime_macos_account_clear(void) {
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)MSIMEAccountQuery());
    return status == errSecSuccess || status == errSecItemNotFound;
}
