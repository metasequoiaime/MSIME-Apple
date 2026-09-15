#pragma once

#import <Foundation/Foundation.h>

// 用完就扔的偏好域。这些测试都建 `<前缀>.<UUID>` 的 suite,跑完清理。
//
// 但 removePersistentDomainForName: 只清空域,**不删盘上的 plist**:文件留在
// ~/Library/Preferences/ 里,内容变成 `{}`。每跑一轮就多攒一批,实测这台开发机上积了 3257 个
// msime.* 的空 plist。把文件一起删掉才算清理干净。
//
// 断言失败时 assert 直接 abort,走不到清理,那种情况会留下一个带内容的域 —— 那是失败的证据,不是
// 这里要解决的问题;跑通的轮次不该留下任何东西。
static inline void MSIMERemoveTestPreferenceSuite(NSUserDefaults *defaults, NSString *suite)
{
    [defaults removePersistentDomainForName:suite];
    [defaults synchronize];
    NSString *path =
        [NSString stringWithFormat:@"%@/Library/Preferences/%@.plist", NSHomeDirectory(), suite];
    [NSFileManager.defaultManager removeItemAtPath:path error:nil];
}
