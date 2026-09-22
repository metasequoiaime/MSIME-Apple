#pragma once
#import <AppKit/AppKit.h>
#import "../../../../shared/apple/TextClient.h"
#include "../candidate/CandidateSkin.h"

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
/// Show the short non-activating Chinese/English mode badge near the caret.
@property(nonatomic) BOOL inputModeHUD;
@property(nonatomic, copy) NSString *inputScheme;
@property(nonatomic, copy) NSString *shuangpinProfile;
@property(nonatomic) BOOL shuangpinPreeditUsesRaw;
/// Allow Pinyin fallback when a Wubi code has no Wubi candidates.
@property(nonatomic) BOOL wubiMixedPinyinEnabled;
/// Shared inline composition display: raw keys, formatted pinyin, or hidden.
@property(nonatomic, readonly) MSIMEInlinePreeditStyle inlinePreeditStyle;
@property(nonatomic) NSUInteger fontSize;
@property(nonatomic, copy) NSString *fontFamily;
/// Optional leading face for Latin glyphs in the candidate cascade.
@property(nonatomic, copy) NSString *candidateEnglishFont;
@property(nonatomic, copy) NSArray<NSString *> *fallbackFonts;
- (NSFont *)candidateFontOfSize:(CGFloat)size;
- (NSFont *)candidateFontOfSize:(CGFloat)size englishFirst:(BOOL)englishFirst;
@property(nonatomic) NSUInteger preeditFontSize;
@property(nonatomic) BOOL showsCandidatePreedit;
@property(nonatomic, copy) NSString *candidateTextColor;
- (NSColor *)candidateTextColorWithDefault:(NSColor *)color;
- (NSColor *)candidateNumberColorWithDefault:(NSColor *)color;
- (NSColor *)candidateAccentColorWithDefault:(NSColor *)color;
- (NSColor *)candidateSelectedColorWithDefault:(NSColor *)color;
- (NSColor *)candidateHoverColorWithDefault:(NSColor *)color;
- (NSColor *)candidateSurfaceColorWithDefault:(NSColor *)color;
- (NSColor *)candidateBorderColorWithDefault:(NSColor *)color;
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
@property(nonatomic) BOOL fullWidthShortcut;
@property(nonatomic) BOOL traditionalOutput;
@property(nonatomic) BOOL fullWidthInput;
@property(nonatomic) BOOL chinesePunctuation;
@property(nonatomic) BOOL smartPunctuation;
@property(nonatomic) BOOL smartPunctuationRepeatToChinese;
/// A space after a just-committed Chinese mark rewrites it as ASCII. Off by default, like the rest of the
/// family on the Windows baseline: it changes a character the user already saw land.
@property(nonatomic) BOOL smartPunctuationSpaceConvert;
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
/// Offline Engine glossary lookup; independent from online candidate translation providers.
@property(nonatomic) BOOL candidateEnglishGloss;
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
/// The handwriting panel and voice buttons, which only this client's toolbar has.
@property(nonatomic) BOOL floatingToolbarHandwriting;
@property(nonatomic) BOOL floatingToolbarScreenKeyboard;
@property(nonatomic) BOOL floatingToolbarVoice;
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
/// The native candidate panel appearance override. A nil value means AppKit follows the system.
@property(nonatomic, readonly) NSAppearance *candidateAppearanceOverride;
@property(nonatomic, readonly) BOOL candidateAppearanceOverrideConfigured;
// 0: -/= (default), 1: [/], 2: Page Up/Page Down only.
@property(nonatomic) NSInteger pageShortcut;
- (BOOL)navigationEnabled:(NSString *)key;
- (void)setNavigation:(NSString *)key enabled:(BOOL)enabled;
- (NSDictionary *)wordCharacterOptions;
- (void)setWordCharacterEnabled:(BOOL)enabled keys:(NSString *)keys;
@end
