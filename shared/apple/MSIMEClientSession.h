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
/// Returns the current View, not a transition; preserves live composition.
- (nullable NSDictionary<NSString *, id> *)setChinesePunctuationEnabled:(BOOL)enabled error:(NSError **)error;
/// Returns a View (not a transition). Finish composition before changing mode.
- (nullable NSDictionary *)setDedicatedEnglishEnabled:(BOOL)enabled error:(NSError **)error;
/// Compatibility selector with the same session-mode restoration behavior.
- (nullable NSDictionary *)setEnglishMode:(BOOL)enabled error:(NSError **)error;
/// Returns a View; remembers an explicit live width override across recreation.
- (nullable NSDictionary *)setCharacterWidthFull:(BOOL)fullwidth error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)typeASCII:(uint8_t)character shift:(BOOL)shift error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)command:(uint32_t)command error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)selectGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error;
- (nullable NSDictionary *)selectEdgeGeneration:(uint64_t)generation index:(NSUInteger)index edge:(uint8_t)edge error:(NSError **)error;
- (nullable NSDictionary *)pinGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error;
- (nullable NSDictionary *)removeGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error;
- (nullable NSDictionary *)fixGeneration:(uint64_t)generation index:(NSUInteger)index position:(uint8_t)position error:(NSError **)error;
- (nullable NSDictionary *)clearPositionGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)viewWithError:(NSError **)error;
/// Copied Engine query, or nil when ineligible. Does not perform network I/O.
- (nullable NSDictionary *)onlineQueryWithError:(NSError **)error;
+ (nullable NSString *)cloudRequestURLForQuery:(NSDictionary *)query error:(NSError **)error;
/// Shared bounded parser and stale-query guard; returns {applied,view}.
- (nullable NSDictionary *)applyCloudResponse:(NSData *)body query:(NSDictionary *)query error:(NSError **)error;
/// Apply a copied cloud (source=0) or AI (source=1) string batch on the session thread.
/// Engine validates candidate limit, eligibility and query identity. No network I/O.
- (nullable NSDictionary *)applyOnlineCandidates:(NSArray<NSString *> *)candidates source:(NSUInteger)source
                                           query:(NSDictionary *)query error:(NSError **)error;
/// Copied enabled translation query, or nil when no candidates are eligible.
/// May contain custom/Tencent credentials for native transport; never log it.
- (nullable NSDictionary *)translationQueryWithError:(NSError **)error;
/// Pure descriptor construction. Contains optional credentials; never log it.
+ (nullable NSDictionary *)customTranslationHTTPRequest:(NSDictionary *)request error:(NSError **)error;
/// Signed Tencent descriptor. Send body_utf8 unchanged; never log credentials.
+ (nullable NSDictionary *)tencentTranslationHTTPRequest:(NSDictionary *)request error:(NSError **)error;
/// Worker-only private disk I/O; same bounded request as msime_client_learned_translation_request.
/// Supply a private user directory, never packaged resources. Do not log learned text.
+ (nullable NSDictionary *)learnedTranslationRequest:(NSDictionary *)request error:(NSError **)error;
/// Exact batch positions: NSString or NSNull. nil means an invalid response.
+ (nullable NSArray *)parseTencentTranslationResponse:(NSData *)body expectedCount:(NSUInteger)count error:(NSError **)error;
/// Pure script/direction filtering for {target_language,candidates:[{text,source}]}.
+ (nullable NSArray<NSDictionary *> *)customTranslationPlan:(NSDictionary *)request error:(NSError **)error;
/// Parse only a successful HTTP response; nil without error means no usable translation.
+ (nullable NSString *)parseCustomTranslationResponse:(NSData *)body error:(NSError **)error;
/// Offline dictionary lookup; may run on a worker with copied {generation,candidates:[{text,source}]}.
+ (nullable NSDictionary *)candidateGlossRequest:(NSDictionary *)request resources:(NSString *)resources error:(NSError **)error;
/// Apply on the originating session/thread only. A stale generation is ignored.
- (nullable NSDictionary *)applyTranslations:(NSArray<NSDictionary *> *)translations generation:(uint64_t)generation error:(NSError **)error;
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
+ (NSDictionary<NSString *, id> *)enableClipboardHistoryRequest:(NSString *)directory;
+ (NSDictionary<NSString *, id> *)clipboardCaptureEnabledRequest:(NSString *)directory;
+ (NSDictionary<NSString *, id> *)removeClipboardHistoryRequest:(NSDictionary<NSString *, id> *)request;
+ (NSDictionary<NSString *, id> *)captureClipboardHistoryRequest:(NSDictionary<NSString *, id> *)request;
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
