#pragma once
#import <Foundation/Foundation.h>
typedef void (^MSIMECloudClipboardCompletion)(NSData *data, NSInteger status, NSError *error);
FOUNDATION_EXPORT void MSIMEFetchCloudClipboard(NSString *search, NSString *token, MSIMECloudClipboardCompletion completion);
FOUNDATION_EXPORT void MSIMESetCloudClipboardEnabled(BOOL enabled, NSString *token, MSIMECloudClipboardCompletion completion);
FOUNDATION_EXPORT void MSIMEAddCloudClipboard(NSString *text, NSString *token, MSIMECloudClipboardCompletion completion);
FOUNDATION_EXPORT void MSIMERemoveCloudClipboard(NSString *itemID, NSString *token, MSIMECloudClipboardCompletion completion);
