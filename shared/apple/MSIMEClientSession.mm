#import "MSIMEClientSession.h"
#include "msime_client.h"
#include <cstring>

static NSString *const MSIMEClientErrorDomain = @"app.msime.client.host";

static void setError(NSError **error, NSString *message) {
    if (error) *error = [NSError errorWithDomain:MSIMEClientErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey: message}];
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
}

- (nullable instancetype)initWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    if (![NSThread isMainThread]) { setError(error, @"输入会话必须在主线程创建"); return nil; }
    self = [super init];
    if (!self) return nil;
    if (![NSJSONSerialization isValidJSONObject:options]) { setError(error, @"输入会话配置必须是 JSON 对象"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:options options:0 error:error];
    if (!data) return nil;
    NSDictionary *view = decode(msime_client_create(static_cast<const uint8_t *>(data.bytes), data.length), error);
    if (!view) return nil;
    _handle = [view[@"session"] unsignedLongLongValue];
    if (!_handle) { setError(error, @"输入会话句柄无效"); return nil; }
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
- (nullable NSDictionary *)updatePreferencesSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error {
    if (![self checkThreadAndHandle:error]) return nil;
    if (![NSJSONSerialization isValidJSONObject:snapshot]) { setError(error, @"偏好快照必须是 JSON 对象"); return nil; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:snapshot options:0 error:error];
    if (!data) return nil;
    return decode(msime_client_update_preferences(_handle, static_cast<const uint8_t *>(data.bytes), data.length), error);
}
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
