#pragma once
#import <Foundation/Foundation.h>
#ifdef __cplusplus
#include <metasequoia/session.h>
namespace metasequoia::apple {
// Stable digest of one consistent logical journal snapshot. Only the digest is
// exposed to callers; pair it with the active generation ID.
std::string DictionaryStateRevision(const RuntimePaths &paths);
}
#endif

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary<NSString *, id> *_Nullable (^MSIMESnapshotNextRecord)(NSError *_Nullable *_Nonnull error);

@interface MSIMEPreparedDictionarySnapshot : NSObject
@property(nonatomic, copy, readonly) NSString *identifier;
- (nullable NSString *)stateRevisionWithError:(NSError **)error NS_SWIFT_NAME(stateRevision());
- (instancetype)init NS_UNAVAILABLE;
#ifdef __cplusplus
- (const metasequoia::RuntimePaths &)runtimePaths;
#endif
@end

@interface DictionarySnapshotBridge : NSObject
+ (BOOL)discardInactiveIdentifier:(NSString *)identifier userDirectory:(NSURL *)user error:(NSError **)error
    NS_SWIFT_NAME(discardInactive(identifier:user:));
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
