#import <Foundation/Foundation.h>

/// A single sequential batch for the visible candidate page (at most nine items).
/// All methods and completion run on the main thread. Retain until completion.
@interface MSIMECustomTranslationBatch : NSObject
/// NiuTrans plan items use the shared direction plan. Sign immediately before each request.
- (instancetype)initWithNiuTransItems:(NSArray<NSDictionary *> *)items config:(NSDictionary *)config
                        configuration:(NSURLSessionConfiguration *)configuration
                           completion:(void (^)(NSArray<NSDictionary *> *translations))completion;
/// Items are {text, request}, where request is a shared custom HTTP descriptor.
/// Copies the input. Completion receives successful {text, translation} results.
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items
                configuration:(NSURLSessionConfiguration *)configuration
                   completion:(void (^)(NSArray<NSDictionary *> *translations))completion;
/// Tencent plan items are {text, key, source_language, target_language}.
/// Groups matching directions; signs each group immediately before transport.
/// Copies inputs and retains no credentials after cancellation/completion.
- (instancetype)initWithTencentItems:(NSArray<NSDictionary *> *)items
                               config:(NSDictionary *)config
                        configuration:(NSURLSessionConfiguration *)configuration
                           completion:(void (^)(NSArray<NSDictionary *> *translations))completion;
/// AI items are {text, request}; each request is a shared AI HTTP descriptor.
- (instancetype)initWithAIItems:(NSArray<NSDictionary *> *)items
                   configuration:(NSURLSessionConfiguration *)configuration
                      completion:(void (^)(NSArray<NSDictionary *> *translations))completion;
/// Single-use. A six-second whole-batch deadline returns completed partial results.
- (void)start;
/// Suppresses completion, aborts transport and releases credential-bearing inputs.
- (void)cancel;
@end
