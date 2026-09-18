#import "../src/ChineseTextConversion.h"

#import <Foundation/Foundation.h>

#include <stdexcept>

namespace
{
void require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}
} // namespace

int main()
{
    @autoreleasepool
    {
        NSString *simplified = @"开发软件，后台里面";
        require([[MetasequoiaChineseOutputString(simplified, YES) description] isEqualToString:@"開發軟件，後台裡面"],
                "Traditional output did not convert the visible Chinese text.");
        require(MetasequoiaChineseOutputString(simplified, NO) == simplified,
                "Simplified output unnecessarily copied or transformed its text.");
        require([MetasequoiaChineseOutputString(@"MSIME 123 😀", YES) isEqualToString:@"MSIME 123 😀"],
                "Traditional output changed non-Chinese text.");
        require([MetasequoiaChineseOutputString(@"", YES) isEqualToString:@""],
                "Traditional output did not preserve an empty string.");
        NSString *convertedSimplifiedGan = MetasequoiaChineseOutputString(@"干", YES);
        NSString *convertedTraditionalGan = MetasequoiaChineseOutputString(@"乾", YES);
        require([convertedSimplifiedGan isEqualToString:@"乾"] && [convertedTraditionalGan isEqualToString:@"乾"],
                "The real simplified/traditional candidate collision fixture changed.");
    }
    return 0;
}
