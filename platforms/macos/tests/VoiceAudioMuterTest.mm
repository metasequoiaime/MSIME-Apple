#import <Foundation/Foundation.h>
#import "../VoiceAudioMuter.h"

int main() {
    @autoreleasepool {
        MSIMEVoiceAudioMuter *muter = [[MSIMEVoiceAudioMuter alloc] init];
        [muter restore];
    }
    return 0;
}
