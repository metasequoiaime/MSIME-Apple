#pragma once
#import <AppKit/AppKit.h>
#include "CandidateSkin.h"

FOUNDATION_EXPORT NSNotificationName const MSIMEAppearanceDidChangeNotification;
FOUNDATION_EXPORT NSNotificationName const MSIMETranslationPreferencesDidSaveNotification;

// macOS-only presentation settings; never change Engine composition/configuration.
@interface MSIMEAppearancePreferences : NSWindowController
+ (instancetype)sharedPreferences;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults;
- (instancetype)initWithDefaults:(NSUserDefaults *)defaults skinsRoot:(NSURL *)root;
- (void)reloadSkins;
- (BOOL)applyCloudSettingsSnapshot:(NSDictionary *)values;
- (NSDictionary *)cloudSettingsSnapshot;
- (NSWindowController *)skinCatalogController;
- (void)setTranslationPreferencesDirectory:(NSString *)directory;
/// Applies only settings owned by this window to an existing shared Preferences object.
- (NSDictionary<NSString *, id> *)sharedPreferencesByMerging:(NSDictionary<NSString *, id> *)snapshot;
- (msime::mac::ResolvedSkin)resolvedSkinForDark:(BOOL)dark;
@property(nonatomic, readonly) NSImage *decorationImage;
@property(nonatomic, readonly) NSURL *skinsRoot;
@property(nonatomic) BOOL vertical;
@property(nonatomic) BOOL candidateFollowCursor;
@property(nonatomic, copy) NSString *inputScheme;
@property(nonatomic, copy) NSString *shuangpinProfile;
@property(nonatomic) BOOL shuangpinPreeditUsesRaw;
@property(nonatomic) NSUInteger fontSize;
@property(nonatomic, copy) NSString *fontFamily;
@property(nonatomic, copy) NSArray<NSString *> *fallbackFonts;
- (NSFont *)candidateFontOfSize:(CGFloat)size;
@property(nonatomic) NSUInteger preeditFontSize;
@property(nonatomic) BOOL showsCandidatePreedit;
@property(nonatomic, copy) NSString *candidateTextColor;
- (NSColor *)candidateTextColorWithDefault:(NSColor *)color;
@property(nonatomic) NSUInteger pageSize;
@property(nonatomic, copy) NSString *skinID;
// Native routing preferences; English passes keys through without preparing Engine.
@property(nonatomic) BOOL englishMode;
@property(nonatomic, copy) NSString *defaultImeMode;
@property(nonatomic, copy) NSString *imeModeScope;
- (void)activateInputModeForApplication:(NSString *)identifier;
- (void)lockActiveInputMode;
- (void)resetGlobalInputMode;
@property(nonatomic) BOOL inputModeShortcut;
@property(nonatomic) BOOL shiftTapShortcut;
@property(nonatomic) BOOL controlTapShortcut;
@property(nonatomic) BOOL controlOptionSpaceShortcut;
@property(nonatomic) BOOL characterSetShortcut;
@property(nonatomic) BOOL traditionalOutput;
@property(nonatomic) BOOL fullWidthInput;
@property(nonatomic) BOOL chinesePunctuation;
@property(nonatomic) BOOL pairedPunctuation;
@property(nonatomic, copy) NSString *punctuationLock;
@property(nonatomic) BOOL mixedEnglishInput;
@property(nonatomic) NSInteger mixedEnglishMinimumPrefix;
@property(nonatomic) BOOL mixedEmojiInput;
@property(nonatomic) BOOL mixedKaomojiInput;
@property(nonatomic) BOOL autocorrect;
@property(nonatomic) BOOL candidateLearningEnabled;
@property(nonatomic, copy) NSString *frequencyAdjustmentMode;
@property(nonatomic) NSInteger frequencyTriggerCount;
@property(nonatomic) NSInteger frequencyLinearStep;
@property(nonatomic) BOOL fuzzyPinyinEnabled;
- (BOOL)fuzzyPinyinRuleEnabled:(NSString *)rule;
- (void)setFuzzyPinyinRule:(NSString *)rule enabled:(BOOL)enabled;
@property(nonatomic) BOOL cloudCandidates;
@property(nonatomic) BOOL candidateTranslations;
@property(nonatomic) BOOL autocorrectTransposition;
@property(nonatomic) BOOL autocorrectNeighbor;
// Legacy fallback for both schemes; setting it explicitly still sets both.
@property(nonatomic) BOOL helpcodeEnabled;
@property(nonatomic) BOOL quanpinHelpcodeEnabled;
@property(nonatomic) BOOL shuangpinHelpcodeEnabled;
- (void)applySharedAssistancePreferences:(NSDictionary *)preferences;
- (NSDictionary *)helpcodeOptionsForScheme:(NSString *)scheme;
@property(nonatomic) BOOL shuangpinKeymap;
@property(nonatomic) BOOL wubiAutoCommitUnique;
@property(nonatomic) BOOL floatingToolbarEnabled;
@property(nonatomic) BOOL floatingToolbarPunctuation;
@property(nonatomic) BOOL floatingToolbarFullWidth;
@property(nonatomic) BOOL floatingToolbarCharacterSet;
@property(nonatomic) BOOL floatingToolbarEmoji;
@property(nonatomic) BOOL floatingToolbarScreenKeyboard;
@property(nonatomic) BOOL floatingToolbarSettings;
@property(nonatomic) NSInteger floatingToolbarScalePercent;
@property(nonatomic) NSInteger floatingToolbarFontSize;
/// Refresh shared toolbar options without persisting them locally.
- (void)applySharedToolbarPreferences:(NSDictionary *)preferences;
/// Cache shared visibility without emitting a local-save notification.
- (void)applySharedToolbarVisibility:(BOOL)enabled;
- (BOOL)localModeEnabled:(NSString *)mode;
- (void)setLocalMode:(NSString *)mode enabled:(BOOL)enabled;
/// Refresh shared state without emitting a local-save notification.
- (void)applySharedLocalModes:(NSDictionary *)modes;
/// Cache input choices from shared storage without saving them back.
- (void)applySharedInputPreferences:(NSDictionary *)preferences;
- (void)applySharedCandidatePreferences:(NSDictionary *)preferences;
// 0: -/= (default), 1: [/], 2: Page Up/Page Down only.
@property(nonatomic) NSInteger pageShortcut;
- (BOOL)navigationEnabled:(NSString *)key;
- (void)setNavigation:(NSString *)key enabled:(BOOL)enabled;
- (NSDictionary *)wordCharacterOptions;
- (void)setWordCharacterEnabled:(BOOL)enabled keys:(NSString *)keys;
@end
