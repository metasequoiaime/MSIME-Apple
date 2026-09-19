#import "../../src/core/DesktopCloudClipboard.h"
#include <sys/socket.h>
#include <sys/un.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <atomic>
#include <cassert>
#include <memory>
#include <thread>

@interface PendingAccountProvider : NSObject <MSIMEDesktopCloudClipboardProvider>
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL cancelled;
@end
@implementation PendingAccountProvider
- (NSProgress *)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
    (void)request; (void)completion;
    self.started = YES;
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1];
    progress.cancellationHandler = ^{ dispatch_async(dispatch_get_main_queue(), ^{ self.cancelled = YES; }); };
    return progress;
}
@end

int main() {
    @autoreleasepool {
        PendingAccountProvider *provider = [PendingAccountProvider new];
        MSIMEDesktopCloudClipboardSession *session = [[MSIMEDesktopCloudClipboardSession alloc] initWithProvider:provider dictionary:YES];
        assert(session);
        auto live = std::make_shared<std::atomic<bool>>(true);
        [session authorizePID:getpid() stillValid:^BOOL { return live->load(); }];
        NSData *json = [session.launchEnvironment[@"MSIME_CLIENT_CLOUD_DICTIONARY_SESSION"] dataUsingEncoding:NSUTF8StringEncoding];
        NSString *path = [NSJSONSerialization JSONObjectWithData:json options:0 error:nil][@"path"];
        std::atomic<bool> done{false};
        std::thread worker([&] {
            @autoreleasepool {
                int fd = socket(AF_UNIX, SOCK_STREAM, 0); assert(fd >= 0);
                timeval timeout{5, 0}; setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
                sockaddr_un address{}; address.sun_family = AF_UNIX; address.sun_len = sizeof(address);
                strlcpy(address.sun_path, path.fileSystemRepresentation, sizeof(address.sun_path));
                assert(connect(fd, reinterpret_cast<sockaddr *>(&address), sizeof(address)) == 0);
                const char body[] = "{\"operation\":\"export\",\"kind\":\"pinyin\",\"format\":\"standard\"}";
                const uint32_t length = htonl(sizeof(body) - 1);
                assert(send(fd, &length, sizeof(length), 0) == sizeof(length));
                assert(send(fd, body, sizeof(body) - 1, 0) == sizeof(body) - 1);
                shutdown(fd, SHUT_WR);
                char response;
                assert(recv(fd, &response, 1, 0) <= 0);
                close(fd); done.store(true);
            }
        });
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
        while (!provider.started && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        assert(provider.started);
        live->store(false); // The panel process is no longer authorized/alive.
        while ((!provider.cancelled || !done.load()) && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        assert(provider.cancelled && done.load());
        worker.join();
        [session stop];
    }
}
