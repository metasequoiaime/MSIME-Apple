#import "Uninstaller.h"

#import <Security/Security.h>

namespace
{
BOOL Fail(NSError **error, NSInteger code, NSString *message)
{
    if (error)
    {
        *error = [NSError errorWithDomain:@"MetasequoiaUninstall"
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey : message}];
    }
    return NO;
}

// 废纸篓里的东西 Finder 能「放回原处」,所以这是可撤销的一步。移不动就当整次卸载失败,不去猜原因,
// 也不接着删别的 —— 半卸载状态比没卸载更难收拾。
BOOL TrashIfPresent(NSURL *url, NSString *what, NSURL **trashed, NSError **error)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (url == nil || ![fileManager fileExistsAtPath:url.path])
    {
        return YES;
    }
    NSError *failure = nil;
    NSURL *destination = nil;
    if ([fileManager trashItemAtURL:url resultingItemURL:&destination error:&failure])
    {
        if (trashed)
        {
            *trashed = destination;
        }
        return YES;
    }
    NSString *reason = failure.localizedDescription;
    return Fail(error, 1,
                [NSString stringWithFormat:@"%@未能移到废纸篓：%@", what, reason.length > 0 ? reason : @"未知错误"]);
}
} // namespace

BOOL UninstallMetasequoia(NSURL *bundle, NSURL *userData, NSString *preferencesDomain, BOOL removeUserData,
                          NSURL **trashedBundle, NSError **error)
{
    if (bundle == nil)
    {
        return Fail(error, 2, @"找不到已安装的输入法。");
    }
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL bundleInstalled = [fileManager fileExistsAtPath:bundle.path];
    BOOL dataPresent = userData != nil && [fileManager fileExistsAtPath:userData.path];
    if (!bundleInstalled && !(removeUserData && dataPresent))
    {
        return Fail(error, 3, @"输入法没有安装在当前用户下。");
    }

    // bundle 先走。它要是移不动,后面的用户数据就不该动 —— 那样会留下一个能用却没了词库的安装。
    if (!TrashIfPresent(bundle, @"输入法", trashedBundle, error))
    {
        return NO;
    }
    if (!removeUserData)
    {
        return YES;
    }
    if (!TrashIfPresent(userData, @"词库与学习数据", nil, error))
    {
        return NO;
    }

    if (preferencesDomain.length > 0)
    {
        [[NSUserDefaults standardUserDefaults] removePersistentDomainForName:preferencesDomain];
        // removePersistentDomainForName 只改这个进程看到的那一份,盘上那个 plist 归 cfprefsd 管,而我们
        // 马上就要退出。把文件本身也送进废纸篓,免得它在退出之后被重新写回来。
        NSURL *library = [fileManager URLForDirectory:NSLibraryDirectory
                                             inDomain:NSUserDomainMask
                                    appropriateForURL:nil
                                               create:NO
                                                error:nil];
        NSURL *plist = [[library URLByAppendingPathComponent:@"Preferences" isDirectory:YES]
            URLByAppendingPathComponent:[preferencesDomain stringByAppendingPathExtension:@"plist"]];
        if (!TrashIfPresent(plist, @"偏好设置", nil, error))
        {
            return NO;
        }

        // 语音密钥是用户自己填的第三方凭据,留在钥匙串里既没人用也没人管。删不掉不算卸载失败:bundle
        // 已经走了,为一条钥匙串记录把整件事判成失败,只会让人以为输入法还在。
        NSString *service = [preferencesDomain stringByAppendingString:@".voice"];
        NSDictionary *query =
            @{(__bridge id)kSecClass : (__bridge id)kSecClassGenericPassword, (__bridge id)kSecAttrService : service};
        OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
        if (status != errSecSuccess && status != errSecItemNotFound)
        {
            NSLog(@"MetasequoiaIME: 语音密钥未能从钥匙串删除 (OSStatus %d)，请在「钥匙串访问」里手动删除 %@。",
                  (int)status, service);
        }
    }
    return YES;
}

BOOL UninstallMetasequoiaForCurrentUser(BOOL removeUserData, NSError **error)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *library = [fileManager URLForDirectory:NSLibraryDirectory
                                         inDomain:NSUserDomainMask
                                appropriateForURL:nil
                                           create:NO
                                            error:error];
    if (library == nil)
    {
        return NO;
    }
    // 卸载的是装好的那一份,不是 mainBundle —— 从构建目录直接跑设置时,要卸的仍然是用户装着的输入法。
    NSURL *bundle = [[library URLByAppendingPathComponent:@"Input Methods"
                                              isDirectory:YES] URLByAppendingPathComponent:@"MetasequoiaIME.app"
                                                                               isDirectory:YES];
    NSURL *applicationSupport = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                                    inDomain:NSUserDomainMask
                                           appropriateForURL:nil
                                                      create:NO
                                                       error:nil];
    NSURL *userData = [applicationSupport URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
    return UninstallMetasequoia(bundle, userData, @"app.msime.inputmethod.MetasequoiaIME", removeUserData, NULL, error);
}
