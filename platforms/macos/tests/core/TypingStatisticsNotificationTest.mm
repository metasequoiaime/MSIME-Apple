#import <Foundation/Foundation.h>

#include <cassert>

extern "C" void msime_macos_notify_typing_statistics_enabled(bool enabled);

int main() {
    @autoreleasepool {
        NSDistributedNotificationCenter *center = NSDistributedNotificationCenter.defaultCenter;
        NSNotificationName const name = @"MetasequoiaTypingStatisticsEnabledChangedNotification";
        __block NSNumber *received = nil;
        id observer = [center addObserverForName:name object:nil queue:NSOperationQueue.mainQueue
                                      usingBlock:^(NSNotification *notification) {
            id enabled = notification.userInfo[@"enabled"];
            if ([enabled isKindOfClass:NSNumber.class]) received = enabled;
        }];

        msime_macos_notify_typing_statistics_enabled(true);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!received && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(received != nil);
        assert(received.boolValue);

        received = nil;
        msime_macos_notify_typing_statistics_enabled(false);
        deadline = [NSDate dateWithTimeIntervalSinceNow:2.0];
        while (!received && deadline.timeIntervalSinceNow > 0) {
            [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode
                                  beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
        }
        assert(received != nil);
        assert(!received.boolValue);
        [center removeObserver:observer];
    }
    return 0;
}
