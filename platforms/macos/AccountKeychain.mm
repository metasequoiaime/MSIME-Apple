#import "AccountKeychain.h"
#import <Security/Security.h>
NSString *MSIMEKeychainToken(NSString *accountID, NSError **error) {
    if (accountID.length == 0 || [accountID rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) { if (error) *error = [NSError errorWithDomain:@"MSIMEAccount" code:400 userInfo:nil]; return nil; }
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: @"com.metasequoia.msime.account", (__bridge id)kSecAttrAccount: accountID, (__bridge id)kSecReturnData: @YES};
    CFTypeRef result = NULL; OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) { if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]; return nil; }
    return [[NSString alloc] initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding];
}

BOOL MSIMEStoreKeychainToken(NSString *accountID, NSString *token, NSError **error) {
    if (accountID.length == 0 || token.length == 0 || [accountID rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) { if (error) *error = [NSError errorWithDomain:@"MSIMEAccount" code:400 userInfo:nil]; return NO; }
    NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding]; NSDictionary *query = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,(__bridge id)kSecAttrService:@"com.metasequoia.msime.account",(__bridge id)kSecAttrAccount:accountID};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query, (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
    if (status == errSecItemNotFound) { NSMutableDictionary *item = [query mutableCopy]; item[(__bridge id)kSecValueData] = data; status = SecItemAdd((__bridge CFDictionaryRef)item, NULL); }
    if (status != errSecSuccess) { if (error) *error = [NSError errorWithDomain:@"MSIMEAccount" code:status userInfo:nil]; return NO; } return YES;
}
