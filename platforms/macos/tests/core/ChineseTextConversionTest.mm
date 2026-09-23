#import "../../src/core/ChineseTextConversion.h"

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
        require([[MetasequoiaChineseOutputString(simplified, YES) description] isEqualToString:@"開發軟件，後臺裏面"],
                "Traditional output did not convert the visible Chinese text.");
        require(MetasequoiaChineseOutputString(simplified, NO) == simplified,
                "Simplified output unnecessarily copied or transformed its text.");
        require([MetasequoiaChineseOutputString(@"MSIME 123 😀", YES) isEqualToString:@"MSIME 123 😀"],
                "Traditional output changed non-Chinese text.");
        require([MetasequoiaChineseOutputString(@"", YES) isEqualToString:@""],
                "Traditional output did not preserve an empty string.");
        NSString *convertedSimplifiedGan = MetasequoiaChineseOutputString(@"干", YES);
        NSString *convertedTraditionalGan = MetasequoiaChineseOutputString(@"乾", YES);
        require([convertedSimplifiedGan isEqualToString:@"幹"] && [convertedTraditionalGan isEqualToString:@"乾"],
                "The OpenCC s2t 干/乾 fixture changed: standalone 干 is 幹 and 乾 stays 乾.");
        NSDictionary<NSString *, NSString *> *phrases = @{
            @"头发" : @"頭髮",
            @"蓬松" : @"蓬鬆",
            @"余下" : @"餘下",
            @"答复" : @"答覆",
            @"凭借" : @"憑藉",
        };
        for (NSString *source in phrases)
        {
            require([MetasequoiaChineseOutputString(source, YES) isEqualToString:phrases[source]],
                    "Traditional output did not use the OpenCC s2t phrase tables.");
        }
    }
    return 0;
}
