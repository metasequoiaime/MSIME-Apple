#import <Foundation/Foundation.h>

// Keep this notification name in sync with InputController.mm. The settings process is separate from the input-method process, so the distributed center is what wakes IMK at once; the quiesce lease the caller has already written beside the dictionary lock is what IMK checks before it releases, and its one-second preferences timer finds the lease if this notification is missed. It goes to the local center as well, which is how the native dictionary window inside the input method reaches its own controllers.
extern "C" void msime_macos_quiesce_input_sessions(void)
{
    NSNotificationName const name = @"MSIMEDictionaryMaintenanceWillBeginNotification";
    [NSNotificationCenter.defaultCenter postNotificationName:name object:nil];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:name
                                                                   object:nil
                                                                 userInfo:nil
                                                        deliverImmediately:YES];
}

// Keep this notification name in sync with InputController.mm. The settings window and IMK input
// method live in separate processes, so changing the aggregate-statistics opt-in must cross that
// boundary before the hot capture path can stop (or resume) at its first instruction.
extern "C" void msime_macos_notify_typing_statistics_enabled(bool enabled)
{
    NSNotificationName const name = @"MetasequoiaTypingStatisticsEnabledChangedNotification";
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:name
                                                                   object:nil
                                                                 userInfo:@{ @"enabled": @(enabled) }
                                                        deliverImmediately:YES];
}
