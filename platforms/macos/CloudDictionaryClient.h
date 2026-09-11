#pragma once
#import <Foundation/Foundation.h>
typedef void (^MSIMECloudDictionaryCompletion)(NSData *data, NSInteger status, NSError *error);
FOUNDATION_EXPORT void MSIMEFetchCloudDictionary(NSString *kind, NSString *search, NSUInteger offset, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEMutateCloudDictionary(NSString *method, NSString *kind, NSString *entryID, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT NSString *MSIMEReadDictionaryImportFile(NSURL *url, NSError **error);
FOUNDATION_EXPORT BOOL MSIMESaveDictionaryExportFile(NSData *data, NSURL *url, NSError **error);
