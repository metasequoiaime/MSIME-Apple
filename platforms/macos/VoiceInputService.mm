#import "VoiceInputService.h"
#import <AVFoundation/AVFoundation.h>
@implementation MSIMEVoiceInputService { __weak MSIMEClientSession *_session; BOOL _active; }
- (AVAuthorizationStatus)microphoneAuthorizationStatus { return [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeAudio]; }
- (void)requestMicrophonePermission:(void (^)(BOOL))completion { [AVCaptureDevice requestAccessForMediaType:AVMediaTypeAudio completionHandler:^(BOOL granted) { dispatch_async(dispatch_get_main_queue(), ^{ completion(granted); }); }]; }
- (BOOL)isActive { return _active; }
- (BOOL)startWithSession:(MSIMEClientSession *)session generation:(uint64_t *)generation error:(NSError **)error { if (_active) return YES; NSDictionary *result = [session startVoiceWithError:error]; if (!result) return NO; _session = session; _active = YES; if (generation) *generation = [result[@"generation"] unsignedLongLongValue]; return YES; }
- (BOOL)cancelWithError:(NSError **)error { if (!_active) return YES; BOOL ok = [_session cancelVoiceWithError:error]; _active = NO; _session = nil; return ok; }
- (void)applyText:(NSString *)text generation:(uint64_t)generation completion:(MSIMEVoiceInputResult)completion { MSIMEClientSession *session = _session; dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ NSError *error = nil; NSDictionary *result = [session applyVoiceText:text generation:generation error:&error]; dispatch_async(dispatch_get_main_queue(), ^{ completion(result, error); }); }); }
@end
