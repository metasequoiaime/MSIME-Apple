#import "../BackendAccountEntry.h"
#include <cassert>

@interface RecordingAccountWindow : NSObject <MSIMEBackendAccountEntry>
@property(nonatomic) NSUInteger presentations;
@end
@implementation RecordingAccountWindow
+ (id)shared {
    static RecordingAccountWindow *window = [RecordingAccountWindow new];
    return window;
}
- (void)showAccount { self.presentations += 1; }
@end

@interface InvalidAccountWindow : NSObject
@end
@implementation InvalidAccountWindow
+ (id)shared { return [NSObject new]; }
@end

int main() {
    @autoreleasepool {
        assert(!MSIMEOpenBackendAccount(Nil));
        assert(!MSIMEOpenBackendAccount(NSObject.class));
        assert(!MSIMEOpenBackendAccount(InvalidAccountWindow.class));
        assert(MSIMEOpenBackendAccount(RecordingAccountWindow.class));
        assert(MSIMEOpenBackendAccount(RecordingAccountWindow.class));
        assert(((RecordingAccountWindow *)[RecordingAccountWindow shared]).presentations == 2);
    }
}
