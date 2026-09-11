#pragma once
#import <Foundation/Foundation.h>
typedef void (^MSIMECloudDictionaryCompletion)(NSData *data, NSInteger status, NSError *error);
FOUNDATION_EXPORT void MSIMEFetchCloudDictionary(NSString *kind, NSString *search, NSUInteger offset, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEMutateCloudDictionary(NSString *method, NSString *kind, NSString *entryID, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT NSString *MSIMEReadDictionaryImportFile(NSURL *url, NSError **error);
FOUNDATION_EXPORT BOOL MSIMESaveDictionaryExportFile(NSData *data, NSURL *url, NSError **error);
FOUNDATION_EXPORT void MSIMEImportCloudDictionary(NSString *kind, NSString *format, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEExportCloudDictionary(NSString *kind, NSString *format, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEFetchCloudDictionaryCatalog(NSString *kind, NSString *code, NSUInteger offset, NSString *scheme, NSString *profile, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEEditCloudDictionaryCatalog(NSString *kind, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEFetchCloudDictionaryChanges(long long after, NSUInteger limit, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMESendCloudCandidateRequest(NSString *path, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEListCloudFixedPositions(NSString *context, NSUInteger offset, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEMutateCloudFixedPosition(NSString *method, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
FOUNDATION_EXPORT void MSIMEFetchCloudDictionarySnapshot(NSString *bearerToken, MSIMECloudDictionaryCompletion completion);
