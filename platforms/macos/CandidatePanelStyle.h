#pragma once

#import <Carbon/Carbon.h>
#import <InputMethodKit/InputMethodKit.h>

namespace metasequoia::mac
{
enum class CandidatePanelStyle : NSInteger
{
    Horizontal = 0,
    Vertical = 1,
};

inline CandidatePanelStyle NormalizeCandidatePanelStyle(NSInteger value)
{
    return value == static_cast<NSInteger>(CandidatePanelStyle::Vertical) ? CandidatePanelStyle::Vertical
                                                                          : CandidatePanelStyle::Horizontal;
}

inline IMKCandidatePanelType CandidatePanelTypeForStyle(CandidatePanelStyle style)
{
    return style == CandidatePanelStyle::Vertical ? kIMKSingleColumnScrollingCandidatePanel
                                                  : kIMKSingleRowSteppingCandidatePanel;
}

inline bool IsPrimaryCandidateDirection(unsigned short keyCode, IMKCandidatePanelType panelType)
{
    if (panelType == kIMKSingleColumnScrollingCandidatePanel)
    {
        return keyCode == kVK_UpArrow || keyCode == kVK_DownArrow;
    }
    return keyCode == kVK_LeftArrow || keyCode == kVK_RightArrow;
}
} // namespace metasequoia::mac
