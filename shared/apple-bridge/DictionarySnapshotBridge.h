#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
#include <metasequoia/session.h>
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id> *_Nullable (^MSIMESnapshotNextRecord)(NSError *_Nullable *_Nonnull error);

@interface MSIMEPreparedDictionarySnapshot : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
- (instancetype)init NS_UNAVAILABLE;
#ifdef __cplusplus
- (const metasequoia::RuntimePaths &)runtimePaths;
#endif
@end

@interface DictionarySnapshotBridge : NSObject
// This callback supplies validated overlay/position/selection records. It returns
// nil only at checksum-verified EOF, and supplies an error on truncation/cancel.
// Preparation does not publish or activate the new generation.
+ (nullable MSIMEPreparedDictionarySnapshot *)prepareResources:(NSURL *)resources
                                                userDirectory:(NSURL *)user
                                                   identifier:(NSString *)identifier
                                            contentIdentifier:(NSString *)contentIdentifier
                                               maximumRecords:(NSUInteger)maximumRecords
                                                   nextRecord:(MSIMESnapshotNextRecord)nextRecord
                                                        error:(NSError **)error
    NS_SWIFT_NAME(prepare(resources:user:identifier:contentIdentifier:maximumRecords:nextRecord:));
@end

NS_ASSUME_NONNULL_END
