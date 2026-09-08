#import "DictionarySnapshotBridge.h"
#include "DictionaryInstallation.h"
#include <metasequoia/dictionary_state.h>
#include <stdexcept>
#import <CommonCrypto/CommonDigest.h>
#include <array>
#include <type_traits>

namespace
{
std::string Text(NSDictionary *data, NSString *key)
{
    id value = data[key];
    if (![value isKindOfClass:NSString.class])
        throw std::runtime_error("Invalid snapshot text");
    NSData *bytes = [value dataUsingEncoding:NSUTF8StringEncoding];
    if (!bytes)
        throw std::runtime_error("Invalid snapshot encoding");
    return bytes.length == 0 ? std::string() : std::string(static_cast<const char *>(bytes.bytes), bytes.length);
}
std::int64_t Integer(NSDictionary *data, NSString *key)
{
    id value = data[key];
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID())
        throw std::runtime_error("Invalid snapshot integer");
    const std::string number = [value stringValue].UTF8String;
    std::size_t consumed = 0;
    const auto result = std::stoll(number, &consumed);
    if (consumed != number.size())
        throw std::runtime_error("Invalid snapshot integer");
    return result;
}
bool Boolean(NSDictionary *data, NSString *key, bool fallback)
{
    id value = data[key];
    if (!value)
        return fallback;
    if (![value isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID())
        throw std::runtime_error("Invalid snapshot boolean");
    return [value boolValue];
}
metasequoia::DictionaryStateRecord Decode(NSDictionary *record)
{
    using namespace metasequoia;
    id data = record[@"data"];
    if (![data isKindOfClass:NSDictionary.class])
        throw std::runtime_error("Invalid snapshot record");
    const auto type = Text(record, @"type");
    const auto code = Text(data, @"code"), word = Text(data, @"word");
    if (type == "overlay")
    {
        DictionaryStateEntry entry;
        const auto kind = Text(data, @"kind");
        if (kind == "pinyin") entry.kind = PersonalDictionaryKind::Pinyin;
        else if (kind == "wubi") entry.kind = PersonalDictionaryKind::Wubi;
        else if (kind == "quick") entry.kind = PersonalDictionaryKind::QuickPhrase;
        else if (kind == "english") entry.kind = PersonalDictionaryKind::English;
        else throw std::runtime_error("Invalid snapshot kind");
        entry.key = code;
        entry.value = word;
        entry.weight = Integer(data, @"weight");
        if (!record[@"deleted"])
            throw std::runtime_error("Missing snapshot deletion state");
        entry.deleted = Boolean(record, @"deleted", false);
        entry.user_inserted = Boolean(data, @"user_inserted", true);
        entry.display = kind == "english" && !entry.deleted ? word : "";
        return entry;
    }
    const auto context = Text(data, @"context");
    if (type == "position")
    {
        const auto position = Integer(data, @"position");
        if (position < 1 || position > 5) throw std::runtime_error("Invalid snapshot position");
        return DictionaryStatePosition{context, code, word, static_cast<int>(position)};
    }
    if (type == "selection")
    {
        const auto count = Integer(data, @"count");
        if (count < 0 || count > 10) throw std::runtime_error("Invalid snapshot count");
        return DictionaryStateSelection{context, code, word, static_cast<int>(count)};
    }
    throw std::runtime_error("Invalid snapshot type");
}
}

namespace metasequoia::apple
{
std::string DictionaryStateRevision(const RuntimePaths &paths)
{
    CC_SHA256_CTX hash;
    CC_SHA256_Init(&hash);
    const auto integer = [&](std::uint64_t value) {
        std::array<unsigned char, 8> bytes;
        for (int index = 7; index >= 0; --index) { bytes[index] = value & 255; value >>= 8; }
        CC_SHA256_Update(&hash, bytes.data(), static_cast<CC_LONG>(bytes.size()));
    };
    const auto text = [&](const std::string &value) {
        integer(value.size());
        CC_SHA256_Update(&hash, value.data(), static_cast<CC_LONG>(value.size()));
    };
    text("msime-local-dictionary-state-v1");
    stream_dictionary_state(paths, [&](const DictionaryStateRecord &record) {
        std::visit([&](const auto &value) {
            using T = std::decay_t<decltype(value)>;
            if constexpr (std::is_same_v<T, DictionaryStateEntry>)
            {
                text("entry");
                switch (value.kind)
                {
                case PersonalDictionaryKind::Pinyin: text("pinyin"); break;
                case PersonalDictionaryKind::Wubi: text("wubi"); break;
                case PersonalDictionaryKind::QuickPhrase: text("quick"); break;
                case PersonalDictionaryKind::English: text("english"); break;
                }
                text(value.key); text(value.value); integer(value.weight); text(value.display);
                integer(value.deleted); integer(value.user_inserted);
            }
            else
            {
                if constexpr (std::is_same_v<T, DictionaryStatePosition>) text("position");
                else text("selection");
                text(value.context); text(value.key); text(value.value);
                if constexpr (std::is_same_v<T, DictionaryStatePosition>) integer(value.position);
                else integer(value.count);
            }
        }, record);
        return true;
    });
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &hash);
    const char digits[] = "0123456789abcdef";
    std::string result;
    result.reserve(64);
    for (const auto byte : digest) { result += digits[byte >> 4]; result += digits[byte & 15]; }
    return result;
}
}

@interface MSIMEPreparedDictionarySnapshot ()
- (instancetype)initWithIdentifier:(NSString *)identifier paths:(const metasequoia::RuntimePaths &)paths;
@end

@implementation MSIMEPreparedDictionarySnapshot
{
    metasequoia::RuntimePaths _paths;
}
- (instancetype)initWithIdentifier:(NSString *)identifier paths:(const metasequoia::RuntimePaths &)paths
{
    if ((self = [super init])) { _identifier = [identifier copy]; _paths = paths; }
    return self;
}
- (const metasequoia::RuntimePaths &)runtimePaths { return _paths; }
- (NSString *)stateRevisionWithError:(NSError **)error
{
    try { return [NSString stringWithUTF8String:metasequoia::apple::DictionaryStateRevision(_paths).c_str()]; }
    catch (const std::exception &)
    {
        if (error) *error = [NSError errorWithDomain:@"app.msime.snapshot" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"无法读取本地词库版本，请稍后重试。"}];
        return nil;
    }
}
@end

@implementation DictionarySnapshotBridge
+ (MSIMEPreparedDictionarySnapshot *)prepareResources:(NSURL *)resources userDirectory:(NSURL *)user
                                           identifier:(NSString *)identifier contentIdentifier:(NSString *)contentIdentifier
                                       maximumRecords:(NSUInteger)maximumRecords nextRecord:(MSIMESnapshotNextRecord)nextRecord
                                                error:(NSError **)error
{
    NSError *streamError = nil;
    try
    {
        if (!resources.isFileURL || !user.isFileURL || maximumRecords == 0 || contentIdentifier.length != 128 ||
            [contentIdentifier rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound)
            throw std::runtime_error("Invalid snapshot preparation");
        auto paths = metasequoia::stage_dictionary_state(resources.fileSystemRepresentation,
            metasequoia::apple::DictionarySnapshotDirectory(user, identifier), contentIdentifier.UTF8String,
            [&](metasequoia::DictionaryStateRecord &record) {
                @autoreleasepool {
                    NSError *failure = nil;
                    NSDictionary *next = nextRecord(&failure);
                    if (failure) { streamError = failure; throw std::runtime_error("Snapshot stream failed"); }
                    if (!next) return false;
                    record = Decode(next);
                    return true;
                }
            }, maximumRecords);
        return [[MSIMEPreparedDictionarySnapshot alloc] initWithIdentifier:identifier paths:paths];
    }
    catch (const std::exception &)
    {
        if (error) *error = streamError ?: [NSError errorWithDomain:@"app.msime.snapshot" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"词库快照准备失败，原有词库未更改。"}];
        return nil;
    }
}
@end
