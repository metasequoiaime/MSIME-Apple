#import "DoubaoVoiceRequest.h"
#import "VoiceFailureMessages.h"
#include <msime/voice/doubao_protocol.h>
#include "msime_client.h"
#include <cmath>
#include <cstring>
#include <memory>
#include <stdexcept>

namespace {
NSError *DoubaoFailure(NSString *detail = nil) {
    NSMutableDictionary *info = [@{NSLocalizedDescriptionKey:@"豆包语音请求失败，请检查服务设置或重试"} mutableCopy];
    if (detail.length) info[MSIMEVoiceFailureDetailKey] = detail;
    return [NSError errorWithDomain:@"app.msime.client.voice.doubao" code:1 userInfo:info];
}
NSData *PacketData(const std::vector<std::uint8_t> &packet) {
    return [NSData dataWithBytes:packet.data() length:packet.size()];
}
}
// Never follow a redirect with custom authentication headers. This separate
// delegate does not retain the request owner, so dropping it cancels the socket.
@interface MSIMEDoubaoSocketPolicy : NSObject <NSURLSessionTaskDelegate>
@end
@implementation MSIMEDoubaoSocketPolicy
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
    willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
    completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    completionHandler(nil);
}
@end

@implementation MSIMEDoubaoVoiceRequest {
    NSURLRequest *_request;
    NSData *_initialPacket;
    NSURLSession *_session;
    NSURLSessionWebSocketTask *_socket;
    NSMutableArray<NSData *> *_packets;
    std::vector<float> _pending;
    NSUInteger _queuedBytes;
    int32_t _sequence;
    BOOL _started, _finishing, _done, _cancelled, _sending, _finalDispatched, _legacyAuth, _opened;
    NSString *_lastText;
    MSIMEDoubaoResult _result;
}
- (instancetype)initWithOptions:(NSDictionary *)options error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    if (![options isKindOfClass:NSDictionary.class]) { if (error) *error = DoubaoFailure(); return nil; }
    NSMutableDictionary *snapshot = [NSMutableDictionary dictionary];
    for (NSString *key in @[@"asr_endpoint", @"asr_token", @"asr_app_key", @"asr_resource_id",
        @"doubao_auth_mode", @"doubao_boosting_table_id"]) {
        id value = options[key];
        if (value && (![value isKindOfClass:NSString.class] || [value length] > 8192 ||
            ![value UTF8String])) {
            if (error) *error = DoubaoFailure(); return nil;
        }
        if (([key isEqual:@"asr_endpoint"] || [key isEqual:@"doubao_boosting_table_id"]) && value &&
            [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) {
            if (error) *error = DoubaoFailure(); return nil;
        }
        if (value) snapshot[key] = [value copy];
    }
    NSString *endpoint = [snapshot[@"asr_endpoint"] length] ? snapshot[@"asr_endpoint"] : @"wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async";
    NSURLComponents *url = [NSURLComponents componentsWithString:endpoint];
    BOOL local = [@[@"127.0.0.1", @"localhost", @"::1"] containsObject:url.host.lowercaseString];
    if (!url.URL || !url.host.length || url.user || url.password || url.fragment ||
        (![url.scheme.lowercaseString isEqual:@"wss"] && !(local && [url.scheme.lowercaseString isEqual:@"ws"]))) {
        if (error) *error = DoubaoFailure(); return nil;
    }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    request.timeoutInterval = 10;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    // The same client-core policy owns probe and recording authentication on all
    // hosts. This adapter only translates the sensitive ABI result to NSURLRequest.
    NSData *authInput = [NSJSONSerialization dataWithJSONObject:@{
        @"auth_mode":snapshot[@"doubao_auth_mode"] ?: @"", @"app_id":snapshot[@"asr_app_key"] ?: @"",
        @"token":snapshot[@"asr_token"] ?: @"", @"resource_id":[snapshot[@"asr_resource_id"] length]
            ? snapshot[@"asr_resource_id"] : @"volc.bigasr.sauc.duration"} options:0 error:nil];
    std::unique_ptr<char, decltype(&msime_client_string_free)> authRaw(
        msime_client_doubao_auth_headers(static_cast<const uint8_t *>(authInput.bytes), authInput.length),
        msime_client_string_free);
    id auth = authRaw ? [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:authRaw.get()
        length:std::strlen(authRaw.get())] options:0 error:nil] : nil;
    if (![auth isKindOfClass:NSDictionary.class] || ![auth[@"ok"] isEqual:@YES] ||
        ![auth[@"value"] isKindOfClass:NSDictionary.class] ||
        ![auth[@"value"][@"headers"] isKindOfClass:NSArray.class] || ![auth[@"value"][@"headers"] count]) {
        if (error) *error = DoubaoFailure(); return nil;
    }
    for (id header in auth[@"value"][@"headers"]) {
        if (![header isKindOfClass:NSArray.class] || [header count] != 2 ||
            ![header[0] isKindOfClass:NSString.class] || ![header[1] isKindOfClass:NSString.class]) {
            if (error) *error = DoubaoFailure(); return nil;
        }
        [request setValue:header[1] forHTTPHeaderField:header[0]];
        // Which console the credentials belong to decides which of them a failure message asks the user to check; the shared policy has already resolved it, so read it back from the headers rather than inferring it again.
        if ([header[0] caseInsensitiveCompare:@"x-api-app-key"] == NSOrderedSame) _legacyAuth = YES;
    }
    metasequoia::voice::DoubaoRequestOptions config;
    bool *flags[] = {&config.enable_itn, &config.enable_punc, &config.enable_ddc};
    NSArray *keys = @[@"doubao_enable_itn", @"doubao_enable_punc", @"doubao_enable_ddc"];
    for (NSUInteger i = 0; i < keys.count; ++i) {
        id value = options[keys[i]];
        if (value && (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())) {
            if (error) *error = DoubaoFailure(); return nil;
        }
        if (value) *flags[i] = [value boolValue];
    }
    NSString *boosting = snapshot[@"doubao_boosting_table_id"];
    if (boosting) config.boosting_table_id = boosting.UTF8String;
    try { _initialPacket = PacketData(metasequoia::voice::make_doubao_request(config)); }
    catch (const std::exception &) { if (error) *error = DoubaoFailure(); return nil; }
    _request = [request copy];
    _packets = [NSMutableArray array];
    _sequence = 2;
    return self;
}
- (void)deliver:(NSString *)text final:(BOOL)final error:(NSError *)error {
    MSIMEDoubaoResult result = _result;
    if (final) {
        _done = YES;
        _result = nil;
        [_packets removeAllObjects]; _pending.clear(); _queuedBytes = 0;
        [_socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeNormalClosure reason:nil];
        [_session invalidateAndCancel]; _socket = nil; _session = nil;
    }
    __weak MSIMEDoubaoVoiceRequest *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        MSIMEDoubaoVoiceRequest *owner = weakSelf;
        if (!owner) return;
        @synchronized(owner) { if (owner->_cancelled) return; }
        if (result) result(text, final, error);
    });
}
// Whether the websocket upgrade completed: a message has arrived, or the task holds the 101 answer. A refused connection has no response and a rejected upgrade (a wrong key is answered 401) has another status, and both are the connection failure Windows reports.
- (BOOL)socketOpened {
    if (_opened) return YES;
    NSHTTPURLResponse *response = (NSHTTPURLResponse *)_socket.response;
    return [response isKindOfClass:NSHTTPURLResponse.class] && response.statusCode == 101;
}
- (void)receive {
    __weak MSIMEDoubaoVoiceRequest *weakSelf = self;
    [_socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        MSIMEDoubaoVoiceRequest *owner = weakSelf;
        if (!owner) return;
        @synchronized(owner) {
            if (owner->_done || owner->_cancelled) return;
            if (error) {
                [owner deliver:nil final:YES error:[owner socketOpened] ? DoubaoFailure()
                    : DoubaoFailure(MSIMEDoubaoFailureMessage(MSIMEDoubaoFailureConnect, owner->_legacyAuth, 0))];
                return;
            }
            owner->_opened = YES;
            if (message.type != NSURLSessionWebSocketMessageTypeData) {
                [owner deliver:nil final:YES error:DoubaoFailure()]; return;
            }
            try {
                NSData *data = message.data;
                if (data.length > metasequoia::voice::doubao_response_limit) throw std::invalid_argument("size");
                std::vector<uint8_t> bytes(data.length);
                if (data.length) std::memcpy(bytes.data(), data.bytes, data.length);
                const auto response = metasequoia::voice::parse_doubao_response(bytes);
                NSString *text = [[NSString alloc] initWithBytes:response.text.data() length:response.text.size() encoding:NSUTF8StringEncoding];
                if (response.code) {
                    [owner deliver:nil final:YES error:DoubaoFailure(MSIMEDoubaoFailureMessage(MSIMEDoubaoFailureServerCode,
                        owner->_legacyAuth, static_cast<int32_t>(response.code)))];
                    return;
                }
                if (response.last && !owner->_finalDispatched) {
                    [owner deliver:nil final:YES error:DoubaoFailure()]; return;
                }
                BOOL changed = text.length && ![text isEqual:owner->_lastText];
                if (text.length) owner->_lastText = text;
                if (response.last) {
                    [owner deliver:owner->_lastText final:YES error:owner->_lastText.length ? nil : DoubaoFailure()]; return;
                }
                if (changed) [owner deliver:text final:NO error:nil];
                [owner receive];
            } catch (const std::exception &) { [owner deliver:nil final:YES error:DoubaoFailure()]; }
        }
    }];
}
- (void)pump {
    if (_sending || _done || _cancelled || !_packets.count) return;
    NSData *data = _packets.firstObject;
    [_packets removeObjectAtIndex:0];
    _sending = YES;
    if (_finishing && !_packets.count) _finalDispatched = YES;
    __weak MSIMEDoubaoVoiceRequest *weakSelf = self;
    [_socket sendMessage:[[NSURLSessionWebSocketMessage alloc] initWithData:data] completionHandler:^(NSError *error) {
        MSIMEDoubaoVoiceRequest *owner = weakSelf;
        if (!owner) return;
        @synchronized(owner) {
            if (owner->_done || owner->_cancelled) return;
            owner->_sending = NO;
            owner->_queuedBytes -= data.length;
            if (!error) { [owner pump]; return; }
            // Windows names the two failures before any audio moves: a socket that never opened, and an opening request that could not be sent over one that did. A later audio send failing is left to the generic message, as Windows shows none of its own.
            NSString *detail = nil;
            if (![owner socketOpened]) detail = MSIMEDoubaoFailureMessage(MSIMEDoubaoFailureConnect, owner->_legacyAuth, 0);
            else if (data == owner->_initialPacket) detail = MSIMEDoubaoFailureMessage(MSIMEDoubaoFailureHandshake, owner->_legacyAuth, 0);
            [owner deliver:nil final:YES error:DoubaoFailure(detail)];
        }
    }];
}
- (BOOL)startWithResult:(MSIMEDoubaoResult)result error:(NSError **)error {
    @synchronized(self) {
        if (_started || _cancelled || !result) { if (error) *error = DoubaoFailure(); return NO; }
        _started = YES; _result = [result copy];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.HTTPCookieStorage = nil; configuration.URLCredentialStorage = nil; configuration.URLCache = nil;
        // No whole-session budget. The old 100 s one was sized for a 60 s recording, while MSIME-Windows streams for as long as the user records and bounds only individual network operations; a fixed session length cut dictation off while the user was still speaking. The 30 s request timeout stays, and a finished stream still has its own deadline in finishWithError:.
        configuration.timeoutIntervalForRequest = 30;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:[MSIMEDoubaoSocketPolicy new] delegateQueue:nil];
        _socket = [_session webSocketTaskWithRequest:_request];
        _socket.maximumMessageSize = metasequoia::voice::doubao_response_limit;
        [_socket resume];
        [_packets addObject:_initialPacket]; _queuedBytes = _initialPacket.length;
        [self receive]; [self pump];
        return YES;
    }
}
- (BOOL)appendPCM:(NSData *)pcm error:(NSError **)error {
    @synchronized(self) {
        if (!_started || _done || _cancelled || _finishing) { if (error) *error = DoubaoFailure(); return NO; }
        try {
            if (!pcm.length || pcm.length % sizeof(float))
                throw std::invalid_argument("size");
            std::vector<float> samples(pcm.length / sizeof(float));
            std::memcpy(samples.data(), pcm.bytes, pcm.length);
            for (float sample : samples) if (!std::isfinite(sample) || std::fabs(sample) > 1) throw std::invalid_argument("pcm");
            _pending.insert(_pending.end(), samples.begin(), samples.end());
            std::size_t offset = 0;
            while (_pending.size() - offset >= metasequoia::voice::doubao_chunk_samples) {
                NSData *packet = PacketData(metasequoia::voice::make_doubao_audio(_pending.data() + offset,
                    metasequoia::voice::doubao_chunk_samples, _sequence++, false));
                _queuedBytes += packet.length;
                if (_queuedBytes > 320000) throw std::invalid_argument("backpressure");
                [_packets addObject:packet]; offset += metasequoia::voice::doubao_chunk_samples;
            }
            _pending.erase(_pending.begin(), _pending.begin() + offset);
            [self pump]; return YES;
        } catch (const std::exception &) {
            if (error) *error = DoubaoFailure(); [self deliver:nil final:YES error:DoubaoFailure()]; return NO;
        }
    }
}
- (BOOL)finishWithError:(NSError **)error {
    @synchronized(self) {
        if (!_started || _done || _cancelled || _finishing) { if (error) *error = DoubaoFailure(); return NO; }
        _finishing = YES;
        try {
            NSData *packet = PacketData(metasequoia::voice::make_doubao_audio(_pending.data(), _pending.size(), _sequence, true));
            [_packets addObject:packet]; _queuedBytes += packet.length; _pending.clear(); [self pump];
        } catch (const std::exception &) {
            if (error) *error = DoubaoFailure(); [self deliver:nil final:YES error:DoubaoFailure()]; return NO;
        }
        __weak MSIMEDoubaoVoiceRequest *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            MSIMEDoubaoVoiceRequest *owner = weakSelf;
            if (!owner) return;
            @synchronized(owner) { if (!owner->_done && !owner->_cancelled) [owner deliver:nil final:YES error:DoubaoFailure()]; }
        });
        return YES;
    }
}
- (void)cancel {
    @synchronized(self) {
        _cancelled = YES; _done = YES; _result = nil;
        [_socket cancelWithCloseCode:NSURLSessionWebSocketCloseCodeGoingAway reason:nil];
        [_session invalidateAndCancel]; _socket = nil; _session = nil;
        [_packets removeAllObjects]; _pending.clear(); _queuedBytes = 0;
    }
}
- (void)dealloc { [self cancel]; }
@end
