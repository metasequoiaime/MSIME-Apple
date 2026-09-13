#pragma once

#import <AppKit/AppKit.h>

typedef NS_ENUM(NSInteger, MSIMESupportPage) {
    MSIMESupportPageHelp = 0,
    MSIMESupportPageAbout,
    MSIMESupportPageFeedback,
};

NS_ASSUME_NONNULL_BEGIN

/// Native counterparts of the Windows help, about, and feedback pages.
@interface MSIMESupportWindowController : NSWindowController
+ (instancetype)sharedController;
@property(nonatomic, readonly) MSIMESupportPage page;
- (void)showPage:(MSIMESupportPage)page;
@end

NS_ASSUME_NONNULL_END
