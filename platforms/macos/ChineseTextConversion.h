#pragma once
#import <Foundation/Foundation.h>

// Based on MSIME-Apple b637828e15eafcb5e459edd270a962dd14517285.
FOUNDATION_EXPORT NSString *MSIMEChineseOutputString(NSString *text, BOOL traditionalOutput);
FOUNDATION_EXPORT BOOL MSIMEScriptConversionApplies(NSDictionary *context);
