#import "AccountKeychain.h"
#import <Security/Security.h>
NSString *MSIMEKeychainToken(NSString *accountID, NSError **error) {
    if (accountID.length == 0 || [accountID rangeOfCharacterFromSet:[NSCharacterSet controlCharacterSet]].location != NSNotFound) { if (error) *error = [NSError errorWithDomain:@"MSIMEAccount" code:400 userInfo:nil]; return nil; }
    NSDictionary *query = @{(__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService: @"com.metasequoia.msime.account", (__bridge id)kSecAttrAccount: accountID, (__bridge id)kSecReturnData: @YES};
    CFTypeRef result = NULL; OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess) { if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain code:status userInfo:nil]; return nil; }
    return [[NSString alloc] initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding];
}
