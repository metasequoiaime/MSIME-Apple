#pragma once
#import <AppKit/AppKit.h>
#include <cmath>

// Platform appearance preferences are local until the backend declares their schema.
inline NSString *const MetasequoiaAppearancePreferencesKey = @"MetasequoiaImeCandidateAppearance";
inline NSString *const MetasequoiaAppearanceDidChange = @"MetasequoiaCandidateAppearanceDidChange";
inline NSDictionary *MetasequoiaAppearancePreferences()
{
    NSDictionary *values = [NSUserDefaults.standardUserDefaults dictionaryForKey:MetasequoiaAppearancePreferencesKey];
    return values ? values : @{};
}
inline void MetasequoiaSetAppearancePreference(NSString *key, id value)
{
    [NSUserDefaults.standardUserDefaults synchronize];
    NSMutableDictionary *values = [MetasequoiaAppearancePreferences() mutableCopy];
    if (value)
        values[key] = value;
    else
        [values removeObjectForKey:key];
    [NSUserDefaults.standardUserDefaults setObject:values forKey:MetasequoiaAppearancePreferencesKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    [NSNotificationCenter.defaultCenter postNotificationName:MetasequoiaAppearanceDidChange object:nil];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:MetasequoiaAppearanceDidChange
                                                                 object:nil
                                                               userInfo:nil
                                                     deliverImmediately:YES];
}
inline NSInteger MetasequoiaAppearanceInteger(NSString *key, NSInteger fallback, NSInteger minimum, NSInteger maximum)
{
    id value = MetasequoiaAppearancePreferences()[key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID() ||
        !std::isfinite([value doubleValue]) || [value doubleValue] != [value integerValue])
        return fallback;
    NSInteger number = [value integerValue];
    return number >= minimum && number <= maximum ? number : fallback;
}
inline BOOL MetasequoiaCandidateFollowsCaret()
{
    id value = MetasequoiaAppearancePreferences()[@"followCaret"];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}
inline NSAppearance *MetasequoiaForcedAppearance()
{
    NSInteger mode = MetasequoiaAppearanceInteger(@"theme", 0, 0, 2);
    return mode == 0 ? nil : [NSAppearance appearanceNamed:mode == 1 ? NSAppearanceNameAqua : NSAppearanceNameDarkAqua];
}
inline NSFont *MetasequoiaCandidateFont(CGFloat size)
{
    NSDictionary *values = MetasequoiaAppearancePreferences();
    NSString *name = [values[@"font"] isKindOfClass:NSString.class] ? values[@"font"] : @"";
    NSFont *font = [NSFont fontWithName:name size:size];
    if (!font)
        font = [NSFont systemFontOfSize:size];
    NSString *fallback = [values[@"fallbackFont"] isKindOfClass:NSString.class] ? values[@"fallbackFont"] : @"";
    NSFont *fallbackFont = [NSFont fontWithName:fallback size:size];
    if (fallbackFont)
    {
        NSFontDescriptor *descriptor = [font.fontDescriptor fontDescriptorByAddingAttributes:@{
            NSFontCascadeListAttribute : @[ fallbackFont.fontDescriptor ]
        }];
        NSFont *cascaded = [NSFont fontWithDescriptor:descriptor size:size];
        if (cascaded)
            font = cascaded;
    }
    return font;
}
inline NSColor *MetasequoiaCandidateTextColor()
{
    id value = MetasequoiaAppearancePreferences()[@"textColor"];
    if (![value isKindOfClass:NSArray.class] || [value count] != 3)
        return nil;
    for (id component in value)
        if (![component isKindOfClass:NSNumber.class] || !std::isfinite([component doubleValue]) ||
            [component doubleValue] < 0 || [component doubleValue] > 1)
            return nil;
    return [NSColor colorWithSRGBRed:[value[0] doubleValue]
                               green:[value[1] doubleValue]
                                blue:[value[2] doubleValue]
                               alpha:1];
}
