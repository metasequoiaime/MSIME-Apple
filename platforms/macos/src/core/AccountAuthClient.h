#pragma once
#import <Foundation/Foundation.h>
typedef void (^MSIMEAuthCompletion)(NSData *data, NSInteger status, NSError *error);
FOUNDATION_EXPORT void MSIMEAuthChallenge(NSString *linkToken, MSIMEAuthCompletion completion);
FOUNDATION_EXPORT void MSIMEAuthLogin(NSString *challenge, NSString *credential, NSString *linkToken, MSIMEAuthCompletion completion);
FOUNDATION_EXPORT void MSIMEAuthRefresh(NSString *refreshToken, MSIMEAuthCompletion completion);
