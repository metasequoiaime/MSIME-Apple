#import <Foundation/Foundation.h>

/// A single sequential batch for the visible candidate page (at most nine items).
/// All methods and completion run on the main thread. Retain until completion.
@interface MSIMECustomTranslationBatch : NSObject
/// Items are {text, request}, where request is a shared custom HTTP descriptor.
/// Copies the input. Completion receives successful {text, translation} results.
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items
                configuration:(NSURLSessionConfiguration *)configuration
                   completion:(void (^)(NSArray<NSDictionary *> *translations))completion;
/// Single-use. A six-second whole-batch deadline returns completed partial results.
- (void)start;
/// Suppresses completion, aborts transport and releases credential-bearing inputs.
- (void)cancel;
@end
