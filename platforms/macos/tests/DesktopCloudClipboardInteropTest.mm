#import "../DesktopCloudClipboard.h"
#include <cassert>
#include <sys/stat.h>

@interface SyntheticCloudProvider : NSObject <MSIMEDesktopCloudClipboardProvider>
@property(nonatomic) unsigned calls;
@end
@implementation SyntheticCloudProvider
- (NSProgress *)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
    assert(NSThread.isMainThread);
    ++self.calls;
    if ([request[@"operation"] isEqual:@"add"]) {
        assert([request[@"text"] length] == 3000);
        assert([request[@"text"] containsString:@"\n\t"]);
    }
    completion(@{@"ok":@YES, @"value":@{@"operation":request[@"operation"]}});
    return [NSProgress progressWithTotalUnitCount:1];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        SyntheticCloudProvider *provider = [SyntheticCloudProvider new];
        MSIMEDesktopCloudClipboardSession *session = [[MSIMEDesktopCloudClipboardSession alloc] initWithProvider:provider];
        assert(session);
        NSData *configuration = [session.launchEnvironment[@"MSIME_CLIENT_CLOUD_CLIPBOARD_SESSION"] dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = [NSJSONSerialization JSONObjectWithData:configuration options:0 error:nil][@"path"];
        struct stat status{};
        assert(stat(path.fileSystemRepresentation, &status) == 0 && (status.st_mode & 0777) == 0600);
        assert(stat(path.stringByDeletingLastPathComponent.fileSystemRepresentation, &status) == 0 && (status.st_mode & 0777) == 0700);
        NSTask *probe = [NSTask new];
        probe.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        probe.environment = session.launchEnvironment;
        NSPipe *gate = [NSPipe pipe];
        probe.standardInput = gate;
        assert([probe launchAndReturnError:nil]);
        [session authorizePID:probe.processIdentifier stillValid:^BOOL { return probe.running; }];
        const char ready = 1;
        [gate.fileHandleForWriting writeData:[NSData dataWithBytes:&ready length:1]];
        [gate.fileHandleForWriting closeFile];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
        while (probe.running && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        assert(!probe.running && probe.terminationStatus == 0 && provider.calls == 4);
        // Peer termination must close and remove the private endpoint by itself.
        deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while ([NSFileManager.defaultManager fileExistsAtPath:path] && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        assert(![NSFileManager.defaultManager fileExistsAtPath:path.stringByDeletingLastPathComponent]);
        [session stop];
    }
}
