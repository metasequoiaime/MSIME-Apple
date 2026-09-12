#import "../BackendSelectionObservation.h"
#include <cassert>

@interface SelectionObserver : NSObject
@property(nonatomic) NSUInteger calls;
- (void)selected:(NSNotification *)notification;
@end
@implementation SelectionObserver
- (void)selected:(NSNotification *)notification { (void)notification; self.calls += 1; }
@end

int main() {
    @autoreleasepool {
        NSNotificationCenter *center = [NSNotificationCenter new];
        SelectionObserver *observer = [SelectionObserver new];
        NSString *name = @"MSIMEHandwritingCandidateSelected";
        // Reproduce the old repeated activation behavior with Foundation itself.
        for (int i = 0; i < 2; ++i)
            [center addObserver:observer selector:@selector(selected:) name:name object:nil];
        [center postNotificationName:name object:nil];
        assert(observer.calls == 2);
        observer.calls = 0;
        for (int i = 0; i < 10; ++i)
            MSIMESetBackendSelectionObservation(center, observer, @selector(selected:), YES);
        [center postNotificationName:name object:nil];
        assert(observer.calls == 1);
        [center addObserver:observer selector:@selector(selected:) name:@"UnrelatedFixture" object:nil];
        MSIMESetBackendSelectionObservation(center, observer, @selector(selected:), NO);
        [center postNotificationName:name object:nil];
        assert(observer.calls == 1);
        [center postNotificationName:@"UnrelatedFixture" object:nil];
        assert(observer.calls == 2);
        MSIMESetBackendSelectionObservation(center, observer, @selector(selected:), YES);
        [center postNotificationName:name object:nil];
        assert(observer.calls == 3);
        [center removeObserver:observer];
    }
}
