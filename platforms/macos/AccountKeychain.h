#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *MSIMEKeychainToken(NSString *accountID, NSError **error);
FOUNDATION_EXPORT BOOL MSIMEStoreKeychainToken(NSString *accountID, NSString *token, NSError **error);
FOUNDATION_EXPORT BOOL MSIMERemoveKeychainToken(NSString *accountID, NSError **error);
