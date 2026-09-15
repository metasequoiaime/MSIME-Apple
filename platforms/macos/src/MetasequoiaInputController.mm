#import "MetasequoiaInputController.h"

// Implemented in CandidateGlossClient.swift and BackendAccountBridge.swift.
extern "C" void MSIMEFetchCandidateGlosses(const char *wordsJSON, const char *primaryCode, const char *secondaryCode,
                                           unsigned long long generation);
extern "C" void MSIMEEnsureAnonymousAccount(void);

#import "DictionaryInstaller.h"
#include "DictionaryRuntime.h"
#include "../../../shared/apple-bridge/DictionarySessionLease.h"
#import "FloatingToolbarPanel.h"
#import "InputModeHUDPanel.h"
#import "ChineseTextConversion.h"
#include "CandidateFontSize.h"
#import "CandidatePanel.h"
#include "CandidateDisplay.h"
#include "CandidatePageSize.h"
#include "CandidatePanelStyle.h"
#import "InputMenu.h"
#include "InputModeRouting.h"
#include "FullWidthInput.h"
#include "FrequencyAdjustmentPreference.h"
#include "HelpcodeSchemaPreference.h"
#include "InputSchemePreference.h"
#include "WubiCommitPolicy.h"
#import "PreferencesWindowController.h"
#import "VoiceInputService.h"
#import "VoiceSettings.h"
#import "ShuangpinKeymapPanel.h"
#import "UpdateController.h"
#import "TranslationClient.h"
#include "StringConversion.h"
#include "CandidateSelectionState.h"
#include "CandidateTranslation.h"
#include "InputControllerKeyRouting.h"
#include "InputBehaviorPreferences.h"
#include "CandidateTranslationLanguage.h"
#include <metasequoia/session.h>
#include "contracts/assets/assets.h"
#include "english/english_dictionary.h"
#include "contracts/punctuation/policy.h"
#include "quanpin/quanpin_utils.h"

#import <Carbon/Carbon.h>

#include <memory>
#include <cmath>
#include <string>

namespace
{
bool IsEnginePunctuationCharacter(char character)
{
    return std::string(",.?!;:\"'()[]<>\\`$^_").find(character) != std::string::npos;
}
constexpr NSTimeInterval kDictionaryRetryDelay = 2.0;

// The Engine split its single autocorrect flag into a per-type mask. The one preference this app
// exposes is still a checkbox, and the flag it replaced corrected transpositions and neighbour
// substitutions together, so an enabled checkbox means every type the Engine offers. Leaving a type
// out here would silently narrow what an existing user already had switched on.
constexpr unsigned kAllQuanpinAutocorrectTypes = quanpin::kAutocorrectTransposition | quanpin::kAutocorrectNeighbor;

constexpr unsigned QuanpinAutocorrectTypesFor(bool enabled)
{
    return enabled ? kAllQuanpinAutocorrectTypes : 0u;
}

struct SessionPreferences
{
    SchemeType scheme;
    std::string shuangpinSchema;
    bool autocorrectEnabled;
    bool helpcodeEnabled;
    std::string helpcodeSchema;
    bool chinesePunctuationEnabled;
    metasequoia::mac::CandidatePanelStyle candidatePanelStyle;
    size_t candidatePageSize;
    size_t candidateFontSize;
    bool candidateLearningEnabled;
    metasequoia::FrequencyAdjustmentOptions frequency;
    bool wubiAutoCommitUniqueEnabled;
    bool wubiMixedPinyinEnabled;
    bool mixedEnglish;
    size_t englishMinimumPrefix;
};

SessionPreferences ReadSessionPreferences()
{
    const SchemeType scheme = MetasequoiaInputInteger(@"japaneseMode", 0, 0, 1)
                                  ? SchemeType::JapaneseRomaji
                                  : metasequoia::mac::EngineSchemeForStoredPreference(
                                        static_cast<int>([MetasequoiaPreferencesWindowController storedScheme]));
    const NSInteger helpcodeSchema = scheme == SchemeType::Shuangpin
                                         ? [MetasequoiaPreferencesWindowController storedShuangpinHelpcodeSchema]
                                         : [MetasequoiaPreferencesWindowController storedQuanpinHelpcodeSchema];
    const std::string shuangpinSchema = [MetasequoiaPreferencesWindowController storedShuangpinSchema].UTF8String;
    return {
        scheme,
        shuangpinSchema,
        [MetasequoiaPreferencesWindowController storedAutocorrectEnabled] == YES,
        MetasequoiaInputFlag(scheme == SchemeType::Shuangpin ? @"shuangpinHelpcodeEnabled" : @"quanpinHelpcodeEnabled",
                             [MetasequoiaPreferencesWindowController storedHelpcodeEnabled]) == YES,
        metasequoia::mac::HelpcodeSchemaIdentifier(static_cast<int>(helpcodeSchema)),
        [MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled] == YES,
        metasequoia::mac::NormalizeCandidatePanelStyle(
            [MetasequoiaPreferencesWindowController storedCandidatePanelStyle]),
        metasequoia::mac::NormalizeCandidatePageSize(
            static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidatePageSize])),
        metasequoia::mac::NormalizeCandidateFontSize(
            static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidateFontSize])),
        [MetasequoiaPreferencesWindowController storedCandidateLearningEnabled] == YES,
        metasequoia::mac::EngineFrequencyOptions(
            [MetasequoiaPreferencesWindowController storedCandidateLearningEnabled] == YES,
            [MetasequoiaPreferencesWindowController storedFrequencyAdjustmentMode].UTF8String,
            static_cast<int>([MetasequoiaPreferencesWindowController storedFrequencyTriggerCount]),
            static_cast<int>([MetasequoiaPreferencesWindowController storedFrequencyLinearStep])),
        [MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled] == YES,
        [MetasequoiaPreferencesWindowController storedWubiMixedPinyinEnabled] == YES,
        MetasequoiaInputInteger(@"mixedEnglish", 0, 0, 1) != 0,
        static_cast<size_t>(MetasequoiaInputInteger(@"englishMinimumPrefix", 2, 1, 10)),
    };
}

// Helpcode preferences only affect pinyin schemes; changing that preference must not rebuild a Wubi session.
bool SchemeUsesHelpcodes(SchemeType scheme)
{
    return scheme == SchemeType::Quanpin || scheme == SchemeType::Shuangpin;
}

bool SessionMatchesPreferences(const metasequoia::SessionOptions &options, const SessionPreferences &preferences)
{
    const bool helpcodeMatches =
        !SchemeUsesHelpcodes(preferences.scheme) || options.helpcode == preferences.helpcodeEnabled;
    const bool shuangpinMatches =
        preferences.scheme != SchemeType::Shuangpin || options.shuangpin_profile.name == preferences.shuangpinSchema;
    const bool wubiMixedPinyinMatches =
        preferences.scheme != SchemeType::Wubi || options.wubi.mixed_pinyin == preferences.wubiMixedPinyinEnabled;
    return options.scheme == preferences.scheme && shuangpinMatches &&
           options.autocorrect_types == QuanpinAutocorrectTypesFor(preferences.autocorrectEnabled) && helpcodeMatches &&
           options.chinese_punctuation == preferences.chinesePunctuationEnabled &&
           options.learning == preferences.candidateLearningEnabled && wubiMixedPinyinMatches &&
           options.frequency.mode == preferences.frequency.mode &&
           options.frequency.trigger_count == preferences.frequency.trigger_count &&
           options.frequency.linear_step == preferences.frequency.linear_step &&
           options.english.mixed_candidates == preferences.mixedEnglish &&
           options.english.minimum_prefix == preferences.englishMinimumPrefix;
}
} // namespace

static NSHashTable *LiveDictionaryControllers()
{
    static NSHashTable *controllers = [NSHashTable weakObjectsHashTable];
    return controllers;
}

@interface MetasequoiaInputController () <MetasequoiaFloatingToolbarDelegate, MetasequoiaCandidatePanelDelegate>
@end

@implementation MetasequoiaInputController
{
    std::unique_ptr<metasequoia::apple::DictionarySessionLease> _dictionaryLease;
    std::unique_ptr<metasequoia::Session> _session;
    std::unique_ptr<EnglishDictionary> _translationDictionary;
    // Display positions can differ from Engine indices after pinning.
    std::vector<size_t> _candidateEngineIndices;
    metasequoia::SessionOptions _sessionOptions;
    metasequoia::SessionSnapshot _sessionSnapshot;
    std::string _activeHelpcodeSchema;
    HelpcodeUtils::SharedKeymap _activeHelpcodeKeymap;
    metasequoia::mac::CandidateSelectionState _candidateSelection;
    MetasequoiaCandidatePanel *_candidatePanel;
    MetasequoiaFloatingToolbarPanel *_floatingToolbarPanel;
    MetasequoiaShuangpinKeymapPanel *_shuangpinKeymapPanel;
    NSArray *_candidateData;
    NSArray *_visibleCandidateData;
    NSUInteger _candidatePageSize;
    NSUInteger _candidateHighlightedIndex;
    NSUInteger _candidatePageStart;
    BOOL _candidateLineIdentifiersCollapsed;
    BOOL _wubiAutoCommitUniqueEnabled;
    BOOL _serverActive;
    BOOL _shuangpinKeymapEnabled;
    BOOL _localInputModesEnabled;
    NSTimeInterval _dictionaryRetryAfter;
    id<MetasequoiaVoiceService> _voiceService;
    NSUInteger _voiceGeneration;
    id _voiceMouseMonitor;

    NSURLSessionDataTask *_translationTask;
    NSUInteger _translationGeneration;
    // 组字期间安静下来才发请求。常驻释义意味着每个候选页都要问一整页的词,而一次组字要敲好几下:
    // 不防抖的话 pingguo 七个字母就是七次整页请求,每次都被下一次按键作废,额度全烧在没人看见的
    // 中间态上。
    dispatch_source_t _translationDebounce;
    unichar _lastAsciiPunctuation;
    NSTimeInterval _lastAsciiPunctuationTime;
    metasequoia::mac::SolitaryShiftTracker _solitaryShift;
}

// Main-thread publication first checks every composition, then releases every
// idle session. Cross-process readers remain protected by DictionarySessionLease.
+ (NSNumber *)suspendForCloudDictionarySwitch
{
    if (!NSThread.isMainThread)
        return @NO;
    for (MetasequoiaInputController *controller in LiveDictionaryControllers())
        if (controller->_session && (!controller->_sessionSnapshot.preedit.empty() ||
                                     controller->_sessionSnapshot.local_mode != metasequoia::LocalInputMode::None))
            return @NO;
    for (MetasequoiaInputController *controller in LiveDictionaryControllers())
        [controller prepareForLearnedDataReset:nil];
    return @YES;
}

- (instancetype)initWithServer:(IMKServer *)server delegate:(id)delegate client:(id)inputClient
{
    self = [super initWithServer:server delegate:delegate client:inputClient];
    if (self != nil)
    {
        _candidatePanel = [MetasequoiaCandidatePanel new];
        _candidatePanel.delegate = self;
        _floatingToolbarPanel = [MetasequoiaFloatingToolbarPanel sharedPanel];
        _shuangpinKeymapPanel = [[MetasequoiaShuangpinKeymapPanel alloc] init];
        [_candidatePanel setAttributes:metasequoia::mac::CandidatePanelAttributes(static_cast<size_t>(
                                           [MetasequoiaPreferencesWindowController storedCandidateFontSize]))];

        if (metasequoia::mac::ShouldPrepareInputSession(
                [MetasequoiaPreferencesWindowController storedEnglishInputMode]))
        {
            [self prepareSessionIfNeeded];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(prepareForLearnedDataReset:)
                                                     name:MetasequoiaWillResetLearnedDataNotification
                                                   object:nil];
        for (NSNotificationName notificationName in @[
                 MetasequoiaFloatingToolbarDidChangeNotification,
                 @"MetasequoiaChinesePunctuationDidChangeNotification",
                 @"MetasequoiaEnglishInputModeDidChangeNotification",
                 @"MetasequoiaFullWidthInputDidChangeNotification",
                 MetasequoiaTraditionalChineseOutputDidChangeNotification,
             ])
        {
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(floatingToolbarPreferenceDidChange:)
                                                         name:notificationName
                                                       object:nil];
        }
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(wubiCodeHintPreferenceDidChange:)
                                                     name:@"MetasequoiaWubiCodeHintDidChangeNotification"
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(candidateTranslationsDidArrive:)
                                                     name:@"MetasequoiaCandidateTranslationsDidArrive"
                                                   object:nil];
    }
    return self;
}

- (void)dealloc
{
    [_translationTask cancel];
    if (_translationDebounce != nil)
        dispatch_source_cancel(_translationDebounce);
    [_voiceService cancel];
    if (_voiceMouseMonitor)
        [NSEvent removeMonitor:_voiceMouseMonitor];
    [_floatingToolbarPanel deactivateForDelegate:self];
    [_shuangpinKeymapPanel orderOut:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)refreshFloatingToolbar
{
    [_floatingToolbarPanel
                 updateEnglishInputMode:[MetasequoiaPreferencesWindowController storedEnglishInputMode]
              chinesePunctuationEnabled:[MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled]
                       fullWidthEnabled:[MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]
        traditionalChineseOutputEnabled:[MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled]];
    if (!_serverActive || _floatingToolbarPanel.toolbarDelegate != self)
    {
        return;
    }
    [_floatingToolbarPanel setVisible:[MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]
                          forDelegate:self];
}

- (void)floatingToolbarPreferenceDidChange:(NSNotification *)notification
{
    [self refreshFloatingToolbar];
    if ([notification.name isEqualToString:MetasequoiaTraditionalChineseOutputDidChangeNotification] && _serverActive &&
        _session != nullptr && !_sessionSnapshot.preedit.empty())
    {
        [self refreshCandidatePanelPreservingSelection];
    }
}

// The hint is drawn from the snapshot already on screen, so a composition in progress can take the
// new setting where a session option would have had to wait for the composition to end.
- (void)wubiCodeHintPreferenceDidChange:(NSNotification *)notification
{
    (void)notification;
    if (_serverActive && _session != nullptr && !_sessionSnapshot.preedit.empty())
    {
        [self refreshCandidatePanelPreservingSelection];
    }
}

// The account model answers for a whole page at once, so one reply fills several cache entries. A
// reply for a composition that has already moved on is dropped rather than drawn over the new one.
- (void)candidateTranslationsDidArrive:(NSNotification *)notification
{
    NSDictionary *info = notification.userInfo;
    NSDictionary<NSString *, NSString *> *translations = info[@"translations"];
    NSDictionary<NSString *, NSString *> *secondaryArriving = info[@"secondaryTranslations"];
    const BOOL hasPrimary = [translations isKindOfClass:[NSDictionary class]];
    const BOOL hasSecondary = [secondaryArriving isKindOfClass:[NSDictionary class]];
    // 两种语言是分别发过来的,只带第二条的那批同样要收 —— 原来这里要求 translations 必须在,于是日文
    // 那条通知整条被丢掉。
    if ((!hasPrimary && !hasSecondary) || _session == nullptr)
        return;
    // 代际只决定要不要重绘,不决定要不要收下。The cache is keyed by language and word, so a reply that
    // arrives after the next keystroke is still the right gloss for the word it names. Dropping it on
    // the generation meant that typing at any speed at all threw every answer away: the model takes
    // seconds, every keystroke rebuilds the panel and bumps the generation, and the request issued
    // for the new one was in turn cancelled by the keystroke after it.
    const auto &languageEntry =
        metasequoia::mac::CandidateTranslationLanguageAt(static_cast<std::size_t>(MetasequoiaInputInteger(
            @"translationLanguage", 0, 0, metasequoia::mac::kCandidateTranslationLanguageCount - 1)));
    NSString *language = @(languageEntry.code);
    for (NSString *word in (hasPrimary ? translations : @{}))
    {
        NSString *translation = translations[word];
        // 到达只进内存。落盘要等这个词真的被上屏 —— 见 applyResult: 里的 persistCommittedGloss:。
        if ([word isKindOfClass:[NSString class]] && [translation isKindOfClass:[NSString class]] && translation.length)
            MetasequoiaSharedTranslationCache()[[NSString stringWithFormat:@"%@|%@", language, word]] = translation;
    }
    NSDictionary<NSString *, NSString *> *secondaryTranslations = secondaryArriving;
    const NSInteger secondaryIndex = MetasequoiaSecondaryTranslationLanguageIndex();
    if (secondaryIndex >= 0 && hasSecondary)
    {
        NSString *secondaryLanguage =
            @(metasequoia::mac::CandidateTranslationLanguageAt(static_cast<std::size_t>(secondaryIndex)).code);
        for (NSString *word in secondaryTranslations)
        {
            NSString *translation = secondaryTranslations[word];
            if ([word isKindOfClass:[NSString class]] && [translation isKindOfClass:[NSString class]] &&
                translation.length)
                MetasequoiaSharedSecondaryTranslationCache()[
                    [NSString stringWithFormat:@"%@|%@", secondaryLanguage, word]] = translation;
        }
    }
    // 只让活跃实例重绘,而且用它此刻的会话状态判断,不看这个实例自己那份可能早已过期的快照。
    MetasequoiaInputController *active = gActiveController;
    if (active != nil && active->_session != nullptr && !active->_session->snapshot().preedit.empty())
        [active rebuildCandidatePanelPreservingSelection:YES];
}

- (void)prepareForLearnedDataReset:(NSNotification *)notification
{
    (void)notification;
    [self commitLeadingCandidate:self.client];
    _session.reset();
    _dictionaryLease.reset();
    _candidateSelection.reset();
    _candidateHighlightedIndex = 0;
    _candidatePageStart = 0;
    _candidateLineIdentifiersCollapsed = NO;
    _candidateData = @[];
    _visibleCandidateData = @[];
    [_candidatePanel setCandidateData:_visibleCandidateData];
    [_candidatePanel hide];
    [_shuangpinKeymapPanel orderOut:nil];
    _dictionaryRetryAfter = 0.0;
}

- (void)reloadSessionFromPreferences
{
    [LiveDictionaryControllers() addObject:self];
    const NSInteger storedScheme = [MetasequoiaPreferencesWindowController storedScheme];
    _shuangpinKeymapEnabled = [MetasequoiaPreferencesWindowController storedShuangpinKeymapEnabled];
    if (storedScheme != 1 || !_shuangpinKeymapEnabled)
    {
        [_shuangpinKeymapPanel orderOut:nil];
    }
    if (_session != nullptr && !_sessionSnapshot.preedit.empty())
    {
        // Keep the scheme chosen when this composition began. Preferences from another
        // controller must not change the helpcodes of this live session.
        return;
    }

    const SessionPreferences preferences = ReadSessionPreferences();
    [_candidatePanel setPanelType:metasequoia::mac::CandidatePanelTypeForStyle(preferences.candidatePanelStyle)];
    _candidatePageSize = preferences.candidatePageSize;
    [_candidatePanel setSelectionKeys:metasequoia::mac::CandidateSelectionKeys(_candidatePageSize)];
    [_candidatePanel setAttributes:metasequoia::mac::CandidatePanelAttributes(preferences.candidateFontSize)];
    _wubiAutoCommitUniqueEnabled = preferences.wubiAutoCommitUniqueEnabled;
    const bool helpcodeSchemaMatches = _activeHelpcodeSchema == preferences.helpcodeSchema;
    _activeHelpcodeSchema = preferences.helpcodeSchema;
    _localInputModesEnabled = [MetasequoiaPreferencesWindowController storedLocalInputModesEnabled];
    if (_session != nullptr && helpcodeSchemaMatches && SessionMatchesPreferences(_sessionOptions, preferences) &&
        _sessionOptions.local_modes.unicode == _localInputModesEnabled)
    {
        return;
    }
    if (!_dictionaryLease)
        _dictionaryLease =
            std::make_unique<metasequoia::apple::DictionarySessionLease>(MetasequoiaDictionaryUserDirectory());
    const auto paths = MetasequoiaCurrentDictionaryPaths();
    metasequoia::SessionOptions options;
    options.paths = paths;
    options.scheme = preferences.scheme;
    options.shuangpin_profile = GetShuangpinProfile(preferences.shuangpinSchema);
    options.autocorrect_types = QuanpinAutocorrectTypesFor(preferences.autocorrectEnabled);
    options.helpcode = preferences.helpcodeEnabled;
    options.helpcode_schema = preferences.helpcodeSchema;
    options.chinese_punctuation = preferences.chinesePunctuationEnabled;
    options.learning = preferences.candidateLearningEnabled;
    options.frequency = preferences.frequency;
    options.english.mixed_candidates = preferences.mixedEnglish;
    options.english.minimum_prefix = preferences.englishMinimumPrefix;
    options.wubi.mixed_pinyin = preferences.wubiMixedPinyinEnabled;
    options.local_modes = [self localInputModeOptions];
    _session = std::make_unique<metasequoia::Session>(options);
    _sessionOptions = options;
    _sessionSnapshot = _session->snapshot();
    _activeHelpcodeKeymap = HelpcodeUtils::load_helpcode_keymap(paths.resources, preferences.helpcodeSchema);
    _candidateSelection.reset();
    _candidateHighlightedIndex = 0;
    _candidatePageStart = 0;
    _candidateLineIdentifiersCollapsed = NO;
    _candidateData = @[];
    _visibleCandidateData = @[];
    [_candidatePanel setCandidateData:_visibleCandidateData];
    [_candidatePanel hide];
    [_shuangpinKeymapPanel orderOut:nil];
}

// The engine enables every local input mode by default, but this bundle ships only msime.db. Emoji
// and kaomoji read others.db, temporary English reads english.db and temporary Japanese reads
// dict_japanese.dat, none of which are fetched, so those four could only ever fail. The remaining
// four need nothing beyond what is here: Unicode parses its own input, date and time has a built-in
// provider, quick phrases live in msime.db's quick_parases table, and super jianpin uses the pinyin
// tables. Turning the whole family off by preference keeps Shift+letter inserting a capital.
- (metasequoia::LocalModeOptions)localInputModeOptions
{
    metasequoia::LocalModeOptions options;
    options.unicode = _localInputModesEnabled;
    options.date_time = _localInputModesEnabled;
    options.quick_phrase = _localInputModesEnabled;
    options.super_jianpin = _localInputModesEnabled;
    options.emoji = false;
    options.kaomoji = false;
    options.temporary_english = false;
    options.temporary_japanese = false;
    return options;
}

- (BOOL)prepareSessionIfNeeded
{
    if (_session != nullptr)
    {
        return YES;
    }

    const NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now < _dictionaryRetryAfter)
    {
        return NO;
    }

    NSError *error = nil;
    if (!EnsureMetasequoiaDictionary(&error))
    {
        _dictionaryRetryAfter = now + kDictionaryRetryDelay;
        NSLog(@"Failed to prepare the Metasequoia dictionary: %@", error.localizedDescription);
        return NO;
    }

    _dictionaryRetryAfter = 0.0;
    try
    {
        [self reloadSessionFromPreferences];
    }
    catch (const std::exception &)
    {
        _session.reset();
        _dictionaryLease.reset();
        _dictionaryRetryAfter = now + kDictionaryRetryDelay;
        return NO;
    }
    return _session != nullptr;
}

- (void)activateServer:(id)sender
{
    gActiveController = self;
    [super activateServer:sender];
    // 装完即有账号,不必先去找登录入口。Candidate translation and cloud sync both need one, and every
    // other provider asks for something the user already holds; a fresh install has none of it.
    MSIMEEnsureAnonymousAccount();
    _serverActive = YES;
    _dictionaryRetryAfter = 0.0;
    [NSUserDefaults.standardUserDefaults synchronize];
    if (MetasequoiaInputInteger(@"perApplicationMode", 0, 0, 1))
    {
        NSString *identifier =
            [sender respondsToSelector:@selector(bundleIdentifier)] ? [sender bundleIdentifier] : nil;
        [MetasequoiaPreferencesWindowController setEnglishInputMode:MetasequoiaRememberedEnglishMode(identifier)];
    }
    if (metasequoia::mac::ShouldPrepareInputSession([MetasequoiaPreferencesWindowController storedEnglishInputMode]) &&
        [self prepareSessionIfNeeded])
    {
        [self reloadSessionFromPreferences];
    }
    [self refreshFloatingToolbar];
    [_floatingToolbarPanel activateForDelegate:self
                                       visible:[MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]];
}

- (std::optional<size_t>)engineIndexForDisplayIndex:(NSUInteger)index
{
    if (_session == nullptr || index >= _candidateData.count || index >= _candidateEngineIndices.size())
        return std::nullopt;
    const size_t engineIndex = _candidateEngineIndices[index];
    const auto current = _session->snapshot();
    if (engineIndex >= current.candidates.size() || engineIndex >= _sessionSnapshot.candidates.size() ||
        current.candidates[engineIndex].word != _sessionSnapshot.candidates[engineIndex].word)
        return std::nullopt;
    return engineIndex;
}

- (metasequoia::KeyResult)selectDisplayedCandidateAtIndex:(NSUInteger)index
{
    if (const auto engineIndex = [self engineIndexForDisplayIndex:index])
        return _session->select(*engineIndex);
    return {};
}

- (metasequoia::KeyResult)handlePunctuation:(char)character client:(id)sender
{
    // Finish the displayed selection before Engine punctuation auto-commits candidate zero.
    [self commitLeadingCandidate:sender];
    if (!_session->snapshot().preedit.empty())
    {
        metasequoia::KeyResult result;
        result.handled = true;
        return result;
    }
    return _session->punctuation(character);
}

- (void)trackCandidateAtIndex:(NSUInteger)index
{
    const auto engineIndex = [self engineIndexForDisplayIndex:index];
    if (!engineIndex)
    {
        return;
    }

    _candidateSelection.update(*engineIndex, _sessionSnapshot.candidates[*engineIndex].word);
    _candidateHighlightedIndex = index;
    _candidatePageStart = metasequoia::mac::CandidatePageStart(index, _candidateData.count, _candidatePageSize);
}

- (void)showCurrentCandidatePage
{
    // On macOS 26, selectionKeys does not reliably limit the visible list.
    // Own page boundaries here; retain global display positions on each string.
    const NSUInteger count = std::min(_candidatePageSize, _candidateData.count - _candidatePageStart);
    _visibleCandidateData = [_candidateData subarrayWithRange:NSMakeRange(_candidatePageStart, count)];
    _candidateLineIdentifiersCollapsed = NO;
    _candidatePanel.hasPreviousPage = _candidatePageStart > 0;
    _candidatePanel.hasNextPage = _candidatePageStart + count < _candidateData.count;
    NSRect caretRect = NSZeroRect;
    [self.client attributesForCharacterIndex:0 lineHeightRectangle:&caretRect];
    _candidatePanel.caretRect = caretRect;
    _candidatePanel.preedit = MetasequoiaStringFromUtf8(_sessionSnapshot.preedit);
    [_candidatePanel setCandidateData:_visibleCandidateData];
    [_candidatePanel show:kIMKLocateCandidatesBelowHint];
    if (count >= 2)
    {
        const NSInteger first = [_candidatePanel candidateIdentifierAtLineNumber:0];
        const NSInteger second = [_candidatePanel candidateIdentifierAtLineNumber:1];
        _candidateLineIdentifiersCollapsed = first != NSNotFound && first == second;
    }
}

- (void)candidatePanelPreviousPage
{
    if (_candidatePageSize > 0 && _candidatePageStart >= _candidatePageSize)
    {
        const NSUInteger target = _candidatePageStart - _candidatePageSize;
        [self selectCandidateAtIndex:target pageStart:target];
    }
}

- (void)candidatePanelNextPage
{
    if (_candidatePageSize > 0 && _candidatePageStart + _candidatePageSize < _candidateData.count)
    {
        const NSUInteger target = _candidatePageStart + _candidatePageSize;
        [self selectCandidateAtIndex:target pageStart:target];
    }
}

- (BOOL)selectCandidateAtIndex:(NSUInteger)index pageStart:(NSUInteger)pageStart
{
    if (index >= _candidateData.count || index < pageStart || index - pageStart >= _candidatePageSize)
    {
        return NO;
    }
    const NSUInteger previousPageStart = _candidatePageStart;
    const NSUInteger previousIndex = _candidateHighlightedIndex;
    if (pageStart != _candidatePageStart)
    {
        _candidatePageStart = pageStart;
        [self showCurrentCandidatePage];
    }
    const NSUInteger line = index - pageStart;
    const NSInteger identifier = [_candidatePanel candidateIdentifierAtLineNumber:static_cast<NSInteger>(line)];
    const BOOL lineMappingIsUsable =
        !_candidateLineIdentifiersCollapsed && identifier != NSNotFound &&
        [_candidatePanel lineNumberForCandidateWithIdentifier:identifier] == static_cast<NSInteger>(line);
    BOOL selected = NO;
    if (lineMappingIsUsable)
    {
        selected = [_candidatePanel selectCandidateWithIdentifier:identifier] &&
                   [[_candidatePanel selectedCandidateString].string isEqualToString:[_candidateData[index] string]];
    }
    else if (_candidateLineIdentifiersCollapsed && NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26)
    {
        // This workaround takes an ordinal within the data passed to the panel,
        // which is now the current page, not the complete engine candidate list.
        selected = [_candidatePanel selectCandidateWithIdentifier:static_cast<NSInteger>(line)];
    }
    if (selected)
    {
        _candidateSelection.begin_navigation();
        [self trackCandidateAtIndex:index];
        return YES;
    }
    if (previousPageStart != _candidatePageStart)
    {
        _candidatePageStart = previousPageStart;
        [self showCurrentCandidatePage];
        [self selectCandidateAtIndex:previousIndex pageStart:previousPageStart];
    }
    return NO;
}

- (BOOL)handleEvent:(NSEvent *)event client:(id)sender
{
    if (event.type == NSEventTypeFlagsChanged)
    {
        [self handleSolitaryShiftFlags:event client:sender];
        // Shift produces no text, and swallowing the flag change would keep it from the client that
        // still needs to know the key is down -- shift-clicking a selection, for one.
        return NO;
    }
    if (event.type != NSEventTypeKeyDown)
    {
        return NO;
    }
    // Whatever this key turns out to be, Shift was not tapped on its own.
    _solitaryShift.keyDown();
    const NSEventModifierFlags voiceModifiers =
        event.modifierFlags & (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand |
                               NSEventModifierFlagShift);
    if (event.keyCode == 9 && voiceModifiers == (NSEventModifierFlagControl | NSEventModifierFlagOption))
    {
        if (!event.isARepeat)
            [self toggleVoiceInput:sender];
        return YES;
    }
    if (_voiceService.active)
    {
        [self cancelVoiceInput];
        if (event.keyCode == 53)
            return YES;
    }
    const NSEventModifierFlags inputModeModifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    // Both toggles swallow their repeats. Holding the chord past the system repeat delay used to
    // flip the persisted preference once per repeat and land on whichever parity the repeat count
    // reached, which is the same reason the voice shortcut above guards on isARepeat.
    if (metasequoia::mac::ShouldToggleInputMode([MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled],
                                                event.keyCode, inputModeModifiers))
    {
        if (!event.isARepeat)
        {
            [self setEnglishInputMode:![MetasequoiaPreferencesWindowController storedEnglishInputMode] client:sender];
        }
        return YES;
    }
    if ([MetasequoiaPreferencesWindowController storedEnglishInputMode])
    {
        [_shuangpinKeymapPanel orderOut:nil];
        return NO;
    }
    if (metasequoia::mac::IsFullWidthInputToggle(event.keyCode, inputModeModifiers))
    {
        if (!event.isARepeat)
        {
            [MetasequoiaPreferencesWindowController
                setFullWidthInputEnabled:![MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]];
        }
        return YES;
    }
    // Full-width conversion deliberately happens after the session has declined the key, in the
    // !result.handled branch below. Converting letters up here instead made Chinese input
    // impossible: the guard was "no composition is running", which is exactly the state every
    // composition starts from, so the first letter was always committed full-width and the engine
    // never saw a keystroke. Lowercase letters compose; the capitals and punctuation the engine
    // does not take still come back through the fallback and are converted there.
    if (![self prepareSessionIfNeeded])
    {
        return NO;
    }

    [self reloadSessionFromPreferences];
    const NSEventModifierFlags modifiers = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    // ⌥数字 上屏那一格的第一条释义,⌃数字 上屏第二条。数字键本身仍然选候选词 —— 它是最贵的按键,
    // 不能拿去买「偶尔想上屏一次译文」这个动作。没有释义就落回下面的通用修饰键处理。
    if ([self insertGlossForModifiedDigit:event modifiers:modifiers client:sender])
    {
        return YES;
    }
    if ((modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0)
    {
        [self commitLeadingCandidate:sender];
        return NO;
    }

    // Captured before the key is dispatched: a commit clears the local mode, and applyResult still
    // needs to know which one produced the text it is inserting.
    const metasequoia::LocalInputMode localModeForKey = _sessionSnapshot.local_mode;
    metasequoia::KeyResult result;
    const BOOL candidatePageShortcutModified =
        (modifiers & (NSEventModifierFlagShift | NSEventModifierFlagCommand | NSEventModifierFlagControl |
                      NSEventModifierFlagOption)) != 0;
    NSString *charactersIgnoringModifiers = event.charactersIgnoringModifiers;
    const char candidatePageShortcutCharacter =
        charactersIgnoringModifiers.length == 1 && [charactersIgnoringModifiers characterAtIndex:0] <= 0x7f
            ? static_cast<char>([charactersIgnoringModifiers characterAtIndex:0])
            : '\0';
    if (charactersIgnoringModifiers.length == 1 &&
        metasequoia::punctuation_contract::is_supported(candidatePageShortcutCharacter) &&
        MetasequoiaInputFlag(@"alwaysEnglishPunctuation") && !MetasequoiaInputFlag(@"alwaysChinesePunctuation") &&
        _sessionSnapshot.preedit.empty())
    {
        if (MetasequoiaInputFlag(@"repeatPunctuation") && _lastAsciiPunctuation == candidatePageShortcutCharacter &&
            [NSDate timeIntervalSinceReferenceDate] - _lastAsciiPunctuationTime <= 2.0)
        {
            id<IMKTextInput> inputClient = sender;
            NSRange selected = [inputClient selectedRange];
            if (selected.location != NSNotFound && selected.location > 0)
            {
                const char *mapped = metasequoia::punctuation_contract::simple_output(candidatePageShortcutCharacter);
                NSString *replacement = mapped ? MetasequoiaStringFromUtf8(mapped) : @"";
                if (replacement.length)
                {
                    [sender insertText:replacement replacementRange:NSMakeRange(selected.location - 1, 1)];
                    _lastAsciiPunctuation = 0;
                    return YES;
                }
            }
        }
        [sender insertText:charactersIgnoringModifiers replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
        _lastAsciiPunctuation = candidatePageShortcutCharacter;
        _lastAsciiPunctuationTime = [NSDate timeIntervalSinceReferenceDate];
        return YES;
    }
    // 智能标点:中文标点状态下,逗号/句点/冒号紧跟在数字或字母后面时输出英文的那一个,和 Windows 一致。
    // 1 + . 得到 1. 而不是 1。 —— 写小数、版本号、序号时要的就是这个。
    //
    // 判断只能在这一层做:前一个字符属于宿主文档,引擎看不到它,所以命中时直接插入英文标点,不再经过
    // PunctuationPolicy 的中文转换。设置面板里那个复选框此前没有任何一处读它,勾了不起作用。
    if (charactersIgnoringModifiers.length == 1 && _sessionSnapshot.preedit.empty() &&
        MetasequoiaInputFlag(@"smartPunctuation") && !MetasequoiaInputFlag(@"alwaysChinesePunctuation") &&
        !MetasequoiaInputFlag(@"alwaysEnglishPunctuation"))
    {
        const unichar typed = [charactersIgnoringModifiers characterAtIndex:0];
        if (typed == ',' || typed == '.' || typed == ':')
        {
            id<IMKTextInput> inputClient = sender;
            const NSRange selected = [inputClient selectedRange];
            if (selected.location != NSNotFound && selected.location > 0)
            {
                NSAttributedString *before =
                    [inputClient attributedSubstringFromRange:NSMakeRange(selected.location - 1, 1)];
                const NSString *previous = before.string;
                if (previous.length == 1)
                {
                    const unichar character = [previous characterAtIndex:0];
                    const BOOL latinOrDigit = (character >= '0' && character <= '9') ||
                                              (character >= 'a' && character <= 'z') ||
                                              (character >= 'A' && character <= 'Z');
                    if (latinOrDigit)
                    {
                        [sender insertText:charactersIgnoringModifiers
                            replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
                        return YES;
                    }
                }
            }
        }
    }
    if (charactersIgnoringModifiers.length == 1 && _sessionSnapshot.preedit.empty() &&
        MetasequoiaInputFlag(@"pairedPunctuation"))
    {
        NSString *pair = nil;
        switch (candidatePageShortcutCharacter)
        {
        case '(':
            pair = @"（）";
            break;
        case '[':
            pair = @"【】";
            break;
        case '"':
            pair = @"“”";
            break;
        case '\'':
            pair = @"‘’";
            break;
        case '<':
            pair = @"《》";
            break;
        default:
            break;
        }
        if (pair != nil)
        {
            // IMK has no setSelectedRange API. A marked pair with the caret between
            // delimiters is the supported, focus-safe representation; the next key
            // naturally replaces/commits it through the same client.
            [sender setMarkedText:pair
                   selectionRange:NSMakeRange(1, 0)
                 replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
            return YES;
        }
    }
    switch (metasequoia::mac::ClassifyConfiguredControllerKey(
        event.keyCode, [_candidatePanel isVisible],
        MetasequoiaCandidateKeyOptions([MetasequoiaPreferencesWindowController storedCandidatePageShortcut]),
        candidatePageShortcutCharacter, candidatePageShortcutModified))
    {
    case metasequoia::mac::ControllerKeyAction::MoveCandidateLeft:
    case metasequoia::mac::ControllerKeyAction::MoveCandidateRight:
    case metasequoia::mac::ControllerKeyAction::MoveCandidateUp:
    case metasequoia::mac::ControllerKeyAction::MoveCandidateDown: {
        if (event.keyCode != kVK_UpArrow && event.keyCode != kVK_DownArrow &&
            !metasequoia::mac::IsPrimaryCandidateDirection(event.keyCode, _candidatePanel.panelType))
        {
            return YES;
        }
        const BOOL backwards = event.keyCode == kVK_LeftArrow || event.keyCode == kVK_UpArrow;
        const NSUInteger target = backwards ? (_candidateHighlightedIndex > 0 ? _candidateHighlightedIndex - 1 : 0)
                                            : std::min(_candidateHighlightedIndex + 1, _candidateData.count - 1);
        [self selectCandidateAtIndex:target
                           pageStart:metasequoia::mac::CandidatePageStart(target, _candidateData.count,
                                                                          _candidatePageSize)];
        return YES;
    }
    case metasequoia::mac::ControllerKeyAction::MoveCandidatePageUp:
        if (_candidatePageSize > 0 && _candidatePageStart >= _candidatePageSize)
        {
            const NSUInteger target = _candidatePageStart - _candidatePageSize;
            [self selectCandidateAtIndex:target pageStart:target];
        }
        return YES;
    case metasequoia::mac::ControllerKeyAction::MoveCandidatePageDown:
        if (_candidatePageSize > 0 && _candidatePageStart + _candidatePageSize < _candidateData.count)
        {
            const NSUInteger target = _candidatePageStart + _candidatePageSize;
            [self selectCandidateAtIndex:target pageStart:target];
        }
        return YES;
    case metasequoia::mac::ControllerKeyAction::MoveCandidateHome:
        [self selectCandidateAtIndex:_candidatePageStart pageStart:_candidatePageStart];
        return YES;
    case metasequoia::mac::ControllerKeyAction::MoveCandidateEnd:
        [self selectCandidateAtIndex:metasequoia::mac::CandidatePageEnd(_candidatePageStart, _candidateData.count,
                                                                        _candidatePageSize)
                           pageStart:_candidatePageStart];
        return YES;
    case metasequoia::mac::ControllerKeyAction::Backspace:
        result = _session->command(metasequoia::Command::Backspace);
        break;
    case metasequoia::mac::ControllerKeyAction::CommitRaw:
        result = _session->command(metasequoia::Command::CommitRaw);
        break;
    case metasequoia::mac::ControllerKeyAction::Cancel:
        result = _session->command(metasequoia::Command::Cancel);
        break;
    case metasequoia::mac::ControllerKeyAction::CommitCandidate:
        result = _candidateData.count > 0 ? [self selectDisplayedCandidateAtIndex:_candidateHighlightedIndex]
                                          : _candidateSelection.commit(*_session);
        break;
    case metasequoia::mac::ControllerKeyAction::CommitFirstHan:
    case metasequoia::mac::ControllerKeyAction::CommitLastHan: {
        // Never commit a stale highlighted entry after a candidate refresh.
        const auto index = [self engineIndexForDisplayIndex:_candidateHighlightedIndex];
        if (!index)
            return YES;
        result =
            _session->select_edge(*index, candidatePageShortcutCharacter == '[' ? metasequoia::CandidateEdge::FirstHan
                                                                                : metasequoia::CandidateEdge::LastHan);
        break;
    }
    case metasequoia::mac::ControllerKeyAction::Character: {
        NSString *characters = event.characters;
        if (characters.length == 1)
        {
            const unichar character = [characters characterAtIndex:0];
            if (character >= 'a' && character <= 'z')
            {
                result = metasequoia::mac::HandleCharacterWithWubiAutoCommit(*_session, static_cast<char>(character),
                                                                             _wubiAutoCommitUniqueEnabled);
            }
            else if (character >= 'A' && character <= 'Z')
            {
                const bool shiftOnly =
                    (modifiers & NSEventModifierFlagShift) != 0 && (modifiers & ~NSEventModifierFlagShift) == 0;
                if (!_sessionSnapshot.preedit.empty())
                {
                    result = _session->character(static_cast<char>(character), shiftOnly);
                }
                else if (_localInputModesEnabled && shiftOnly)
                {
                    result = _session->character(static_cast<char>(character), true);
                }
            }
            else if (character == '\'' && !_sessionSnapshot.preedit.empty())
            {
                result = _session->character(static_cast<char>(character));
            }
            else if (metasequoia::mac::ShouldRouteSemicolonAsShuangpinInput(_sessionSnapshot.scheme,
                                                                            _sessionOptions.shuangpin_profile.name) &&
                     character == ';')
            {
                result = _session->character(static_cast<char>(character));
                if (!result.handled)
                {
                    result = [self handlePunctuation:static_cast<char>(character) client:sender];
                }
            }
            // Unicode mode reads a hex code point, so while it is open its digits and its optional
            // "+" are input rather than candidate numbers. Every other local mode takes letters
            // only and leaves the digits to selection, which is what they already did.
            else if ((character >= '0' && character <= '9') || character == '+')
            {
                if (_sessionSnapshot.local_mode == metasequoia::LocalInputMode::Unicode)
                {
                    result = _session->character(static_cast<char>(character));
                }
                else if (character >= '1' && character <= '9')
                {
                    const NSUInteger offset = character - '1';
                    if (_candidateData.count > 0)
                    {
                        if (offset < _candidatePageSize)
                            result = [self selectDisplayedCandidateAtIndex:_candidatePageStart + offset];
                    }
                    else
                        result = _candidateSelection.commit_number(*_session, static_cast<char>(character),
                                                                   _candidatePageSize);
                    if (!result.handled && !_sessionSnapshot.preedit.empty())
                    {
                        return YES;
                    }
                }
            }
            // Keep the host's routing predicate tied to the Engine punctuation contract. The
            // Session still owns translation and stateful quote/book-title behaviour.
            else if (IsEnginePunctuationCharacter(static_cast<char>(character)))
            {
                result = [self handlePunctuation:static_cast<char>(character) client:sender];
            }
        }
        break;
    }
    }

    if (!result.handled)
    {
        _sessionSnapshot = _session->snapshot();
        [self commitLeadingCandidate:sender];
        if (_session != nullptr && _sessionSnapshot.preedit.empty() &&
            [MetasequoiaPreferencesWindowController storedFullWidthInputEnabled] && event.characters.length == 1)
        {
            const unichar character = [event.characters characterAtIndex:0];
            if (metasequoia::mac::IsFullWidthConvertibleCharacter(character))
            {
                const unichar fullWidthCharacter = metasequoia::mac::FullWidthCharacter(character);
                NSString *converted = [NSString stringWithCharacters:&fullWidthCharacter length:1];
                [sender insertText:converted replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
                return YES;
            }
        }
        return NO;
    }
    [self applyResult:result localMode:localModeForKey client:sender];
    return YES;
}

- (void)commitLeadingCandidate:(id)sender
{
    [self cancelVoiceInput];
    if (_session == nullptr || _sessionSnapshot.preedit.empty())
    {
        return;
    }
    // Every automatic commit runs through here: pressing a modifier, typing a key the session does
    // not take, resetting learned data. finish_composition defaults to the engine's own first
    // candidate for the leading segment, which threw away a candidate the user had arrowed onto.
    // The rest of the composition still finishes from the engine's first candidate, which is what
    // the default argument means and what this path already did.
    const metasequoia::LocalInputMode localMode = _sessionSnapshot.local_mode;
    const auto index = [self engineIndexForDisplayIndex:_candidateHighlightedIndex];
    if (_candidateData.count > 0 && !index)
        return;
    const auto result = _session->finish(index.value_or(0));
    if (result.handled)
    {
        [self applyResult:result localMode:localMode client:sender];
    }
}

// 只认「单独的 ⌥」和「单独的 ⌃」:带上 ⌘ 或 ⇧ 的组合是别人的快捷键,不该被输入法吃掉。
- (BOOL)insertGlossForModifiedDigit:(NSEvent *)event modifiers:(NSEventModifierFlags)modifiers client:(id)sender
{
    if (_session == nullptr || _sessionSnapshot.preedit.empty() || _visibleCandidateData.count == 0)
    {
        return NO;
    }
    NSString *digits = event.charactersIgnoringModifiers;
    if (digits.length != 1)
    {
        return NO;
    }
    const unichar digit = [digits characterAtIndex:0];
    const int request = metasequoia::mac::CandidateGlossRequestForModifiers(modifiers, digit);
    if (request == 0)
    {
        return NO;
    }
    const BOOL wantsSecondary = request == 2;
    const NSUInteger offset = static_cast<NSUInteger>(digit - '1');
    if (offset >= _visibleCandidateData.count)
    {
        return NO;
    }
    NSAttributedString *candidate = _visibleCandidateData[offset];
    NSString *gloss = wantsSecondary ? MetasequoiaCandidateSecondaryTranslation(candidate)
                                     : MetasequoiaCandidateTranslation(candidate);
    if (gloss.length == 0)
    {
        return NO;
    }
    // 先上屏译文再作废组字:顺序反过来的话,取消会先把预编辑文本撤掉,译文就落在了它原本的位置之前。
    [sender insertText:gloss replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
    const metasequoia::LocalInputMode localMode = _sessionSnapshot.local_mode;
    const auto cancelled = _session->command(metasequoia::Command::Cancel);
    [self applyResult:cancelled localMode:localMode client:sender];
    return YES;
}

// Single source of truth for the traditional-output predicate so the candidate panel and the committed text can never
// disagree about which script the user sees.
- (BOOL)traditionalChineseOutputActive
{
    return _session != nullptr && _sessionSnapshot.scheme != SchemeType::JapaneseRomaji &&
           [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled];
}

// Dictated text does not come from the session, so it has to follow the script preference even
// when no session exists — the voice shortcut is dispatched before prepareSessionIfNeeded, and a
// controller built while English mode is stored, or one whose dictionary keeps failing to prepare,
// never has one. EngineSchemeForStoredPreference only ever yields Quanpin, Shuangpin or Wubi, so
// the Japanese romaji exclusion above cannot apply to the stored preference.
- (BOOL)voiceOutputUsesTraditionalChinese
{
    return _session != nullptr ? [self traditionalChineseOutputActive]
                               : [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled];
}

// The local input mode is taken as an argument rather than read from the session, because
// committing resets it: by the time a result arrives here the session has already forgotten that a
// Unicode code point is what produced it, and converting that to traditional would hand back a
// different character than the one the user named.
- (void)applyResult:(const metasequoia::KeyResult &)result
          localMode:(metasequoia::LocalInputMode)localMode
             client:(id)sender
{
    _sessionSnapshot = _session->snapshot();
    id<IMKTextInput> client = sender;
    const NSRange replacementRange = NSMakeRange(NSNotFound, NSNotFound);
    if (result.commit.has_value())
    {
        const BOOL traditionalOutput =
            [self traditionalChineseOutputActive] && metasequoia::mac::ScriptConversionAppliesToLocalMode(localMode);
        NSString *commit = MetasequoiaChineseOutputString(MetasequoiaStringFromUtf8(*result.commit), traditionalOutput);
        [client insertText:commit replacementRange:replacementRange];
        // 落盘的唯一时机:用户真的把这个词打出去了。用未经繁简转换的原文做键 —— 缓存和引擎词库都按
        // 简体索引,转换只影响上屏显示。
        [self persistCommittedGloss:MetasequoiaStringFromUtf8(*result.commit)];
        _candidateSelection.reset();
        if (_sessionSnapshot.preedit.empty())
        {
            [_candidatePanel hide];
            [_shuangpinKeymapPanel orderOut:nil];
            return;
        }
    }

    NSString *preedit = MetasequoiaStringFromUtf8(_sessionSnapshot.preedit);
    [client setMarkedText:preedit selectionRange:NSMakeRange(preedit.length, 0) replacementRange:replacementRange];
    [self updateCandidatePanel];
    [self updateShuangpinKeymapPanelForClient:client];
}

- (void)updateShuangpinKeymapPanelForClient:(id<IMKTextInput>)client
{
    const BOOL hasComposition = _session != nullptr && !_sessionSnapshot.preedit.empty();
    const BOOL isShuangpin = _session != nullptr && _sessionSnapshot.scheme == SchemeType::Shuangpin;
    if (!MetasequoiaShouldShowShuangpinKeymap(isShuangpin, _shuangpinKeymapEnabled, hasComposition) || client == nil)
    {
        [_shuangpinKeymapPanel orderOut:nil];
        return;
    }
    [_shuangpinKeymapPanel setProfileName:@(_sessionOptions.shuangpin_profile.name.c_str())];

    NSRect caretRect = NSZeroRect;
    [client attributesForCharacterIndex:0 lineHeightRectangle:&caretRect];
    if (!std::isfinite(NSMinX(caretRect)) || !std::isfinite(NSMinY(caretRect)) || !std::isfinite(NSMaxX(caretRect)) ||
        !std::isfinite(NSMaxY(caretRect)) || NSHeight(caretRect) <= 0.0)
    {
        [_shuangpinKeymapPanel orderOut:nil];
        return;
    }

    NSString *preedit = MetasequoiaStringFromUtf8(_sessionSnapshot.preedit);
    NSString *highlightedKey = @"";
    if (preedit.length > 0)
    {
        const unichar character = [preedit characterAtIndex:preedit.length - 1];
        if ((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z') || character == ';')
        {
            highlightedKey = [NSString stringWithCharacters:&character length:1];
        }
    }
    [_shuangpinKeymapPanel updateHighlightedKey:highlightedKey];

    const CGFloat fontSize = static_cast<CGFloat>([MetasequoiaPreferencesWindowController storedCandidateFontSize]);
    CGFloat candidateClearance = fontSize + 42.0;
    if (_candidatePanel.panelType != kIMKSingleRowSteppingCandidatePanel)
    {
        const NSUInteger visibleCandidates =
            MIN(_candidateData.count,
                static_cast<NSUInteger>([MetasequoiaPreferencesWindowController storedCandidatePageSize]));
        candidateClearance = (fontSize + 10.0) * visibleCandidates + 24.0;
    }
    [_shuangpinKeymapPanel showNearCaretRect:caretRect candidateClearance:candidateClearance];
}

- (void)updateCandidatePanel
{
    [self rebuildCandidatePanelPreservingSelection:NO];
}

- (void)refreshCandidatePanelPreservingSelection
{
    [self rebuildCandidatePanelPreservingSelection:YES];
}

- (EnglishDictionary *)translationDictionary
{
    if (_translationDictionary)
        return _translationDictionary.get();
    NSBundle *bundle = [NSBundle bundleForClass:self.class];
    NSString *databasePath = [bundle pathForResource:@"english" ofType:@"db"];
    if (databasePath.length == 0)
        return nullptr;
    NSString *translationsPath = [bundle pathForResource:@"custom_translations" ofType:@"txt"];
    // 第四个参数是持久化的在线释义。给了它之后 query_*_gloss 自动多一层回落:
    // custom_translations.txt > 随包发的 ECDICT > 上次联网补回来的那份。查询处不用改。
    _translationDictionary = std::make_unique<EnglishDictionary>(
        databasePath.fileSystemRepresentation, false,
        translationsPath.length > 0 ? translationsPath.fileSystemRepresentation : "",
        MetasequoiaGlossCachePath().fileSystemRepresentation);
    return _translationDictionary.get();
}

// 固顶候选。The engine orders by frequency alone, so a word the user always wants first drifts down
// again as soon as something else is typed more often. Pinning is kept here rather than in the engine
// because it is a macOS-scoped preference and the shared ranking serves three platforms.
//
// 存的是「编码 → 词的顺序表」,不是权重:固顶要的是钉死在最前,而加权只是提高概率,仍会被更高频的词压下去。
static NSString *const kMetasequoiaPinnedCandidatesKey = @"MetasequoiaImePinnedCandidates";

static NSArray<NSString *> *MetasequoiaPinnedWords(const std::string &code)
{
    if (code.empty())
        return @[];
    NSDictionary *all = [NSUserDefaults.standardUserDefaults dictionaryForKey:kMetasequoiaPinnedCandidatesKey];
    NSArray *words = all[MetasequoiaStringFromUtf8(code)];
    return [words isKindOfClass:NSArray.class] ? words : @[];
}

static void MetasequoiaTogglePinnedWord(const std::string &code, NSString *word)
{
    if (code.empty() || word.length == 0)
        return;
    NSString *key = MetasequoiaStringFromUtf8(code);
    NSDictionary *stored = [NSUserDefaults.standardUserDefaults dictionaryForKey:kMetasequoiaPinnedCandidatesKey];
    NSMutableDictionary *all = stored == nil ? [NSMutableDictionary dictionary] : [stored mutableCopy];
    NSArray *existing = all[key];
    NSMutableArray *words = existing == nil ? [NSMutableArray array] : [existing mutableCopy];
    if ([words containsObject:word])
        [words removeObject:word];
    else
        [words insertObject:word atIndex:0];
    // 空数组就把这一项删掉,不留一堆空壳键。
    if (words.count == 0)
        [all removeObjectForKey:key];
    else
        all[key] = words;
    [NSUserDefaults.standardUserDefaults setObject:all forKey:kMetasequoiaPinnedCandidatesKey];
}

- (void)rebuildCandidatePanelPreservingSelection:(BOOL)preserveSelection
{
    ++_translationGeneration;
    _sessionSnapshot = _session->snapshot();
    const std::optional<size_t> preservedSelection =
        preserveSelection ? _candidateSelection.live_selected_index(_sessionSnapshot) : std::nullopt;
    if (!preserveSelection)
    {
        _candidateSelection.reset();
        _candidateHighlightedIndex = 0;
        _candidatePageStart = 0;
    }
    _candidateLineIdentifiersCollapsed = NO;
    NSMutableArray *data = [NSMutableArray arrayWithCapacity:_sessionSnapshot.candidates.size()];
    const metasequoia::LocalInputMode localMode = _sessionSnapshot.local_mode;
    const BOOL traditionalOutput =
        [self traditionalChineseOutputActive] && metasequoia::mac::ScriptConversionAppliesToLocalMode(localMode);
    const bool annotateHelpcodes =
        (_sessionOptions.helpcode && SchemeUsesHelpcodes(_sessionSnapshot.scheme)) &&
        MetasequoiaInputFlag(_sessionSnapshot.scheme == SchemeType::Shuangpin ? @"shuangpinHelpcodeHints"
                                                                              : @"quanpinHelpcodeHints",
                             YES) &&
        metasequoia::mac::HelpcodesAnnotateLocalMode(localMode);
    // The preedit of a wubi composition is the code as typed, which is what each candidate's own
    // code is measured against. A local input mode synthesises its candidates and the pinyin
    // fallback answers with pinyin keys, and in neither case do the letters left over lead
    // anywhere, so the hint is withheld by handing the display an empty code.
    const bool annotateWubiCodes = _sessionSnapshot.scheme == SchemeType::Wubi &&
                                   localMode == metasequoia::LocalInputMode::None &&
                                   !_sessionSnapshot.answered_by_pinyin_fallback &&
                                   [MetasequoiaPreferencesWindowController storedWubiCodeHintEnabled];
    const std::string wubiTypedCode = annotateWubiCodes ? _sessionSnapshot.preedit : std::string{};
    // 默认开。The gloss goes through the account's own model at api.msime.app, so it costs the user
    // no keys of their own and there is nothing to set up before it works; leaving it off by default
    // meant the feature existed and nobody saw it.
    const BOOL onlineTranslation = MetasequoiaInputFlag(@"candidateTranslation", YES);
    // 本地词典是回落,不是替代品。It used to be consulted only when the online path was switched off,
    // so turning that on and having nothing to serve it -- no account signed in, a request still in
    // flight, a word the model did not return -- left the candidate with no gloss at all rather than
    // the offline one it would have had.
    EnglishDictionary *glossDictionary = nullptr;
    // 横竖排都给。The panel used to read this attribute only when vertical, so a gloss computed for a
    // horizontal panel was thrown away; both now draw it.
    if ([MetasequoiaPreferencesWindowController storedCandidateTranslationsEnabled] &&
        _sessionSnapshot.scheme != SchemeType::JapaneseRomaji)
    {
        glossDictionary = [self translationDictionary];
    }
    const NSInteger secondaryIndex = MetasequoiaSecondaryTranslationLanguageIndex();
    NSString *secondaryLanguage =
        secondaryIndex >= 0
            ? @(metasequoia::mac::CandidateTranslationLanguageAt(static_cast<std::size_t>(secondaryIndex)).code)
            : @"";
    NSUInteger candidateIndex = 0;
    // 固顶的词提到最前,其余保持引擎给的顺序。Reordering here rather than asking the engine keeps the
    // shared ranking untouched, and the panel is the only thing that needs to know about the pin.
    _candidateEngineIndices.clear();
    _candidateEngineIndices.reserve(_sessionSnapshot.candidates.size());
    {
        NSArray<NSString *> *pinned = MetasequoiaPinnedWords(_sessionSnapshot.preedit);
        if (pinned.count > 0)
        {
            for (NSString *word in pinned)
            {
                const std::string wanted = word.UTF8String ? word.UTF8String : "";
                for (size_t index = 0; index < _sessionSnapshot.candidates.size(); ++index)
                    if (_sessionSnapshot.candidates[index].word == wanted)
                        _candidateEngineIndices.push_back(index);
            }
            for (size_t index = 0; index < _sessionSnapshot.candidates.size(); ++index)
                if (![pinned containsObject:MetasequoiaStringFromUtf8(_sessionSnapshot.candidates[index].word)])
                    _candidateEngineIndices.push_back(index);
        }
        else
        {
            for (size_t index = 0; index < _sessionSnapshot.candidates.size(); ++index)
                _candidateEngineIndices.push_back(index);
        }
    }
    for (const size_t engineIndex : _candidateEngineIndices)
    {
        const WordItem &candidate = _sessionSnapshot.candidates[engineIndex];
        NSString *display = MetasequoiaStringFromUtf8(metasequoia::mac::CandidateDisplayText(
            candidate, _sessionSnapshot.scheme, annotateHelpcodes, _activeHelpcodeKeymap.get(), wubiTypedCode));
        NSString *convertedDisplay = MetasequoiaChineseOutputString(display, traditionalOutput);
        NSString *onlineGloss = nil;
        if (onlineTranslation)
        {
            NSString *language =
                @(metasequoia::mac::CandidateTranslationLanguageAt(
                      static_cast<std::size_t>(MetasequoiaInputInteger(
                          @"translationLanguage", 0, 0, metasequoia::mac::kCandidateTranslationLanguageCount - 1)))
                      .code);
            NSString *translation = MetasequoiaSharedTranslationCache()[
                [NSString stringWithFormat:@"%@|%@", language, MetasequoiaStringFromUtf8(candidate.word)]];
            // 释义走属性,不拼进显示串。拼接是横排面板还不读这个属性时的将就 —— 面板拿到「苹果 apple」
            // 这样一个标题就没法把释义单独排一行,而叠排的整个意义就是让它独占一行。
            if (translation.length)
                onlineGloss = translation;
        }
        NSAttributedString *indexed = MetasequoiaIndexedCandidateString(convertedDisplay, candidateIndex);
        // 离线优先。本机词典查一整页九个词是 0.03 毫秒,而模型是 2 秒起步、长尾到 7 秒 —— 组字往往只
        // 有两三秒,慢的那条根本赶不上。实测常用词(你好/中国/输入法/今天/我们…)离线命中 8/9,没命中的
        // 基本是「评过、平果、恭恭敬敬」这类没人会选的冷僻候选。所以先查本机,查不到才用网络那份。
        NSString *offlineGloss = nil;
        if (glossDictionary != nullptr)
        {
            if (const auto query = metasequoia::mac::TranslationQueryForCandidate(candidate))
            {
                const std::string gloss = metasequoia::mac::LookupCandidateGloss(*glossDictionary, *query);
                // ECDICT 对生僻字的「英文释义」常常就是那个字本身(孖→孖、聑→聑)。这种释义等于没有,
                // 还会占住位置让网络那份不去补,所以把它当作未命中。
                if (!gloss.empty() && gloss != candidate.word)
                    offlineGloss = MetasequoiaStringFromUtf8(gloss);
            }
        }
        if (offlineGloss.length > 0)
            indexed = MetasequoiaCandidateStringByAddingTranslation(indexed, offlineGloss);
        else if (onlineGloss.length > 0)
            indexed = MetasequoiaCandidateStringByAddingTranslation(indexed, onlineGloss);
        // 第二条释义单独挂,不并进显示文本:候选格把它画在自己那一行,而上屏的仍然只是候选词本身。
        if (secondaryLanguage.length > 0)
        {
            NSString *secondary = MetasequoiaSharedSecondaryTranslationCache()[
                [NSString stringWithFormat:@"%@|%@", secondaryLanguage, MetasequoiaStringFromUtf8(candidate.word)]];
            if (secondary.length > 0)
                indexed = MetasequoiaCandidateStringByAddingSecondaryTranslation(indexed, secondary);
        }
        [data addObject:indexed];
        ++candidateIndex;
    }
    _candidateData = [data copy];
    [self scheduleCandidateTranslations];
    if (!_sessionSnapshot.preedit.empty() && _candidateData.count > 0)
    {
        const auto preserved = preservedSelection ? std::find(_candidateEngineIndices.begin(),
                                                              _candidateEngineIndices.end(), *preservedSelection)
                                                  : _candidateEngineIndices.end();
        const NSUInteger selectedIndex =
            preserved != _candidateEngineIndices.end() ? std::distance(_candidateEngineIndices.begin(), preserved) : 0;
        _candidatePageStart =
            metasequoia::mac::CandidatePageStart(selectedIndex, _candidateData.count, _candidatePageSize);
        [self showCurrentCandidatePage];
        if (preservedSelection.has_value())
        {
            if (![self selectCandidateAtIndex:selectedIndex pageStart:_candidatePageStart])
            {
                _candidateSelection.reset();
                _candidateHighlightedIndex = 0;
                _candidatePageStart = 0;
                [self showCurrentCandidatePage];
            }
        }
    }
    else
    {
        _visibleCandidateData = @[];
        [_candidatePanel setCandidateData:_visibleCandidateData];
        [_candidatePanel hide];
    }
}

// 350ms:一个音节敲下来大约 150-250ms,所以这个窗口只在你停下来看候选时才到期 —— 那正是需要
// 释义的一刻。每次按键重排计时器,中间态一次请求都不发。
// 释义缓存是进程级的,不是控制器实例的。IMKit 为每个文本输入客户端建一个 MetasequoiaInputController,
// 一次会话下来有十几个实例;取回释义的那个实例和下一次组字所在的实例往往不是同一个。缓存放在实例上,
// 结果就是答案散落在一堆已经没有组字的实例里(实测死实例里攒了 29、32 条,正在组字的那个只有 3 条),
// 而换一个输入框就从零开始 —— 这正是「第一次没有、第二次才有」:第二次恰好还是同一个实例。
//
// 键是「语言|词」,与实例无关,所以共享是安全的:任何实例取回的释义对其他实例同样正确。
// 当前活跃的那个控制器。IMKit 为每个文本输入客户端建一个实例,一次会话下来有十几个,而释义到达时
// 是广播给所有实例的。原来每个实例各自判断「我的 _sessionSnapshot 是不是空的」来决定要不要重绘,
// 实测到达那一刻十二个实例全部 preeditLen=0,于是没有任何一个重绘 —— 答案进了缓存却没人画。
// 只有 activateServer: 点名的那个实例在组字,让它负责重绘。
static __weak MetasequoiaInputController *gActiveController = nil;

// 这一页要问的词的签名。页面没变就不再发请求 —— 照搬 Windows 的 g_candidate_translation_signature。
// 原来每次重绘都发,而重绘由按键、翻页、释义到达三处触发,实测同一批词在几秒内被请求两三次,还把后端
// 每分钟 120 次的限流打满,于是真正需要的那次请求反而被拒。
static NSString *gCandidateTranslationSignature = nil;

static NSMutableDictionary<NSString *, NSString *> *MetasequoiaSharedTranslationCache(void)
{
    static NSMutableDictionary<NSString *, NSString *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

// 在线释义落盘的位置。跟 msime_user.db 同一个目录:这是用户数据,不是随时可丢的缓存 —— 换一代词库
// 时 english.db 会从资源目录重拷,写进那里的释义会被清掉,所以引擎给了这个独立的 user 文件。
static NSString *MetasequoiaGlossCachePath(void)
{
    static NSString *path;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      NSFileManager *manager = NSFileManager.defaultManager;
      NSURL *support = [manager URLForDirectory:NSApplicationSupportDirectory
                                       inDomain:NSUserDomainMask
                              appropriateForURL:nil
                                         create:YES
                                          error:nil];
      if (support == nil)
          support = [[NSURL fileURLWithPath:NSHomeDirectory()
                                isDirectory:YES] URLByAppendingPathComponent:@"Library/Application Support"
                                                                 isDirectory:YES];
      NSURL *root = [support URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
      [manager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];
      path = [root URLByAppendingPathComponent:@(metasequoia::assets::gloss_cache)].path;
    });
    return path;
}

// 一次最多联网翻几个候选。原来是整页九个 —— 而用户最终只会选其中一个,剩下八个的译文既费上游调用量,
// 又污染所有人共用的服务端缓存。生产库实测:752 行里只有 16 行(2.13%)被命中过,48% 是「吋 忖 洊 皴
// 邨」这类没人会选的单字。
//
// 本机 ECDICT 查一整页是 0.03 毫秒且常用词命中 8/9,所以排在后面的候选大多仍有离线释义;联网这条路
// 只补最前面几个和用户实际停留的那个。
static constexpr NSUInteger kCandidateTranslationOnlineLimit = 3;

// 该不该把这个候选送去联网翻译。候选本身合不合适由 CandidateSupportsOnlineGloss 判断(含汉字才送,
// 理由见那里);这里只加位置这一层:前几个,外加用户当前停留的那个。
static BOOL MetasequoiaCandidateWantsOnlineGloss(const WordItem &candidate, NSUInteger index,
                                                 const std::optional<size_t> &highlighted)
{
    if (!metasequoia::mac::CandidateSupportsOnlineGloss(candidate))
        return NO;
    return index < kCandidateTranslationOnlineLimit ||
           (highlighted.has_value() && *highlighted == static_cast<size_t>(index));
}

// 把网络回来的释义写进引擎的持久缓存,下次开机就不用再问一遍。
//
// 只写目标语言是英文的那份:引擎那张表是 en_zh_glosses / zh_en_glosses 两个方向,没有语言维度。日语
// 韩语等目标语言仍然只活在进程内的 MetasequoiaSharedTranslationCache 里,重启就没了 —— 要让它们也
// 持久,得先给引擎一张按语言分的表,那是另一件事。
//
// 方向跟 TranslationQueryForCandidate 对齐:含汉字的候选按 ChineseToEnglish 存进 zh_en_glosses,
// 读回来走 query_english_gloss。英文候选译成英文没有意义,直接跳过。
static void MetasequoiaPersistOnlineGloss(EnglishDictionary *dictionary, NSString *language, NSString *word,
                                          NSString *gloss)
{
    if (dictionary == nullptr || word.length == 0 || gloss.length == 0 || ![language isEqualToString:@"EN"])
        return;
    const std::string text = word.UTF8String != nullptr ? word.UTF8String : "";
    if (!metasequoia::mac::CandidateSupportsOnlineGloss(WordItem{"", text, 0}))
        return;
    (void)dictionary->cache_gloss(true, text, gloss.UTF8String);
}

// 只把用户真正上屏的词写进持久缓存。
//
// 整页候选联网取回来是为了**显示**,显示用进程内的 MetasequoiaSharedTranslationCache 就够了。之前
// 到达即落盘,等于把用户没选的候选也存下来 —— 生产库里因此堆着「但是在」「都坐」「存了起来」这类
// 组字中途的片段,以及「次 此 大 打 级 集 几」这类没人会专门去查的单字,实测 98% 的条目一次都没被
// 命中过。上屏是唯一可靠的「用户真的要了这个词」的信号。
//
// 内存缓存里没有就什么都不做:说明这个词的释义是离线词库给的(那本来就在 english.db 里),或者压根
// 没取到。
- (void)persistCommittedGloss:(NSString *)word
{
    if (word.length == 0)
        return;
    const auto &languageEntry =
        metasequoia::mac::CandidateTranslationLanguageAt(static_cast<std::size_t>(MetasequoiaInputInteger(
            @"translationLanguage", 0, 0, metasequoia::mac::kCandidateTranslationLanguageCount - 1)));
    NSString *language = @(languageEntry.code);
    NSString *gloss = MetasequoiaSharedTranslationCache()[[NSString stringWithFormat:@"%@|%@", language, word]];
    if (gloss.length == 0)
        return;
    MetasequoiaPersistOnlineGloss([self translationDictionary], language, word, gloss);
}

static NSMutableDictionary<NSString *, NSString *> *MetasequoiaSharedSecondaryTranslationCache(void)
{
    static NSMutableDictionary<NSString *, NSString *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
      cache = [NSMutableDictionary dictionary];
    });
    return cache;
}

static const int64_t kCandidateTranslationQuietNanoseconds = 350 * NSEC_PER_MSEC;

// 第二条释义默认关:读日文的人开它值一行,不读的人白白让每格高一截。-1 表示关闭,其余是语言表下标。
static NSInteger MetasequoiaSecondaryTranslationLanguageIndex()
{
    return MetasequoiaInputInteger(@"translationSecondaryLanguage", -1, -1,
                                   static_cast<NSInteger>(metasequoia::mac::kCandidateTranslationLanguageCount) - 1);
}

- (void)scheduleCandidateTranslations
{
    if (_translationDebounce != nil)
    {
        dispatch_source_cancel(_translationDebounce);
        _translationDebounce = nil;
    }
    if (_sessionSnapshot.preedit.empty() || !MetasequoiaInputFlag(@"candidateTranslation", YES))
        return;
    __weak MetasequoiaInputController *weakSelf = self;
    dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, dispatch_get_main_queue());
    dispatch_source_set_timer(timer, dispatch_time(DISPATCH_TIME_NOW, kCandidateTranslationQuietNanoseconds),
                              DISPATCH_TIME_FOREVER, 20 * NSEC_PER_MSEC);
    dispatch_source_set_event_handler(timer, ^{
      MetasequoiaInputController *strongSelf = weakSelf;
      if (strongSelf == nullptr)
          return;
      dispatch_source_cancel(strongSelf->_translationDebounce);
      strongSelf->_translationDebounce = nil;
      if (strongSelf->_session == nullptr || strongSelf->_sessionSnapshot.preedit.empty())
          return;
      [strongSelf requestCandidateTranslationsForSnapshot:strongSelf->_sessionSnapshot];
    });
    _translationDebounce = timer;
    dispatch_resume(timer);
}

- (void)requestCandidateTranslationsForSnapshot:(const metasequoia::SessionSnapshot &)snapshot
{
    if (!MetasequoiaInputFlag(@"candidateTranslation", YES) || !snapshot.preedit.size())
        return;
    NSString *endpoint = [NSUserDefaults.standardUserDefaults stringForKey:@"translationEndpoint"];
    const NSInteger providerIndex = MetasequoiaInputInteger(@"translationProvider", 0, 0, 2);
    const auto provider = metasequoia::mac::CandidateTranslationProviderAt(static_cast<std::size_t>(providerIndex));
    NSString *secretId = [NSUserDefaults.standardUserDefaults stringForKey:@"translationSecretId"];
    NSString *secretKey = [NSUserDefaults.standardUserDefaults stringForKey:@"translationSecretKey"];
    if ((provider == metasequoia::mac::CandidateTranslationProvider::DeepLX && endpoint.length == 0) ||
        (provider == metasequoia::mac::CandidateTranslationProvider::TencentMachineTranslation &&
         (!secretId.length || !secretKey.length)))
        return;
    const NSUInteger generation = _translationGeneration;
    const auto &languageEntry =
        metasequoia::mac::CandidateTranslationLanguageAt(static_cast<std::size_t>(MetasequoiaInputInteger(
            @"translationLanguage", 0, 0, metasequoia::mac::kCandidateTranslationLanguageCount - 1)));
    NSString *language = @(languageEntry.code);
    const NSUInteger pageSize = metasequoia::mac::NormalizeCandidatePageSize(
        static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidatePageSize]));
    const NSUInteger limit = MIN(pageSize, snapshot.candidates.size());
    // 当前高亮的候选总是要问,即使它排在联网上限之外 —— 用方向键停在第七个上时,下一次 debounce 要
    // 把它带上。live_selected_index 会在候选列表重建后失效,拿到的不会是过期的下标。
    const auto highlighted = _candidateSelection.live_selected_index(snapshot);
    if (provider == metasequoia::mac::CandidateTranslationProvider::AccountModel)
    {
        // One request for the whole page: a model keeps a page consistent when it sees it at once,
        // and the account pays per call rather than per word.
        NSMutableArray<NSString *> *pending = [NSMutableArray arrayWithCapacity:limit];
        NSMutableString *signature = [NSMutableString stringWithString:language];
        for (NSUInteger i = 0; i < limit; ++i)
        {
            if (!MetasequoiaCandidateWantsOnlineGloss(snapshot.candidates[i], i, highlighted))
                continue;
            NSString *word = MetasequoiaStringFromUtf8(snapshot.candidates[i].word);
            // 签名只包含真正会问的词。否则移动高亮不会改变签名,新选中的那个候选永远等不到请求。
            [signature appendFormat:@"|%@", word];
            if (MetasequoiaSharedTranslationCache()[[NSString stringWithFormat:@"%@|%@", language, word]] == nil)
                [pending addObject:word];
        }
        if (pending.count == 0)
        {
            gCandidateTranslationSignature = [signature copy];
            return;
        }
        // 同一页问过一次就够了。回复没到之前重绘多少次都不该再发。
        if ([signature isEqualToString:gCandidateTranslationSignature])
            return;
        gCandidateTranslationSignature = [signature copy];
        NSData *payload = [NSJSONSerialization dataWithJSONObject:pending options:0 error:nil];
        NSString *wordsJSON =
            payload != nil ? [[NSString alloc] initWithData:payload encoding:NSUTF8StringEncoding] : nil;
        if (wordsJSON.length)
        {
            const NSInteger secondary = MetasequoiaSecondaryTranslationLanguageIndex();
            const char *secondaryCode =
                secondary >= 0
                    ? metasequoia::mac::CandidateTranslationLanguageAt(static_cast<std::size_t>(secondary)).code
                    : "";
            MSIMEFetchCandidateGlosses(wordsJSON.UTF8String, languageEntry.code, secondaryCode,
                                       static_cast<unsigned long long>(generation));
        }
        return;
    }
    for (NSUInteger i = 0; i < limit; ++i)
    {
        if (!MetasequoiaCandidateWantsOnlineGloss(snapshot.candidates[i], i, highlighted))
            continue;
        NSString *word = MetasequoiaStringFromUtf8(snapshot.candidates[i].word);
        NSString *key = [NSString stringWithFormat:@"%@|%@", language, word];
        if (MetasequoiaSharedTranslationCache()[key] != nil)
            continue;
        __weak MetasequoiaInputController *weakSelf = self;
        const bool viaDeepLX = provider == metasequoia::mac::CandidateTranslationProvider::DeepLX;
        id client = viaDeepLX ? (id)[MetasequoiaDeepLXClient new] : (id)[MetasequoiaTencentTmtClient new];
        void (^completion)(NSString *, NSError *) = ^(NSString *text, NSError *error) {
          dispatch_async(dispatch_get_main_queue(), ^{
            MetasequoiaInputController *strongSelf = weakSelf;
            if (!strongSelf || error || !text.length || !strongSelf->_session)
                return;
            // 同上:词条缓存与代际无关,晚到也照收。同样只进内存,落盘等上屏。
            MetasequoiaSharedTranslationCache()[key] = text;
            if (!strongSelf->_sessionSnapshot.preedit.empty())
                [strongSelf rebuildCandidatePanelPreservingSelection:YES];
          });
        };
        if (viaDeepLX)
            [(MetasequoiaDeepLXClient *)client translateText:word
                                              targetLanguage:language
                                                    endpoint:endpoint
                                                  completion:completion];
        else
            [(MetasequoiaTencentTmtClient *)client translateText:word
                                                  targetLanguage:language
                                                          region:@"ap-guangzhou"
                                                        secretId:secretId
                                                       secretKey:secretKey
                                                      completion:completion];
    }
}

- (NSArray *)candidates:(id)sender
{
    (void)sender;
    return _visibleCandidateData != nil ? _visibleCandidateData : @[];
}

- (void)candidateSelectionChanged:(NSAttributedString *)candidateString
{
    (void)candidateString;
}

- (void)candidatePinToggled:(NSAttributedString *)candidateString
{
    if (_session == nullptr || _sessionSnapshot.preedit.empty())
        return;
    const auto index = [self engineIndexForDisplayIndex:MetasequoiaCandidateIndex(candidateString)];
    if (!index)
        return;
    MetasequoiaTogglePinnedWord(_sessionSnapshot.preedit,
                                MetasequoiaStringFromUtf8(_sessionSnapshot.candidates[*index].word));
    // 就地重排,不动引擎状态:固顶只改显示顺序,组字和候选集都不该因为右键而变化。
    [self rebuildCandidatePanelPreservingSelection:NO];
}

- (void)candidateSelected:(NSAttributedString *)candidateString
{
    if (_session == nullptr)
    {
        return;
    }
    NSUInteger index = MetasequoiaCandidateIndex(candidateString);
    if (index == NSNotFound)
    {
        const NSInteger selectedIdentifier = [_candidatePanel selectedCandidate];
        NSUInteger identifierIndex = NSNotFound;
        if (selectedIdentifier != NSNotFound)
        {
            for (NSUInteger candidateIndex = 0; candidateIndex < _visibleCandidateData.count; ++candidateIndex)
            {
                if ([_candidatePanel candidateStringIdentifier:_visibleCandidateData[candidateIndex]] !=
                    selectedIdentifier)
                {
                    continue;
                }
                if (identifierIndex != NSNotFound)
                {
                    identifierIndex = NSNotFound;
                    break;
                }
                identifierIndex = _candidatePageStart + candidateIndex;
            }
        }
        index = identifierIndex;
    }
    if (index == NSNotFound)
    {
        NSMutableArray<NSString *> *displayStrings = [NSMutableArray arrayWithCapacity:_visibleCandidateData.count];
        for (NSAttributedString *candidate in _visibleCandidateData)
        {
            [displayStrings addObject:candidate.string];
        }
        const NSUInteger line = MetasequoiaUniqueStringIndex(displayStrings, candidateString.string);
        if (line != NSNotFound)
            index = _candidatePageStart + line;
    }
    if (index == NSNotFound)
    {
        // Last resort for display strings that collide after conversion (干/乾): the highlighted line is only
        // trustworthy relative to the page the controller itself navigated to, so exact text matching runs first.
        const NSInteger selectedIdentifier = [_candidatePanel selectedCandidate];
        const NSInteger selectedLine = selectedIdentifier == NSNotFound
                                           ? NSNotFound
                                           : [_candidatePanel lineNumberForCandidateWithIdentifier:selectedIdentifier];
        if (selectedLine != NSNotFound && selectedLine >= 0 &&
            static_cast<NSUInteger>(selectedLine) < _visibleCandidateData.count)
        {
            index = _candidatePageStart + static_cast<NSUInteger>(selectedLine);
        }
    }
    if (index == NSNotFound)
    {
        return;
    }
    const metasequoia::LocalInputMode localMode = _sessionSnapshot.local_mode;
    const auto result = [self selectDisplayedCandidateAtIndex:index];
    if (result.handled)
    {
        [self applyResult:result localMode:localMode client:self.client];
    }
}

- (id)composedString:(id)sender
{
    (void)sender;
    return _session == nullptr ? @"" : MetasequoiaStringFromUtf8(_sessionSnapshot.preedit);
}

- (NSAttributedString *)originalString:(id)sender
{
    (void)sender;
    NSString *raw = _session == nullptr ? @"" : MetasequoiaStringFromUtf8(_sessionSnapshot.preedit);
    return [[NSAttributedString alloc] initWithString:raw];
}

- (void)commitComposition:(id)sender
{
    [self cancelVoiceInput];
    if (_session == nullptr || _sessionSnapshot.preedit.empty())
    {
        return;
    }
    const metasequoia::LocalInputMode localMode = _sessionSnapshot.local_mode;
    const auto result = _session->command(metasequoia::Command::CommitRaw);
    if (result.handled)
    {
        [self applyResult:result localMode:localMode client:sender];
    }
}

- (void)prepareForDeactivation:(id)sender
{
    _serverActive = NO;
    [_floatingToolbarPanel deactivateForDelegate:self];
    [self commitComposition:sender];
    [_candidatePanel hide];
    [_shuangpinKeymapPanel orderOut:nil];
}

- (void)deactivateServer:(id)sender
{
    if (gActiveController == self)
        gActiveController = nil;
    [self prepareForDeactivation:sender];
    [super deactivateServer:sender];
}

- (id<MetasequoiaVoiceService>)voiceService
{
    if (!_voiceService)
        _voiceService = [MetasequoiaVoiceInputService new];
    return _voiceService;
}

- (void)cancelVoiceInput
{
    ++_voiceGeneration;
    [_voiceService cancel];
    if (_voiceMouseMonitor)
        [NSEvent removeMonitor:_voiceMouseMonitor];
    _voiceMouseMonitor = nil;
}

// Reached from inside -handleEvent:client: — the voice service calls its completion block inline
// when the settings do not validate and when recording stops — so the modal loop has to be pushed
// off the key-event stack. Running it there froze the client application until the alert was
// dismissed, and this process is LSBackgroundOnly, so the alert itself could be behind that frozen
// window.
- (void)showVoiceError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
      NSAlert *alert = [NSAlert new];
      alert.messageText = @"语音输入未完成";
      alert.informativeText = error.localizedDescription;
      [alert addButtonWithTitle:@"好"];
      [alert runModal];
    });
}

- (void)toggleVoiceInput:(id)sender
{
    (void)sender;
    if (!_serverActive)
        return;
    id<MetasequoiaVoiceService> service = [self voiceService];
    if (service.recording)
    {
        [service stop];
        return;
    }
    if (service.active)
    {
        [self cancelVoiceInput];
        return;
    }
    id client = self.client;
    if (!client)
        return;
    [self commitLeadingCandidate:client];
    const NSUInteger generation = ++_voiceGeneration;
    const NSRange selection =
        [client respondsToSelector:@selector(selectedRange)] ? [client selectedRange] : NSMakeRange(NSNotFound, 0);
    __weak MetasequoiaInputController *weakSelf = self;
    _voiceMouseMonitor =
        [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
                                               handler:^(NSEvent *event) {
                                                 (void)event;
                                                 [weakSelf cancelVoiceInput];
                                               }];
    [service startWithCompletion:^(NSString *text, NSError *error) {
      MetasequoiaInputController *owner = weakSelf;
      if (!owner || !owner->_serverActive || owner->_voiceGeneration != generation || owner.client != client)
          return;
      const NSRange currentSelection =
          [client respondsToSelector:@selector(selectedRange)] ? [client selectedRange] : NSMakeRange(NSNotFound, 0);
      [owner cancelVoiceInput];
      if (!NSEqualRanges(currentSelection, selection))
          return;
      if (error)
      {
          [owner showVoiceError:error];
          return;
      }
      if (text.length > 0)
      {
          NSString *output = MetasequoiaChineseOutputString(text, [owner voiceOutputUsesTraditionalChinese]);
          [client insertText:output replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
      }
    }];
}

- (void)showVoiceSettings:(id)sender
{
    (void)sender;
    [self cancelVoiceInput];
    // 语音设置现在是设置窗里的一页,不再是独立窗口 —— 从菜单进来的人和从侧栏进来的人看到同一个东西。
    [[MetasequoiaPreferencesWindowController sharedController] showVoiceInput:nil];
}

- (void)showPreferences:(id)sender
{
    (void)sender;
    [[MetasequoiaPreferencesWindowController sharedController] showAndActivate];
}

- (void)checkForUpdates:(id)sender
{
    [[MetasequoiaUpdateController sharedController] checkForUpdates:sender];
}

- (void)openCharacterPalette:(id)sender
{
    (void)sender;
    // The Character Viewer inserts straight into the client, so settle any marked text first; otherwise the session
    // would resend the pending composition after the inserted symbol.
    [self commitLeadingCandidate:self.client];
    [NSApp orderFrontCharacterPalette:nil];
}

- (void)setEnglishInputMode:(BOOL)enabled client:(id)sender
{
    if (enabled)
    {
        [self commitLeadingCandidate:sender];
    }
    _candidateSelection.reset();
    [_candidatePanel hide];
    [_shuangpinKeymapPanel orderOut:nil];
    [MetasequoiaPreferencesWindowController setEnglishInputMode:enabled];
    NSString *identifier = [sender respondsToSelector:@selector(bundleIdentifier)] ? [sender bundleIdentifier] : nil;
    MetasequoiaRememberEnglishMode(identifier, enabled);
    // Every route into a mode switch -- Shift, Shift+Space, the toolbar, the input menu -- passes
    // through here, so the badge is raised here rather than at each of them.
    if ([MetasequoiaPreferencesWindowController storedInputModeHUDEnabled])
    {
        NSRect caretRect = NSZeroRect;
        id client = sender != nil ? sender : self.client;
        [client attributesForCharacterIndex:0 lineHeightRectangle:&caretRect];
        [[MetasequoiaInputModeHUDPanel sharedPanel] showEnglishInputMode:enabled nearCaretRect:caretRect];
    }
}

// Shift tapped on its own: with letters on screen it commits them as typed, which is how a word the
// dictionary does not carry leaves in the middle of Chinese input; with nothing composing it
// switches between Chinese and English.
- (void)handleSolitaryShiftFlags:(NSEvent *)event client:(id)sender
{
    if (!_solitaryShift.flagsChanged(event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask,
                                     event.timestamp))
    {
        return;
    }
    const bool composing = _session != nullptr && !_sessionSnapshot.preedit.empty();
    switch (metasequoia::mac::ActionForSolitaryShift(
        [MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled], composing))
    {
    case metasequoia::mac::SolitaryShiftAction::CommitComposition:
        [self commitComposition:sender];
        break;
    case metasequoia::mac::SolitaryShiftAction::ToggleInputMode:
        [self setEnglishInputMode:![MetasequoiaPreferencesWindowController storedEnglishInputMode] client:sender];
        break;
    case metasequoia::mac::SolitaryShiftAction::Ignore:
        break;
    }
}

- (void)floatingToolbarDidRequestToggleInputMode:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self setEnglishInputMode:![MetasequoiaPreferencesWindowController storedEnglishInputMode] client:self.client];
}

- (void)floatingToolbarDidRequestTogglePunctuation:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self commitLeadingCandidate:self.client];
    [MetasequoiaPreferencesWindowController
        setChinesePunctuationEnabled:![MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled]];
    if (_session != nullptr)
    {
        [self reloadSessionFromPreferences];
    }
}

- (void)floatingToolbarDidRequestToggleFullWidth:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [MetasequoiaPreferencesWindowController
        setFullWidthInputEnabled:![MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]];
}

- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [MetasequoiaPreferencesWindowController
        setTraditionalChineseOutputEnabled:![MetasequoiaPreferencesWindowController
                                               storedTraditionalChineseOutputEnabled]];
}

- (void)floatingToolbarDidRequestOpenCharacterPalette:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self openCharacterPalette:nil];
}

- (void)floatingToolbarDidRequestOpenSettings:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self showPreferences:nil];
}

- (void)floatingToolbarDidRequestCheckForUpdates:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self checkForUpdates:nil];
}

- (void)floatingToolbarDidRequestOpenWebsite:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://msime.app/"]];
}

- (void)floatingToolbarDidRequestHide:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [MetasequoiaPreferencesWindowController setFloatingToolbarEnabled:NO];
}

- (void)selectChineseMode:(id)sender
{
    (void)sender;
    [self setEnglishInputMode:NO client:self.client];
}

- (void)selectEnglishMode:(id)sender
{
    (void)sender;
    [self setEnglishInputMode:YES client:self.client];
}

- (void)selectSimplifiedOutput:(id)sender
{
    (void)sender;
    [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:NO];
}

- (void)selectTraditionalOutput:(id)sender
{
    (void)sender;
    [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:YES];
}

- (NSMenu *)menu
{
    return CreateMetasequoiaInputMenu(self, [MetasequoiaPreferencesWindowController storedEnglishInputMode],
                                      [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled]);
}

- (NSUInteger)recognizedEvents:(id)sender
{
    (void)sender;
    // Shift on its own never arrives as a key: the only record of it is the pair of flag changes
    // around it, so those have to be recognised for the tap to be seen at all.
    return NSEventMaskKeyDown | NSEventMaskFlagsChanged;
}
@end
