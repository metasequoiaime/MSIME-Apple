#pragma once
#import <Foundation/Foundation.h>
@interface MSIMEAccountSessionManager : NSObject
+ (instancetype)sharedManager;
- (NSString *)accessTokenForAccountID:(NSString *)accountID;
- (NSString *)refreshTokenForAccountID:(NSString *)accountID;
- (BOOL)clearAccount:(NSString *)accountID error:(NSError **)error;
@end
