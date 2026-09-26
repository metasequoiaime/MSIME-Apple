#import "CandidateFontCache.h"
#import <CoreText/CoreText.h>
#include <os/lock.h>

static os_unfair_lock CandidateFontCacheLock = OS_UNFAIR_LOCK_INIT;
// Family name -> matched NSFontDescriptor, or NSNull for a family that is not installed.
static NSMutableDictionary<NSString *, id> *CandidateFontCache;
// Bumped on every clear, so a match that started before a font change cannot store its now stale answer after the clear.
static uint64_t CandidateFontCacheGeneration;

static void ClearCandidateFontCache() {
    os_unfair_lock_lock(&CandidateFontCacheLock);
    [CandidateFontCache removeAllObjects];
    CandidateFontCacheGeneration++;
    os_unfair_lock_unlock(&CandidateFontCacheLock);
}

NSFontDescriptor *MSIMEInstalledFontFamilyDescriptor(NSString *family) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        CandidateFontCache = [NSMutableDictionary dictionary];
        NSNotificationCenter *center = NSNotificationCenter.defaultCenter;
        // Both fire, on the main thread, for a font registered or removed in this process or in any other, persistent user-wide installs included. Measured on macOS 27, AppKit's NSFontSetChangedNotification only starts once the process has created an NSFont, so CoreText's own notification is observed as well.
        [center addObserverForName:(__bridge NSString *)kCTFontManagerRegisteredFontsChangedNotification object:nil queue:nil usingBlock:^(NSNotification *) { ClearCandidateFontCache(); }];
        [center addObserverForName:NSFontSetChangedNotification object:nil queue:nil usingBlock:^(NSNotification *) { ClearCandidateFontCache(); }];
    });
    os_unfair_lock_lock(&CandidateFontCacheLock);
    id cached = CandidateFontCache[family];
    const uint64_t generation = CandidateFontCacheGeneration;
    os_unfair_lock_unlock(&CandidateFontCacheLock);
    if (!cached) {
        // The match runs outside the lock because it is the slow part; two threads racing on one family only store equal answers.
        NSFontDescriptor *requested = [NSFontDescriptor fontDescriptorWithFontAttributes:@{NSFontFamilyAttribute:family}];
        cached = [requested matchingFontDescriptorWithMandatoryKeys:[NSSet setWithObject:NSFontFamilyAttribute]] ?: NSNull.null;
        os_unfair_lock_lock(&CandidateFontCacheLock);
        if (generation == CandidateFontCacheGeneration) CandidateFontCache[family] = cached;
        os_unfair_lock_unlock(&CandidateFontCacheLock);
    }
    return cached == NSNull.null ? nil : cached;
}
