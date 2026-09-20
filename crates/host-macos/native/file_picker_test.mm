#import <Foundation/Foundation.h>
#include <cassert>
#include <cstdlib>
#include <cstring>

extern "C" char *msime_macos_pick_file_with(const char *(*picker)(void));
extern "C" char *msime_macos_pick_file(void);
extern "C" void msime_macos_free_picked_path(char *path);

static const char *ChosePath(void) { return "/Users/someone/models/ggml-base.bin"; }
static const char *ChoseNothing(void) { return nullptr; }
static const char *ChoseEmpty(void) { return ""; }
static const char *ChoseAutoreleased(void) {
    return [[@"/tmp" stringByAppendingPathComponent:@"model.bin"] UTF8String];
}

int main() {
    @autoreleasepool {
        char *path = msime_macos_pick_file_with(ChosePath);
        assert(path && strcmp(path, "/Users/someone/models/ggml-base.bin") == 0);
        msime_macos_free_picked_path(path);

        // Cancelling is not a failure and must not produce an empty path the caller would store.
        assert(msime_macos_pick_file_with(ChoseNothing) == nullptr);
        assert(msime_macos_pick_file_with(ChoseEmpty) == nullptr);
        assert(msime_macos_pick_file_with(nullptr) == nullptr);

        // The panel's path lives in an autorelease pool that ends with the call; the result has to be a
        // copy, or the caller reads freed memory.
        char *copied = msime_macos_pick_file_with(ChoseAutoreleased);
        assert(copied && strcmp(copied, "/tmp/model.bin") == 0);
        msime_macos_free_picked_path(copied);

        // Freeing nothing is allowed, so callers need no null check of their own.
        msime_macos_free_picked_path(nullptr);
    }
    {
        // AppKit cannot show a panel off the main thread, so the entry point refuses rather than trying.
        __block char *offMain = reinterpret_cast<char *>(1);
        dispatch_semaphore_t done = dispatch_semaphore_create(0);
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            offMain = msime_macos_pick_file();
            dispatch_semaphore_signal(done);
        });
        assert(dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC)) == 0);
        assert(offMain == nullptr);
    }
    return 0;
}
