#pragma once

#import <Foundation/Foundation.h>

#include <string>

FOUNDATION_EXPORT NSAttributedStringKey const MetasequoiaCandidateTranslationAttributeName;

NSString *MetasequoiaStringFromUtf8(const std::string &value);
NSUInteger MetasequoiaUniqueStringIndex(NSArray<NSString *> *values, NSString *target);
NSAttributedString *MetasequoiaIndexedCandidateString(NSString *value, NSUInteger index);
NSAttributedString *MetasequoiaCandidateStringByAddingTranslation(NSAttributedString *candidate, NSString *translation);
NSString *MetasequoiaCandidateTranslation(NSAttributedString *candidate);
NSUInteger MetasequoiaCandidateIndex(NSAttributedString *candidate);
