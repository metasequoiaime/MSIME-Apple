#pragma once
#import <Foundation/Foundation.h>

// The voice requests attach the sentence MSIME-Windows shows for a failed recognition to their NSError under this key, next to the fixed NSLocalizedDescriptionKey. It names what went wrong - the provider's own message, the HTTP status, the SiliconFlow trace id, the Doubao code - and never carries a token, a header or a request body.
static NSString *const MSIMEVoiceFailureDetailKey = NSLocalizedFailureReasonErrorKey;

// The detail a voice request attached, or nil. Only errors from this host's voice domains are read: an NSURLSession or system error has its own failure reason, written for developers, which is not what the overlay shows.
static inline NSString *MSIMEVoiceFailureDetail(NSError *error) {
    if (![error.domain hasPrefix:@"app.msime.client.voice"]) return nil;
    id detail = error.userInfo[MSIMEVoiceFailureDetailKey];
    return [detail isKindOfClass:NSString.class] && [detail length] ? detail : nil;
}

// The three Doubao failures MSIME-Windows doubao_asr_client.cpp names: the websocket never opened, the opening request could not be sent, or the service answered with a non-zero code.
typedef NS_ENUM(NSInteger, MSIMEDoubaoFailureKind) {
    MSIMEDoubaoFailureConnect,
    MSIMEDoubaoFailureHandshake,
    MSIMEDoubaoFailureServerCode
};

// The Windows wording, including its hint for which credentials to check: the legacy console signs in with App ID and Access Token, the new one with a single API Key.
static inline NSString *MSIMEDoubaoFailureMessage(MSIMEDoubaoFailureKind kind, BOOL legacyAuth, int32_t code) {
    switch (kind) {
        case MSIMEDoubaoFailureConnect:
            return legacyAuth ? @"无法连接豆包语音识别。请检查 App ID、Access Token 和接口地址。"
                              : @"无法连接豆包语音识别。请检查 API Key 和接口地址。";
        case MSIMEDoubaoFailureHandshake: return @"豆包语音识别握手失败。";
        case MSIMEDoubaoFailureServerCode:
            return [NSString stringWithFormat:@"豆包语音识别失败（code %d）。请检查 Access Token。", code];
    }
    return nil;
}
