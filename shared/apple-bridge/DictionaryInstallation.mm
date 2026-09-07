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

DictionaryInstallation PrepareDictionaryInstallation(NSURL *resources, NSURL *user, NSURL *cache)
{
    RuntimePaths fallback{user.fileSystemRepresentation, user.fileSystemRepresentation, cache.fileSystemRepresentation,
                          user.fileSystemRepresentation};
    NSURL *activeURL = [user URLByAppendingPathComponent:@"active-dictionary-generation"];
    NSString *previous = ReadText(activeURL);
    if (IsGeneration(previous))
    {
        const auto directory = fallback.user_data / "dictionaries" / previous.UTF8String;
        std::error_code error;
        if (HasDictionaries(directory) && std::filesystem::is_regular_file(directory / ".ready", error))
            fallback.dictionaries = directory;
    }
    try
    {
        NSFileManager *manager = NSFileManager.defaultManager;
        if (![manager createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:nil])
            throw std::runtime_error("Cannot create user dictionary directory");
        PreparationLock lock(user);
        NSArray<NSString *> *names = @[ @"msime.db", @"english.db", @"others.db", @"dict_japanese.dat" ];
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
        const bool available = HasDictionaries(fallback.dictionaries);
        return {std::move(fallback), available ? "词库更新未完成，已保留原有数据；下次打开键盘将重试。"
                                               : "词库暂不可用，下次打开键盘将重试；仍可输入字母。"};
    }
}
} // namespace metasequoia::apple
