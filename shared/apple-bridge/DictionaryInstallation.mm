#include "DictionaryInstallation.h"

#import <CommonCrypto/CommonDigest.h>
#include <array>
#include <fstream>
#include <stdexcept>
#include <sys/file.h>
#include <fcntl.h>
#include <unistd.h>

namespace metasequoia::apple
{
namespace
{
bool IsDigest(NSString *value)
{
    return value.length == 64 &&
           [value rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]
                                              invertedSet]]
                   .location == NSNotFound;
}
NSString *ReadText(NSURL *url)
{
    return [[NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil]
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}
NSString *DigestFile(NSURL *url)
{
    std::ifstream file(url.fileSystemRepresentation, std::ios::binary);
    if (!file)
        throw std::runtime_error("Cannot read bundled dictionary");
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    std::array<char, 65536> buffer;
    while (file)
    {
        file.read(buffer.data(), buffer.size());
        CC_SHA256_Update(&context, buffer.data(), static_cast<CC_LONG>(file.gcount()));
    }
    if (!file.eof())
        throw std::runtime_error("Cannot finish reading bundled dictionary");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *text = [NSMutableString stringWithCapacity:64];
    for (auto byte : digest)
        [text appendFormat:@"%02x", byte];
    return text;
}
bool IsGeneration(NSString *value)
{
    return value.length == 128 && IsDigest([value substringToIndex:64]) && IsDigest([value substringFromIndex:64]);
}
bool IsSnapshotIdentifier(NSString *value)
{
    if (value.length != 36)
        return false;
    NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:value];
    return uuid != nil && [uuid.UUIDString isEqualToString:value];
}
bool HasDictionaries(const std::filesystem::path &directory)
{
    std::error_code error;
    return std::filesystem::is_regular_file(directory / "msime.db", error) &&
           std::filesystem::is_regular_file(directory / "english.db", error);
}
class PreparationLock
{
  public:
    explicit PreparationLock(NSURL *user)
    {
        descriptor = open([user URLByAppendingPathComponent:@"dictionary-install.lock"].fileSystemRepresentation,
                          O_CREAT | O_RDWR, 0600);
        if (descriptor < 0 || flock(descriptor, LOCK_EX | LOCK_NB) != 0)
        {
            if (descriptor >= 0)
                close(descriptor);
            throw std::runtime_error("Dictionary preparation is already running");
        }
    }
    ~PreparationLock()
    {
        flock(descriptor, LOCK_UN);
        close(descriptor);
    }

  private:
    int descriptor;
};
} // namespace

NSString *ActiveDictionarySnapshotIdentifier(NSURL *user)
{
    NSURL *marker = [user URLByAppendingPathComponent:@"active-user-generation"];
    if (![NSFileManager.defaultManager fileExistsAtPath:marker.path])
        return @"";
    NSString *identifier = ReadText(marker);
    if (!IsSnapshotIdentifier(identifier))
        throw std::runtime_error("Invalid active user generation");
    return identifier;
}

std::filesystem::path DictionarySnapshotDirectory(NSURL *user, NSString *identifier)
{
    if (!IsSnapshotIdentifier(identifier))
        throw std::runtime_error("Invalid snapshot identifier");
    NSURL *parent = [user URLByAppendingPathComponent:@"snapshot-generations" isDirectory:YES];
    if (![NSFileManager.defaultManager createDirectoryAtURL:parent
                                withIntermediateDirectories:YES
                                                 attributes:@{
                                                     NSFilePosixPermissions : @0700
                                                 }
                                                      error:nil])
        throw std::runtime_error("Cannot create snapshot parent");
    return [parent URLByAppendingPathComponent:identifier].fileSystemRepresentation;
}

bool DiscardInactiveDictionarySnapshot(NSURL *user, NSString *identifier)
{
    PreparationLock lock(user);
    if ([ActiveDictionarySnapshotIdentifier(user) isEqualToString:identifier])
        return false;
    std::filesystem::remove_all(DictionarySnapshotDirectory(user, identifier));
    return true;
}

void PublishDictionaryInstallation(NSURL *user, NSString *identifier, const RuntimePaths &paths,
                                   NSString *expectedIdentifier)
{
    PreparationLock lock(user);
    if (![ActiveDictionarySnapshotIdentifier(user) isEqualToString:expectedIdentifier])
        throw std::runtime_error("Active user generation changed");
    const auto generation = DictionarySnapshotDirectory(user, identifier);
    paths.validate();
    const auto content = paths.dictionaries.filename().string();
    NSString *contentID = [NSString stringWithUTF8String:content.c_str()];
    const auto same = [](const auto &a, const auto &b) {
        return std::filesystem::weakly_canonical(a) == std::filesystem::weakly_canonical(b);
    };
    if (!IsGeneration(contentID) || !same(paths.user_data, generation / "user") ||
        !same(paths.cache, generation / "cache") ||
        !same(paths.dictionaries, generation / "user" / "dictionaries" / content) ||
        !HasDictionaries(paths.dictionaries) || !std::filesystem::is_regular_file(paths.dictionaries / ".ready") ||
        !std::filesystem::is_regular_file(paths.user_data / "msime_user.db"))
        throw std::runtime_error("Snapshot generation is not ready");
    NSURL *preparedUser = [NSURL fileURLWithFileSystemRepresentation:paths.user_data.c_str()
                                                         isDirectory:YES
                                                       relativeToURL:nil];
    if (![contentID writeToURL:[preparedUser URLByAppendingPathComponent:@"active-dictionary-generation"]
                    atomically:YES
                      encoding:NSUTF8StringEncoding
                         error:nil])
        throw std::runtime_error("Cannot save snapshot content generation");
    if (![identifier writeToURL:[user URLByAppendingPathComponent:@"active-user-generation"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil])
        throw std::runtime_error("Cannot publish snapshot generation");
}

DictionaryInstallation PrepareDictionaryInstallation(NSURL *resources, NSURL *rootUser, NSURL *rootCache,
                                                     DictionaryResourceProfile profile)
{
    NSURL *user = rootUser;
    NSURL *cache = rootCache;
    RuntimePaths fallback{user.fileSystemRepresentation, user.fileSystemRepresentation, cache.fileSystemRepresentation,
                          user.fileSystemRepresentation};
    try
    {
        NSFileManager *manager = NSFileManager.defaultManager;
        if (![manager createDirectoryAtURL:rootUser withIntermediateDirectories:YES attributes:nil error:nil])
            throw std::runtime_error("Cannot create user dictionary directory");
        PreparationLock lock(rootUser);
        NSString *snapshot = ActiveDictionarySnapshotIdentifier(rootUser);
        if (snapshot.length > 0)
        {
            NSURL *generation =
                [[rootUser URLByAppendingPathComponent:@"snapshot-generations"] URLByAppendingPathComponent:snapshot];
            user = [generation URLByAppendingPathComponent:@"user"];
            cache = [generation URLByAppendingPathComponent:@"cache"];
            fallback = {resources.fileSystemRepresentation, user.fileSystemRepresentation,
                        cache.fileSystemRepresentation, user.fileSystemRepresentation};
            if (!std::filesystem::is_regular_file(fallback.user_data / "msime_user.db"))
                throw std::runtime_error("Active snapshot journal is missing");
        }
        NSURL *activeURL = [user URLByAppendingPathComponent:@"active-dictionary-generation"];
        NSString *previous = ReadText(activeURL);
        if (IsGeneration(previous))
        {
            const auto directory = fallback.user_data / "dictionaries" / previous.UTF8String;
            std::error_code error;
            if (HasDictionaries(directory) && std::filesystem::is_regular_file(directory / ".ready", error))
                fallback.dictionaries = directory;
        }
        NSArray<NSString *> *names = profile == DictionaryResourceProfile::MainAndEnglish
                                         ? @[ @"msime.db", @"english.db" ]
                                         : @[ @"msime.db", @"english.db", @"others.db", @"dict_japanese.dat" ];
        NSMutableArray<NSString *> *digests = [NSMutableArray array];
        for (NSString *name in names)
        {
            NSString *digest =
                ReadText([resources URLByAppendingPathComponent:[name stringByAppendingString:@".sha256"]]);
            if (!IsDigest(digest))
                throw std::runtime_error("Invalid bundled dictionary digest");
            [digests addObject:digest];
        }
        NSString *generation = [digests[0] stringByAppendingString:digests[1]];
        // App bundle URLs change on installation and their code-signed resources are immutable.
        // Caching this verification avoids hashing 180 MB on every keyboard launch; cache loss
        // simply triggers verification again. The full digest set also covers read-only resources.
        NSString *verification =
            [NSString stringWithFormat:@"%@\n%@", resources.path, [digests componentsJoinedByString:@"\n"]];
        NSURL *verifiedURL = [cache URLByAppendingPathComponent:@"verified-dictionary-bundle"];
        if (![ReadText(verifiedURL) isEqualToString:verification])
        {
            for (NSUInteger index = 0; index < names.count; ++index)
                if (![DigestFile([resources URLByAppendingPathComponent:names[index]]) isEqualToString:digests[index]])
                    throw std::runtime_error("Bundled dictionary checksum mismatch");
        }
        fallback.resources = resources.fileSystemRepresentation;
        const auto incoming = fallback.user_data / "dictionaries" / (std::string(generation.UTF8String) + ".incoming");
        // Under the installation lock, an incoming directory can only be from an interrupted run.
        std::filesystem::remove_all(incoming);
        auto paths = prepare_runtime_paths(resources.fileSystemRepresentation, user.fileSystemRepresentation,
                                           cache.fileSystemRepresentation, generation.UTF8String);
        if (![generation writeToURL:activeURL atomically:YES encoding:NSUTF8StringEncoding error:nil])
            throw std::runtime_error("Cannot save active dictionary generation");
        [verification writeToURL:verifiedURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        return {std::move(paths), std::nullopt};
    }
    catch (const std::exception &)
    {
        // A busy preparation lock may fail before selecting the active snapshot.
        // Resolve its already-published root for fallback without mutating it.
        if (fallback.user_data == std::filesystem::path(rootUser.fileSystemRepresentation))
        {
            try
            {
                NSString *snapshot = ActiveDictionarySnapshotIdentifier(rootUser);
                if (snapshot.length > 0)
                {
                    NSURL *generation = [[rootUser URLByAppendingPathComponent:@"snapshot-generations"]
                        URLByAppendingPathComponent:snapshot];
                    NSURL *activeUser = [generation URLByAppendingPathComponent:@"user"];
                    NSURL *activeCache = [generation URLByAppendingPathComponent:@"cache"];
                    fallback.user_data = activeUser.fileSystemRepresentation;
                    fallback.cache = activeCache.fileSystemRepresentation;
                    fallback.dictionaries = fallback.user_data;
                }
            }
            catch (const std::exception &)
            {
            }
        }
        // The preparation lock or bundle verification can fail before the normal
        // fallback lookup. Keep the last ready dictionary in the selected journal.
        NSString *previous = ReadText([[NSURL fileURLWithFileSystemRepresentation:fallback.user_data.c_str()
                                                                      isDirectory:YES
                                                                    relativeToURL:nil]
            URLByAppendingPathComponent:@"active-dictionary-generation"]);
        if (IsGeneration(previous))
        {
            const auto directory = fallback.user_data / "dictionaries" / previous.UTF8String;
            std::error_code error;
            if (HasDictionaries(directory) && std::filesystem::is_regular_file(directory / ".ready", error))
                fallback.dictionaries = directory;
        }
        const bool available = HasDictionaries(fallback.dictionaries);
        return {std::move(fallback), available ? "词库更新未完成，已保留原有数据；下次打开键盘将重试。"
                                               : "词库暂不可用，下次打开键盘将重试；仍可输入字母。"};
    }
}
} // namespace metasequoia::apple
