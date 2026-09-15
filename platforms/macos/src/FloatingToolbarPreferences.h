#pragma once
#import <AppKit/AppKit.h>

// 悬浮工具栏显示哪几个按钮。本地产品选项,不进后端那份版本化的偏好快照 —— 快照按固定键数校验,多一个
// 键会让整次同步失败,而不只是这一项同步不了。
inline NSString *const MetasequoiaFloatingToolbarItemsKey = @"MetasequoiaImeFloatingToolbarItems";
inline NSString *const MetasequoiaFloatingToolbarItemsDidChange = @"MetasequoiaFloatingToolbarItemsDidChange";

// 齿轮不在这份名单里:隐藏工具栏、打开设置都只有它一个入口,全关之后还得留条路出去。
inline NSArray<NSString *> *MetasequoiaFloatingToolbarItemKeys()
{
    return @[ @"inputMode", @"punctuation", @"fullWidth", @"traditionalOutput" ];
}

inline NSString *MetasequoiaFloatingToolbarItemTitle(NSString *item)
{
    NSDictionary<NSString *, NSString *> *titles = @{
        @"inputMode" : @"中英文切换",
        @"punctuation" : @"中西文标点",
        @"fullWidth" : @"全角 / 半角",
        @"traditionalOutput" : @"简繁输出",
    };
    NSString *title = titles[item];
    return title != nil ? title : item;
}

inline BOOL MetasequoiaFloatingToolbarItemVisible(NSString *item)
{
    NSDictionary *values = [NSUserDefaults.standardUserDefaults dictionaryForKey:MetasequoiaFloatingToolbarItemsKey];
    id value = values[item];
    return [value isKindOfClass:NSNumber.class] ? [value boolValue] : YES;
}

inline void MetasequoiaSetFloatingToolbarItemVisible(NSString *item, BOOL visible)
{
    [NSUserDefaults.standardUserDefaults synchronize];
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:MetasequoiaFloatingToolbarItemsKey];
    NSMutableDictionary *values = stored != nil ? [stored mutableCopy] : [NSMutableDictionary dictionary];
    values[item] = @(visible);
    [NSUserDefaults.standardUserDefaults setObject:values forKey:MetasequoiaFloatingToolbarItemsKey];
    [NSUserDefaults.standardUserDefaults synchronize];
    // 设置窗口可以是独立进程(--show-settings),工具栏活在输入法进程里,所以两个通知中心都要发。
    [NSNotificationCenter.defaultCenter postNotificationName:MetasequoiaFloatingToolbarItemsDidChange object:nil];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:MetasequoiaFloatingToolbarItemsDidChange
                                                                 object:nil
                                                               userInfo:nil
                                                     deliverImmediately:YES];
}
