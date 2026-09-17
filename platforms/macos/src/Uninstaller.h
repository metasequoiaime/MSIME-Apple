#pragma once

#import <Foundation/Foundation.h>

// 卸载在输入法自己的进程里做,不外调脚本。脚本那条路要先 pkill 掉输入法,也就是会去启动它的那个进程;
// 在进程内做就没有这个问题 —— 我们就是那个进程,活儿干完最后再退出自己。
//
// 移除一律走废纸篓,不 rm。放错了能取回,这也是 scripts/uninstall.sh 一直以来的承诺。
// 调用方负责在成功之后退出进程:bundle 已经不在原处了,继续跑下去只会拿到一个半截的安装。
// trashedBundle 回报 bundle 在废纸篓里的落点。scripts/uninstall.sh 一直会把这个路径打印出来,而「放错了能
// 取回」这句承诺,只有在说得出东西在哪时才算数。传 NULL 表示不关心。
BOOL UninstallMetasequoia(NSURL *bundle, NSURL *userData, NSString *preferencesDomain, BOOL removeUserData,
                          NSURL **trashedBundle, NSError **error);
// 对当前用户:~/Library/Input Methods/MetasequoiaIME.app 与 ~/Library/Application Support/metasequoiaime。
BOOL UninstallMetasequoiaForCurrentUser(BOOL removeUserData, NSError **error);
