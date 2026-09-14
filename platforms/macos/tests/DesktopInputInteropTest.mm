#import "../DesktopInputSession.h"
#include <cassert>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        __block unsigned committed = 0;
        MSIMEDesktopInputSession *session = [[MSIMEDesktopInputSession alloc]
            initWithTargetPID:NSProcessInfo.processInfo.processIdentifier launchTime:42
            handler:^(NSString *text, double deadline, MSIMEPanelTextCompletion completion) {
                assert(NSThread.isMainThread);
                assert([text isEqualToString:@"synthetic"]);
                assert(deadline > NSProcessInfo.processInfo.systemUptime);
                ++committed;
                completion(YES);
            }];
        assert(session);
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
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
        while (probe.running && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        assert(!probe.running);
        assert(probe.terminationStatus == 0 && committed == 1);
        [session stop];
    }
}
