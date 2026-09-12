#pragma once

#import <AppKit/AppKit.h>

FOUNDATION_EXPORT NSNotificationName const MetasequoiaWillResetLearnedDataNotification;
FOUNDATION_EXPORT NSNotificationName const MetasequoiaStandalonePreferencesDidCloseNotification;
FOUNDATION_EXPORT NSNotificationName const MetasequoiaFloatingToolbarDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const MetasequoiaTraditionalChineseOutputDidChangeNotification;

bool MetasequoiaShouldShowPreferences(int argc, const char *argv[]);

@interface MetasequoiaPreferencesWindowController : NSWindowController <NSWindowDelegate>
+ (instancetype)sharedController;
+ (void)prepareInputSessionsForLearnedDataReset;
+ (NSDictionary<NSString *, id> *)cloudSettingsSnapshot;
+ (NSNumber *)validateCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values;
+ (NSNumber *)applyCloudSettingsSnapshot:(NSDictionary<NSString *, id> *)values;
+ (NSInteger)storedScheme;
+ (void)setStoredScheme:(NSInteger)scheme;
+ (NSString *)storedShuangpinSchema;
+ (void)setShuangpinSchema:(NSString *)schema;
+ (BOOL)storedAutocorrectEnabled;
+ (void)setAutocorrectEnabled:(BOOL)enabled;
+ (BOOL)storedHelpcodeEnabled;
+ (void)setHelpcodeEnabled:(BOOL)enabled;
+ (NSInteger)storedQuanpinHelpcodeSchema;
+ (void)setQuanpinHelpcodeSchema:(NSInteger)schema;
+ (NSInteger)storedShuangpinHelpcodeSchema;
+ (void)setShuangpinHelpcodeSchema:(NSInteger)schema;
+ (BOOL)storedChinesePunctuationEnabled;
+ (void)setChinesePunctuationEnabled:(BOOL)enabled;
+ (NSString *)storedCandidateSkin;
+ (void)setStoredCandidateSkin:(NSString *)skinId;
+ (NSInteger)storedCandidatePanelStyle;
+ (void)setCandidatePanelStyle:(NSInteger)style;
+ (NSInteger)storedCandidatePageSize;
+ (void)setCandidatePageSize:(NSInteger)pageSize;
+ (NSInteger)storedCandidateFontSize;
+ (void)setCandidateFontSize:(NSInteger)fontSize;
+ (BOOL)storedCandidateTranslationsEnabled;
+ (void)setCandidateTranslationsEnabled:(BOOL)enabled;
+ (NSInteger)storedCandidatePageShortcut;
+ (void)setCandidatePageShortcut:(NSInteger)shortcut;
+ (BOOL)storedCandidateLearningEnabled;
+ (void)setCandidateLearningEnabled:(BOOL)enabled;
+ (NSString *)storedFrequencyAdjustmentMode;
+ (void)setFrequencyAdjustmentMode:(NSString *)mode;
+ (NSInteger)storedFrequencyTriggerCount;
+ (void)setFrequencyTriggerCount:(NSInteger)count;
+ (NSInteger)storedFrequencyLinearStep;
+ (void)setFrequencyLinearStep:(NSInteger)step;
+ (BOOL)storedEnglishInputMode;
+ (void)setEnglishInputMode:(BOOL)enabled;
+ (BOOL)storedInputModeShortcutEnabled;
+ (BOOL)storedInputModeHUDEnabled;
+ (void)setInputModeHUDEnabled:(BOOL)enabled;
+ (void)setInputModeShortcutEnabled:(BOOL)enabled;
+ (BOOL)storedFullWidthInputEnabled;
+ (void)setFullWidthInputEnabled:(BOOL)enabled;
+ (BOOL)storedFloatingToolbarEnabled;
+ (void)setFloatingToolbarEnabled:(BOOL)enabled;
+ (BOOL)storedTraditionalChineseOutputEnabled;
+ (void)setTraditionalChineseOutputEnabled:(BOOL)enabled;
+ (BOOL)storedWubiAutoCommitUniqueEnabled;
+ (void)setWubiAutoCommitUniqueEnabled:(BOOL)enabled;
+ (BOOL)storedWubiMixedPinyinEnabled;
+ (void)setWubiMixedPinyinEnabled:(BOOL)enabled;
+ (BOOL)storedWubiCodeHintEnabled;
+ (void)setWubiCodeHintEnabled:(BOOL)enabled;
+ (BOOL)storedShuangpinKeymapEnabled;
+ (void)setShuangpinKeymapEnabled:(BOOL)enabled;
+ (BOOL)storedLocalInputModesEnabled;
+ (void)setLocalInputModesEnabled:(BOOL)enabled;
- (void)showAndActivate;
- (void)showAndActivateForStandaloneLaunch;
@end
