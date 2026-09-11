#pragma once
#import <AppKit/AppKit.h>
#import <InputMethodKit/InputMethodKit.h>
#include <cstddef>
namespace metasequoia::mac {
constexpr size_t NormalizeCandidateFontSize(size_t value) { return value == 16 || value == 18 || value == 20 ? value : 18; }
constexpr size_t CandidateFontSizeForOptionIndex(size_t index) { constexpr size_t options[] = {16,18,20}; return index < 3 ? options[index] : 18; }
constexpr size_t CandidateFontSizeOptionIndex(size_t value) { switch (NormalizeCandidateFontSize(value)) { case 16: return 0; case 20: return 2; default: return 1; } }
inline NSDictionary *CandidatePanelAttributes(size_t value) { return @{ IMKCandidatesSendServerKeyEventFirst: @YES, NSFontAttributeName: [NSFont systemFontOfSize:(CGFloat)NormalizeCandidateFontSize(value)] }; }
}
