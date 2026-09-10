#include "LocalResourceModes.h"
extern "C" void MSIMERecordTypingStatistics(const char *text, const char *source);
#import "MetasequoiaInputController.h"

#import "DictionaryInstaller.h"
#include "DictionaryRuntime.h"
#include "WritingSelection.h"
#include "../../../shared/apple-bridge/DictionarySessionLease.h"
#import "FloatingToolbarPanel.h"
#import "ChineseTextConversion.h"
#include "CandidateFontSize.h"
#import "CandidatePanel.h"
#include "CandidateDisplay.h"
#include "CandidatePageSize.h"
#include "CandidatePanelStyle.h"
#import "InputMenu.h"
#include "InputModeRouting.h"
#include "FullWidthInput.h"
#include "HelpcodeSchemaPreference.h"
#include "InputSchemePreference.h"
#include "KeyFeedback.h"
#include "WubiCommitPolicy.h"
#import "PreferencesWindowController.h"
#import "VoiceInputService.h"
#import "VoiceSettings.h"
#import "ShuangpinKeymapPanel.h"
#import "UpdateController.h"
#include "StringConversion.h"
#include "CandidateSelectionState.h"
#include "InputControllerKeyRouting.h"
#include <metasequoia/session.h>
#include "../../../vendor/MetasequoiaImeEngine/contracts/punctuation/policy.h"

#import <Carbon/Carbon.h>

#include <memory>
#include <cmath>
#include <string>

namespace
{
constexpr NSTimeInterval kDictionaryRetryDelay = 2.0;

struct SessionPreferences
{
    SchemeType scheme;
    bool autocorrectEnabled;
    bool helpcodeEnabled;
    std::string helpcodeSchema;
    bool chinesePunctuationEnabled;
    metasequoia::mac::CandidatePanelStyle candidatePanelStyle;
    size_t candidatePageSize;
    size_t candidateFontSize;
    bool candidateLearningEnabled;
    bool wubiAutoCommitUniqueEnabled;
    std::uint32_t fuzzyPinyinRules;
    std::string shuangpinProfile;
    bool nineKeyEnabled;
};

SessionPreferences ReadSessionPreferences()
{
    const SchemeType scheme = metasequoia::mac::EngineSchemeForStoredPreference(
        static_cast<int>([MetasequoiaPreferencesWindowController storedScheme]));
    const NSInteger helpcodeSchema = scheme == SchemeType::Shuangpin
                                         ? [MetasequoiaPreferencesWindowController storedShuangpinHelpcodeSchema]
                                         : [MetasequoiaPreferencesWindowController storedQuanpinHelpcodeSchema];
    return {
        scheme,
        [MetasequoiaPreferencesWindowController storedAutocorrectEnabled] == YES,
        [MetasequoiaPreferencesWindowController storedHelpcodeEnabled] == YES,
        metasequoia::mac::HelpcodeSchemaIdentifier(static_cast<int>(helpcodeSchema)),
        [MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled] == YES,
        metasequoia::mac::NormalizeCandidatePanelStyle(
            [MetasequoiaPreferencesWindowController storedCandidatePanelStyle]),
        metasequoia::mac::NormalizeCandidatePageSize(
            static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidatePageSize])),
        metasequoia::mac::NormalizeCandidateFontSize(
            static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidateFontSize])),
        [MetasequoiaPreferencesWindowController storedCandidateLearningEnabled] == YES,
        [MetasequoiaPreferencesWindowController storedWubiAutoCommitUniqueEnabled] == YES,
        static_cast<std::uint32_t>([MetasequoiaPreferencesWindowController activeFuzzyPinyinRules]),
        [MetasequoiaPreferencesWindowController storedShuangpinProfile].UTF8String,
        scheme == SchemeType::Quanpin && [NSUserDefaults.standardUserDefaults boolForKey:@"MetasequoiaImeNineKeyEnabled"],
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
    return options.scheme == preferences.scheme && options.autocorrect == preferences.autocorrectEnabled &&
           helpcodeMatches && options.chinese_punctuation == preferences.chinesePunctuationEnabled &&
           options.learning == preferences.candidateLearningEnabled &&
           options.fuzzy_pinyin.rules == preferences.fuzzyPinyinRules &&
           (preferences.scheme != SchemeType::Shuangpin || options.shuangpin_profile.name == preferences.shuangpinProfile);
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
    metasequoia::SessionOptions _sessionOptions;
    bool _nineKeyEnabled;
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
    MSIMEWritingSelection *_writingSelection;
    id _writingMouseMonitor;
    id _writingActivationObserver;
    BOOL _writingRestoring;
    BOOL _shuangpinKeymapEnabled;
    BOOL _localInputModesEnabled;
    NSTimeInterval _dictionaryRetryAfter;
    id<MetasequoiaVoiceService> _voiceService;
    NSUInteger _voiceGeneration;
    id _voiceMouseMonitor;
}

+ (void)initialize
{
    if (self != MetasequoiaInputController.class) return;
    [[NSDistributedNotificationCenter defaultCenter]
        addObserver:self selector:@selector(releaseIdleDictionarySessions:)
               name:MetasequoiaReleaseIdleDictionarySessionsNotification object:nil
        suspensionBehavior:NSNotificationSuspensionBehaviorDeliverImmediately];
}

+ (void)releaseIdleDictionarySessions:(NSNotification *)notification
{
    if (![notification.object isKindOfClass:NSString.class]) return;
    NSString *directory = notification.object;
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([directory isEqualToString:MetasequoiaDictionaryUserDirectory().URLByStandardizingPath.path])
            [self suspendForCloudDictionarySwitch];
    });
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
    }
    return self;
}

- (void)dealloc
{
    [self cancelWritingSelection];
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
    [_floatingToolbarPanel updateJapaneseScheme:[MetasequoiaPreferencesWindowController storedScheme] == 3
                                    englishMode:[MetasequoiaPreferencesWindowController storedEnglishInputMode]];
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
    const BOOL englishMode = [MetasequoiaPreferencesWindowController storedEnglishInputMode];
    if (englishMode || storedScheme != 1 || !_shuangpinKeymapEnabled)
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
    if (_session != nullptr && _sessionSnapshot.dedicated_english == static_cast<bool>(englishMode) &&
        _nineKeyEnabled == (preferences.nineKeyEnabled && !englishMode) &&
        helpcodeSchemaMatches && SessionMatchesPreferences(_sessionOptions, preferences) &&
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
    options.shuangpin_profile = GetShuangpinProfile(preferences.shuangpinProfile);
    options.autocorrect = preferences.autocorrectEnabled;
    options.helpcode = preferences.helpcodeEnabled;
    options.helpcode_schema = preferences.helpcodeSchema;
    options.chinese_punctuation = preferences.chinesePunctuationEnabled;
    options.learning = preferences.candidateLearningEnabled;
    options.fuzzy_pinyin.rules = preferences.fuzzyPinyinRules;
    options.local_modes = metasequoia::mac::LocalResourceModes(_localInputModesEnabled, paths);
    _session = std::make_unique<metasequoia::Session>(options);
    _session->set_dedicated_english(englishMode);
    _nineKeyEnabled = preferences.nineKeyEnabled && !englishMode;
    _session->set_nine_key_enabled(_nineKeyEnabled);
    _sessionOptions = options;
    [_shuangpinKeymapPanel setProfileName:@(options.shuangpin_profile.name.c_str())];
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
    // Preparation keeps the legacy dictionary available on a busy reader or a
    // failed bundle check. An active composition is never interrupted.
    if (!MetasequoiaPrepareBundledDictionaryRuntime(NSBundle.mainBundle.resourceURL, &error))
        NSLog(@"Full dictionary preparation deferred: %@", error.localizedDescription);
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
    [super activateServer:sender];
    _serverActive = YES;
    _dictionaryRetryAfter = 0.0;
    if (metasequoia::mac::ShouldPrepareInputSession([MetasequoiaPreferencesWindowController storedEnglishInputMode]) &&
        [self prepareSessionIfNeeded])
    {
        [self reloadSessionFromPreferences];
    }
    [self refreshFloatingToolbar];
    [_floatingToolbarPanel activateForDelegate:self
                                       visible:[MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]];
}

- (void)trackCandidateAtIndex:(NSUInteger)index
{
    if (_session == nullptr || index >= _candidateData.count || index >= _sessionSnapshot.candidates.size())
    {
        return;
    }

    _candidateSelection.update(static_cast<size_t>(index), _sessionSnapshot.candidates[index].word);
    _candidateHighlightedIndex = index;
    _candidatePageStart = metasequoia::mac::CandidatePageStart(index, _candidateData.count, _candidatePageSize);
}

- (void)showCurrentCandidatePage
{
    // On macOS 26, selectionKeys does not reliably limit the visible list.
    // Own page boundaries here; retain global engine indices on each string.
    const NSUInteger count = std::min(_candidatePageSize, _candidateData.count - _candidatePageStart);
    _visibleCandidateData = [_candidateData subarrayWithRange:NSMakeRange(_candidatePageStart, count)];
    _candidateLineIdentifiersCollapsed = NO;
    _candidatePanel.hasPreviousPage = _candidatePageStart > 0;
    _candidatePanel.hasNextPage = _candidatePageStart + count < _candidateData.count;
    NSRect caretRect = NSZeroRect;
    [self.client attributesForCharacterIndex:0 lineHeightRectangle:&caretRect];
    _candidatePanel.caretRect = caretRect;
    [_candidatePanel setCandidateData:_visibleCandidateData];
    [_candidatePanel show:kIMKLocateCandidatesBelowHint];
    if (count >= 2)
    {
        const NSInteger first = [_candidatePanel candidateIdentifierAtLineNumber:0];
        const NSInteger second = [_candidatePanel candidateIdentifierAtLineNumber:1];
        _candidateLineIdentifiersCollapsed = first != NSNotFound && first == second;
    }
}

- (void)candidatePanelChooseSpelling:(NSUInteger)index text:(NSString *)text
{
    if (!_session || !_nineKeyEnabled || ![_candidatePanel isVisible]) return;
    const auto snapshot = _session->snapshot();
    if (index >= snapshot.nine_key_spellings.size() ||
        ![text isEqualToString:@(snapshot.nine_key_spellings[index].c_str())]) return;
    const auto result = _session->choose_nine_key_spelling(index);
    if (result.handled) [self applyResult:result localMode:snapshot.local_mode client:self.client];
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
    if (event.type != NSEventTypeKeyDown)
    {
        return NO;
    }
    [self cancelWritingSelection];
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
    if (![MetasequoiaPreferencesWindowController storedEnglishInputMode] &&
        metasequoia::mac::IsFullWidthInputToggle(event.keyCode, inputModeModifiers))
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
    if ((modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0)
    {
        [self commitLeadingCandidate:sender];
        return NO;
    }

    if (_sessionSnapshot.dedicated_english)
    {
        NSString *text = event.characters;
        const unichar character = text.length == 1 ? [text characterAtIndex:0] : 0;
        if ((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z'))
        {
            const auto result = _session->character(static_cast<char>(character));
            if (result.handled) metasequoia::mac::PlayHandledKeyFeedback(event);
            [self applyResult:result
                    localMode:metasequoia::LocalInputMode::None client:sender];
            return YES;
        }
        if (event.keyCode == kVK_Tab && (modifiers & NSEventModifierFlagShift) == 0 &&
            !_sessionSnapshot.preedit.empty())
        {
            const auto result = _candidateSelection.commit(*_session);
            if (result.handled) metasequoia::mac::PlayHandledKeyFeedback(event);
            [self applyResult:result
                    localMode:metasequoia::LocalInputMode::None client:sender];
            return YES;
        }
        // Native word boundaries preserve raw spelling unless the user navigated
        // to a completion. Return NO so the host receives its space, digit,
        // punctuation, or Return exactly once. These never select a numbered word.
        const BOOL navigation = event.keyCode == kVK_LeftArrow || event.keyCode == kVK_RightArrow ||
            event.keyCode == kVK_UpArrow || event.keyCode == kVK_DownArrow ||
            event.keyCode == kVK_PageUp || event.keyCode == kVK_PageDown ||
            event.keyCode == kVK_Home || event.keyCode == kVK_End;
        if (!navigation && event.keyCode != kVK_Delete && event.keyCode != kVK_Escape)
        {
            [self commitLeadingCandidate:sender];
            return NO;
        }
    }

    if (_nineKeyEnabled && event.keyCode == kVK_Tab && modifiers == 0 &&
        !_sessionSnapshot.nine_key_spellings.empty() && [_candidatePanel isVisible] &&
        [_candidatePanel respondsToSelector:@selector(showNineKeySpellings)]) {
        [_candidatePanel showNineKeySpellings];
        return YES;
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
    switch (metasequoia::mac::ClassifyControllerKey(
        event.keyCode, [_candidatePanel isVisible],
        metasequoia::mac::NormalizeCandidatePageShortcut(
            static_cast<int>([MetasequoiaPreferencesWindowController storedCandidatePageShortcut])),
        candidatePageShortcutCharacter, candidatePageShortcutModified))
    {
    case metasequoia::mac::ControllerKeyAction::MoveCandidateLeft:
    case metasequoia::mac::ControllerKeyAction::MoveCandidateRight:
    case metasequoia::mac::ControllerKeyAction::MoveCandidateUp:
    case metasequoia::mac::ControllerKeyAction::MoveCandidateDown: {
        if (!metasequoia::mac::IsPrimaryCandidateDirection(event.keyCode, _candidatePanel.panelType))
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
        result = _sessionSnapshot.scheme == SchemeType::JapaneseRomaji ||
                 _sessionSnapshot.local_mode == metasequoia::LocalInputMode::TemporaryJapanese
            ? _session->finish(_candidateSelection.live_selected_index(_sessionSnapshot).value_or(0))
            : _session->command(metasequoia::Command::CommitRaw);
        break;
    case metasequoia::mac::ControllerKeyAction::Cancel:
        result = _session->command(metasequoia::Command::Cancel);
        break;
    case metasequoia::mac::ControllerKeyAction::CommitCandidate:
        result = _candidateSelection.commit(*_session);
        break;
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
            else if (character == ';' && _sessionOptions.scheme == SchemeType::Shuangpin && !_sessionSnapshot.preedit.empty())
            {
                result = _session->character(';');
                if (!result.handled) result = _session->punctuation(';');
            }
            else if (character == '\'' && !_sessionSnapshot.preedit.empty())
            {
                result = _session->character(static_cast<char>(character));
            }
            // Unicode mode reads a hex code point, so while it is open its digits and its optional
            // "+" are input rather than candidate numbers. Every other local mode takes letters
            // only and leaves the digits to selection, which is what they already did.
            else if ((character >= '0' && character <= '9') || character == '+')
            {
                if (_sessionSnapshot.local_mode == metasequoia::LocalInputMode::Unicode ||
                    (_nineKeyEnabled && _sessionSnapshot.local_mode == metasequoia::LocalInputMode::None && character >= '2' && character <= '9' &&
                     (_sessionSnapshot.preedit.empty() || (!_sessionSnapshot.editing_text.empty() &&
                      std::all_of(_sessionSnapshot.editing_text.begin(), _sessionSnapshot.editing_text.end(),
                                  [](char digit) { return digit >= '2' && digit <= '9'; })))))
                {
                    result = _session->character(static_cast<char>(character));
                }
                else if (character >= '1' && character <= '9')
                {
                    result =
                        _candidateSelection.commit_number(*_session, static_cast<char>(character), _candidatePageSize);
                    if (!result.handled && !_sessionSnapshot.preedit.empty())
                    {
                        return YES;
                    }
                }
            }
            // Keep the host's routing predicate tied to the Engine punctuation contract. The
            // Session still owns translation and stateful quote/book-title behaviour.
            else if (metasequoia::punctuation_contract::is_supported(static_cast<char>(character)))
            {
                result = _session->punctuation(static_cast<char>(character));
            }
        }
        break;
    }
    }

    if (!result.handled)
    {
        _sessionSnapshot = _session->snapshot();
        [self commitLeadingCandidate:sender];
        if (_session != nullptr && !_sessionSnapshot.dedicated_english && _sessionSnapshot.preedit.empty() &&
            [MetasequoiaPreferencesWindowController storedFullWidthInputEnabled] && event.characters.length == 1)
        {
            const unichar character = [event.characters characterAtIndex:0];
            if (metasequoia::mac::IsFullWidthConvertibleCharacter(character))
            {
                const unichar fullWidthCharacter = metasequoia::mac::FullWidthCharacter(character);
                NSString *converted = [NSString stringWithCharacters:&fullWidthCharacter length:1];
                [sender insertText:converted replacementRange:NSMakeRange(NSNotFound, NSNotFound)];
                if (sender != nil) [self recordCommittedText:converted source:@"local"];
                return YES;
            }
        }
        return NO;
    }
    metasequoia::mac::PlayHandledKeyFeedback(event);
    [self applyResult:result localMode:localModeForKey client:sender];
    return YES;
}

- (metasequoia::KeyResult)finishRawInput
{
    // CommitRaw explicitly learns English. finish with an out-of-range index
    // is the public Engine operation for completing raw text without learning.
    const bool learnEnglish = _sessionOptions.learning &&
        _sessionOptions.paths.dictionaries != _sessionOptions.paths.user_data;
    if (_sessionSnapshot.dedicated_english && !learnEnglish)
        return _session->finish(_sessionSnapshot.candidates.size());
    return _session->command(metasequoia::Command::CommitRaw);
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
    const auto selection = _candidateSelection.live_selected_index(_sessionSnapshot);
    const auto result = _sessionSnapshot.dedicated_english && !selection
        ? [self finishRawInput] : _session->finish(selection.value_or(0));
    if (result.handled)
    {
        [self applyResult:result localMode:localMode client:sender];
    }
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
// never has one. Honor the stored Japanese scheme before a session is available too.
- (BOOL)voiceOutputUsesTraditionalChinese
{
    return _session != nullptr ? [self traditionalChineseOutputActive]
                               : ([MetasequoiaPreferencesWindowController storedScheme] != 3 &&
                                  [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled]);
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
        NSString *source = _sessionSnapshot.dedicated_english ? @"english" : localMode != metasequoia::LocalInputMode::None ? @"local" :
            _sessionOptions.scheme == SchemeType::Shuangpin ?
                (_sessionOptions.shuangpin_profile.name == "xiaohe" ? @"shuangpin" : @(_sessionOptions.shuangpin_profile.name.c_str())) :
            _sessionOptions.scheme == SchemeType::Wubi ? @"wubi" :
            _sessionOptions.scheme == SchemeType::JapaneseRomaji ? @"japanese" : @"quanpin";
        if (client != nil) [self recordCommittedText:commit source:source];
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
    const BOOL isShuangpin = _session != nullptr && !_sessionSnapshot.dedicated_english &&
        _sessionSnapshot.scheme == SchemeType::Shuangpin;
    if (!MetasequoiaShouldShowShuangpinKeymap(isShuangpin, _shuangpinKeymapEnabled, hasComposition) || client == nil)
    {
        [_shuangpinKeymapPanel orderOut:nil];
        return;
    }

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

- (void)rebuildCandidatePanelPreservingSelection:(BOOL)preserveSelection
{
    _sessionSnapshot = _session->snapshot();
    if ([_candidatePanel respondsToSelector:@selector(setNineKeySpellings:)]) {
        NSMutableArray<NSString *> *spellings = [NSMutableArray array];
        for (const auto &value : _sessionSnapshot.nine_key_spellings) [spellings addObject:@(value.c_str())];
        _candidatePanel.nineKeySpellings = spellings;
    }
    const std::optional<size_t> preservedSelection =
        preserveSelection ? _candidateSelection.selected_index() : std::nullopt;
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
    const bool annotateHelpcodes = (_sessionOptions.helpcode && SchemeUsesHelpcodes(_sessionSnapshot.scheme)) &&
                                   metasequoia::mac::HelpcodesAnnotateLocalMode(localMode);
    NSUInteger candidateIndex = 0;
    for (const WordItem &candidate : _sessionSnapshot.candidates)
    {
        NSString *display = MetasequoiaStringFromUtf8(metasequoia::mac::CandidateDisplayText(
            candidate, _sessionSnapshot.scheme, annotateHelpcodes, _activeHelpcodeKeymap.get()));
        NSString *convertedDisplay = MetasequoiaChineseOutputString(display, traditionalOutput);
        [data addObject:MetasequoiaIndexedCandidateString(convertedDisplay, candidateIndex)];
        ++candidateIndex;
    }
    _candidateData = [data copy];
    if (!_sessionSnapshot.preedit.empty() && _candidateData.count > 0)
    {
        const NSUInteger selectedIndex =
            preservedSelection.has_value() && preservedSelection.value() < _candidateData.count
                ? preservedSelection.value()
                : 0;
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
        if (!_sessionSnapshot.nine_key_spellings.empty()) {
            _candidatePanel.hasPreviousPage = NO; _candidatePanel.hasNextPage = NO;
            NSRect caret = NSZeroRect;
            [self.client attributesForCharacterIndex:0 lineHeightRectangle:&caret];
            _candidatePanel.caretRect = caret;
            [_candidatePanel show:kIMKLocateCandidatesBelowHint];
        } else [_candidatePanel hide];
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
    if (index == NSNotFound || index >= _sessionSnapshot.candidates.size())
    {
        return;
    }
    const metasequoia::LocalInputMode localMode = _sessionSnapshot.local_mode;
    const auto result = _session->select(static_cast<size_t>(index));
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
    const auto result = [self finishRawInput];
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
          if (client != nil) [owner recordCommittedText:output source:@"voice"];
      }
    }];
}

- (void)recordCommittedText:(NSString *)text source:(NSString *)source
{
    if (text.length > 0) MSIMERecordTypingStatistics(text.UTF8String, source.UTF8String);
}

- (void)showVoiceSettings:(id)sender
{
    (void)sender;
    [self cancelVoiceInput];
    [[MetasequoiaVoiceSettingsWindow sharedController] showAndActivate];
}

- (void)cancelWritingSelection
{
    _writingSelection.valid = NO;
    _writingSelection = nil;
    if (_writingMouseMonitor) [NSEvent removeMonitor:_writingMouseMonitor];
    _writingMouseMonitor = nil;
    if (_writingActivationObserver)
        [NSWorkspace.sharedWorkspace.notificationCenter removeObserver:_writingActivationObserver];
    _writingActivationObserver = nil;
    _writingRestoring = NO;
}

- (void)showWritingError:(NSError *)error
{
    dispatch_async(dispatch_get_main_queue(), ^{
        NSAlert *alert = [NSAlert new];
        alert.messageText = @"无法读取选中文字"; alert.informativeText = error.localizedDescription;
        [alert addButtonWithTitle:@"好"]; [alert runModal];
    });
}

- (void)showWritingAssistant:(id)sender
{
    (void)sender;
    [self cancelWritingSelection];
    if (!_serverActive || (_session && !_sessionSnapshot.preedit.empty())) return;
    MSIMEWritingSelection *selection = [MSIMEWritingSelection capture:self.client];
    NSRunningApplication *application = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!selection || !application || application.processIdentifier == NSProcessInfo.processInfo.processIdentifier)
    {
        [self showWritingError:[NSError errorWithDomain:@"app.msime.writing" code:1 userInfo:@{
            NSLocalizedDescriptionKey: @"请完成输入，再选中要润色的文字。此应用需要支持输入法读取选区；也可从账户窗口粘贴文字。"}]];
        return;
    }
    _writingSelection = selection;
    __weak MetasequoiaInputController *weakSelf = self;
    _writingMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
        handler:^(NSEvent *event) { (void)event; [weakSelf cancelWritingSelection]; }];
    _writingActivationObserver = [NSWorkspace.sharedWorkspace.notificationCenter
        addObserverForName:NSWorkspaceDidActivateApplicationNotification object:nil queue:NSOperationQueue.mainQueue
        usingBlock:^(NSNotification *note) {
            MetasequoiaInputController *owner = weakSelf;
            NSRunningApplication *active = note.userInfo[NSWorkspaceApplicationKey];
            if (!owner) return;
            if (active.processIdentifier != NSProcessInfo.processInfo.processIdentifier &&
                !(owner->_writingRestoring && active.processIdentifier == application.processIdentifier))
                [owner cancelWritingSelection];
        }];
    BOOL (^validate)(void) = ^BOOL {
        MetasequoiaInputController *owner = weakSelf;
        return owner && owner->_writingSelection == selection && [selection matches:owner.client];
    };
    void (^restore)(void) = ^{
        MetasequoiaInputController *owner = weakSelf;
        if (!owner || owner->_writingSelection != selection) return;
        owner->_writingRestoring = YES;
        [application activateWithOptions:NSApplicationActivateIgnoringOtherApps];
    };
    BOOL (^apply)(NSString *, NSString *) = ^BOOL(NSString *text, NSString *source) {
        MetasequoiaInputController *owner = weakSelf;
        if (!owner || !owner->_serverActive || !owner->_writingRestoring || !validate() ||
            NSWorkspace.sharedWorkspace.frontmostApplication.processIdentifier != application.processIdentifier)
            return NO;
        if (![selection replace:text client:owner.client]) return NO;
        [owner recordCommittedText:text source:[source isEqualToString:@"reply"] ? @"reply" : @"ai"];
        [owner cancelWritingSelection];
        return YES;
    };
    Class bridge = NSClassFromString(@"MSIMEMacWriting");
    SEL show = NSSelectorFromString(@"show:");
    if (!bridge || ![bridge respondsToSelector:show]) { [self cancelWritingSelection]; return; }
    using Show = void (*)(id, SEL, NSDictionary *);
    NSDictionary *parameters = @{@"text": selection.text, @"validate": validate, @"restore": restore,
        @"apply": apply, @"cancel": ^{
            MetasequoiaInputController *owner = weakSelf;
            if (owner && owner->_writingSelection == selection) [owner cancelWritingSelection];
        }};
    // Leave the host's key/menu callback before presenting an activating window.
    dispatch_async(dispatch_get_main_queue(), ^{
        reinterpret_cast<Show>([bridge methodForSelector:show])(bridge, show, parameters);
    });
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
    [self commitLeadingCandidate:sender];
    _candidateSelection.reset();
    [_candidatePanel hide];
    [_shuangpinKeymapPanel orderOut:nil];
    [MetasequoiaPreferencesWindowController setEnglishInputMode:enabled];
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
                                      [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled],
                                      [MetasequoiaPreferencesWindowController storedScheme] == 3);
}

- (NSUInteger)recognizedEvents:(id)sender
{
    (void)sender;
    return NSEventMaskKeyDown;
}
@end
