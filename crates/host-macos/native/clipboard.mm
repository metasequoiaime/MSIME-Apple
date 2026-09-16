#import <AppKit/AppKit.h>

#include <cstdint>
#include <cstddef>
#include <cstring>

extern "C" bool msime_macos_read_clipboard(
    unsigned char *buffer,
    size_t capacity,
    bool readText,
    size_t *length,
    bool *hasText,
    int64_t *changeCount) {
    if (!buffer || !length || !hasText || !changeCount) return false;
    @autoreleasepool {
        NSPasteboard *pasteboard = NSPasteboard.generalPasteboard;
        if (!pasteboard) return false;
        *length = 0;
        *hasText = false;
        *changeCount = static_cast<int64_t>(pasteboard.changeCount);
        if (!readText) return true;
        NSString *text = [pasteboard stringForType:NSPasteboardTypeString];
        if (!text) return true;
        if (text.length > 4000) return true;
        NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
        if (!data || data.length > capacity) return true;
        if (data.length) std::memcpy(buffer, data.bytes, data.length);
        *length = data.length;
        *hasText = true;
        return true;
    }
}
