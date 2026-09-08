#include "PersonalDictionaryBridge.h"

namespace metasequoia::apple
{
void PersonalDictionaryError(NSError **error, const std::string &message)
{
    if (!error)
        return;
    NSString *reason = @"词条未能保存，请刷新词库后重试。";
    if (message == "Use complete pinyin syllables separated by apostrophes or spaces")
        reason = @"请填写完整拼音，用空格或英文单引号分隔音节，例如 ni hao。";
    else if (message == "Each character must have one pinyin syllable (maximum 64)")
        reason = @"每个字需要一个拼音音节，最多 64 个字。";
    else if (message == "Wubi codes contain one to four letters")
        reason = @"五笔编码需要 1 至 4 个英文字母。";
    else if (message == "Quick-phrase codes contain one to 32 letters or digits")
        reason = @"快捷短语编码需要 1 至 32 个字母或数字。";
    else if (message == "English code must match the word's letters, ignoring case")
        reason = @"英文编码应与词条字母一致，可使用不同大小写，最多 64 个字母。";
    else if (message == "Weight must be between 1 and 100000000")
        reason = @"词条权重必须在 1 到 100000000 之间。";
    else if (message == "A valid, bounded UTF-8 word and input code are required")
        reason = @"请填写词条和编码，词条不能超过 4096 字节。";
    else if (message == "The word contains an unsupported control character")
        reason = @"词条中包含不支持的控制字符。";
    else if (message == "The entry changed; reload it before editing")
        reason = @"这个词条已发生变化，请刷新后重新编辑。";
    else if (message == "Composition is active")
        reason = @"请先完成当前输入，再同步个人词库。";
    *error = [NSError errorWithDomain:@"app.msime.personal-dictionary"
                                 code:1
                             userInfo:@{NSLocalizedDescriptionKey : reason}];
}
std::optional<PersonalDictionaryEntry> DecodePersonalWord(NSDictionary *entry, NSError **error)
{
    if (![entry isKindOfClass:NSDictionary.class] || ![entry[@"kind"] isKindOfClass:NSString.class] ||
        ![entry[@"key"] isKindOfClass:NSString.class] || ![entry[@"value"] isKindOfClass:NSString.class] ||
        ![entry[@"weight"] isKindOfClass:NSNumber.class])
    {
        PersonalDictionaryError(error, "Invalid entry payload");
        return std::nullopt;
    }
    PersonalDictionaryEntry result;
    NSString *kind = entry[@"kind"];
    if ([kind isEqualToString:@"pinyin"])
        result.kind = PersonalDictionaryKind::Pinyin;
    else if ([kind isEqualToString:@"wubi"])
        result.kind = PersonalDictionaryKind::Wubi;
    else if ([kind isEqualToString:@"quickPhrase"])
        result.kind = PersonalDictionaryKind::QuickPhrase;
    else if ([kind isEqualToString:@"english"])
        result.kind = PersonalDictionaryKind::English;
    else
    {
        PersonalDictionaryError(error, "Invalid entry kind");
        return std::nullopt;
    }
    NSString *key = entry[@"key"], *value = entry[@"value"];
    result.key = std::string(key.UTF8String, [key lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    result.value = std::string(value.UTF8String, [value lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
    result.weight = [entry[@"weight"] longLongValue];
    auto validation = validate_personal_dictionary_entry(std::move(result));
    if (!validation.entry)
        PersonalDictionaryError(error, validation.error);
    return validation.entry;
}
NSDictionary *EncodePersonalWord(const PersonalDictionaryEntry &entry)
{
    NSString *kind = @"pinyin";
    switch (entry.kind)
    {
    case PersonalDictionaryKind::Pinyin:
        break;
    case PersonalDictionaryKind::Wubi:
        kind = @"wubi";
        break;
    case PersonalDictionaryKind::QuickPhrase:
        kind = @"quickPhrase";
        break;
    case PersonalDictionaryKind::English:
        kind = @"english";
        break;
    }
    return @{
        @"kind" : kind,
        @"key" : @(entry.key.c_str()),
        @"value" : @(entry.value.c_str()),
        @"weight" : @(entry.weight)
    };
}
} // namespace metasequoia::apple
@implementation PersonalDictionaryBridge
+ (NSDictionary<NSString *, id> *)validateEntry:(NSDictionary<NSString *, id> *)entry error:(NSError **)error
{
    auto result = metasequoia::apple::DecodePersonalWord(entry, error);
    return result ? metasequoia::apple::EncodePersonalWord(*result) : nil;
}
@end
