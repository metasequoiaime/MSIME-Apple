#pragma once

#import <AppKit/AppKit.h>

@class MetasequoiaFloatingToolbarPanel;

@protocol MetasequoiaFloatingToolbarDelegate <NSObject>
- (void)floatingToolbarDidRequestToggleInputMode:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestTogglePunctuation:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleFullWidth:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MetasequoiaFloatingToolbarPanel *)toolbar;
- (void)floatingToolbarDidRequestOpenCharacterPalette:(MetasequoiaFloatingToolbarPanel *)toolbar;
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
- (void)updateJapaneseScheme:(BOOL)japanese englishMode:(BOOL)englishMode;
- (void)updateEnglishInputMode:(BOOL)englishInputMode
          chinesePunctuationEnabled:(BOOL)chinesePunctuationEnabled
                   fullWidthEnabled:(BOOL)fullWidthEnabled
    traditionalChineseOutputEnabled:(BOOL)traditionalChineseOutputEnabled;
- (void)activateForDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate visible:(BOOL)visible;
- (void)setVisible:(BOOL)visible forDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate;
- (void)deactivateForDelegate:(id<MetasequoiaFloatingToolbarDelegate>)delegate;
@end
