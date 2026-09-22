#import <Foundation/Foundation.h>

// Keep this notification name in sync with the IMK bundle.  The settings
// process is separate from the input-method process, so the distributed
// center is the only reliable way to release the IMK dictionary lease before
// a maintenance write.
extern "C" void msime_macos_quiesce_input_sessions(void)
{
    NSNotificationName const name = @"MetasequoiaWillResetLearnedDataNotification";
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
