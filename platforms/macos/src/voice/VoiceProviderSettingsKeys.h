#pragma once
#import <Foundation/Foundation.h>

// The native voice window keeps its own "voiceInput" dictionary and the input method reads the
// MSIMEClientVoice* defaults. For a long time only the first of those was written, so every choice made in
// that window was stored and then ignored - the window looked like it worked and no recording ever used it.
//
// These two functions are the pairing, in one place so the window and its test agree: what a saved field is
// written to, and which of the two stores wins when the window is reopened. A field added to the window
// without a line here is a field the runtime will not see.

// The window's private key for each editable string, and the shared default the input method reads.
static inline NSDictionary<NSString *, NSString *> *MSIMEVoiceProviderSharedKeys(void)
{
    return @{
        @"provider" : @"MSIMEClientVoiceASRProvider",
        @"endpoint" : @"MSIMEClientVoiceASREndpoint",
        @"model" : @"MSIMEClientVoiceASRModel",
        @"modelPath" : @"MSIMEClientVoiceASRModelPath",
        @"token" : @"MSIMEClientVoiceASRToken",
        @"polishEndpoint" : @"MSIMEClientVoicePolishEndpoint",
        @"polishModel" : @"MSIMEClientVoicePolishModel",
        @"polishToken" : @"MSIMEClientVoicePolishToken",
        @"captureDevice" : @"MSIMEClientVoiceCaptureDevice",
    };
}

// Prefer whatever the shared default holds, because the Tauri settings page writes only that one and it is
// the primary editor. Fall back to the window's own dictionary so a configuration saved by an older build
// is not silently dropped on first open, and to `fallback` when neither store has been written.
//
// `saved` is read leniently on purpose: dictionaryForKey: type-checks the container and nothing inside it,
// and an out-of-band edit that leaves a number where a string belongs used to reach -length and kill the
// input method on the next Control+Option+V.
static inline NSString *MSIMEVoiceProviderSharedSetting(NSDictionary *saved, NSString *key, id sharedValue,
                                                        NSString *fallback)
{
    if ([sharedValue isKindOfClass:NSString.class] && [(NSString *)sharedValue length] > 0)
        return (NSString *)sharedValue;
    id value = [saved isKindOfClass:NSDictionary.class] ? saved[key] : nil;
    return [value isKindOfClass:NSString.class] ? (NSString *)value : fallback;
}
