#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSDictionary *_Nullable (^MSIMESnapshotNextRecord)(NSError *_Nullable *error);

/// Foundation adapter for macOS input controllers and iOS keyboard extensions.
/// Construct and use on the main thread. No Tauri process is required.
@interface MSIMEClientSession : NSObject
FOUNDATION_EXPORT NSNotificationName const MSIMEClientSessionDidReplaceSnapshotNotification;
/// The validated creation options, copied for native maintenance UI; never mutable by callers.
@property(nonatomic, readonly) NSDictionary<NSString *, id> *hostOptions;
- (nullable instancetype)initWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
- (nullable NSDictionary<NSString *, id> *)setFocused:(BOOL)focused error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)setChinesePunctuationEnabled:(BOOL)enabled error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)typeASCII:(uint8_t)character shift:(BOOL)shift error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)command:(uint32_t)command error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)selectGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)viewWithError:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)setCandidatePageSize:(uint8_t)size error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)updatePreferencesSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)startVoiceWithError:(NSError **)error;
- (BOOL)cancelVoiceWithError:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)applyVoiceText:(NSString *)text generation:(uint64_t)generation error:(NSError **)error;
/// Management is separate from live sessions; call only after all sessions are closed.
+ (nullable NSDictionary<NSString *, id> *)dictionaryRequest:(NSDictionary<NSString *, id> *)request error:(NSError **)error;
+ (nullable NSDictionary<NSString *, id> *)handwritingProviderRequest:(NSDictionary<NSString *, id> *)request error:(NSError **)error;
+ (NSDictionary<NSString *, id> *)handwritingProviderRequest:(NSDictionary<NSString *, id> *)request;
+ (NSDictionary<NSString *, id> *)emojiCatalogRequest:(NSDictionary<NSString *, id> *)request;
+ (NSDictionary<NSString *, id> *)clipboardHistoryRequest:(NSString *)directory;
/// Return the current local dictionary version without exposing dictionary text.
+ (nullable NSString *)snapshotVersionForOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;
/// Dynamic Swift-backend form; returns {version} or {error}.
+ (NSDictionary<NSString *, id> *)snapshotVersion:(NSDictionary<NSString *, id> *)options;
/// Discard a process-owned, unpublished preparation handle.
+ (BOOL)discardSnapshotHandle:(uint64_t)handle error:(NSError **)error;
/// Dynamic Swift-backend form; returns {discarded} or {error}.
+ (NSDictionary<NSString *, id> *)discardSnapshot:(NSDictionary<NSString *, id> *)parameters;
/// Atomically publish and recreate the active session; must be called on main thread while idle.
+ (BOOL)applySnapshotHandle:(uint64_t)handle expectedVersion:(NSString *)version error:(NSError **)error;
/// Dynamic Swift-backend form; parameters contains handle and expectedVersion.
+ (NSDictionary<NSString *, id> *)applySnapshot:(NSDictionary<NSString *, id> *)parameters;
/// Current validated host options for the live input session, or an error dictionary.
+ (nullable NSDictionary<NSString *, id> *)activeHostOptions;
/// Prepare a bounded, checksummed record stream synchronously; invoke off-main-thread.
+ (nullable NSDictionary<NSString *, id> *)prepareSnapshotRequest:(NSDictionary<NSString *, id> *)request
                                                       nextRecord:(MSIMESnapshotNextRecord)nextRecord
                                                            error:(NSError **)error;
/// Dynamic Swift-backend form; parameters contains request and nextRecord.
+ (NSDictionary<NSString *, id> *)prepareSnapshot:(NSDictionary<NSString *, id> *)parameters;
/// Prepare isolated Engine working data; call off the main thread and before creating sessions.
+ (nullable NSDictionary<NSString *, id> *)prepareHostWithResourcesDirectory:(NSString *)resourcesDirectory stateRoot:(NSString *)stateRoot error:(NSError **)error;
+ (nullable NSDictionary<NSString *, id> *)savePreferencesInDirectory:(NSString *)directory expectedRevision:(uint64_t)revision snapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error;
/// Read the complete shared snapshot, including its current revision.
+ (nullable NSDictionary<NSString *, id> *)loadPreferencesInDirectory:(NSString *)directory error:(NSError **)error;
/// Start on main thread; disk/lock work runs in background, completion on main.
- (void)reloadPreferencesDirectory:(NSString *)directory completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;
- (BOOL)closeWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
