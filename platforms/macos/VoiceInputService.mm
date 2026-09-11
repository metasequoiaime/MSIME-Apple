#import "VoiceInputService.h"
#import <AVFoundation/AVFoundation.h>
@implementation MSIMEVoiceInputService { __weak MSIMEClientSession *_session; BOOL _active; AVAudioEngine *_audioEngine; }
- (AVAuthorizationStatus)microphoneAuthorizationStatus { return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]; }
- (void)requestMicrophonePermission:(void (^)(BOOL))completion { [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) { dispatch_async(dispatch_get_main_queue(), ^{ completion(granted); }); }]; }
- (BOOL)isActive { return _active; }
- (BOOL)startMicrophoneCapture:(MSIMEVoiceAudioBuffer)bufferHandler error:(NSError **)error {
    if ([self microphoneAuthorizationStatus] != AVAuthorizationStatusAuthorized) { if (error) *error = [NSError errorWithDomain:@"app.msime.client.voice" code:1 userInfo:@{NSLocalizedDescriptionKey: @"麦克风权限未授权"}]; return NO; }
    if (_audioEngine) return YES;
    _audioEngine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *input = _audioEngine.inputNode;
    AVAudioFormat *format = [input inputFormatForBus:0];
    [input installTapOnBus:0 bufferSize:1024 format:format block:^(AVAudioPCMBuffer *buffer, AVAudioTime *time) { (void)time; bufferHandler(buffer); }];
    NSError *startError = nil;
    if (![_audioEngine startAndReturnError:&startError]) { [input removeTapOnBus:0]; _audioEngine = nil; if (error) *error = startError; return NO; }
    return YES;
}
- (void)stopMicrophoneCapture { if (!_audioEngine) return; [_audioEngine.inputNode removeTapOnBus:0]; [_audioEngine stop]; _audioEngine = nil; }
- (BOOL)startWithSession:(MSIMEClientSession *)session generation:(uint64_t *)generation error:(NSError **)error { if (_active) return YES; NSDictionary *result = [session startVoiceWithError:error]; if (!result) return NO; _session = session; _active = YES; if (generation) *generation = [result[@"generation"] unsignedLongLongValue]; return YES; }
- (BOOL)cancelWithError:(NSError **)error { if (!_active) return YES; BOOL ok = [_session cancelVoiceWithError:error]; _active = NO; _session = nil; return ok; }
- (void)applyText:(NSString *)text generation:(uint64_t)generation completion:(MSIMEVoiceInputResult)completion { MSIMEClientSession *session = _session; dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ NSError *error = nil; NSDictionary *result = [session applyVoiceText:text generation:generation error:&error]; dispatch_async(dispatch_get_main_queue(), ^{ completion(result, error); }); }); }
@end
