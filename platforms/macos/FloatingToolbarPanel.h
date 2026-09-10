#pragma once

#import <AppKit/AppKit.h>

@class MSIMEFloatingToolbarPanel;

@protocol MSIMEFloatingToolbarDelegate <NSObject>
- (void)floatingToolbarDidRequestToggleInputMode:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestTogglePunctuation:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleFullWidth:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenCharacterPalette:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenSettings:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestCheckForUpdates:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenWebsite:(MSIMEFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestHide:(MSIMEFloatingToolbarPanel *)toolbar;
@end

FOUNDATION_EXPORT NSRect MSIMEFloatingToolbarFrame(NSRect proposedFrame, NSRect visibleFrame, BOOL hasSavedFrame);
FOUNDATION_EXPORT NSMenu *CreateMSIMEFloatingToolbarUtilityMenu(id target);

@interface MSIMEFloatingToolbarPanel : NSPanel
@property(nonatomic, weak) id<MSIMEFloatingToolbarDelegate> toolbarDelegate;
+ (instancetype)sharedPanel;
- (void)updateEnglishInputMode:(BOOL)englishInputMode
          chinesePunctuationEnabled:(BOOL)chinesePunctuationEnabled
                   fullWidthEnabled:(BOOL)fullWidthEnabled
    traditionalChineseOutputEnabled:(BOOL)traditionalChineseOutputEnabled;
- (void)activateForDelegate:(id<MSIMEFloatingToolbarDelegate>)delegate visible:(BOOL)visible;
- (void)setVisible:(BOOL)visible forDelegate:(id<MSIMEFloatingToolbarDelegate>)delegate;
- (void)deactivateForDelegate:(id<MSIMEFloatingToolbarDelegate>)delegate;
@end
