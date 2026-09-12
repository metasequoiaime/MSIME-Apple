#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
typedef void (^MetasequoiaTranslationCompletion)(NSString *_Nullable text, NSError *_Nullable error);
@interface MetasequoiaDeepLXClient : NSObject
- (NSURLSessionDataTask *)translateText:(NSString *)text
                         targetLanguage:(NSString *)targetLanguage
                               endpoint:(NSString *)endpoint
                             completion:(MetasequoiaTranslationCompletion)completion;
@end
@interface MetasequoiaTencentTmtClient : NSObject
- (NSURLSessionDataTask *)translateText:(NSString *)text
                         targetLanguage:(NSString *)targetLanguage
                                 region:(NSString *)region
                               secretId:(NSString *)secretId
                              secretKey:(NSString *)secretKey
                             completion:(MetasequoiaTranslationCompletion)completion;
@end
NS_ASSUME_NONNULL_END
