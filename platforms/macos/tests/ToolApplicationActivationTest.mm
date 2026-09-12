#import "../ToolApplicationActivation.h"
#include <cassert>

static NSUInteger step;
@interface ActivationHost : NSObject
@property(nonatomic) id expectedTarget;
- (void)yieldActivationToApplication:(id)target;
@end
@implementation ActivationHost
- (void)yieldActivationToApplication:(id)target { assert(target == self.expectedTarget); assert(step == 0); step = 1; }
@end
@interface ActivationTarget : NSObject
@property(nonatomic, getter=isTerminated) BOOL terminated;
@property(nonatomic) BOOL allowed;
@property(nonatomic) id expectedSource;
- (BOOL)activateFromApplication:(id)source options:(NSApplicationActivationOptions)options;
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options;
@end
@implementation ActivationTarget
- (BOOL)activateFromApplication:(id)source options:(NSApplicationActivationOptions)options {
    assert(source == self.expectedSource && options == 0 && step == 1); step = 2; return self.allowed;
}
- (BOOL)activateWithOptions:(NSApplicationActivationOptions)options { assert(options == 0 && step == 0); step = 3; return self.allowed; }
@end

int main() {
    @autoreleasepool {
        assert(MSIMEToolApplicationMatches(@"test.fixture", @"test.fixture"));
        assert(!MSIMEToolApplicationMatches(@"test.fixture", @"test.other"));
        assert(!MSIMEToolApplicationMatches(nil, nil));
        assert(!MSIMEToolApplicationMatches(@"", @""));
        ActivationHost *host = [ActivationHost new];
        ActivationTarget *target = [ActivationTarget new];
        NSObject *source = [NSObject new];
        host.expectedTarget = target;
        target.expectedSource = source;
        const BOOL allowedValues[] = {NO, YES};
        for (BOOL allowed : allowedValues) {
            target.allowed = allowed;
            step = 0;
            assert(MSIMEActivateToolApplication((NSApplication *)host, (NSRunningApplication *)source, (NSRunningApplication *)target, NO) == allowed);
            assert(step == 3);
            if (@available(macOS 14.0, *)) {
                step = 0;
                assert(MSIMEActivateToolApplication((NSApplication *)host, (NSRunningApplication *)source, (NSRunningApplication *)target) == allowed);
                assert(step == 2);
            }
        }
        target.terminated = YES;
        step = 0;
        assert(!MSIMEActivateToolApplication((NSApplication *)host, (NSRunningApplication *)source, (NSRunningApplication *)target));
        assert(step == 0);
    }
}
