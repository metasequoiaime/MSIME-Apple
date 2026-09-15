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
// 标上 nullability:macOS 的目标开着 -Werror=nullability-completeness,不标就编不过。
std::optional<PersonalDictionaryEntry> DecodePersonalWord(NSDictionary *_Nullable entry,
                                                          NSError *_Nullable *_Nullable error);
NSDictionary *_Nonnull EncodePersonalWord(const PersonalDictionaryEntry &entry);
void PersonalDictionaryError(NSError *_Nullable *_Nullable error, const std::string &message);
} // namespace metasequoia::apple
#endif
