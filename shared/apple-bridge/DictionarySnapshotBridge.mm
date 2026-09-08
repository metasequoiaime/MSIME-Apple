#import "DictionarySnapshotBridge.h"
#include "DictionaryInstallation.h"
#include <metasequoia/dictionary_state.h>
#include <stdexcept>

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
