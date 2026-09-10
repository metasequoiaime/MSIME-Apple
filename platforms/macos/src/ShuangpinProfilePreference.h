#pragma once
#import <Foundation/Foundation.h>

inline NSArray<NSString *> *MetasequoiaShuangpinProfileNames()
{
    return @[ @"xiaohe", @"ziranma", @"microsoft", @"shoudao" ];
}
inline NSArray<NSString *> *MetasequoiaShuangpinProfileTitles()
{
    return @[ @"小鹤双拼", @"自然码双拼", @"微软双拼", @"Shoudao 双拼" ];
}
inline NSString *MetasequoiaNormalizeShuangpinProfile(id value)
{
    return [value isKindOfClass:NSString.class] && [MetasequoiaShuangpinProfileNames() containsObject:value]
               ? value : @"xiaohe";
}
inline NSString *MetasequoiaShuangpinProfileTitle(NSString *name)
{
    return MetasequoiaShuangpinProfileTitles()[[MetasequoiaShuangpinProfileNames()
        indexOfObject:MetasequoiaNormalizeShuangpinProfile(name)]];
}
