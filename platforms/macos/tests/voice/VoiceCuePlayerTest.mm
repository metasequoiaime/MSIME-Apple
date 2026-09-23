#import "../../src/voice/VoiceCuePlayer.h"
#import <AppKit/AppKit.h>
#include <cassert>

namespace {
// A throwaway .bundle with the given cue files under Contents/Resources/audios, laid out as the input method bundle stages them.
NSBundle *MakeBundle(NSURL *root, NSString *name, NSArray<NSString *> *cues) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSURL *bundle = [root URLByAppendingPathComponent:name isDirectory:YES];
    NSURL *contents = [bundle URLByAppendingPathComponent:@"Contents" isDirectory:YES];
    NSURL *audios = [contents URLByAppendingPathComponent:@"Resources/audios" isDirectory:YES];
    assert([files createDirectoryAtURL:audios withIntermediateDirectories:YES attributes:nil error:nil]);
    NSDictionary *info = @{@"CFBundleIdentifier": [@"app.msime.test." stringByAppendingString:name], @"CFBundlePackageType": @"BNDL"};
    assert([info writeToURL:[contents URLByAppendingPathComponent:@"Info.plist"] error:nil]);
    NSURL *source = [NSURL fileURLWithPath:@MSIME_VOICE_CUE_SOURCE_DIR isDirectory:YES];
    for (NSString *cue in cues) {
        assert([files copyItemAtURL:[source URLByAppendingPathComponent:cue] toURL:[audios URLByAppendingPathComponent:cue] error:nil]);
    }
    NSBundle *result = [NSBundle bundleWithURL:bundle];
    assert(result);
    return result;
}
}

int main() {
    @autoreleasepool {
        NSURL *root = [NSFileManager.defaultManager.temporaryDirectory URLByAppendingPathComponent:NSUUID.UUID.UUIDString isDirectory:YES];

        // Both product cues present: they are the ones loaded, and each is decodable audio rather than an empty placeholder.
        NSBundle *full = MakeBundle(root, @"Full.bundle", @[@"start.mp3", @"end.mp3"]);
        assert([MSIMEVoiceCueResourceURL(full, YES).lastPathComponent isEqual:@"start.mp3"]);
        assert([MSIMEVoiceCueResourceURL(full, NO).lastPathComponent isEqual:@"end.mp3"]);
        MSIMEVoiceCuePlayer *player = [[MSIMEVoiceCuePlayer alloc] initWithBundle:full];
        assert(player.startCueIsBundled && player.stopCueIsBundled);
        assert(player.startSound && player.stopSound && player.startSound != player.stopSound);
        assert(player.startSound.duration > 0 && player.stopSound.duration > 0);

        // A bundle without the cues must still give audible feedback: each side falls back to the system sound on its own.
        NSBundle *partial = MakeBundle(root, @"Partial.bundle", @[@"start.mp3"]);
        assert(!MSIMEVoiceCueResourceURL(partial, NO));
        MSIMEVoiceCuePlayer *fallback = [[MSIMEVoiceCuePlayer alloc] initWithBundle:partial];
        assert(fallback.startCueIsBundled && !fallback.stopCueIsBundled);
        assert(fallback.stopSound);

        // A test executable's main bundle carries no cues at all; the default initialiser must not fail.
        MSIMEVoiceCuePlayer *bare = [[MSIMEVoiceCuePlayer alloc] init];
        assert(bare && !bare.startCueIsBundled && !bare.stopCueIsBundled && bare.startSound && bare.stopSound);

        [NSFileManager.defaultManager removeItemAtURL:root error:nil];
    }
    return 0;
}
