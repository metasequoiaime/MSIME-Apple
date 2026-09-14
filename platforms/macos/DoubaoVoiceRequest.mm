#import "DoubaoVoiceRequest.h"
#include <msime/voice/doubao_protocol.h>
#include <cmath>
#include <cstring>
#include <stdexcept>

namespace {
NSError *DoubaoFailure() {
    return [NSError errorWithDomain:@"app.msime.client.voice.doubao" code:1
        userInfo:@{NSLocalizedDescriptionKey:@"豆包语音请求失败，请检查服务设置或重试"}];
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
    NSUInteger _totalSamples, _queuedBytes;
    int32_t _sequence;
    BOOL _started, _finishing, _done, _cancelled, _sending, _finalDispatched;
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
            ![value UTF8String] ||
            [value rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound)) {
            if (error) *error = DoubaoFailure(); return nil;
        }
        if (value) snapshot[key] = [value copy];
    }
    NSString *endpoint = [snapshot[@"asr_endpoint"] length] ? snapshot[@"asr_endpoint"] : @"wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async";
    NSURLComponents *url = [NSURLComponents componentsWithString:endpoint];
    BOOL local = [@[@"127.0.0.1", @"localhost", @"::1"] containsObject:url.host.lowercaseString];
    if (!url.URL || !url.host.length || url.user || url.password || url.fragment ||
        (![url.scheme.lowercaseString isEqual:@"wss"] && !(local && [url.scheme.lowercaseString isEqual:@"ws"])) ||
        ![snapshot[@"asr_token"] length]) { if (error) *error = DoubaoFailure(); return nil; }
    NSString *mode = snapshot[@"doubao_auth_mode"];
    if (mode.length && ![@[@"api_key", @"legacy"] containsObject:mode]) { if (error) *error = DoubaoFailure(); return nil; }
    BOOL legacy = mode.length ? [mode isEqual:@"legacy"] : [snapshot[@"asr_app_key"] length] > 0;
    if (legacy && ![snapshot[@"asr_app_key"] length]) { if (error) *error = DoubaoFailure(); return nil; }
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
    request.timeoutInterval = 10;
    request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    if (legacy) {
        [request setValue:snapshot[@"asr_app_key"] forHTTPHeaderField:@"X-Api-App-Key"];
        [request setValue:snapshot[@"asr_token"] forHTTPHeaderField:@"X-Api-Access-Key"];
    } else [request setValue:snapshot[@"asr_token"] forHTTPHeaderField:@"X-Api-Key"];
    [request setValue:[snapshot[@"asr_resource_id"] length] ? snapshot[@"asr_resource_id"] : @"volc.bigasr.sauc.duration"
        forHTTPHeaderField:@"X-Api-Resource-Id"];
    [request setValue:NSUUID.UUID.UUIDString forHTTPHeaderField:@"X-Api-Request-Id"];
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
- (void)receive {
    __weak MSIMEDoubaoVoiceRequest *weakSelf = self;
    [_socket receiveMessageWithCompletionHandler:^(NSURLSessionWebSocketMessage *message, NSError *error) {
        MSIMEDoubaoVoiceRequest *owner = weakSelf;
        if (!owner) return;
        @synchronized(owner) {
            if (owner->_done || owner->_cancelled) return;
            if (error || message.type != NSURLSessionWebSocketMessageTypeData) {
                [owner deliver:nil final:YES error:DoubaoFailure()]; return;
            }
            try {
                NSData *data = message.data;
                if (data.length > metasequoia::voice::doubao_response_limit) throw std::invalid_argument("size");
                std::vector<uint8_t> bytes(data.length);
                if (data.length) std::memcpy(bytes.data(), data.bytes, data.length);
                const auto response = metasequoia::voice::parse_doubao_response(bytes);
                NSString *text = [[NSString alloc] initWithBytes:response.text.data() length:response.text.size() encoding:NSUTF8StringEncoding];
                if (response.code || (response.last && !owner->_finalDispatched)) {
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
            if (error) [owner deliver:nil final:YES error:DoubaoFailure()];
            else [owner pump];
        }
    }];
}
- (BOOL)startWithResult:(MSIMEDoubaoResult)result error:(NSError **)error {
    @synchronized(self) {
        if (_started || _cancelled || !result) { if (error) *error = DoubaoFailure(); return NO; }
        _started = YES; _result = [result copy];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.HTTPCookieStorage = nil; configuration.URLCredentialStorage = nil; configuration.URLCache = nil;
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 100;
        _session = [NSURLSession sessionWithConfiguration:configuration delegate:[MSIMEDoubaoSocketPolicy new] delegateQueue:nil];
        _socket = [_session webSocketTaskWithRequest:_request];
        _socket.maximumMessageSize = metasequoia::voice::doubao_response_limit;
        [_socket resume];
        [_packets addObject:_initialPacket]; _queuedBytes = _initialPacket.length;
        [self receive]; [self pump];
        __weak MSIMEDoubaoVoiceRequest *weakSelf = self;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_SEC), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            MSIMEDoubaoVoiceRequest *owner = weakSelf;
            if (!owner) return;
            @synchronized(owner) { if (!owner->_done && !owner->_cancelled) [owner deliver:nil final:YES error:DoubaoFailure()]; }
        });
        return YES;
    }
}
- (BOOL)appendPCM:(NSData *)pcm error:(NSError **)error {
    @synchronized(self) {
        if (!_started || _done || _cancelled || _finishing) { if (error) *error = DoubaoFailure(); return NO; }
        try {
            if (!pcm.length || pcm.length % sizeof(float) || pcm.length / sizeof(float) > 16000 * 60 - _totalSamples)
                throw std::invalid_argument("size");
            std::vector<float> samples(pcm.length / sizeof(float));
            std::memcpy(samples.data(), pcm.bytes, pcm.length);
            for (float sample : samples) if (!std::isfinite(sample) || std::fabs(sample) > 1) throw std::invalid_argument("pcm");
            _totalSamples += samples.size();
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
