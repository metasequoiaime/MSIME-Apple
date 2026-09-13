#pragma once

#import <AppKit/AppKit.h>
#include "CandidateSkin.h"

@class MetasequoiaFloatingToolbarPanel;

@protocol MetasequoiaFloatingToolbarDelegate <NSObject>
- (void)floatingToolbarDidRequestToggleInputMode:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestTogglePunctuation:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleFullWidth:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenCharacterPalette:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenEmoji:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenHandwriting:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenScreenKeyboard:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleVoice:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenSettings:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestCheckForUpdates:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenWebsite:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestHide:(MetasequoiaFloatingToolbarPanel *)toolbar;
@end

FOUNDATION_EXPORT NSRect MetasequoiaFloatingToolbarFrame(NSRect proposedFrame, NSRect visibleFrame, BOOL hasSavedFrame);
FOUNDATION_EXPORT NSMenu *CreateMetasequoiaFloatingToolbarUtilityMenu(id target);

@interface MetasequoiaFloatingToolbarPanel : NSPanel
@property(nonatomic, weak) id<MetasequoiaFloatingToolbarDelegate> toolbarDelegate;
+ (instancetype)sharedPanel;
- (void)updateEnglishInputMode:(BOOL)englishInputMode
          chinesePunctuationEnabled:(BOOL)chinesePunctuationEnabled
                   fullWidthEnabled:(BOOL)fullWidthEnabled
    traditionalChineseOutputEnabled:(BOOL)traditionalChineseOutputEnabled;
- (void)activateForDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate visible:(BOOL)visible;
- (void)setVisible:(BOOL)visible forDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate;
- (void)deactivateForDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate;
/// Apply validated shared preferences without persisting platform-local defaults.
- (void)applyThemePreferences:(NSDictionary *)preferences;
- (void)applySizingPreferences:(NSDictionary *)preferences;
/// Use the active host's resolved palette without reading another preference store.
- (void)applyLightSkin:(const msime::mac::SkinTokens &)light darkSkin:(const msime::mac::SkinTokens &)dark;
@end
#define MSIMEFloatingToolbarDelegate MetasequoiaFloatingToolbarDelegate
#define MSIMEFloatingToolbarPanel MetasequoiaFloatingToolbarPanel
#define MSIMEFloatingToolbarFrame MetasequoiaFloatingToolbarFrame
#define CreateMSIMEFloatingToolbarUtilityMenu CreateMetasequoiaFloatingToolbarUtilityMenu
