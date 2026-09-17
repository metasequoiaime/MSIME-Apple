#import <Foundation/Foundation.h>

#import "../src/Uninstaller.h"

#include <cstdio>
#include <cstdlib>

namespace
{
int failures = 0;

void require(bool condition, const char *message)
{
    if (!condition)
    {
        std::fprintf(stderr, "FAIL: %s\n", message);
        ++failures;
    }
}

NSURL *MakeDirectory(NSURL *parent, NSString *name)
{
    NSURL *url = [parent URLByAppendingPathComponent:name isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
    return url;
}

BOOL Exists(NSURL *url)
{
    return [[NSFileManager defaultManager] fileExistsAtPath:url.path];
}
} // namespace

int main()
{
    @autoreleasepool
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];

        // 只勾选卸载:bundle 走,用户数据留下。默认不带走学习记录,是为了重装之后还能接着用 —— 这条要是
        // 反了,一次误点就抹掉了长期积累的词频。
        {
            NSURL *root = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            NSURL *sandbox =
                MakeDirectory(root, [NSString stringWithFormat:@"msime-uninstall-%@", NSUUID.UUID.UUIDString]);
            NSURL *bundle = MakeDirectory(sandbox, @"MetasequoiaIME.app");
            NSURL *userData = MakeDirectory(sandbox, @"metasequoiaime");
            NSError *error = nil;
            BOOL ok = UninstallMetasequoia(bundle, userData, @"", NO, NULL, &error);
            require(ok, "Uninstalling with user data preserved reported a failure.");
            require(!Exists(bundle), "The bundle was left in place.");
            require(Exists(userData), "User data was removed even though it was meant to be preserved.");
            [fileManager removeItemAtURL:sandbox error:nil];
        }

        // 勾了「同时删除」:两样都走。偏好域留空,这个用例不碰 NSUserDefaults 和钥匙串 —— 那两样是全局
        // 状态,测试进程去动它们会碰到真实的用户数据。
        {
            NSURL *root = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            NSURL *sandbox =
                MakeDirectory(root, [NSString stringWithFormat:@"msime-uninstall-%@", NSUUID.UUID.UUIDString]);
            NSURL *bundle = MakeDirectory(sandbox, @"MetasequoiaIME.app");
            NSURL *userData = MakeDirectory(sandbox, @"metasequoiaime");
            NSError *error = nil;
            BOOL ok = UninstallMetasequoia(bundle, userData, @"", YES, NULL, &error);
            require(ok, "Uninstalling with user data removal reported a failure.");
            require(!Exists(bundle), "The bundle was left in place.");
            require(!Exists(userData), "User data was left in place.");
            [fileManager removeItemAtURL:sandbox error:nil];
        }

        // 没装就该说没装,而不是报成功。报成功的话,人会以为卸载干净了,而废纸篓里什么都没有。
        {
            NSURL *root = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            NSURL *sandbox =
                MakeDirectory(root, [NSString stringWithFormat:@"msime-uninstall-%@", NSUUID.UUID.UUIDString]);
            NSURL *bundle = [sandbox URLByAppendingPathComponent:@"MetasequoiaIME.app" isDirectory:YES];
            NSURL *userData = [sandbox URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
            NSError *error = nil;
            BOOL ok = UninstallMetasequoia(bundle, userData, @"", NO, NULL, &error);
            require(!ok, "Uninstalling a missing installation reported success.");
            require(error != nil, "A failed uninstall produced no error to show.");
            [fileManager removeItemAtURL:sandbox error:nil];
        }

        // bundle 不在、但用户数据还在,且勾了「同时删除」:这是重装过又卸过之后剩下的残留,要能清掉。
        {
            NSURL *root = [NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES];
            NSURL *sandbox =
                MakeDirectory(root, [NSString stringWithFormat:@"msime-uninstall-%@", NSUUID.UUID.UUIDString]);
            NSURL *bundle = [sandbox URLByAppendingPathComponent:@"MetasequoiaIME.app" isDirectory:YES];
            NSURL *userData = MakeDirectory(sandbox, @"metasequoiaime");
            NSError *error = nil;
            BOOL ok = UninstallMetasequoia(bundle, userData, @"", YES, NULL, &error);
            require(ok, "Leftover user data could not be removed once the bundle was already gone.");
            require(!Exists(userData), "Leftover user data was left in place.");
            [fileManager removeItemAtURL:sandbox error:nil];
        }

        // 移除一律走废纸篓。rm 掉就取不回来了,而「放错了能取回」正是确认框对用户的承诺。
        {
            // 这一个沙箱建在 home 里,不在 NSTemporaryDirectory。/var/folders 下的东西被 trash 之后不落在
            // ~/.Trash,于是「有没有真的进废纸篓」就无从查起 —— 那正是这条用例要问的。
            NSURL *root = [fileManager URLForDirectory:NSCachesDirectory
                                              inDomain:NSUserDomainMask
                                     appropriateForURL:nil
                                                create:YES
                                                 error:nil];
            NSURL *sandbox =
                MakeDirectory(root, [NSString stringWithFormat:@"msime-uninstall-%@", NSUUID.UUID.UUIDString]);
            NSURL *bundle = MakeDirectory(sandbox, @"MetasequoiaIME.app");
            NSString *marker = [NSString stringWithFormat:@"msime-trash-marker-%@", NSUUID.UUID.UUIDString];
            [marker writeToURL:[bundle URLByAppendingPathComponent:marker]
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:nil];
            NSError *error = nil;
            NSURL *trashed = nil;
            require(UninstallMetasequoia(bundle, nil, @"", NO, &trashed, &error), "Trashing the bundle failed.");
            // 按函数报告的落点去查,不去枚举 ~/.Trash —— 那个目录受 TCC 保护,没有完全磁盘访问权限的测试
            // 进程列出来是空的,于是一次正常的卸载会被误判成「直接删掉了」。
            require(trashed != nil, "The uninstaller did not report where the bundle went.");
            require([trashed.path containsString:@".Trash"], "The bundle did not land in Trash.");
            require(Exists([trashed URLByAppendingPathComponent:marker]),
                    "The bundle was deleted outright instead of being moved to Trash.");
            [fileManager removeItemAtURL:trashed error:nil];
            [fileManager removeItemAtURL:sandbox error:nil];
        }

        if (failures == 0)
        {
            std::printf("All uninstaller tests passed.\n");
        }
        return failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
    }
}
