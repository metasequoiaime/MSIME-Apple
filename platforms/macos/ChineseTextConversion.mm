#import "ChineseTextConversion.h"

NSString *MetasequoiaChineseOutputString(NSString *text, BOOL traditionalOutput)
{
    if (!traditionalOutput || text.length == 0)
    {
        return text;
    }

    NSMutableString *converted = [text mutableCopy];
    if (!CFStringTransform((__bridge CFMutableStringRef)converted, nullptr, CFSTR("Simplified-Traditional"), false))
    {
        return text;
    }
    return [converted copy];
}
