#import "MetasequoiaInputController.h"

#import "DictionaryInstaller.h"
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
#include "WubiCommitPolicy.h"
#import "PreferencesWindowController.h"
#import "VoiceInputService.h"
#import "VoiceSettings.h"
#import "ShuangpinKeymapPanel.h"
#import "UpdateController.h"
#include "StringConversion.h"
#include "CandidateSelectionState.h"
#include "InputControllerKeyRouting.h"
#include "core/input_session.h"
#include "common/helpcode_utils.h"

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
    };
}

// helpcode_enabled() reports false for every scheme that has no helpcodes, so comparing it directly can never match a Wubi session built with the preference on, and the caller would rebuild the engine on every keystroke. Only the schemes that carry helpcodes can be compared on it.
bool SchemeUsesHelpcodes(SchemeType scheme)
{
    return scheme == SchemeType::Quanpin || scheme == SchemeType::Shuangpin;
}

bool SessionMatchesPreferences(const metasequoia::InputSession &session, const SessionPreferences &preferences)
{
    const bool helpcodeMatches = !SchemeUsesHelpcodes(preferences.scheme) ||
                                 session.helpcode_enabled() == preferences.helpcodeEnabled;
    return session.scheme_type() == preferences.scheme &&
           session.quanpin_autocorrect_enabled() == preferences.autocorrectEnabled &&
           helpcodeMatches &&
           session.chinese_punctuation_enabled() == preferences.chinesePunctuationEnabled &&
           session.candidate_learning_enabled() == preferences.candidateLearningEnabled;
}
} // namespace

@interface MetasequoiaInputController () <MetasequoiaFloatingToolbarDelegate, MetasequoiaCandidatePanelDelegate>
@end

@implementation MetasequoiaInputController
{
    std::unique_ptr<metasequoia::InputSession> _session;
    std::string _activeHelpcodeSchema;
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
        [_candidatePanel setAttributes:metasequoia::mac::CandidatePanelAttributes(
                                           static_cast<size_t>([MetasequoiaPreferencesWindowController storedCandidateFontSize]))];

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
    [_voiceService cancel];
    if (_voiceMouseMonitor) [NSEvent removeMonitor:_voiceMouseMonitor];
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
    [_floatingToolbarPanel
        setVisible:[MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]
       forDelegate:self];
}

- (void)floatingToolbarPreferenceDidChange:(NSNotification *)notification
{
    [self refreshFloatingToolbar];
    if ([notification.name isEqualToString:MetasequoiaTraditionalChineseOutputDidChangeNotification] &&
        _serverActive && _session != nullptr && _session->has_composition())
    {
        [self refreshCandidatePanelPreservingSelection];
    }
}

- (void)prepareForLearnedDataReset:(NSNotification *)notification
{
    (void)notification;
    [self commitLeadingCandidate:self.client];
    _session.reset();
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
    const NSInteger storedScheme = [MetasequoiaPreferencesWindowController storedScheme];
    _shuangpinKeymapEnabled = [MetasequoiaPreferencesWindowController storedShuangpinKeymapEnabled];
    if (storedScheme != 1 || !_shuangpinKeymapEnabled)
    {
        [_shuangpinKeymapPanel orderOut:nil];
    }
    if (_session != nullptr && _session->has_composition())
    {
        HelpcodeUtils::select_helpcode_schema(_activeHelpcodeSchema);
        return;
    }

    const SessionPreferences preferences = ReadSessionPreferences();
    [_candidatePanel setPanelType:metasequoia::mac::CandidatePanelTypeForStyle(preferences.candidatePanelStyle)];
    _candidatePageSize = preferences.candidatePageSize;
    [_candidatePanel setSelectionKeys:metasequoia::mac::CandidateSelectionKeys(_candidatePageSize)];
    [_candidatePanel setAttributes:metasequoia::mac::CandidatePanelAttributes(preferences.candidateFontSize)];
    _wubiAutoCommitUniqueEnabled = preferences.wubiAutoCommitUniqueEnabled;
    const bool helpcodeSchemaMatches = _activeHelpcodeSchema == preferences.helpcodeSchema;
    HelpcodeUtils::select_helpcode_schema(preferences.helpcodeSchema);
    _activeHelpcodeSchema = preferences.helpcodeSchema;
    // Applied above the early return, like every other preference a live session can take. It used
    // to be applied only to a freshly constructed session, and SessionMatchesPreferences does not
    // compare it, so toggling 启用本地输入模式 changed nothing until something unrelated forced a
    // rebuild. set_local_mode_options is a plain setter and is safe on a running session.
    [self applyLocalInputModeOptions];
    if (_session != nullptr && helpcodeSchemaMatches && SessionMatchesPreferences(*_session, preferences))
    {
        return;
    }
    _session = std::make_unique<metasequoia::InputSession>(
        preferences.scheme, preferences.autocorrectEnabled, preferences.helpcodeEnabled,
        preferences.chinesePunctuationEnabled, preferences.candidateLearningEnabled);
    [self applyLocalInputModeOptions];
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
- (void)applyLocalInputModeOptions
{
    if (_session == nullptr)
    {
        return;
    }

    _localInputModesEnabled = [MetasequoiaPreferencesWindowController storedLocalInputModesEnabled];
    metasequoia::LocalModeOptions options;
    options.unicode = _localInputModesEnabled;
    options.date_time = _localInputModesEnabled;
    options.quick_phrase = _localInputModesEnabled;
    options.super_jianpin = _localInputModesEnabled;
    options.emoji = false;
    options.kaomoji = false;
    options.temporary_english = false;
    options.temporary_japanese = false;
    _session->set_local_mode_options(options);
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
    [self reloadSessionFromPreferences];
    return _session != nullptr;
}

- (void)activateServer:(id)sender
{
    [super activateServer:sender];
    _serverActive = YES;
    _dictionaryRetryAfter = 0.0;
    if (metasequoia::mac::ShouldPrepareInputSession(
            [MetasequoiaPreferencesWindowController storedEnglishInputMode]) &&
        [self prepareSessionIfNeeded])
    {
        [self reloadSessionFromPreferences];
    }
    [self refreshFloatingToolbar];
    [_floatingToolbarPanel
        activateForDelegate:self
                    visible:[MetasequoiaPreferencesWindowController storedFloatingToolbarEnabled]];
}

- (void)trackCandidateAtIndex:(NSUInteger)index
{
    if (_session == nullptr || index >= _candidateData.count || index >= _session->candidates().size())
    {
        return;
    }

    _candidateSelection.update(static_cast<size_t>(index), _session->candidates()[index].word);
    _candidateHighlightedIndex = index;
    _candidatePageStart = metasequoia::mac::CandidatePageStart(
        index, _candidateData.count, _candidatePageSize);
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
    const BOOL lineMappingIsUsable = !_candidateLineIdentifiersCollapsed && identifier != NSNotFound &&
        [_candidatePanel lineNumberForCandidateWithIdentifier:identifier] == static_cast<NSInteger>(line);
    BOOL selected = NO;
    if (lineMappingIsUsable)
    {
        selected = [_candidatePanel selectCandidateWithIdentifier:identifier] &&
            [[_candidatePanel selectedCandidateString].string isEqualToString:[_candidateData[index] string]];
    }
    else if (_candidateLineIdentifiersCollapsed &&
             NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26)
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
    const NSEventModifierFlags voiceModifiers = event.modifierFlags &
        (NSEventModifierFlagControl | NSEventModifierFlagOption | NSEventModifierFlagCommand | NSEventModifierFlagShift);
    if (event.keyCode == 9 && voiceModifiers == (NSEventModifierFlagControl | NSEventModifierFlagOption))
    {
        if (!event.isARepeat) [self toggleVoiceInput:sender];
        return YES;
    }
    if (_voiceService.active)
    {
        [self cancelVoiceInput];
        if (event.keyCode == 53) return YES;
    }
    const NSEventModifierFlags inputModeModifiers =
        event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    // Both toggles swallow their repeats. Holding the chord past the system repeat delay used to
    // flip the persisted preference once per repeat and land on whichever parity the repeat count
    // reached, which is the same reason the voice shortcut above guards on isARepeat.
    if (metasequoia::mac::ShouldToggleInputMode(
            [MetasequoiaPreferencesWindowController storedInputModeShortcutEnabled], event.keyCode,
            inputModeModifiers))
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
            [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:
                ![MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]];
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

    // Captured before the key is dispatched: a commit clears the local mode, and applyResult still
    // needs to know which one produced the text it is inserting.
    const metasequoia::LocalInputMode localModeForKey = _session->local_input_mode();
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
    case metasequoia::mac::ControllerKeyAction::MoveCandidateDown:
    {
        if (!metasequoia::mac::IsPrimaryCandidateDirection(event.keyCode, _candidatePanel.panelType))
        {
            return YES;
        }
        const BOOL backwards = event.keyCode == kVK_LeftArrow || event.keyCode == kVK_UpArrow;
        const NSUInteger target = backwards ? (_candidateHighlightedIndex > 0 ? _candidateHighlightedIndex - 1 : 0)
                                            : std::min(_candidateHighlightedIndex + 1, _candidateData.count - 1);
        [self selectCandidateAtIndex:target pageStart:metasequoia::mac::CandidatePageStart(
            target, _candidateData.count, _candidatePageSize)];
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
        [self selectCandidateAtIndex:metasequoia::mac::CandidatePageEnd(
                                         _candidatePageStart, _candidateData.count,
                                         _candidatePageSize)
                           pageStart:_candidatePageStart];
        return YES;
    case metasequoia::mac::ControllerKeyAction::Backspace:
        result = _session->handle_command(metasequoia::Command::Backspace);
        break;
    case metasequoia::mac::ControllerKeyAction::CommitRaw:
        result = _session->handle_command(metasequoia::Command::CommitRaw);
        break;
    case metasequoia::mac::ControllerKeyAction::Cancel:
        result = _session->handle_command(metasequoia::Command::Cancel);
        break;
    case metasequoia::mac::ControllerKeyAction::CommitCandidate:
        result = _candidateSelection.commit(*_session);
        break;
    case metasequoia::mac::ControllerKeyAction::Character:
    {
        NSString *characters = event.characters;
        if (characters.length == 1)
        {
            const unichar character = [characters characterAtIndex:0];
            // Only lowercase reaches the session. The engine now treats A-Z during a composition as helpcode input, which macOS never asked for and does not document; forwarding it would swallow the capital instead of committing the leading candidate and letting the application insert it.
            if (character >= 'a' && character <= 'z')
            {
                result = metasequoia::mac::HandleCharacterWithWubiAutoCommit(
                    *_session, static_cast<char>(character), _wubiAutoCommitUniqueEnabled);
            }
            // Shift and a capital with nothing being composed is how the engine opens a local input
            // mode. It stays out of the helpcode path above, which only applies during a
            // composition, and a capital that is not one of the triggers still comes back unhandled
            // so the application inserts it.
            else if (_localInputModesEnabled && character >= 'A' && character <= 'Z' &&
                     !_session->has_composition() && (modifiers & NSEventModifierFlagShift) != 0 &&
                     (modifiers & ~NSEventModifierFlagShift) == 0)
            {
                result = _session->handle_character(static_cast<char>(character), true);
            }
            else if (character == '\'' && _session->has_composition())
            {
                result = _session->handle_character(static_cast<char>(character));
            }
            // Unicode mode reads a hex code point, so while it is open its digits and its optional
            // "+" are input rather than candidate numbers. Every other local mode takes letters
            // only and leaves the digits to selection, which is what they already did.
            else if ((character >= '0' && character <= '9') || character == '+')
            {
                if (_session->local_input_mode() == metasequoia::LocalInputMode::Unicode)
                {
                    result = _session->handle_character(static_cast<char>(character));
                }
                else if (character >= '1' && character <= '9')
                {
                    result = _candidateSelection.commit_number(
                        *_session, static_cast<char>(character), _candidatePageSize);
                    if (!result.handled && _session->has_composition())
                    {
                        return YES;
                    }
                }
            }
            else if (character == ',' || character == '.' || character == '?' || character == '!' ||
                     character == ';' || character == ':' || character == '"' || character == '\'' ||
                     character == '(' || character == ')' || character == '[' || character == ']' ||
                     character == '<' || character == '>' || character == '\\')
            {
                result = _session->handle_punctuation(static_cast<char>(character));
            }
        }
        break;
    }
    }

    if (!result.handled)
    {
        [self commitLeadingCandidate:sender];
        if (_session != nullptr && !_session->has_composition() &&
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
    if (_session == nullptr || !_session->has_composition())
    {
        return;
    }
    // Every automatic commit runs through here: losing focus, pressing a modifier, typing a key the
    // session does not take, resetting learned data. finish_composition defaults to the engine's
    // own first candidate for the leading segment, which threw away a candidate the user had
    // arrowed onto — type shi, press Down to highlight 时, click into another application, and 是
    // was committed. The rest of the composition still finishes from the engine's first candidate,
    // which is what the default argument means and what this path already did.
    const metasequoia::LocalInputMode localMode = _session->local_input_mode();
    const auto result =
        _session->finish_composition(_candidateSelection.live_selected_index(*_session).value_or(0));
    if (result.handled)
    {
        [self applyResult:result localMode:localMode client:sender];
    }
}

// Single source of truth for the traditional-output predicate so the candidate panel and the committed text can never disagree about which script the user sees.
- (BOOL)traditionalChineseOutputActive
{
    return _session != nullptr && _session->scheme_type() != SchemeType::JapaneseRomaji &&
           [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled];
}

// Dictated text does not come from the session, so it has to follow the script preference even
// when no session exists — the voice shortcut is dispatched before prepareSessionIfNeeded, and a
// controller built while English mode is stored, or one whose dictionary keeps failing to prepare,
// never has one. EngineSchemeForStoredPreference only ever yields Quanpin, Shuangpin or Wubi, so
// the Japanese romaji exclusion above cannot apply to the stored preference.
- (BOOL)voiceOutputUsesTraditionalChinese
{
    return _session != nullptr
               ? [self traditionalChineseOutputActive]
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
    id<IMKTextInput> client = sender;
    const NSRange replacementRange = NSMakeRange(NSNotFound, NSNotFound);
    if (result.commit.has_value())
    {
        const BOOL traditionalOutput = [self traditionalChineseOutputActive] &&
                                       metasequoia::mac::ScriptConversionAppliesToLocalMode(localMode);
        NSString *commit = MetasequoiaChineseOutputString(MetasequoiaStringFromUtf8(*result.commit),
                                                           traditionalOutput);
        [client insertText:commit replacementRange:replacementRange];
        _candidateSelection.reset();
        if (!_session->has_composition())
        {
            [_candidatePanel hide];
            [_shuangpinKeymapPanel orderOut:nil];
            return;
        }
    }

    NSString *preedit = MetasequoiaStringFromUtf8(_session->preedit());
    [client setMarkedText:preedit selectionRange:NSMakeRange(preedit.length, 0) replacementRange:replacementRange];
    [self updateCandidatePanel];
    [self updateShuangpinKeymapPanelForClient:client];
}

- (void)updateShuangpinKeymapPanelForClient:(id<IMKTextInput>)client
{
    const BOOL hasComposition = _session != nullptr && _session->has_composition();
    const BOOL isShuangpin = _session != nullptr && _session->scheme_type() == SchemeType::Shuangpin;
    if (!MetasequoiaShouldShowShuangpinKeymap(isShuangpin, _shuangpinKeymapEnabled, hasComposition) ||
        client == nil)
    {
        [_shuangpinKeymapPanel orderOut:nil];
        return;
    }

    NSRect caretRect = NSZeroRect;
    [client attributesForCharacterIndex:0 lineHeightRectangle:&caretRect];
    if (!std::isfinite(NSMinX(caretRect)) || !std::isfinite(NSMinY(caretRect)) ||
        !std::isfinite(NSMaxX(caretRect)) || !std::isfinite(NSMaxY(caretRect)) ||
        NSHeight(caretRect) <= 0.0)
    {
        [_shuangpinKeymapPanel orderOut:nil];
        return;
    }

    NSString *preedit = MetasequoiaStringFromUtf8(_session->preedit());
    NSString *highlightedKey = @"";
    if (preedit.length > 0)
    {
        const unichar character = [preedit characterAtIndex:preedit.length - 1];
        if ((character >= 'a' && character <= 'z') || (character >= 'A' && character <= 'Z'))
        {
            highlightedKey = [NSString stringWithCharacters:&character length:1];
        }
    }
    [_shuangpinKeymapPanel updateHighlightedKey:highlightedKey];

    const CGFloat fontSize = static_cast<CGFloat>(
        [MetasequoiaPreferencesWindowController storedCandidateFontSize]);
    CGFloat candidateClearance = fontSize + 42.0;
    if (_candidatePanel.panelType != kIMKSingleRowSteppingCandidatePanel)
    {
        const NSUInteger visibleCandidates = MIN(
            _candidateData.count,
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
    const std::optional<size_t> preservedSelection =
        preserveSelection ? _candidateSelection.selected_index() : std::nullopt;
    if (!preserveSelection)
    {
        _candidateSelection.reset();
        _candidateHighlightedIndex = 0;
        _candidatePageStart = 0;
    }
    _candidateLineIdentifiersCollapsed = NO;
    NSMutableArray *data = [NSMutableArray arrayWithCapacity:_session->candidates().size()];
    const metasequoia::LocalInputMode localMode = _session->local_input_mode();
    const BOOL traditionalOutput = [self traditionalChineseOutputActive] &&
                                   metasequoia::mac::ScriptConversionAppliesToLocalMode(localMode);
    const bool annotateHelpcodes =
        _session->helpcode_enabled() && metasequoia::mac::HelpcodesAnnotateLocalMode(localMode);
    NSUInteger candidateIndex = 0;
    for (const WordItem &candidate : _session->candidates())
    {
        NSString *display = MetasequoiaStringFromUtf8(metasequoia::mac::CandidateDisplayText(
            candidate, _session->scheme_type(), annotateHelpcodes));
        NSString *convertedDisplay = MetasequoiaChineseOutputString(display, traditionalOutput);
        [data addObject:MetasequoiaIndexedCandidateString(convertedDisplay, candidateIndex)];
        ++candidateIndex;
    }
    _candidateData = [data copy];
    if (_session->has_composition() && _candidateData.count > 0)
    {
        const NSUInteger selectedIndex = preservedSelection.has_value() && preservedSelection.value() < _candidateData.count
                                             ? preservedSelection.value() : 0;
        _candidatePageStart = metasequoia::mac::CandidatePageStart(selectedIndex, _candidateData.count, _candidatePageSize);
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
                if ([_candidatePanel candidateStringIdentifier:_visibleCandidateData[candidateIndex]] != selectedIdentifier)
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
        if (line != NSNotFound) index = _candidatePageStart + line;
    }
    if (index == NSNotFound)
    {
        // Last resort for display strings that collide after conversion (干/乾): the highlighted line is only trustworthy relative to the page the controller itself navigated to, so exact text matching runs first.
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
    if (index == NSNotFound || index >= _session->candidates().size())
    {
        return;
    }
    const metasequoia::LocalInputMode localMode = _session->local_input_mode();
    const auto result = _session->select_candidate(static_cast<size_t>(index));
    if (result.handled)
    {
        [self applyResult:result localMode:localMode client:self.client];
    }
}

- (id)composedString:(id)sender
{
    (void)sender;
    return _session == nullptr ? @"" : MetasequoiaStringFromUtf8(_session->preedit());
}

- (NSAttributedString *)originalString:(id)sender
{
    (void)sender;
    NSString *raw = _session == nullptr ? @"" : MetasequoiaStringFromUtf8(_session->preedit());
    return [[NSAttributedString alloc] initWithString:raw];
}

- (void)commitComposition:(id)sender
{
    [self commitLeadingCandidate:sender];
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
    if (!_voiceService) _voiceService = [MetasequoiaVoiceInputService new];
    return _voiceService;
}

- (void)cancelVoiceInput
{
    ++_voiceGeneration;
    [_voiceService cancel];
    if (_voiceMouseMonitor) [NSEvent removeMonitor:_voiceMouseMonitor];
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
    if (!_serverActive) return;
    id<MetasequoiaVoiceService> service = [self voiceService];
    if (service.recording) { [service stop]; return; }
    if (service.active) { [self cancelVoiceInput]; return; }
    id client = self.client;
    if (!client) return;
    [self commitLeadingCandidate:client];
    const NSUInteger generation = ++_voiceGeneration;
    const NSRange selection = [client respondsToSelector:@selector(selectedRange)] ? [client selectedRange] : NSMakeRange(NSNotFound, 0);
    __weak MetasequoiaInputController *weakSelf = self;
    _voiceMouseMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown
        handler:^(NSEvent *event) { (void)event; [weakSelf cancelVoiceInput]; }];
    [service startWithCompletion:^(NSString *text, NSError *error) {
        MetasequoiaInputController *owner = weakSelf;
        if (!owner || !owner->_serverActive || owner->_voiceGeneration != generation || owner.client != client) return;
        const NSRange currentSelection = [client respondsToSelector:@selector(selectedRange)] ? [client selectedRange] : NSMakeRange(NSNotFound, 0);
        [owner cancelVoiceInput];
        if (!NSEqualRanges(currentSelection, selection)) return;
        if (error) { [owner showVoiceError:error]; return; }
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
    [[MetasequoiaVoiceSettingsWindow sharedController] showAndActivate];
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
    // The Character Viewer inserts straight into the client, so settle any marked text first; otherwise the session would resend the pending composition after the inserted symbol.
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
}

- (void)floatingToolbarDidRequestToggleInputMode:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self setEnglishInputMode:![MetasequoiaPreferencesWindowController storedEnglishInputMode]
                       client:self.client];
}

- (void)floatingToolbarDidRequestTogglePunctuation:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [self commitLeadingCandidate:self.client];
    [MetasequoiaPreferencesWindowController setChinesePunctuationEnabled:
        ![MetasequoiaPreferencesWindowController storedChinesePunctuationEnabled]];
    if (_session != nullptr)
    {
        [self reloadSessionFromPreferences];
    }
}

- (void)floatingToolbarDidRequestToggleFullWidth:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [MetasequoiaPreferencesWindowController setFullWidthInputEnabled:
        ![MetasequoiaPreferencesWindowController storedFullWidthInputEnabled]];
}

- (void)floatingToolbarDidRequestToggleTraditionalOutput:(MetasequoiaFloatingToolbarPanel *)toolbar
{
    (void)toolbar;
    [MetasequoiaPreferencesWindowController setTraditionalChineseOutputEnabled:
        ![MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled]];
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
    return CreateMetasequoiaInputMenu(
        self, [MetasequoiaPreferencesWindowController storedEnglishInputMode],
        [MetasequoiaPreferencesWindowController storedTraditionalChineseOutputEnabled]);
}

- (NSUInteger)recognizedEvents:(id)sender
{
    (void)sender;
    return NSEventMaskKeyDown;
}
@end
