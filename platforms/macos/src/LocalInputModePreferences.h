#pragma once
#import <AppKit/AppKit.h>

#include "InputBehaviorPreferences.h"

// 本地输入模式逐项开关,存在既有的 InputBehavior 字典里 —— 那份字典已经被排除在后端的版本化快照之外,
// 也已经在「恢复默认设置」的清除名单上,不用为这几项再起一个顶层键。
//
// 只列引擎能在这个 bundle 里真正跑起来的模式:Unicode 自己解析输入,日期时间有内建 provider,快捷短语
// 和超级简拼读 msime.db,临时英文读 english.db —— 后者随 app 一起打包,中英混输走的就是同一份词典。
// emoji 和颜文字要 others.db、临时日语要 dict_japanese.dat,两者都不打包,所以不在这里出现。
inline NSArray<NSString *> *MetasequoiaLocalInputModeKeys()
{
    return @[
        @"localModeUnicode", @"localModeDateTime", @"localModeQuickPhrase", @"localModeSuperJianpin",
        @"localModeTemporaryEnglish"
    ];
}

inline NSString *MetasequoiaLocalInputModeTitle(NSString *item)
{
    NSDictionary<NSString *, NSString *> *titles = @{
        @"localModeUnicode" : @"Unicode 码点（Shift+U）",
        @"localModeDateTime" : @"日期与时间（Shift+T）",
        @"localModeQuickPhrase" : @"快捷短语（Shift+K）",
        @"localModeSuperJianpin" : @"超级简拼（Shift+J）",
        @"localModeTemporaryEnglish" : @"临时英文（Shift+Y）",
    };
    NSString *title = titles[item];
    return title != nil ? title : item;
}

inline NSString *MetasequoiaLocalInputModeHint(NSString *item)
{
    NSDictionary<NSString *, NSString *> *hints = @{
        @"localModeUnicode" : @"输入码点后上屏对应字符，例如 4e2d 得到「中」。",
        @"localModeDateTime" : @"输入当天的日期、时间与星期，可选多种格式。",
        @"localModeQuickPhrase" : @"用自定义缩写上屏常用短语。",
        @"localModeSuperJianpin" : @"只打每个字的首字母，用更长的串换更准的长词。",
        @"localModeTemporaryEnglish" : @"临时只出英文候选，不用切到英文状态再切回来。",
    };
    NSString *hint = hints[item];
    return hint != nil ? hint : @"";
}

inline BOOL MetasequoiaLocalInputModeEnabled(NSString *item)
{
    return MetasequoiaInputFlag(item, YES);
}

inline void MetasequoiaSetLocalInputModeEnabled(NSString *item, BOOL enabled)
{
    MetasequoiaSetInputBehavior(item, enabled ? 1 : 0);
}
