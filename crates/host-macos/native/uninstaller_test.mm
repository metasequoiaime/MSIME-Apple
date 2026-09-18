#import <Foundation/Foundation.h>

#include <cassert>
#include <cstdio>
#include <cstdlib>

extern "C" bool msime_macos_uninstall_input_source(const char *, const char *, const char *, bool);

static NSURL *Directory(NSURL *root, NSString *name) {
    NSURL *url = [root URLByAppendingPathComponent:name isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

int main() {
    @autoreleasepool {
        NSURL *root = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
        NSURL *sandbox = Directory(root, [NSString stringWithFormat:@"msime-uninstaller-%@", NSUUID.UUID.UUIDString]);
        NSURL *bundle = Directory(sandbox, @"Input.app");
        NSURL *data = Directory(sandbox, @"state");
        NSString *bundlePath = bundle.path;
        NSString *dataPath = data.path;
        assert(msime_macos_uninstall_input_source(bundlePath.fileSystemRepresentation, dataPath.fileSystemRepresentation,
                                                   "app.msime.test", false));
        assert(![[NSFileManager defaultManager] fileExistsAtPath:bundle.path]);
        assert([[NSFileManager defaultManager] fileExistsAtPath:data.path]);
        [[NSFileManager defaultManager] removeItemAtURL:sandbox error:nil];
    }
    std::puts("macOS uninstaller boundary passed.");
    return EXIT_SUCCESS;
}
