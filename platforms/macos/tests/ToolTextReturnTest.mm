#import "../ToolTextReturn.h"
#include <cassert>

int main() {
    @autoreleasepool {
        MSIMEToolTextReturn state;
        NSObject *first = [NSObject new];
        NSObject *other = [NSObject new];
        auto token = state.capture(first);
        assert(!state.queue(@"", token, 10));
        assert(state.queue(@"synthetic-one", token, 10));
        assert(!state.queue(@"synthetic-duplicate", token, 10));
        assert([state.take(first, 11) isEqual:@"synthetic-one"]);
        assert(!state.take(first, 11));
        assert(!state.queue(@"synthetic-stale", token, 11));

        token = state.capture(first);
        assert(state.queue(@"synthetic-two", token, 20));
        assert(!state.take(other, 21));
        assert(!state.take(first, 21));

        token = state.capture(first);
        assert(state.queue(@"synthetic-expired", token, 30));
        assert(!state.take(first, 32));

        const auto old = state.capture(first);
        token = state.capture(other);
        assert(!state.queue(@"synthetic-old-window", old, 40));
        assert(state.queue(@"synthetic-new-window", token, 40));
        state.discard(old);
        assert([state.take(other, 41) isEqual:@"synthetic-new-window"]);

        @autoreleasepool {
            NSObject *temporary = [NSObject new];
            token = state.capture(temporary);
        }
        assert(!state.target);
        assert(!state.queue(@"synthetic-no-target", token, 50));
        token = state.capture(first);
        assert(state.queue(@"synthetic-cancelled", token, 60));
        state.discard(token);
        assert(!state.take(first, 61));
    }
}
