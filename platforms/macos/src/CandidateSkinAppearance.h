#pragma once

#import <AppKit/AppKit.h>

#include "CandidateSkin.h"

FOUNDATION_EXPORT NSNotificationName const MetasequoiaCandidateSkinDidChangeNotification;

NSColor *MetasequoiaColorFromRgba(metasequoia::mac::Rgba color);
BOOL MetasequoiaAppearanceIsDark(NSAppearance *appearance);
NSURL *MetasequoiaCandidateSkinsDirectoryURL(void);
NSString *MetasequoiaStoredCandidateSkin(void);
void MetasequoiaSetStoredCandidateSkin(NSString *skinId);
metasequoia::mac::ResolvedSkin MetasequoiaResolveCandidateSkin(NSString *skinId, BOOL dark);
metasequoia::mac::ResolvedSkin MetasequoiaResolveStoredCandidateSkin(BOOL dark);
