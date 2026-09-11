#include "StringConversion.h"

NSString *MetasequoiaStringFromUtf8(const std::string &value)
{
    NSString *decoded = [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
    return decoded != nil ? decoded : @"�";
}

NSUInteger MetasequoiaUniqueStringIndex(NSArray<NSString *> *values, NSString *target)
{
    NSUInteger match = NSNotFound;
    for (NSUInteger index = 0; index < values.count; ++index) {
        if ([values[index] isEqualToString:target]) {
            if (match != NSNotFound) return NSNotFound;
            match = index;
        }
    }
    return match;
}

namespace {
NSAttributedStringKey const kCandidateIndex = @"MetasequoiaCandidateIndex";
}

NSAttributedString *MetasequoiaIndexedCandidateString(NSString *value, NSUInteger index)
{
    return [[NSAttributedString alloc] initWithString:value attributes:@{kCandidateIndex: @(index)}];
}

NSUInteger MetasequoiaCandidateIndex(NSAttributedString *candidate)
{
    if (candidate.length == 0) return NSNotFound;
    id value = [candidate attribute:kCandidateIndex atIndex:0 effectiveRange:nil];
    return [value isKindOfClass:[NSNumber class]] ? [value unsignedIntegerValue] : NSNotFound;
}
