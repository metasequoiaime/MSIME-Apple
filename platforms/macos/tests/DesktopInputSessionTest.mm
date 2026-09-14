#import "../DesktopInputSession.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <atomic>
#include <cassert>
#include <thread>
#include <vector>

static void Check(std::vector<unsigned char> body, uint32_t declared, bool authorized,
                  bool accept, bool expectedCall, int expectedResponse) {
    __block unsigned calls = 0;
    MSIMEDesktopInputSession *session = [[MSIMEDesktopInputSession alloc]
        initWithTargetPID:getpid() launchTime:42 handler:^(NSString *text, double deadline,
                                                        MSIMEPanelTextCompletion completion) {
            assert(NSThread.isMainThread);
            assert([text isEqualToString:@"synthetic"]);
            assert(deadline > NSProcessInfo.processInfo.systemUptime);
            ++calls;
            completion(accept);
            completion(!accept); // A duplicate completion cannot reverse the result.
        }];
    assert(session);
    [session authorizePID:authorized ? getpid() : getpid() + 1 stillValid:^BOOL { return YES; }];
    NSData *json = [session.launchEnvironment[@"MSIME_CLIENT_PANEL_SESSION"] dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *configuration = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil];
    NSString *path = configuration[@"path"];
    struct stat info{};
    assert(stat(path.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0600);
    assert(stat(path.stringByDeletingLastPathComponent.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0700);
    std::atomic<bool> done{false};
    std::thread worker([&] {
        @autoreleasepool {
            int fd = socket(AF_UNIX, SOCK_STREAM, 0);
            assert(fd >= 0);
            int noSignal = 1;
            setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSignal, sizeof(noSignal));
            timeval timeout{5, 0};
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
            sockaddr_un address{};
            address.sun_family = AF_UNIX; address.sun_len = sizeof(address);
            strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
            assert(connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0);
            uint32_t length = htonl(declared);
            // An unauthorized peer may be closed before it can write.
            (void)send(fd, &length, sizeof(length), 0);
            if (!body.empty()) (void)send(fd, body.data(), body.size(), 0);
            shutdown(fd, SHUT_WR);
            unsigned char response = 255;
            ssize_t count = recv(fd, &response, 1, 0);
            if (expectedResponse < 0) assert(count <= 0);
            else assert(count == 1 && response == expectedResponse);
            close(fd);
            done.store(true);
        }
    });
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:8];
    while (!done.load() && timeout.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(done.load());
    worker.join();
    assert(calls == unsigned(expectedCall));
    [session stop];
    for (int attempt = 0; attempt < 100 && access(path.fileSystemRepresentation, F_OK) == 0; ++attempt)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(access(path.fileSystemRepresentation, F_OK) != 0);
    assert(access(path.stringByDeletingLastPathComponent.fileSystemRepresentation, F_OK) != 0);
}

int main() {
    @autoreleasepool {
        const std::vector<unsigned char> text{'s','y','n','t','h','e','t','i','c'};
        Check(text, 9, true, true, true, 0);
        Check(text, 9, true, false, true, 1);
        Check(text, 9, false, true, false, -1);
        Check({}, 0, true, true, false, -1);
        Check({}, 4097, true, true, false, 1);
        Check({0xff}, 1, true, true, false, -1);
        Check({0}, 1, true, true, false, -1);
        Check(text, 8, true, true, false, -1); // Trailing bytes.
        Check(text, 10, true, true, false, -1); // Truncated frame.
    }
}
