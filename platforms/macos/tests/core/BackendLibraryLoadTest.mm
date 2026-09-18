#import <Foundation/Foundation.h>
#include <dlfcn.h>
#include <cassert>
int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        void *library = dlopen(argv[1], RTLD_NOW | RTLD_GLOBAL);
        assert(library);
        Class bridge = NSClassFromString(@"MSIMEBackendWindowBridge");
        assert(bridge && [bridge respondsToSelector:NSSelectorFromString(@"shared")]);
        for (NSString *selector in @[@"showDictionaryForAccountID:", @"showClipboardForAccountID:",
                                    @"showSnapshotForAccountID:", @"showSettingsForAccountID:",
                                    @"showCommunityResourcesForAccountID:", @"showHandwriting", @"showHandwritingWithSelectionAttempt:",
                                    @"showEmojiWithOptions:selectionAttempt:", @"applyEmojiPreferences:",
                                    @"showEmojiDeliveryFailure", @"startClipboardCaptureWithOptions:",
                                    @"stopClipboardCapture"]) {
            assert([bridge instancesRespondToSelector:NSSelectorFromString(selector)]);
        }
        Class account = NSClassFromString(@"MSIMEBackendAccountWindow");
        assert(account && [account respondsToSelector:@selector(shared)]);
        assert([account instancesRespondToSelector:@selector(showAccount)]);
        assert([account instancesRespondToSelector:@selector(showCloudClipboard)]);
        Class clipboard = NSClassFromString(@"MSIMEBackendCloudClipboardProvider");
        assert(clipboard && [clipboard respondsToSelector:NSSelectorFromString(@"prepareWithCompletion:")]);
        assert([clipboard instancesRespondToSelector:NSSelectorFromString(@"request:completion:")]);
        Class dictionary = NSClassFromString(@"MSIMEBackendCloudDictionaryProvider");
        assert(dictionary && [dictionary respondsToSelector:NSSelectorFromString(@"prepareWithCompletion:")]);
        assert([dictionary instancesRespondToSelector:NSSelectorFromString(@"request:completion:")]);
        // Objective-C classes remain registered; retain the library for process lifetime.
    }
    return 0;
}
