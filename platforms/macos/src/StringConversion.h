#pragma once

#import <Foundation/Foundation.h>

#include <string>

FOUNDATION_EXPORT NSAttributedStringKey const MetasequoiaCandidateTranslationAttributeName;
// 第二条释义。候选格要同时摆英文和日文,而一个属性只装得下一条。
FOUNDATION_EXPORT NSAttributedStringKey const MetasequoiaCandidateSecondaryTranslationAttributeName;

NSString *MetasequoiaStringFromUtf8(const std::string &value);
NSUInteger MetasequoiaUniqueStringIndex(NSArray<NSString *> *values, NSString *target);
NSAttributedString *MetasequoiaIndexedCandidateString(NSString *value, NSUInteger index);
NSAttributedString *MetasequoiaCandidateStringByAddingTranslation(NSAttributedString *candidate, NSString *translation);
NSString *MetasequoiaCandidateTranslation(NSAttributedString *candidate);
NSAttributedString *MetasequoiaCandidateStringByAddingSecondaryTranslation(NSAttributedString *candidate,
                                                                           NSString *translation);
NSString *MetasequoiaCandidateSecondaryTranslation(NSAttributedString *candidate);
NSUInteger MetasequoiaCandidateIndex(NSAttributedString *candidate);
