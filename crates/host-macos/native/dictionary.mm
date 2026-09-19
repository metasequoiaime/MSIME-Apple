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
