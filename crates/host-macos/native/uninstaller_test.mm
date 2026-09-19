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
        NSURL *bundle2 = Directory(sandbox, @"Input2.app");
        NSURL *data2 = Directory(sandbox, @"state2");
        NSString *domain = @"app.msime.uninstaller-test";
        [[NSUserDefaults standardUserDefaults] setPersistentDomain:@{@"fixture": @YES} forName:domain];
        assert(msime_macos_uninstall_input_source(bundle2.path.fileSystemRepresentation, data2.path.fileSystemRepresentation,
                                                   domain.UTF8String, true));
        assert(![[NSFileManager defaultManager] fileExistsAtPath:bundle2.path]);
        assert(![[NSFileManager defaultManager] fileExistsAtPath:data2.path]);
        // removePersistentDomainForName: empties the domain; it does not unregister it. Foundation answers an empty dictionary afterwards, not nil, so ask what the uninstall is actually for: that nothing the user stored survives.
        assert([[NSUserDefaults standardUserDefaults] persistentDomainForName:domain].count == 0);
        [[NSFileManager defaultManager] removeItemAtURL:sandbox error:nil];
    }
    std::puts("macOS uninstaller boundary passed.");
    return EXIT_SUCCESS;
}
