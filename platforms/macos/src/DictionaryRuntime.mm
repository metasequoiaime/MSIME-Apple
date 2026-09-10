#include "DictionaryRuntime.h"
#include "../../../shared/apple-bridge/DictionaryInstallation.h"
#include <stdexcept>
#include <metasequoia/dictionary_state.h>
#include <vector>
#include <fstream>
#include <array>
#import <CommonCrypto/CommonDigest.h>

NSURL *MetasequoiaDictionaryUserDirectory()
{
    const auto legacy = metasequoia::RuntimePaths::legacy();
    return [NSURL fileURLWithFileSystemRepresentation:legacy.user_data.c_str() isDirectory:YES relativeToURL:nil];
}

void MetasequoiaRequestIdleDictionarySessions()
{
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:MetasequoiaReleaseIdleDictionarySessionsNotification
                      object:MetasequoiaDictionaryUserDirectory().URLByStandardizingPath.path
                    userInfo:nil deliverImmediately:YES];
}

metasequoia::RuntimePaths MetasequoiaCurrentDictionaryPaths()
{
    NSURL *user = MetasequoiaDictionaryUserDirectory();
    NSString *identifier = metasequoia::apple::ActiveDictionarySnapshotIdentifier(user);
    if (identifier.length == 0)
        return metasequoia::RuntimePaths::legacy();
    NSURL *generation =
        [[user URLByAppendingPathComponent:@"snapshot-generations"] URLByAppendingPathComponent:identifier];
    NSURL *journal = [generation URLByAppendingPathComponent:@"user"];
    NSString *content = [[NSString
        stringWithContentsOfURL:[journal URLByAppendingPathComponent:@"active-dictionary-generation"]
                       encoding:NSUTF8StringEncoding
                          error:nil] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (content.length != 128 ||
        [content rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]
                                             invertedSet]]
                .location != NSNotFound)
        throw std::runtime_error("Invalid desktop dictionary generation");
    metasequoia::RuntimePaths paths{
        NSBundle.mainBundle.resourceURL.fileSystemRepresentation, journal.fileSystemRepresentation,
        [generation URLByAppendingPathComponent:@"cache"].fileSystemRepresentation,
        [[journal URLByAppendingPathComponent:@"dictionaries"] URLByAppendingPathComponent:content]
            .fileSystemRepresentation};
    paths.validate();
    for (const char *file : {"msime.db", "english.db", ".ready"})
        if (!std::filesystem::is_regular_file(paths.dictionaries / file))
            throw std::runtime_error("Desktop dictionary generation is incomplete");
    if (!std::filesystem::is_regular_file(paths.user_data / "msime_user.db"))
        throw std::runtime_error("Desktop dictionary journal is missing");
    return paths;
}

#include "DictionaryInstaller.h"
#include "../../../shared/apple-bridge/DictionarySnapshotBridge.h"
#include "../../../shared/apple-bridge/DictionarySessionLease.h"

namespace
{
std::string ResourceDigest(NSURL *url)
{
    std::ifstream input(url.fileSystemRepresentation, std::ios::binary);
    if (!input)
        throw std::runtime_error("Cannot read snapshot resource");
    CC_SHA256_CTX state;
    CC_SHA256_Init(&state);
    std::array<char, 65536> buffer;
    while (input)
    {
        input.read(buffer.data(), buffer.size());
        CC_SHA256_Update(&state, buffer.data(), static_cast<CC_LONG>(input.gcount()));
    }
    if (!input.eof())
        throw std::runtime_error("Cannot finish snapshot resource verification");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &state);
    std::string result;
    for (auto byte : digest)
    {
        result += "0123456789abcdef"[byte >> 4];
        result += "0123456789abcdef"[byte & 15];
    }
    return result;
}

NSString *RuntimeVersion()
{
    NSString *identifier = metasequoia::apple::ActiveDictionarySnapshotIdentifier(MetasequoiaDictionaryUserDirectory());
    const auto revision = metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths());
    return [NSString stringWithFormat:@"local-v1:%@:%s", identifier, revision.c_str()];
}
NSDictionary *RuntimeFailure(NSInteger code, NSString *message)
{
    return @{
        @"error" : [NSError errorWithDomain:@"app.msime.snapshot"
                                       code:code
                                   userInfo:@{NSLocalizedDescriptionKey : message}]
    };
}
NSDictionary *RuntimeBusy()
{
    MetasequoiaRequestIdleDictionarySessions();
    return @{@"error": [NSError errorWithDomain:@"app.msime.snapshot" code:423 userInfo:@{
        NSLocalizedDescriptionKey: @"另一个输入进程仍在使用词库，请完成输入后重试。",
        @"retryableDictionaryBusy": @YES
    }]};
}
} // namespace

BOOL MetasequoiaPrepareBundledDictionaryRuntime(NSURL *resources, NSError **error)
{
    if (error) *error = nil;
    auto fail = [&](NSDictionary *result) {
        if (error) *error = result[@"error"];
        return NO;
    };
    if (!NSThread.isMainThread)
        return fail(RuntimeFailure(400, @"请在输入法主线程准备词库。"));
    NSString *identifier = nil;
    NSURL *user = MetasequoiaDictionaryUserDirectory();
    try
    {
        // A published snapshot already contains both dictionaries. Resolving it
        // validates readiness without replaying a journal used by live sessions.
        if (metasequoia::apple::ActiveDictionarySnapshotIdentifier(user).length > 0)
        {
            (void)MetasequoiaCurrentDictionaryPaths();
            return YES;
        }
        Class controller = NSClassFromString(@"MetasequoiaInputController");
        SEL suspend = NSSelectorFromString(@"suspendForCloudDictionarySwitch");
        using Suspend = NSNumber *(*)(id, SEL);
        if (!controller || ![controller respondsToSelector:suspend] ||
            !reinterpret_cast<Suspend>([controller methodForSelector:suspend])(controller, suspend).boolValue)
            return fail(RuntimeFailure(423, @"请完成当前输入后重试词库准备。"));
        metasequoia::apple::DictionarySessionLease lease(user);
        if (!lease.exclusively([&] {
            // Another process may have published between the first check and locking.
            if (metasequoia::apple::ActiveDictionarySnapshotIdentifier(user).length > 0)
            {
                (void)MetasequoiaCurrentDictionaryPaths();
                return;
            }
            NSMutableString *content = [NSMutableString string];
            for (NSString *name in @[ @"msime.db", @"english.db" ])
            {
                NSString *expected = [[NSString stringWithContentsOfURL:
                    [resources URLByAppendingPathComponent:[name stringByAppendingString:@".sha256"]]
                    encoding:NSUTF8StringEncoding error:nil]
                    stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if (expected.length != 64 ||
                    ResourceDigest([resources URLByAppendingPathComponent:name]) != std::string(expected.UTF8String))
                    throw std::runtime_error("Bundled dictionary checksum mismatch");
                [content appendString:expected];
            }
            // Engine exports a consistent complete journal: overlays, deletions,
            // candidate positions and selection counts. Never copy live SQLite files.
            std::vector<metasequoia::DictionaryStateRecord> records;
            metasequoia::stream_dictionary_state(MetasequoiaCurrentDictionaryPaths(), [&](const auto &record) {
                if (records.size() >= 500000)
                    throw std::runtime_error("Dictionary migration exceeds record limit");
                records.push_back(record);
                return true;
            });
            identifier = NSUUID.UUID.UUIDString;
            size_t index = 0;
            const auto paths = metasequoia::stage_dictionary_state(resources.fileSystemRepresentation,
                metasequoia::apple::DictionarySnapshotDirectory(user, identifier), content.UTF8String,
                [&](auto &record) {
                    if (index == records.size()) return false;
                    record = std::move(records[index++]);
                    return true;
                });
            metasequoia::SessionOptions options;
            options.paths = paths;
            options.learning = false;
            metasequoia::Session probe(options);
            metasequoia::apple::PublishDictionaryInstallation(user, identifier, paths, @"");
        }))
            return fail(RuntimeBusy());
        return YES;
    }
    catch (const std::exception &)
    {
        // Only remove our unpublished staging directory. Legacy files are retained.
        if (identifier)
            try { metasequoia::apple::DiscardInactiveDictionarySnapshot(user, identifier); }
            catch (const std::exception &) {}
        return fail(RuntimeFailure(500, @"完整词库准备未完成，已保留原有词库；下次启用输入法将重试。"));
    }
}

@interface MSIMEMacDictionarySync : NSObject
+ (NSDictionary *)context;
+ (NSDictionary *)prepare:(NSDictionary *)parameters;
+ (NSDictionary *)activate:(NSDictionary *)parameters;
@end

@implementation MSIMEMacDictionarySync
+ (NSDictionary *)context
{
    if (!NSThread.isMainThread)
        return RuntimeFailure(400, @"请在输入法主线程读取同步状态。");
    try
    {
        NSError *error = nil;
        if (!std::filesystem::is_regular_file(metasequoia::RuntimePaths::legacy().dictionaries / "msime.db") &&
            !EnsureMetasequoiaDictionary(&error))
            return @{@"error" : error ? error : [NSError errorWithDomain:@"app.msime.snapshot" code:1 userInfo:nil]};
        NSURL *resources = NSBundle.mainBundle.resourceURL;
        NSMutableString *content = [NSMutableString string];
        for (NSString *name in @[ @"msime.db.sha256", @"english.db.sha256" ])
        {
            NSString *digest = [[NSString stringWithContentsOfURL:[resources URLByAppendingPathComponent:name]
                                                         encoding:NSUTF8StringEncoding
                                                            error:nil]
                stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (digest.length != 64 ||
                [digest rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]
                                                    invertedSet]]
                        .location != NSNotFound)
                return RuntimeFailure(400, @"安装包缺少完整词库摘要，请更新输入法。");
            [content appendString:digest];
        }
        return @{
            @"resources" : resources,
            @"user" : MetasequoiaDictionaryUserDirectory(),
            @"contentIdentifier" : content,
            @"version" : RuntimeVersion()
        };
    }
    catch (const std::exception &)
    {
        return RuntimeFailure(500, @"无法读取本机词库状态。");
    }
}
+ (NSDictionary *)prepare:(NSDictionary *)parameters
{
    NSDictionary *context = parameters[@"context"];
    NSError *error = nil;
    MSIMESnapshotNextRecord next = parameters[@"nextRecord"];
    if (![context isKindOfClass:NSDictionary.class] || !next)
        return RuntimeFailure(400, @"快照准备参数无效。");
    try
    {
        NSURL *resources = context[@"resources"];
        NSString *content = context[@"contentIdentifier"];
        if (![resources isKindOfClass:NSURL.class] || !resources.isFileURL || ![content isKindOfClass:NSString.class])
            return RuntimeFailure(400, @"词库资源参数无效。");
        const auto digest = ResourceDigest([resources URLByAppendingPathComponent:@"msime.db"]) +
                            ResourceDigest([resources URLByAppendingPathComponent:@"english.db"]);
        if (digest != content.UTF8String)
            return RuntimeFailure(400, @"安装包词库完整性校验失败，请重新安装输入法。");
    }
    catch (const std::exception &)
    {
        return RuntimeFailure(400, @"无法校验安装包词库，请重新安装输入法。");
    }
    MSIMEPreparedDictionarySnapshot *prepared =
        [DictionarySnapshotBridge prepareResources:context[@"resources"]
                                     userDirectory:context[@"user"]
                                        identifier:parameters[@"identifier"]
                                 contentIdentifier:context[@"contentIdentifier"]
                                    maximumRecords:[parameters[@"maximumRecords"] unsignedIntegerValue]
                                        nextRecord:next
                                             error:&error];
    if (!prepared)
        return @{@"error" : error ? error : [NSError errorWithDomain:@"app.msime.snapshot" code:1 userInfo:nil]};
    return @{@"prepared" : prepared};
}
+ (NSDictionary *)discard:(NSDictionary *)parameters
{
    NSError *error = nil;
    if (![DictionarySnapshotBridge discardInactiveIdentifier:parameters[@"identifier"]
                                               userDirectory:parameters[@"user"]
                                                       error:&error])
        return @{@"error" : error ? error : [NSError errorWithDomain:@"app.msime.snapshot" code:1 userInfo:nil]};
    return @{};
}
+ (NSDictionary *)reset
{
    NSDictionary *context = [self context];
    if (context[@"error"])
        return context;
    NSString *identifier = NSUUID.UUID.UUIDString;
    MSIMESnapshotNextRecord empty = ^NSDictionary *(NSError **error) {
      (void)error;
      return nil;
    };
    NSDictionary *staged = [self
        prepare:@{@"context" : context, @"identifier" : identifier, @"maximumRecords" : @1, @"nextRecord" : empty}];
    if (staged[@"error"])
        return staged;
    NSDictionary *result = [self activate:@{@"prepared" : staged[@"prepared"], @"version" : context[@"version"]}];
    [self discard:@{@"identifier" : identifier, @"user" : context[@"user"]}];
    return result;
}
+ (NSDictionary *)activate:(NSDictionary *)parameters
{
    if (!NSThread.isMainThread)
        return RuntimeFailure(400, @"请在输入法主线程应用词库。");
    MSIMEPreparedDictionarySnapshot *prepared = parameters[@"prepared"];
    NSString *expected = parameters[@"version"];
    if (![prepared isKindOfClass:MSIMEPreparedDictionarySnapshot.class] || ![expected isKindOfClass:NSString.class])
        return RuntimeFailure(400, @"快照应用参数无效。");
    Class controller = NSClassFromString(@"MetasequoiaInputController");
    SEL suspend = NSSelectorFromString(@"suspendForCloudDictionarySwitch");
    if (!controller || ![controller respondsToSelector:suspend])
        return RuntimeFailure(423, @"输入会话暂不可用。");
    using Suspend = NSNumber *(*)(id, SEL);
    if (!reinterpret_cast<Suspend>([controller methodForSelector:suspend])(controller, suspend).boolValue)
        return RuntimeFailure(423, @"请先完成正在输入的内容，再应用云词库。");
    try
    {
        NSURL *user = MetasequoiaDictionaryUserDirectory();
        metasequoia::apple::DictionarySessionLease lease(user);
        NSDictionary *result = nil;
        if (!lease.exclusively([&] {
                NSString *active = metasequoia::apple::ActiveDictionarySnapshotIdentifier(user);
                if ([active isEqualToString:prepared.identifier])
                {
                    result = @{@"version" : RuntimeVersion()};
                    return;
                }
                if (![RuntimeVersion() isEqualToString:expected])
                {
                    result = RuntimeFailure(409, @"本地词库已变化，请重新下载并确认。");
                    return;
                }
                metasequoia::SessionOptions options;
                options.paths = [prepared runtimePaths];
                options.learning = false;
                metasequoia::Session probe(options);
                metasequoia::apple::PublishDictionaryInstallation(user, prepared.identifier, options.paths, active);
                result = @{@"version" : RuntimeVersion()};
            }))
            return RuntimeBusy();
        return result;
    }
    catch (const std::exception &)
    {
        return RuntimeFailure(500, @"快照应用未完成，请重新检查本机词库状态。");
    }
}
@end

#include "../../../shared/apple-bridge/PersonalDictionaryBridge.h"

@interface MSIMEMacPersonalDictionary : NSObject
+ (NSDictionary *)validate:(NSDictionary *)entry;
+ (NSDictionary *)page:(NSDictionary *)parameters;
+ (NSDictionary *)edit:(NSDictionary *)parameters;
@end
@implementation MSIMEMacPersonalDictionary
+ (NSDictionary *)validate:(NSDictionary *)entry
{
    NSError *error = nil;
    auto word = metasequoia::apple::DecodePersonalWord(entry, &error);
    return word ? @{@"entry": metasequoia::apple::EncodePersonalWord(*word)} : @{@"error": error};
}
+ (NSDictionary *)page:(NSDictionary *)parameters
{
    if (!NSThread.isMainThread)
        return RuntimeFailure(400, @"请在输入法主线程读取个人词库。");
    NSNumber *offset = parameters[@"offset"];
    if (![offset isKindOfClass:NSNumber.class] || offset.longLongValue < 0 || offset.longLongValue > 1000000)
        return RuntimeFailure(400, @"词库页码无效。");
    try
    {
        NSError *error = nil;
        if (!std::filesystem::is_regular_file(metasequoia::RuntimePaths::legacy().dictionaries / "msime.db") &&
            !EnsureMetasequoiaDictionary(&error))
            return RuntimeFailure(503, @"本机词库尚未准备好，请先启用水杉输入法。");
        NSURL *user = MetasequoiaDictionaryUserDirectory();
        metasequoia::apple::DictionarySessionLease lease(user);
        const auto page = metasequoia::personal_dictionary_entries(MetasequoiaCurrentDictionaryPaths(), offset.unsignedIntegerValue, 100);
        if (!page.error.empty())
            return RuntimeFailure(500, @"读取个人词库失败，请稍后刷新。");
        NSMutableArray *entries = [NSMutableArray array];
        for (const auto &entry : page.entries) [entries addObject:metasequoia::apple::EncodePersonalWord(entry)];
        return @{@"entries": entries, @"hasMore": @(page.has_more),
                 @"generation": metasequoia::apple::ActiveDictionarySnapshotIdentifier(user)};
    }
    catch (const std::exception &)
    {
        return RuntimeFailure(500, @"无法读取当前个人词库。");
    }
}
+ (NSDictionary *)edit:(NSDictionary *)parameters
{
    if (!NSThread.isMainThread)
        return RuntimeFailure(400, @"请在输入法主线程编辑个人词库。");
    NSString *generation = parameters[@"generation"], *identifier = parameters[@"identifier"];
    if (![generation isKindOfClass:NSString.class] || ![identifier isKindOfClass:NSString.class] || identifier.length == 0 || identifier.length > 128)
        return RuntimeFailure(400, @"编辑请求无效，请刷新后重试。");
    NSError *error = nil;
    std::optional<metasequoia::PersonalDictionaryEntry> previous, replacement;
    if (parameters[@"previous"] && !(previous = metasequoia::apple::DecodePersonalWord(parameters[@"previous"], &error)))
        return @{@"error": error};
    if (parameters[@"replacement"] && !(replacement = metasequoia::apple::DecodePersonalWord(parameters[@"replacement"], &error)))
        return @{@"error": error};
    if (!previous && !replacement) return RuntimeFailure(400, @"请填写要编辑的词条。");
    Class controller = NSClassFromString(@"MetasequoiaInputController");
    SEL suspend = NSSelectorFromString(@"suspendForCloudDictionarySwitch");
    using Suspend = NSNumber *(*)(id, SEL);
    if (!controller || ![controller respondsToSelector:suspend] ||
        !reinterpret_cast<Suspend>([controller methodForSelector:suspend])(controller, suspend).boolValue)
        return RuntimeFailure(423, @"请先完成正在输入的内容，再保存个人词库。");
    try
    {
        NSURL *user = MetasequoiaDictionaryUserDirectory();
        metasequoia::apple::DictionarySessionLease lease(user);
        NSDictionary *response = nil;
        if (!lease.exclusively([&] {
            if (![generation isEqualToString:metasequoia::apple::ActiveDictionarySnapshotIdentifier(user)])
            {
                response = RuntimeFailure(409, @"本机词库已切换，请刷新后重新编辑。");
                return;
            }
            const auto result = metasequoia::edit_personal_dictionary(MetasequoiaCurrentDictionaryPaths(), previous, replacement, identifier.UTF8String);
            if (!result.success)
            {
                NSError *failure = nil;
                metasequoia::apple::PersonalDictionaryError(&failure, result.error);
                response = @{@"error": failure};
            }
            else response = @{@"success": @YES};
        })) return RuntimeBusy();
        return response;
    }
    catch (const std::exception &)
    {
        return RuntimeFailure(500, @"保存个人词库失败，请刷新后重试。");
    }
}
@end
