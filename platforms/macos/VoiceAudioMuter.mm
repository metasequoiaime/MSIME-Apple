#import "VoiceAudioMuter.h"
#import <CoreAudio/CoreAudio.h>
@implementation MSIMEVoiceAudioMuter { AudioDeviceID _device; UInt32 _old; BOOL _changed; }
- (BOOL)mute:(NSError **)error { AudioObjectPropertyAddress a={kAudioHardwarePropertyDefaultOutputDevice,kAudioObjectPropertyScopeGlobal,kAudioObjectPropertyElementMain}; UInt32 n=sizeof(_device); if(AudioObjectGetPropertyData(kAudioObjectSystemObject,&a,0,NULL,&n,&_device)!=noErr||!_device){if(error)*error=[NSError errorWithDomain:@"app.msime.client.voice" code:10 userInfo:nil];return NO;} a.mSelector=kAudioDevicePropertyMute;a.mScope=kAudioDevicePropertyScopeOutput;n=sizeof(_old); if(AudioObjectGetPropertyData(_device,&a,0,NULL,&n,&_old)!=noErr)return NO; UInt32 one=1; if(AudioObjectSetPropertyData(_device,&a,0,NULL,sizeof(one),&one)!=noErr)return NO; _changed=YES; return YES; }
- (void)restore { if(!_changed||!_device)return; AudioObjectPropertyAddress a={kAudioDevicePropertyMute,kAudioDevicePropertyScopeOutput,kAudioObjectPropertyElementMain}; AudioObjectSetPropertyData(_device,&a,0,NULL,sizeof(_old),&_old); _changed=NO; }
- (void)dealloc { [self restore]; }
@end
