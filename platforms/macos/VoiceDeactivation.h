#pragma once
#import "VoiceInputService.h"
#import "VoiceAudioMuter.h"
#import "VoiceWaveOverlay.h"

// Called on the main thread after validating the departing input client.
// Cancel, rather than stop-and-transcribe, so a focus loss never submits speech.
static inline void MSIMEDeactivateVoice(MSIMEVoiceInputService *service,
    MSIMEClientSession *session, MSIMEVoiceAudioMuter *muter,
    MSIMEVoiceWaveOverlay *overlay, NSString *socket, uint64_t generation) {
    const BOOL cancelProvider = service.active && socket.length && session;
    [service cancelWithError:nil];
    [muter restore];
    [overlay setListening:NO];
    if (cancelProvider) {
        // Copy the departing session identity before a new client can activate.
        NSString *path = [socket copy];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
            [session voiceProviderCancelSocket:path generation:generation error:nil];
        });
    }
}
