#import "VoiceAudioMuter.h"
#include <fcntl.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
@implementation MSIMEVoiceAudioMuter {
    MSIMEVoiceAudioAPI _api;
    NSString *_deviceUID;
    UInt32 _old;
    BOOL _changed;
    BOOL _activeMute;
    NSURL *_recoveryDirectory;
    int _journalFD;
}
- (instancetype)init {
    _journalFD = -1;
    NSURL *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
        inDomains:NSUserDomainMask].firstObject;
    NSURL *directory = [support URLByAppendingPathComponent:@"app.msime.client/voice-audio-recovery" isDirectory:YES];
    // A missing support directory must not silently disable crash protection.
    if (!directory) return nil;
    return [self initWithAudioAPI:{} recoveryDirectory:directory];
}
- (instancetype)initWithAudioAPI:(MSIMEVoiceAudioAPI)api {
    return [self initWithAudioAPI:api recoveryDirectory:nil];
}
- (instancetype)initWithAudioAPI:(MSIMEVoiceAudioAPI)api recoveryDirectory:(NSURL *)directory {
    self = [super init];
    if (self) { _api = api; _recoveryDirectory = [directory copy]; _journalFD = -1; }
    return self;
}
- (void)closeJournal {
    if (_journalFD >= 0) close(_journalFD);
    _journalFD = -1;
}
- (BOOL)loadJournal {
    if (!_recoveryDirectory || _journalFD >= 0) return YES;
    if (!_recoveryDirectory.isFileURL) return NO;
    [NSFileManager.defaultManager createDirectoryAtURL:_recoveryDirectory withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700} error:nil];
    int directory = open(_recoveryDirectory.fileSystemRepresentation, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (directory < 0) return NO;
    struct stat info = {};
    if (fstat(directory, &info) || info.st_uid != geteuid() || (info.st_mode & 0777) != 0700) {
        close(directory); return NO;
    }
    int fd = openat(directory, "pending.json", O_RDWR | O_CREAT | O_NOFOLLOW | O_CLOEXEC | O_NONBLOCK, 0600);
    // Keep the directory entry durable before changing any audio state.
    BOOL synced = fsync(directory) == 0;
    close(directory);
    if (fd < 0) return NO;
    if (!synced || fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != geteuid() ||
        info.st_nlink != 1 || (info.st_mode & 0777) != 0600 || flock(fd, LOCK_EX | LOCK_NB)) {
        close(fd); return NO;
    }
    // Re-read size after acquiring the lock; another instance may have just cleared it.
    if (fstat(fd, &info) || info.st_size < 0 || info.st_size > 32768) { close(fd); return NO; }
    if (info.st_size) {
        NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
        if (pread(fd, data.mutableBytes, data.length, 0) != (ssize_t)data.length) { close(fd); return NO; }
        id record = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if (![record isKindOfClass:NSDictionary.class] ||
            ![record[@"version"] isEqual:@1] || ![record[@"previous"] isEqual:@0] ||
            ![record[@"uid"] isKindOfClass:NSString.class] ||
            ![record[@"uid"] length] || [record[@"uid"] length] > 4096) { close(fd); return NO; }
        _deviceUID = [record[@"uid"] copy]; _old = 0; _changed = YES;
    }
    _journalFD = fd;
    return YES;
}
- (BOOL)persistUID:(NSString *)uid previous:(UInt32)previous {
    if (!_recoveryDirectory) return YES;
    if (_journalFD < 0) return NO;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":@1, @"uid":uid, @"previous":@(previous)}
        options:0 error:nil];
    if (!data || data.length > 32768) return NO;
    // A new snapshot is only written after the prior snapshot has been restored.
    return ftruncate(_journalFD, 0) == 0 &&
        pwrite(_journalFD, data.bytes, data.length, 0) == (ssize_t)data.length && fsync(_journalFD) == 0;
}
- (NSString *)deviceUID:(AudioDeviceID)device {
    AudioObjectPropertyAddress address = {kAudioDevicePropertyDeviceUID,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef value = nullptr;
    UInt32 bytes = sizeof(value);
    OSStatus status = _api.get(device, &address, 0, nullptr, &bytes, &value);
    id result = CFBridgingRelease(value);
    if (status != noErr || bytes != sizeof(value) || ![result isKindOfClass:NSString.class] ||
        ![result length] || [result length] > 4096) return nil;
    return [result copy];
}
- (BOOL)mute:(NSError **)error {
    // Repeated starts must not replace the original device or mute snapshot.
    if (_activeMute) return YES;
    auto fail = [&] {
        if (error) *error = [NSError errorWithDomain:@"app.msime.client.voice" code:10
            userInfo:@{NSLocalizedDescriptionKey:@"无法静音系统音频"}];
        return NO;
    };
    if (![self loadJournal]) return fail();
    if (_changed) {
        [self restore];
        if (_changed || ![self loadJournal]) return fail();
    }
    AudioDeviceID device = kAudioObjectUnknown;
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    UInt32 bytes = sizeof(device);
    if (!_api.get || !_api.set ||
        _api.get(kAudioObjectSystemObject, &address, 0, nullptr, &bytes, &device) != noErr ||
        bytes != sizeof(device) || device == kAudioObjectUnknown) return fail();
    address = {kAudioDevicePropertyMute, kAudioDevicePropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 previous = 0;
    bytes = sizeof(previous);
    if (_api.get(device, &address, 0, nullptr, &bytes, &previous) != noErr ||
        bytes != sizeof(previous) || previous > 1) return fail();
    // Do not take ownership of a mute that was already enabled by the user.
    if (previous) { [self closeJournal]; return YES; }
    NSString *uid = [self deviceUID:device];
    if (!uid) return fail();
    if (![self persistUID:uid previous:previous]) { [self closeJournal]; return fail(); }
    _deviceUID = uid; _old = previous; _changed = YES;
    UInt32 muted = 1;
    if (_api.set(device, &address, 0, nullptr, sizeof(muted), &muted) != noErr) {
        [self restore]; return fail();
    }
    _activeMute = YES;
    return YES;
}
- (void)restore {
    _activeMute = NO;
    if (![self loadJournal]) return;
    if (!_changed) { [self closeJournal]; return; }
    if (!_api.get || !_api.set) return;
    // Numeric IDs can be reused after disconnect. Resolve only the owned UID.
    AudioObjectPropertyAddress address = {kAudioHardwarePropertyTranslateUIDToDevice,
        kAudioObjectPropertyScopeGlobal, kAudioObjectPropertyElementMain};
    CFStringRef uid = (__bridge CFStringRef)_deviceUID;
    AudioDeviceID device = kAudioObjectUnknown;
    UInt32 bytes = sizeof(device);
    if (_api.get(kAudioObjectSystemObject, &address, sizeof(uid), &uid, &bytes, &device) != noErr ||
        bytes != sizeof(device) || device == kAudioObjectUnknown ||
        ![[self deviceUID:device] isEqual:_deviceUID]) return;
    address = {kAudioDevicePropertyMute,
        kAudioObjectPropertyScopeOutput, kAudioObjectPropertyElementMain};
    UInt32 current = 0;
    bytes = sizeof(current);
    if (_api.get(device, &address, 0, nullptr, &bytes, &current) != noErr ||
        bytes != sizeof(current) || current > 1) return;
    // The user may already have unmuted it. Never resolve the new default here.
    if (current != _old && _api.set(device, &address, 0, nullptr, sizeof(_old), &_old) != noErr) return;
    // Never unlink the locked inode: other instances must lock this same file.
    if (_journalFD >= 0 && (ftruncate(_journalFD, 0) || fsync(_journalFD))) return;
    // Failed reads/writes retain the original snapshot for the next cleanup.
    _changed = NO; _deviceUID = nil;
    [self closeJournal];
}
- (void)dealloc { [self restore]; [self closeJournal]; }
@end
