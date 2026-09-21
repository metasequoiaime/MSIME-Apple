#import <AppKit/AppKit.h>
#include <cstdlib>
#include <cstring>

// Choosing a local Whisper model by typing its absolute path is not a real option on macOS: the path is
// long, Finder does not show it, and a typo surfaces as a recognizer that fails at the moment the user
// speaks. The reference host puts an NSOpenPanel behind a 选择… button; so does this, exposed as a host
// capability the shared settings page can ask for when the platform offers one.
//
// The panel itself cannot run headless, so the choice is injectable: tests drive the same path handling
// with their own picker, the way input source registration is tested.
extern "C" const char *MSIMEDefaultFilePicker(void) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.canChooseFiles = YES;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;
    if ([panel runModal] != NSModalResponseOK) return nullptr;
    // A security-scoped or aliased URL still answers .path; the recognizer opens by path.
    return panel.URL.path.UTF8String;
}

extern "C" const char *MSIMEDefaultDirectoryPicker(void) {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.resolvesAliases = YES;
    panel.message = @"请选择一个空文件夹存放水杉输入法的词库、学习记录和设置。";
    panel.prompt = @"选择";
    if ([panel runModal] != NSModalResponseOK) return nullptr;
    return panel.URL.path.UTF8String;
}

extern "C" char *msime_macos_pick_file_with(const char *(*picker)(void)) {
    if (picker == nullptr) return nullptr;
    @autoreleasepool {
        const char *chosen = picker();
        // Copy out of the autorelease pool: the caller owns the result and frees it below.
        if (chosen == nullptr || chosen[0] == '\0') return nullptr;
        return strdup(chosen);
    }
}

extern "C" char *msime_macos_pick_file(void) {
    if (!NSThread.isMainThread) return nullptr;
    return msime_macos_pick_file_with(MSIMEDefaultFilePicker);
}

extern "C" char *msime_macos_pick_directory(void) {
    if (!NSThread.isMainThread) return nullptr;
    return msime_macos_pick_file_with(MSIMEDefaultDirectoryPicker);
}

extern "C" void msime_macos_free_picked_path(char *path) { free(path); }
