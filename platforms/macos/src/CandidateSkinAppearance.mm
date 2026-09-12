#import "CandidateSkinAppearance.h"
#import "CandidateAppearancePreferences.h"

NSNotificationName const MetasequoiaCandidateSkinDidChangeNotification =
    @"MetasequoiaCandidateSkinDidChangeNotification";
NSString *const kCandidateSkinPreferenceKey = @"MetasequoiaImeCandidateSkin";

NSColor *MetasequoiaColorFromRgba(metasequoia::mac::Rgba color)
{
    return [NSColor colorWithSRGBRed:color.r green:color.g blue:color.b alpha:color.a];
}

BOOL MetasequoiaAppearanceIsDark(NSAppearance *appearance)
{
    NSAppearance *resolved = MetasequoiaForcedAppearance();
    if (!resolved)
        resolved = appearance;
    if (resolved == nil)
    {
        resolved = NSApp.effectiveAppearance;
    }
    if (resolved == nil)
    {
        resolved = NSAppearance.currentDrawingAppearance;
    }
    if (resolved == nil)
    {
        return NO;
    }
    NSString *match = [resolved bestMatchFromAppearancesWithNames:@[ NSAppearanceNameAqua, NSAppearanceNameDarkAqua ]];
    return [match isEqualToString:NSAppearanceNameDarkAqua];
}

NSURL *MetasequoiaCandidateSkinsDirectoryURL(void)
{
    const std::filesystem::path path = metasequoia::mac::DefaultSkinsRoot();
    if (path.empty())
    {
        return nil;
    }
    return [NSURL fileURLWithPath:@(path.c_str()) isDirectory:YES];
}

NSString *MetasequoiaStoredCandidateSkin(void)
{
    NSString *value = [[NSUserDefaults standardUserDefaults] stringForKey:kCandidateSkinPreferenceKey];
    const char *utf8 = value.UTF8String;
    return @(metasequoia::mac::NormalizeSkinId(utf8 == nullptr ? "" : utf8).c_str());
}

void MetasequoiaSetStoredCandidateSkin(NSString *skinId)
{
    const char *utf8 = skinId.UTF8String;
    const std::string normalized = metasequoia::mac::NormalizeSkinId(utf8 == nullptr ? "" : utf8);
    [[NSUserDefaults standardUserDefaults] setObject:@(normalized.c_str()) forKey:kCandidateSkinPreferenceKey];
    [[NSNotificationCenter defaultCenter] postNotificationName:MetasequoiaCandidateSkinDidChangeNotification
                                                        object:@(normalized.c_str())];
}

metasequoia::mac::ResolvedSkin MetasequoiaResolveCandidateSkin(NSString *skinId, BOOL dark)
{
    const char *utf8 = skinId.UTF8String;
    auto skin = metasequoia::mac::ResolveSkin(utf8 == nullptr ? "" : utf8, dark, metasequoia::mac::DefaultSkinsRoot());
    NSColor *color = [MetasequoiaCandidateTextColor() colorUsingColorSpace:NSColorSpace.sRGBColorSpace];
    if (color)
        skin.tokens.text = {(float)color.redComponent, (float)color.greenComponent, (float)color.blueComponent, 1.0f};
    return skin;
}

metasequoia::mac::ResolvedSkin MetasequoiaResolveStoredCandidateSkin(BOOL dark)
{
    return MetasequoiaResolveCandidateSkin(MetasequoiaStoredCandidateSkin(), dark);
}
