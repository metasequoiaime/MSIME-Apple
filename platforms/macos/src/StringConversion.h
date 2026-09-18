#pragma once

#import <Foundation/Foundation.h>

#include <string>

NSString *MetasequoiaStringFromUtf8(const std::string &value);
NSUInteger MetasequoiaUniqueStringIndex(NSArray<NSString *> *values, NSString *target);
NSAttributedString *MetasequoiaIndexedCandidateString(NSString *value, NSUInteger index);
NSUInteger MetasequoiaCandidateIndex(NSAttributedString *candidate);
