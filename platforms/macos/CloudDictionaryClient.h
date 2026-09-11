#pragma once
#import <Foundation/Foundation.h>
typedef void (^MSIMECloudDictionaryCompletion)(NSData *data, NSInteger status, NSError *error);
FOUNDATION_EXPORT void MSIMEFetchCloudDictionary(NSString *kind, NSString *search, NSUInteger offset, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
