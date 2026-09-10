#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN

/// Paths copied from validated MSIMEClientSession host options; never accepts UI paths.
@interface MSIMEDictionaryRuntime : NSObject
- (nullable instancetype)initWithHostOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;
@property(nonatomic, readonly) NSURL *resourcesDirectory;
@property(nonatomic, readonly) NSURL *userDataDirectory;
@property(nonatomic, readonly) NSURL *cacheDirectory;
@property(nonatomic, readonly) NSURL *dictionariesDirectory;
@end
NS_ASSUME_NONNULL_END
