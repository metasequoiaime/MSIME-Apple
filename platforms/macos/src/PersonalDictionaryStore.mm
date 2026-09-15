#import "PersonalDictionaryStore.h"

// shared/apple-bridge 里的那一份:错误文案映射和编解码,iOS 已经在用。
#import "PersonalDictionaryBridge.h"

#include "DictionaryRuntime.h"

#include <metasequoia/personal_dictionary.h>

#include <optional>
#include <string>

namespace
{
metasequoia::PersonalDictionaryKind EngineKind(MetasequoiaPersonalDictionaryKind kind)
{
    switch (kind)
    {
    case MetasequoiaPersonalDictionaryKindWubi:
        return metasequoia::PersonalDictionaryKind::Wubi;
    case MetasequoiaPersonalDictionaryKindQuickPhrase:
        return metasequoia::PersonalDictionaryKind::QuickPhrase;
    case MetasequoiaPersonalDictionaryKindEnglish:
        return metasequoia::PersonalDictionaryKind::English;
    case MetasequoiaPersonalDictionaryKindPinyin:
        break;
    }
    return metasequoia::PersonalDictionaryKind::Pinyin;
}

MetasequoiaPersonalDictionaryKind BridgeKind(metasequoia::PersonalDictionaryKind kind)
{
    switch (kind)
    {
    case metasequoia::PersonalDictionaryKind::Wubi:
        return MetasequoiaPersonalDictionaryKindWubi;
    case metasequoia::PersonalDictionaryKind::QuickPhrase:
        return MetasequoiaPersonalDictionaryKindQuickPhrase;
    case metasequoia::PersonalDictionaryKind::English:
        return MetasequoiaPersonalDictionaryKindEnglish;
    case metasequoia::PersonalDictionaryKind::Pinyin:
        break;
    }
    return MetasequoiaPersonalDictionaryKindPinyin;
}

metasequoia::PersonalDictionaryEntry EngineEntry(MetasequoiaPersonalDictionaryEntry *entry)
{
    metasequoia::PersonalDictionaryEntry result;
    result.kind = EngineKind(entry.kind);
    result.key = entry.key.UTF8String != nullptr ? entry.key.UTF8String : "";
    result.value = entry.value.UTF8String != nullptr ? entry.value.UTF8String : "";
    result.weight = entry.weight;
    return result;
}

} // namespace

NSString *MetasequoiaPersonalDictionaryKindTitle(MetasequoiaPersonalDictionaryKind kind)
{
    switch (kind)
    {
    case MetasequoiaPersonalDictionaryKindWubi:
        return @"五笔";
    case MetasequoiaPersonalDictionaryKindQuickPhrase:
        return @"快捷短语";
    case MetasequoiaPersonalDictionaryKindEnglish:
        return @"英文";
    case MetasequoiaPersonalDictionaryKindPinyin:
        break;
    }
    return @"拼音";
}

NSString *MetasequoiaPersonalDictionaryKindKeyHint(MetasequoiaPersonalDictionaryKind kind)
{
    switch (kind)
    {
    case MetasequoiaPersonalDictionaryKindWubi:
        return @"1–4 个字母";
    case MetasequoiaPersonalDictionaryKindQuickPhrase:
        return @"1–32 个字母或数字";
    case MetasequoiaPersonalDictionaryKindEnglish:
        return @"1–64 个字母";
    case MetasequoiaPersonalDictionaryKindPinyin:
        break;
    }
    return @"完整音节，用 ' 分隔，如 ni'hao";
}

@implementation MetasequoiaPersonalDictionaryEntry
+ (instancetype)entryWithKind:(MetasequoiaPersonalDictionaryKind)kind
                          key:(NSString *)key
                        value:(NSString *)value
                       weight:(int64_t)weight
{
    MetasequoiaPersonalDictionaryEntry *entry = [[MetasequoiaPersonalDictionaryEntry alloc] init];
    entry.kind = kind;
    entry.key = key;
    entry.value = value;
    entry.weight = weight;
    return entry;
}
@end

@implementation MetasequoiaPersonalDictionaryStore

+ (nullable NSArray<MetasequoiaPersonalDictionaryEntry *> *)entriesAtOffset:(NSUInteger)offset
                                                                      limit:(NSUInteger)limit
                                                                    hasMore:(nullable BOOL *)hasMore
                                                                      error:(NSError **)error
{
    const metasequoia::PersonalDictionaryPage page =
        metasequoia::personal_dictionary_entries(MetasequoiaCurrentDictionaryPaths(), offset, limit);
    if (!page.error.empty())
    {
        if (error != nullptr)
        {
            metasequoia::apple::PersonalDictionaryError(error, page.error);
        }
        return nil;
    }
    NSMutableArray<MetasequoiaPersonalDictionaryEntry *> *entries =
        [NSMutableArray arrayWithCapacity:page.entries.size()];
    for (const auto &entry : page.entries)
    {
        [entries addObject:[MetasequoiaPersonalDictionaryEntry
                               entryWithKind:BridgeKind(entry.kind)
                                         key:[NSString stringWithUTF8String:entry.key.c_str()]
                                       value:[NSString stringWithUTF8String:entry.value.c_str()]
                                      weight:entry.weight]];
    }
    if (hasMore != nullptr)
    {
        *hasMore = page.has_more;
    }
    return entries;
}

+ (BOOL)applyPrevious:(std::optional<metasequoia::PersonalDictionaryEntry>)previous
          replacement:(std::optional<metasequoia::PersonalDictionaryEntry>)replacement
                error:(NSError **)error
{
    // 带上幂等 ID:引擎用它认出「同一次编辑的重试」,重放不会变成加两遍。
    const std::string requestID = NSUUID.UUID.UUIDString.lowercaseString.UTF8String;
    const metasequoia::PersonalDictionaryEditResult result =
        metasequoia::edit_personal_dictionary(MetasequoiaCurrentDictionaryPaths(), previous, replacement, requestID);
    if (!result.success)
    {
        if (error != nullptr)
        {
            metasequoia::apple::PersonalDictionaryError(error, result.error);
        }
        return NO;
    }
    return YES;
}

+ (BOOL)addEntry:(MetasequoiaPersonalDictionaryEntry *)entry error:(NSError **)error
{
    return [self applyPrevious:std::nullopt replacement:EngineEntry(entry) error:error];
}

+ (BOOL)removeEntry:(MetasequoiaPersonalDictionaryEntry *)entry error:(NSError **)error
{
    return [self applyPrevious:EngineEntry(entry) replacement:std::nullopt error:error];
}

+ (BOOL)replaceEntry:(MetasequoiaPersonalDictionaryEntry *)previous
           withEntry:(MetasequoiaPersonalDictionaryEntry *)replacement
               error:(NSError **)error
{
    return [self applyPrevious:EngineEntry(previous) replacement:EngineEntry(replacement) error:error];
}

+ (BOOL)validateEntry:(MetasequoiaPersonalDictionaryEntry *)entry error:(NSError **)error
{
    const metasequoia::PersonalDictionaryValidation validation =
        metasequoia::validate_personal_dictionary_entry(EngineEntry(entry));
    if (!validation.entry.has_value())
    {
        if (error != nullptr)
        {
            metasequoia::apple::PersonalDictionaryError(error, validation.error);
        }
        return NO;
    }
    return YES;
}

@end
