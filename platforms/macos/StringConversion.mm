#include "StringConversion.h"

#pragma clang diagnostic push
#if __has_warning("-Wcharacter-conversion")
#pragma clang diagnostic ignored "-Wcharacter-conversion"
#endif
#include "../../../vendor/MetasequoiaImeEngine/utfcpp/source/utf8.h"
#pragma clang diagnostic pop

NSString *MetasequoiaStringFromUtf8(const std::string &value)
{
    NSString *decoded = [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
    if (decoded != nil)
    {
        return decoded;
    }

    const std::string sanitized = utf8::replace_invalid(value);
    decoded = [[NSString alloc] initWithBytes:sanitized.data() length:sanitized.size() encoding:NSUTF8StringEncoding];
    return decoded != nil ? decoded : @"�";
}

NSUInteger MetasequoiaUniqueStringIndex(NSArray<NSString *> *values, NSString *target)
{
    NSUInteger match = NSNotFound;
    for (NSUInteger index = 0; index < values.count; ++index)
    {
        if (![values[index] isEqualToString:target])
        {
            continue;
        }
        if (match != NSNotFound)
        {
            return NSNotFound;
        }
        match = index;
    }
    return match;
}

namespace
{
NSAttributedStringKey const kMetasequoiaCandidateIndexAttribute = @"MetasequoiaCandidateIndex";
}

NSAttributedString *MetasequoiaIndexedCandidateString(NSString *value, NSUInteger index)
{
    return [[NSAttributedString alloc] initWithString:value
                                           attributes:@{
                                               kMetasequoiaCandidateIndexAttribute : @(index)
                                           }];
}

NSUInteger MetasequoiaCandidateIndex(NSAttributedString *candidate)
{
    if (candidate.length == 0)
    {
        return NSNotFound;
    }
    id value = [candidate attribute:kMetasequoiaCandidateIndexAttribute atIndex:0 effectiveRange:nil];
    return [value isKindOfClass:[NSNumber class]] ? [value unsignedIntegerValue] : NSNotFound;
}
