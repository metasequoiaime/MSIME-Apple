#import "../CloudClipboardClient.h"
#include <cassert>
int main() {
    @autoreleasepool {
        for (id itemID in @[@"", @".", @"..", NSNull.null, @42]) {
            __block BOOL completed = NO;
            MSIMERemoveCloudClipboard(itemID, @"synthetic-session", ^(NSData *data, NSInteger status, NSError *error) {
                assert(data == nil && status == 400 && error == nil);
                completed = YES;
            });
            assert(completed);
        }
        MSIMERemoveCloudClipboard(nil, @"synthetic-session", nil);
    }
}
