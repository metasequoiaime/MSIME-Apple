#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN
@interface PersonalDictionaryBridge : NSObject
+ (nullable NSDictionary<NSString *, id> *)validateEntry:(NSDictionary<NSString *, id> *)entry error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END

#ifdef __cplusplus
#include <metasequoia/personal_dictionary.h>
namespace metasequoia::apple
{
std::optional<PersonalDictionaryEntry> DecodePersonalWord(NSDictionary *entry, NSError **error);
NSDictionary *EncodePersonalWord(const PersonalDictionaryEntry &entry);
void PersonalDictionaryError(NSError **error, const std::string &message);
} // namespace metasequoia::apple
#endif
