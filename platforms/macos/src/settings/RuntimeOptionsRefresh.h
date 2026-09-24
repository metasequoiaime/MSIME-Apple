#pragma once

#import <Foundation/Foundation.h>

#include "msime_client.h"

#include <cstddef>
#include <cstdint>
#include <cstring>

typedef NS_ENUM(NSInteger, MSIMERuntimeOptionsRefreshResult) {
    MSIMERuntimeOptionsRefreshCurrent,
    MSIMERuntimeOptionsRefreshUpdated,
    MSIMERuntimeOptionsRefreshFailed,
};

// The Host API export, or a stand-in in tests; whatever it returns is released with msime_client_string_free.
typedef char *(*MSIMERuntimeOptionsRefreshFunction)(const uint8_t *path, size_t length);

// Whether `path` names the bundle itself or anything inside it. The embedded development runtime-options.json lives in the signed, read-only bundle and is never rewritten.
static inline BOOL MSIMEPathIsInsideBundle(NSString *path, NSString *bundlePath) {
    if (path.length == 0 || bundlePath.length == 0) return NO;
    NSString *candidate = path.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    NSString *bundle = bundlePath.stringByStandardizingPath.stringByResolvingSymlinksInPath;
    return [candidate isEqualToString:bundle] || [candidate hasPrefix:[bundle stringByAppendingString:@"/"]];
}

// Bring runtime options written before an app upgrade up to the installed dictionary generation: the Host API prepares the new generation, replays the user dictionary journal into it and atomically rewrites only `resources` and `dictionaries`. Current, symlinked and non-layout documents are left alone by the Host API and report Current; so does any path inside `bundlePath`, without calling it. Failed leaves the file exactly as it was, so the caller keeps the previous generation and the next start tries again. The Host API error is not surfaced because it can name private paths.
static inline MSIMERuntimeOptionsRefreshResult MSIMERefreshRuntimeOptionsWith(
    NSString *path, NSString *bundlePath, MSIMERuntimeOptionsRefreshFunction refresh) {
    if (path.length == 0 || !path.isAbsolutePath) return MSIMERuntimeOptionsRefreshFailed;
    if (MSIMEPathIsInsideBundle(path, bundlePath)) return MSIMERuntimeOptionsRefreshCurrent;
    const char *text = path.fileSystemRepresentation;
    char *raw = refresh(reinterpret_cast<const uint8_t *>(text), strlen(text));
    if (raw == nullptr) return MSIMERuntimeOptionsRefreshFailed;
    NSData *data = [NSData dataWithBytes:raw length:strlen(raw)];
    msime_client_string_free(raw);
    id result = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    if (![result isKindOfClass:NSDictionary.class] || result[@"ok"] != (__bridge id)kCFBooleanTrue) return MSIMERuntimeOptionsRefreshFailed;
    id value = result[@"value"];
    if (value == (__bridge id)kCFBooleanTrue) return MSIMERuntimeOptionsRefreshUpdated;
    if (value == (__bridge id)kCFBooleanFalse) return MSIMERuntimeOptionsRefreshCurrent;
    return MSIMERuntimeOptionsRefreshFailed;
}

static inline MSIMERuntimeOptionsRefreshResult MSIMERefreshRuntimeOptions(NSString *path) {
    return MSIMERefreshRuntimeOptionsWith(path, NSBundle.mainBundle.bundlePath, msime_client_refresh_host);
}
