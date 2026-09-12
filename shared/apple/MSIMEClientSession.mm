#import "MSIMEClientSession.h"
#import "ClipboardPreferences.h"
#include "msime_client.h"
#include <cstring>

static NSString *const MSIMEClientErrorDomain = @"app.msime.client.host";
static __weak MSIMEClientSession *gActiveSession;
NSNotificationName const MSIMEClientSessionDidReplaceSnapshotNotification = @"MSIMEClientSessionDidReplaceSnapshotNotification";

static void setError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
}

struct SnapshotReaderContext { MSIMESnapshotNextRecord block; };
static intptr_t SnapshotNext(void *opaque, uint8_t *buffer, size_t capacity) {
    auto *context = static_cast<SnapshotReaderContext *>(opaque);
    NSError *failure = nil;
    NSDictionary *record = context->block(&failure);
    if (failure) return -1;
    if (!record) return 0;
    NSError *serializationError = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:record options:0 error:&serializationError];
    if (serializationError || !data || data.length == 0 || data.length > capacity) return -1;
    memcpy(buffer, data.bytes, data.length);
    return static_cast<intptr_t>(data.length);
}

static NSDictionary *decode(char *response, NSError **error) {
    if (!response) { setError(error, @"输入运行时未返回响应"); return nil; }
    NSData *data = [NSData dataWithBytes:response length:std::strlen(response)];
    msime_client_string_free(response);
    id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (![object isKindOfClass:[NSDictionary class]]) { setError(error, @"输入运行时响应格式错误"); return nil; }
    NSDictionary *envelope = object;
    if (![envelope[@"ok"] isEqual:@YES]) {
        setError(error, [envelope[@"error"] isKindOfClass:[NSString class]] ? envelope[@"error"] : @"输入运行时调用失败");
        return nil;
    }
    id value = envelope[@"value"];
    return [value isKindOfClass:[NSDictionary class]] ? value : @{};
}

@implementation MSIMEClientSession {
    uint64_t _handle;
    NSDictionary *_hostOptions;
}
- (NSDictionary *)hostOptions { return _hostOptions; }
+ (NSDictionary *)dictionaryRequest:(NSDictionary<NSString *, id> *)request error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:request]) { setError(error, @"词典请求格式错误"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    if (!data || data.length > 65536) { setError(error, @"词典请求过大"); return nil; }
    return decode(msime_client_dictionary(static_cast<const uint8_t *>(data.bytes), data.length), error);
}
+ (NSDictionary *)handwritingProviderRequest:(NSDictionary<NSString *, id> *)request error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:request]) { setError(error, @"手写请求格式错误"); return nil; }
    NSString *socketPath = request[@"socket_path"];
    if (![socketPath isKindOfClass:NSString.class] || !socketPath.isAbsolutePath || socketPath.length > 4096) { setError(error, @"手写 provider 路径无效"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    if (!data || data.length > 65536) { setError(error, @"手写请求过大"); return nil; }
    NSData *socket = [socketPath dataUsingEncoding:NSUTF8StringEncoding];
    return decode(msime_client_handwriting_provider_request(static_cast<const uint8_t *>(data.bytes), data.length,
                                                            static_cast<const uint8_t *>(socket.bytes), socket.length), error);
}
+ (NSDictionary *)handwritingProviderRequest:(NSDictionary<NSString *, id> *)request {
    NSError *error = nil;
    NSDictionary *result = [self handwritingProviderRequest:request error:&error];
    return result ?: @{ @"error": error ?: [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
}
+ (NSDictionary *)captureClipboardHistoryRequest:(NSDictionary<NSString *, id> *)request {
    if (![NSJSONSerialization isValidJSONObject:request]) return @{ @"error": @YES };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&error];
    if (!data || data.length > 131072) return @{ @"error": @YES };
    NSDictionary *result = decode(msime_client_capture_clipboard_history(
        static_cast<const uint8_t *>(data.bytes), data.length), &error);
    return result ?: @{ @"error": @YES };
}
+ (NSDictionary *)removeClipboardHistoryRequest:(NSDictionary<NSString *, id> *)request {
    if (![NSJSONSerialization isValidJSONObject:request]) return @{ @"error": @YES };
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:&error];
    if (!data || data.length > 131072) return @{ @"error": @YES };
    NSDictionary *result = decode(msime_client_remove_clipboard_history(
        static_cast<const uint8_t *>(data.bytes), data.length), &error);
    return result ?: @{ @"error": @YES };
}
+ (NSDictionary *)clipboardCaptureEnabledRequest:(NSString *)directory {
    if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath) return @{ @"error": @YES };
    NSDictionary *snapshot = [self loadPreferencesInDirectory:directory error:nil];
    id enabled = snapshot[@"preferences"][@"clipboard_history"];
    return [enabled isKindOfClass:NSNumber.class] ? @{ @"enabled": enabled } : @{ @"error": @YES };
}
+ (NSDictionary *)enableClipboardHistoryRequest:(NSString *)directory {
    if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath) return @{ @"error": @YES };
    return MSIMEEnableClipboardHistory(^NSDictionary *{
        return [self loadPreferencesInDirectory:directory error:nil];
    }, ^NSDictionary *(uint64_t revision, NSDictionary *snapshot) {
        return [self savePreferencesInDirectory:directory expectedRevision:revision snapshot:snapshot error:nil];
    });
}
+ (NSDictionary *)clipboardHistoryRequest:(NSString *)directory {
    NSError *error = nil;
    if (![directory isKindOfClass:NSString.class] || !directory.isAbsolutePath) {
        return @{ @"error": @YES };
    }
    NSData *path = [directory dataUsingEncoding:NSUTF8StringEncoding];
    if (!path || path.length > 16384) return @{ @"error": @YES };
    NSDictionary *result = decode(msime_client_load_clipboard_history(
        static_cast<const uint8_t *>(path.bytes), path.length), &error);
    return result ?: @{ @"error": @YES };
}
+ (NSDictionary *)emojiCatalogRequest:(NSDictionary<NSString *, id> *)request {
    NSError *error = nil;
    NSString *resources = request[@"resources"];
    if (![resources isKindOfClass:NSString.class] || !resources.isAbsolutePath ||
        ![NSJSONSerialization isValidJSONObject:request]) {
        return @{ @"error": [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
    }
    NSData *query = [NSJSONSerialization dataWithJSONObject:request options:0 error:&error];
    NSData *path = [resources dataUsingEncoding:NSUTF8StringEncoding];
    if (!query || query.length > 16384 || path.length > 4096) {
        return @{ @"error": [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
    }
    NSDictionary *result = decode(msime_client_emoji_catalog_request(
        static_cast<const uint8_t *>(query.bytes), query.length,
        static_cast<const uint8_t *>(path.bytes), path.length), &error);
    return result ?: @{ @"error": error ?: [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
}
+ (NSString *)snapshotVersionForOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:options]) { setError(error, @"本地词库版本参数无效"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:options options:0 error:error];
    if (!data || data.length > 65536) { setError(error, @"本地词库版本参数过大"); return nil; }
    NSDictionary *value = decode(msime_client_snapshot_version(static_cast<const uint8_t *>(data.bytes), data.length), error);
    NSString *version = value[@"version"];
    if (![version isKindOfClass:NSString.class] || version.length != 64) { setError(error, @"本地词库版本响应无效"); return nil; }
    return version;
}
+ (NSDictionary *)snapshotVersion:(NSDictionary<NSString *, id> *)options {
    NSError *error = nil;
    NSString *value = [self snapshotVersionForOptions:options error:&error];
    return value ? @{ @"version": value } : @{ @"error": error ?: [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
}
+ (BOOL)discardSnapshotHandle:(uint64_t)handle error:(NSError **)error {
    if (!handle) { setError(error, @"本地词库准备句柄无效"); return NO; }
    return decode(msime_client_snapshot_discard(handle), error) != nil;
}
+ (NSDictionary *)discardSnapshot:(NSDictionary<NSString *, id> *)parameters {
    NSError *error = nil;
    BOOL discarded = [self discardSnapshotHandle:[parameters[@"handle"] unsignedLongLongValue] error:&error];
    return discarded ? @{ @"discarded": @YES } : @{ @"error": error ?: [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
}
+ (BOOL)applySnapshotHandle:(uint64_t)handle expectedVersion:(NSString *)version error:(NSError **)error {
    if (![NSThread isMainThread] || !handle || version.length != 64) { setError(error, @"本地词库应用参数无效"); return NO; }
    MSIMEClientSession *session = gActiveSession;
    uint64_t old = session ? session->_handle : 0;
    if (!session || !old) { setError(error, @"输入会话不可用"); return NO; }
    NSDictionary *optionsCopy = [session->_hostOptions copy];
    msime_client_string_free(msime_client_destroy(old));
    session->_handle = 0;
    NSData *data = [version dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *result = decode(msime_client_snapshot_activate(handle, static_cast<const uint8_t *>(data.bytes), data.length), error);
    if (!result) {
        NSData *restore = [NSJSONSerialization dataWithJSONObject:optionsCopy options:0 error:nil];
        NSDictionary *view = decode(msime_client_create(static_cast<const uint8_t *>(restore.bytes), restore.length), nil);
        session->_handle = [view[@"session"] unsignedLongLongValue];
        if (session->_handle != 0) {
            // Recovery creates a fresh session too; the host must clear the
            // destroyed composition and restore focus even though activation failed.
            [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEClientSessionDidReplaceSnapshotNotification object:session];
        }
        return NO;
    }
    NSData *options = [NSJSONSerialization dataWithJSONObject:optionsCopy options:0 error:error];
    if (!options) return NO;
    NSDictionary *view = decode(msime_client_create(static_cast<const uint8_t *>(options.bytes), options.length), error);
    if (!view) return NO;
    session->_handle = [view[@"session"] unsignedLongLongValue];
    if (session->_handle != 0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:MSIMEClientSessionDidReplaceSnapshotNotification object:session];
    }
    return session->_handle != 0;
}
+ (NSDictionary *)applySnapshot:(NSDictionary<NSString *, id> *)parameters {
    NSError *error = nil;
    BOOL ok = [self applySnapshotHandle:[parameters[@"handle"] unsignedLongLongValue]
                        expectedVersion:parameters[@"expectedVersion"] error:&error];
    return ok ? @{ @"activated": @YES } : @{ @"error": error ?: [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
}
+ (NSDictionary *)activeHostOptions { return gActiveSession ? [gActiveSession.hostOptions copy] : @{@"error" : [NSError errorWithDomain:MSIMEClientErrorDomain code:503 userInfo:nil]}; }
+ (NSDictionary *)prepareSnapshotRequest:(NSDictionary<NSString *, id> *)request
                               nextRecord:(MSIMESnapshotNextRecord)nextRecord
                                    error:(NSError **)error {
    if (![NSJSONSerialization isValidJSONObject:request] || !nextRecord) {
        setError(error, @"本地词库快照参数无效"); return nil;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    if (!data || data.length > 65536) { setError(error, @"本地词库快照参数过大"); return nil; }
    SnapshotReaderContext context{[nextRecord copy]};
    NSDictionary *result = decode(msime_client_snapshot_prepare(static_cast<const uint8_t *>(data.bytes), data.length,
                                                                 SnapshotNext, &context), error);
    context.block = nil;
    return result;
}
+ (NSDictionary *)prepareSnapshot:(NSDictionary<NSString *, id> *)parameters {
    NSError *error = nil;
    NSDictionary *request = parameters[@"request"];
    MSIMESnapshotNextRecord next = parameters[@"nextRecord"];
    NSDictionary *result = [self prepareSnapshotRequest:request nextRecord:next error:&error];
    return result ?: @{ @"error": error ?: [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:nil] };
}
+ (NSDictionary *)prepareHostWithResourcesDirectory:(NSString *)resourcesDirectory stateRoot:(NSString *)stateRoot error:(NSError **)error {
    if (![resourcesDirectory isAbsolutePath] || ![stateRoot isAbsolutePath] || resourcesDirectory.length == 0 || stateRoot.length == 0) {
        setError(error, @"词库准备目录必须是绝对路径"); return nil;
    }
    NSDictionary *request = @{@"resources": resourcesDirectory, @"state_root": stateRoot};
    NSData *data = [NSJSONSerialization dataWithJSONObject:request options:0 error:error];
    if (!data || data.length > 16384) { setError(error, @"词库准备请求过大"); return nil; }
    return decode(msime_client_prepare_host(static_cast<const uint8_t *>(data.bytes), data.length), error);
}
+ (NSDictionary *)savePreferencesInDirectory:(NSString *)directory expectedRevision:(uint64_t)revision snapshot:(NSDictionary *)snapshot error:(NSError **)error {
    if (![directory isAbsolutePath] || ![NSJSONSerialization isValidJSONObject:snapshot]) { setError(error, @"偏好保存参数无效"); return nil; }
    NSData *dir = [directory dataUsingEncoding:NSUTF8StringEncoding];
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:error];
    if (!data || data.length > 16384) { setError(error, @"偏好快照过大"); return nil; }
    return decode(msime_client_save_preferences(static_cast<const uint8_t *>(dir.bytes), dir.length, revision, static_cast<const uint8_t *>(data.bytes), data.length), error);
}
+ (NSDictionary *)loadPreferencesInDirectory:(NSString *)directory error:(NSError **)error {
    if (![directory isAbsolutePath] || directory.length == 0) { setError(error, @"偏好目录必须是绝对路径"); return nil; }
    NSData *dir = [directory dataUsingEncoding:NSUTF8StringEncoding];
    return decode(msime_client_load_preferences(static_cast<const uint8_t *>(dir.bytes), dir.length), error);
}
- (nullable instancetype)initWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    if (![NSThread isMainThread]) { setError(error, @"输入会话必须在主线程创建"); return nil; }
    self = [super init];
    if (!self) return nil;
    if (![NSJSONSerialization isValidJSONObject:options]) { setError(error, @"输入会话配置必须是 JSON 对象"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:options options:0 error:error];
    if (!data) return nil;
    // Retain the exact immutable configuration sent to the host, not mutable
    // nested dictionaries owned by the caller and reused during recovery.
    _hostOptions = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!_hostOptions) return nil;
    NSDictionary *view = decode(msime_client_create(static_cast<const uint8_t *>(data.bytes), data.length), error);
    if (!view) return nil;
    _handle = [view[@"session"] unsignedLongLongValue];
    if (!_handle) { setError(error, @"输入会话句柄无效"); return nil; }
    gActiveSession = self;
    return self;
}

- (BOOL)checkThreadAndHandle:(NSError **)error {
    if (![NSThread isMainThread]) { setError(error, @"输入会话必须在主线程调用"); return NO; }
    if (!_handle) { setError(error, @"输入会话已关闭"); return NO; }
    return YES;
}

- (nullable NSDictionary *)setFocused:(BOOL)focused error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_focus(_handle, focused), error);
}
- (nullable NSDictionary *)setEnglishMode:(BOOL)enabled error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_set_english_mode(_handle, enabled), error);
}
- (nullable NSDictionary *)setChinesePunctuationEnabled:(BOOL)enabled error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_set_chinese_punctuation(_handle, enabled), error);
}
- (nullable NSDictionary *)setCharacterWidthFull:(BOOL)fullwidth error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_set_character_width(_handle, fullwidth), error);
}
- (nullable NSDictionary *)typeASCII:(uint8_t)character shift:(BOOL)shift error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_character(_handle, character, shift), error);
}
- (nullable NSDictionary *)command:(uint32_t)command error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_command(_handle, command), error);
}
- (nullable NSDictionary *)selectGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_select(_handle, generation, index), error);
}
- (nullable NSDictionary *)viewWithError:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_view(_handle), error);
}
- (nullable NSDictionary *)setCandidatePageSize:(uint8_t)size error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    return decode(msime_client_set_candidate_page_size(_handle, size), error);
}
- (nullable NSDictionary *)updatePreferencesSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    if (![NSJSONSerialization isValidJSONObject:snapshot]) { setError(error, @"偏好快照必须是 JSON 对象"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:error];
    if (!data) return nil;
    NSDictionary *result = decode(msime_client_update_preferences(_handle, static_cast<const uint8_t *>(data.bytes), data.length), error);
    if (result) {
        // Keep the accepted desired configuration for snapshot replacement/recovery.
        // Decode our serialized input to avoid retaining caller-owned mutable data.
        NSDictionary *accepted = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        NSMutableDictionary *options = [_hostOptions mutableCopy];
        options[@"preferences"] = accepted[@"preferences"];
        _hostOptions = [options copy];
    }
    return result;
}
- (NSDictionary *)startVoiceWithError:(NSError **)error { if (![self checkThreadAndHandle:error]) return nil; return decode(msime_client_voice_start(_handle), error); }
- (BOOL)cancelVoiceWithError:(NSError **)error { if (![self checkThreadAndHandle:error]) return NO; return decode(msime_client_voice_cancel(_handle), error) != nil; }
- (NSDictionary *)applyVoiceText:(NSString *)text generation:(uint64_t)generation error:(NSError **)error { if (![self checkThreadAndHandle:error]) return nil; NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding]; if (!data || data.length > 65536) { setError(error, @"语音文本无效"); return nil; } return decode(msime_client_voice_apply(_handle, generation, static_cast<const uint8_t *>(data.bytes), data.length), error); }
- (BOOL)closeWithError:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return NO;
    NSDictionary *result = decode(msime_client_destroy(_handle), error);
    if (!result) return NO;
    _handle = 0;
    return YES;
}
- (void)reloadPreferencesDirectory:(NSString *)directory completion:(void (^)(NSDictionary *, NSError *))completion {
    NSError *error = nil;
    if (![self checkThreadAndHandle:&error]) { completion(nil, error); return; }
    NSData *path = [directory dataUsingEncoding:NSUTF8StringEncoding];
    __weak MSIMEClientSession *weakSelf = self;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *loadError = nil;
        NSDictionary *snapshot = decode(msime_client_load_preferences(static_cast<const uint8_t *>(path.bytes), path.length), &loadError);
        dispatch_async(dispatch_get_main_queue(), ^{
            MSIMEClientSession *session = weakSelf;
            NSError *updateError = loadError;
            NSDictionary *result = nil;
            if (!session) setError(&updateError, @"输入会话已释放");
            else if (snapshot) result = [session updatePreferencesSnapshot:snapshot error:&updateError];
            completion(result, updateError);
        });
    });
}
- (void)dealloc {
    if (gActiveSession == self) gActiveSession = nil;
    uint64_t handle = _handle;
    if (!handle) return;
    if ([NSThread isMainThread]) {
        msime_client_string_free(msime_client_destroy(handle));
    } else {
        // Destruction must run on the registry's owning thread; capture only the ID.
        dispatch_async(dispatch_get_main_queue(), ^{ msime_client_string_free(msime_client_destroy(handle)); });
    }
}
@end
