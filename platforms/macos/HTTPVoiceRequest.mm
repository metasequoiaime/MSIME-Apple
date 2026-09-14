#import "HTTPVoiceRequest.h"
#include "../../shared/voice/VoiceProviders.h"
#include "../../shared/voice/PolishPrompt.h"
#include <cmath>
#include <cstring>

namespace {
NSError *Failure() {
    return [NSError errorWithDomain:@"app.msime.client.voice" code:6
        userInfo:@{NSLocalizedDescriptionKey: @"语音请求失败，请检查识别服务设置"}];
}
std::string String(NSDictionary *options, NSString *key) {
    NSString *value = options[key];
    return value ? std::string(value.UTF8String) : std::string();
}
BOOL Endpoint(const std::string &value) {
    NSURLComponents *url = [NSURLComponents componentsWithString:@(value.c_str())];
    BOOL loopback = [@[@"127.0.0.1", @"localhost", @"::1"] containsObject:url.host.lowercaseString];
    return url.host.length && !url.user && !url.password && !url.fragment &&
        ([url.scheme.lowercaseString isEqual:@"https"] || (loopback && [url.scheme.lowercaseString isEqual:@"http"]));
}
}
@implementation MSIMEHTTPVoiceRequest {
    NSDictionary *_options;
    std::shared_ptr<std::atomic_bool> _cancelled;
    BOOL _started;
}
- (instancetype)initWithOptions:(NSDictionary *)options error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _cancelled = std::make_shared<std::atomic_bool>(false);
    if (![options isKindOfClass:NSDictionary.class]) { if (error) *error = Failure(); return nil; }
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"asr_provider", @"asr_endpoint", @"asr_model", @"asr_token", @"language",
        @"polish_provider", @"polish_endpoint", @"polish_model", @"polish_token", @"polish_prompt_id",
        @"polish_prompt", @"polish_prompt_custom_1", @"polish_prompt_custom_2", @"polish_prompt_custom_3"]) {
        id value = options[key];
        if (value && (![value isKindOfClass:NSString.class] || [value length] > 8192)) {
            if (error) *error = Failure(); return nil;
        }
        if (value) snapshot[key] = [value copy];
    }
    for (NSString *key in @[@"polish_enabled", @"polish_text"]) {
        id value = options[key];
        if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
            snapshot[key] = value;
    }
    for (NSString *key in @[@"asr_token", @"polish_token"]) {
        NSString *token = snapshot[key];
        if (token && [token rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
            if (error) *error = Failure(); return nil;
        }
    }
    const auto provider = msime::voice::normalize_voice_provider(String(snapshot, @"asr_provider"));
    const auto endpoint = msime::voice::resolved_asr_endpoint(provider, String(snapshot, @"asr_endpoint"));
    if ((provider != "openai" && provider != "groq" && provider != "siliconflow") ||
        !Endpoint(endpoint) || ![snapshot[@"asr_token"] length]) {
        if (error) *error = Failure(); return nil;
    }
    snapshot[@"asr_provider"] = @(provider.c_str());
    snapshot[@"asr_endpoint"] = @(endpoint.c_str());
    if (![snapshot[@"asr_model"] length]) snapshot[@"asr_model"] = @(msime::voice::default_asr_model(provider).c_str());
    _options = [snapshot copy];
    return self;
}
- (BOOL)recognizePCM:(NSData *)pcm completion:(void (^)(NSString *, NSError *))completion error:(NSError **)error {
    @synchronized(self) {
        if (_started || _cancelled->load() || !completion || !pcm.length ||
            pcm.length % sizeof(float) || pcm.length > 16000 * 60 * sizeof(float)) {
            if (error) *error = Failure(); return NO;
        }
        std::vector<float> samples(pcm.length / sizeof(float));
        std::memcpy(samples.data(), pcm.bytes, pcm.length);
        for (float value : samples) if (!std::isfinite(value) || std::fabs(value) > 1) {
            if (error) *error = Failure(); return NO;
        }
        _started = YES;
        auto cancelled = _cancelled;
        NSDictionary *options = _options;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            NSString *result = nil;
            NSError *failure = nil;
            try {
                auto language = String(options, @"language");
                if (language == "en-US") language = "en";
                if (language == "zh-CN") language = "zh-cn";
                auto text = msime::voice::recognize_cloud_asr(samples, String(options, @"asr_provider"),
                    String(options, @"asr_endpoint"), String(options, @"asr_model"), String(options, @"asr_token"), language, cancelled);
                if (!text.empty() && !cancelled->load() &&
                    ([options[@"polish_enabled"] boolValue] || [options[@"polish_text"] boolValue]) && [options[@"polish_token"] length]) {
                    try {
                        auto provider = String(options, @"polish_provider");
                        auto endpoint = String(options, @"polish_endpoint");
                        auto model = String(options, @"polish_model");
                        if (endpoint.empty()) endpoint = msime::voice::default_polish_endpoint(provider);
                        if (model.empty()) model = msime::voice::default_polish_model(provider);
                        auto prompt = msime::windows::polish_prompt_for({String(options, @"polish_prompt_id"),
                            String(options, @"polish_prompt"), String(options, @"polish_prompt_custom_1"),
                            String(options, @"polish_prompt_custom_2"), String(options, @"polish_prompt_custom_3")});
                        if (Endpoint(endpoint)) {
                            auto polished = msime::voice::polish_cloud_text(text, provider, endpoint, model,
                                String(options, @"polish_token"), prompt, cancelled);
                            if (!polished.empty()) text = std::move(polished);
                        }
                    } catch (const std::exception &) { /* Preserve ASR on optional polish failure. */ }
                }
                result = [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding];
                if (!result.length) failure = Failure();
            } catch (const std::exception &) { failure = Failure(); }
            dispatch_async(dispatch_get_main_queue(), ^{ if (!cancelled->load()) completion(failure ? nil : result, failure); });
        });
        return YES;
    }
}
- (void)cancel { if (_cancelled) _cancelled->store(true); }
- (void)dealloc { [self cancel]; }
@end
