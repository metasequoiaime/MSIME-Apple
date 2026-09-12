#include "PublicSessionTestOptions.h"
// Exercise the real controller with a recording window boundary. A headless
// IMKCandidates cannot render without a registered input-method client.
#include "../src/MetasequoiaInputController.mm"
#include "../../../vendor/MetasequoiaImeEngine/user_dictionary/user_dictionary_journal.h"
#include "../../../shared/apple-bridge/DictionarySnapshotBridge.h"
#include <sqlite3.h>
#include <filesystem>
#include <stdexcept>

static void Require(bool condition, const char *message)
{
    if (!condition)
        throw std::runtime_error(message);
}

@interface RecordingCandidatePanel : NSObject
@property(nonatomic, copy) NSArray *data;
@property(nonatomic, copy) NSArray *selectionKeys;
@property(nonatomic) IMKCandidatePanelType panelType;
@property(nonatomic) NSInteger selected;
@property(nonatomic) BOOL visible;
@property(nonatomic) NSRect caretRect;
@property(nonatomic, copy) NSString *preedit;
@property(nonatomic) BOOL hasPreviousPage;
@property(nonatomic) BOOL hasNextPage;
@property(nonatomic) BOOL collapsedIdentifiers;
@property(nonatomic, strong) NSNumber *rejectedEngineIndex;
@end
@implementation RecordingCandidatePanel
- (void)setAttributes:(NSDictionary *)attributes
{
    (void)attributes;
}
- (void)setCandidateData:(NSArray *)data
{
    self.data = data;
    self.selected = 0;
}
- (void)show:(IMKCandidatesLocationHint)hint
{
    (void)hint;
    self.visible = YES;
}
- (void)hide
{
    self.visible = NO;
}
- (BOOL)isVisible
{
    return self.visible;
}
- (NSInteger)candidateIdentifierAtLineNumber:(NSInteger)line
{
    return line >= 0 && (NSUInteger)line < self.data.count ? (self.collapsedIdentifiers ? 0 : 100 + line * 3)
                                                           : NSNotFound;
}
- (NSInteger)lineNumberForCandidateWithIdentifier:(NSInteger)identifier
{
    return self.collapsedIdentifiers ? 0 : (identifier - 100) / 3;
}
- (BOOL)selectCandidateWithIdentifier:(NSInteger)identifier
{
    const NSInteger line =
        self.collapsedIdentifiers ? identifier : [self lineNumberForCandidateWithIdentifier:identifier];
    if (line < 0 || (NSUInteger)line >= self.data.count)
        return NO;
    if (self.rejectedEngineIndex != nil &&
        MetasequoiaCandidateIndex(self.data[line]) == self.rejectedEngineIndex.unsignedIntegerValue)
        return NO;
    self.selected = line;
    return YES;
}
- (NSInteger)selectedCandidate
{
    return self.collapsedIdentifiers ? 0 : 100 + self.selected * 3;
}
- (NSAttributedString *)selectedCandidateString
{
    return self.data[self.selected];
}
- (NSInteger)candidateStringIdentifier:(NSAttributedString *)value
{
    return self.collapsedIdentifiers ? 0 : 100 + (NSInteger)[self.data indexOfObjectIdenticalTo:value] * 3;
}
@end

@interface RecordingInputClient : NSObject
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@end
@implementation RecordingInputClient
- (NSDictionary *)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect *)rect
{
    (void)index;
    *rect = NSMakeRect(100, 400, 1, 20);
    return @{};
}
- (void)insertText:(id)text replacementRange:(NSRange)range
{
    (void)range;
    self.committed = text;
}
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement
{
    self.marked = text;
    (void)selection;
    (void)replacement;
}
@end

// The test category is in the controller's translation unit so it can create a
// session without registering an input source or touching the installed dictionary.
@interface MetasequoiaInputController (PaginationTestFixture)
- (void)prepareTestPanel:(RecordingCandidatePanel *)panel;
- (void)prepareEmptyTestPanel:(RecordingCandidatePanel *)panel;
- (NSUInteger)testCandidateCount;
- (void)preparePartialInput;
- (NSString *)testCandidateAtIndex:(NSUInteger)index;
- (BOOL)testHasComposition;
- (void)prepareHelpcodeProbe;
- (void)refreshHelpcodeProbe;
@end
@implementation MetasequoiaInputController (PaginationTestFixture)
- (void)prepareTestPanel:(RecordingCandidatePanel *)panel
{
    _candidatePanel = (MetasequoiaCandidatePanel *)panel;
    _session.reset();
    [self reloadSessionFromPreferences];
    for (char character : std::string("nihao"))
        _session->character(character);
    [self updateCandidatePanel];
}
// Leaves the session empty so a test can drive every keystroke through handleEvent:client: instead
// of writing into the session directly.
- (void)prepareEmptyTestPanel:(RecordingCandidatePanel *)panel
{
    _candidatePanel = (MetasequoiaCandidatePanel *)panel;
    _session.reset();
    [self reloadSessionFromPreferences];
}
- (BOOL)testHasComposition
{
    return _session != nullptr && (!_session->snapshot().preedit.empty());
}
- (void)prepareHelpcodeProbe
{
    for (char character : std::string("niA"))
        _session->character(character);
    _sessionSnapshot = _session->snapshot();
}
- (void)refreshHelpcodeProbe
{
    [self reloadSessionFromPreferences];
    _session->command(metasequoia::Command::Backspace);
    _session->character('A');
    _sessionSnapshot = _session->snapshot();
}
- (void)preparePartialInput
{
    _sessionOptions = SessionTestOptions(SchemeType::Quanpin, false, false);
    _session = std::make_unique<metasequoia::Session>(_sessionOptions);
    for (char character : std::string("shui'lin"))
        _session->character(character);
    [self updateCandidatePanel];
}
- (NSUInteger)testCandidateCount
{
    return _session->snapshot().candidates.size();
}
- (NSString *)testCandidateAtIndex:(NSUInteger)index
{
    return MetasequoiaStringFromUtf8(_session->snapshot().candidates[index].word);
}
@end

@interface PaginationTestController : MetasequoiaInputController
@property(nonatomic, strong) RecordingInputClient *testClient;
@end
@implementation PaginationTestController
- (id)client
{
    return self.testClient;
}
@end

static void Press(PaginationTestController *controller, unsigned short code, NSString *text)
{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                      location:NSZeroPoint
                                 modifierFlags:0
                                     timestamp:0
                                  windowNumber:0
                                       context:nil
                                    characters:text
                   charactersIgnoringModifiers:text
                                     isARepeat:NO
                                       keyCode:code];
    Require([controller handleEvent:event client:controller.testClient],
            "The controller did not handle a paging test key.");
}

static void RunTests()
{
    Require([MetasequoiaInputController conformsToProtocol:@protocol(MetasequoiaFloatingToolbarDelegate)] &&
                [MetasequoiaInputController conformsToProtocol:@protocol(MetasequoiaCandidatePanelDelegate)],
            "The controller does not support both window delegate contracts.");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSNumber *style in @[ @0, @1 ])
        for (NSNumber *size in @[ @5, @6, @7, @8, @9 ])
        {
            [defaults setVolatileDomain:@{
                @"MetasequoiaImeCandidatePageSize" : size,
                @"MetasequoiaImeCandidatePanelStyle" : style,
                @"MetasequoiaImeCandidateLearning" : @NO,
                @"MetasequoiaImeHelpcodeEnabled" : @NO
            }
                                forName:NSArgumentDomain];
            RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
            PaginationTestController *controller = [PaginationTestController alloc];
            controller.testClient = [RecordingInputClient new];
            [controller prepareTestPanel:panel];
            [controller preparePartialInput];
            Press(controller, 49, @" ");
            Require([controller.testClient.committed isEqualToString:@"水"] &&
                        [controller.testClient.marked isEqualToString:@"lin"] && panel.visible,
                    "Partial selection did not insert the prefix and render the remaining preedit.");
            Press(controller, 49, @" ");
            Require([controller.testClient.committed isEqualToString:@"林"] && !panel.visible,
                    "Completing partial input did not clear the candidate panel.");
            [controller preparePartialInput];
            [controller commitLeadingCandidate:controller.testClient];
            Require([controller.testClient.committed isEqualToString:@"水林"] && !panel.visible,
                    "Host passthrough discarded the unselected suffix.");
            [controller prepareTestPanel:panel];
            Require(![[controller testCandidateAtIndex:0] isEqualToString:@"nihao"],
                    "The fixture candidate collided with the typed input.");
            [controller commitComposition:controller.testClient];
            Require([controller.testClient.committed isEqualToString:@"nihao"] && !panel.visible &&
                        !controller.testHasComposition,
                    "Committing the composition inserted a candidate instead of the typed letters.");
            [controller prepareTestPanel:panel];
            const NSUInteger pageSize = size.unsignedIntegerValue;
            NSMutableDictionary *edgeDefaults = [[defaults volatileDomainForName:NSArgumentDomain] mutableCopy];
            edgeDefaults[MetasequoiaInputBehaviorKey] = @{@"edgeSelection" : @1, @"pageComma" : @1};
            [defaults setVolatileDomain:edgeDefaults forName:NSArgumentDomain];
            NSString *edgeWord = [controller testCandidateAtIndex:0];
            Press(controller, kVK_ANSI_LeftBracket, @"[");
            Require([controller.testClient.committed isEqualToString:[edgeWord substringToIndex:1]],
                    "First-Han selection did not commit the default highlighted candidate's first character.");
            [controller prepareTestPanel:panel];
            Press(controller, kVK_ANSI_Period, @".");
            Require(MetasequoiaCandidateIndex(panel.data[0]) == pageSize,
                    "Comma/period paging did not navigate to the next page.");
            Press(controller, kVK_ANSI_RightBracket, @"]");
            // Fixture words are 候选0…候选11: Engine must skip the trailing ASCII digits.
            Require([controller.testClient.committed isEqualToString:@"选"],
                    "Last-Han selection did not use the highlighted second-page candidate.");
            [edgeDefaults removeObjectForKey:MetasequoiaInputBehaviorKey];
            [defaults setVolatileDomain:edgeDefaults forName:NSArgumentDomain];
            [controller prepareTestPanel:panel];
            Require([controller testCandidateCount] > pageSize, "The fixture needs multiple pages.");
            Require(panel.data.count == pageSize,
                    "The native window received more than the configured candidates per page.");
            Require([[controller candidates:nil] count] == pageSize, "The IMK callback bypassed pagination.");
            Press(controller, kVK_PageDown, @"");
            Require(MetasequoiaCandidateIndex(panel.data[0]) == pageSize,
                    "Page Down did not start at the next engine candidate.");
            Require(panel.data.count <= pageSize, "The second page exceeded the configured page size.");
            NSString *expected = [controller testCandidateAtIndex:pageSize];
            Press(controller, kVK_ANSI_1, @"1");
            Require([controller.testClient.committed isEqualToString:expected],
                    "Digit 1 on page two committed the wrong engine candidate.");

            [controller prepareTestPanel:panel];
            const unsigned short forward = style.intValue == 0 ? kVK_RightArrow : kVK_DownArrow;
            const unsigned short backward = style.intValue == 0 ? kVK_LeftArrow : kVK_UpArrow;
            for (NSUInteger step = 0; step < pageSize; ++step)
                Press(controller, forward, @"");
            Require(MetasequoiaCandidateIndex(panel.data[0]) == pageSize,
                    "Arrow navigation did not cross the page boundary.");
            Press(controller, backward, @"");
            Require(MetasequoiaCandidateIndex(panel.data[0]) == 0,
                    "Reverse navigation did not return to the first page.");
            expected = [controller testCandidateAtIndex:pageSize - 1];
            Press(controller, kVK_Space, @" ");
            Require([controller.testClient.committed isEqualToString:expected],
                    "Space committed a different candidate from the highlighted one.");

            [controller prepareTestPanel:panel];
            const NSUInteger total = [controller testCandidateCount];
            for (NSUInteger page = 1; page * pageSize < total; ++page)
                Press(controller, kVK_PageDown, @"");
            const NSUInteger lastPageStart = ((total - 1) / pageSize) * pageSize;
            Require(total == 12 && MetasequoiaCandidateIndex(panel.data[0]) == lastPageStart,
                    "The last page started at the wrong engine candidate.");
            Require(panel.data.count == total - lastPageStart, "The partial last page lost candidates.");
            NSArray *lastPage = panel.data;
            Press(controller, kVK_PageDown, @"");
            Require([panel.data isEqualToArray:lastPage], "Page Down moved beyond the last page.");
            Press(controller, kVK_PageUp, @"");
            Require(MetasequoiaCandidateIndex(panel.data[0]) == lastPageStart - pageSize, "Page Up skipped a page.");

            for (NSNumber *stripped in @[ @NO, @YES ])
            {
                [controller prepareTestPanel:panel];
                Press(controller, kVK_PageDown, @"");
                panel.selected = 1;
                expected = [controller testCandidateAtIndex:pageSize + 1];
                NSAttributedString *clicked = panel.data[1];
                if (stripped.boolValue)
                    clicked = [[NSAttributedString alloc] initWithString:clicked.string];
                [controller candidateSelected:clicked];
                Require([controller.testClient.committed isEqualToString:expected],
                        "A page-two mouse callback committed the wrong engine candidate.");
            }

            if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26)
            {
                panel.collapsedIdentifiers = YES;
                [controller prepareTestPanel:panel];
                Press(controller, kVK_PageDown, @"");
                Press(controller, forward, @"");
                Require(panel.selected == 1,
                        "Collapsed native identifiers used a global index instead of a page-local ordinal.");
                expected = [controller testCandidateAtIndex:pageSize + 1];
                Press(controller, kVK_Space, @" ");
                Require([controller.testClient.committed isEqualToString:expected],
                        "Collapsed identifiers lost the global engine selection.");
                [controller prepareTestPanel:panel];
                Press(controller, kVK_PageDown, @"");
                panel.selected = 1;
                expected = [controller testCandidateAtIndex:pageSize + 1];
                [controller candidateSelected:[[NSAttributedString alloc] initWithString:[panel.data[1] string]]];
                Require([controller.testClient.committed isEqualToString:expected],
                        "A stripped mouse callback with collapsed identifiers lost its page offset.");
                panel.collapsedIdentifiers = NO;
            }

            [controller prepareTestPanel:panel];
            Press(controller, forward, @"");
            panel.rejectedEngineIndex = @(pageSize);
            Press(controller, kVK_PageDown, @"");
            Require(MetasequoiaCandidateIndex(panel.data[0]) == 0 && panel.selected == 1,
                    "A rejected page selection did not restore the previous page and highlight.");
            expected = [controller testCandidateAtIndex:1];
            Press(controller, kVK_Space, @" ");
            Require([controller.testClient.committed isEqualToString:expected],
                    "Failed page navigation changed the engine selection.");
            panel.rejectedEngineIndex = nil;

            [controller prepareTestPanel:panel];
            Press(controller, kVK_PageDown, @"");
            [controller refreshCandidatePanelPreservingSelection];
            Require(MetasequoiaCandidateIndex(panel.data[0]) == pageSize, "A display refresh reset the current page.");
            Press(controller, kVK_Escape, @"");
            Require(!panel.visible && panel.data.count == 0 && [[controller candidates:nil] count] == 0,
                    "Cancelling retained visible candidates.");
        }
}

static void RunMixedEnglishTests()
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *previous = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *values = [previous mutableCopy];
    values[@"MetasequoiaImeEnglishInputMode"] = @NO;
    values[@"MetasequoiaImeInputScheme"] = @0;
    values[@"MetasequoiaImeHelpcodeEnabled"] = @NO;
    values[MetasequoiaInputBehaviorKey] = @{@"mixedEnglish" : @1, @"englishMinimumPrefix" : @2};
    [defaults setVolatileDomain:values forName:NSArgumentDomain];
    RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
    PaginationTestController *controller = [PaginationTestController alloc];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:panel];
    Press(controller, kVK_ANSI_H, @"h");
    auto hasHello = [&]() {
        for (NSUInteger index = 0; index < [controller testCandidateCount]; ++index)
            if ([[controller testCandidateAtIndex:index] isEqualToString:@"hello"])
                return true;
        return false;
    };
    Require(!hasHello(), "English candidates appeared before the configured minimum prefix.");
    values[MetasequoiaInputBehaviorKey] = @{@"mixedEnglish" : @0, @"englishMinimumPrefix" : @2};
    [defaults setVolatileDomain:values forName:NSArgumentDomain];
    Press(controller, kVK_ANSI_E, @"e");
    Require(hasHello(), "Changing preferences interrupted mixed English in an active composition.");
    Press(controller, kVK_Escape, @"");
    Press(controller, kVK_ANSI_H, @"h");
    Press(controller, kVK_ANSI_E, @"e");
    Require(!hasHello(), "The next composition ignored disabled mixed English.");
    Press(controller, kVK_Escape, @"");
    [controller prepareForLearnedDataReset:nil];
    [defaults setVolatileDomain:previous forName:NSArgumentDomain];
}

#ifdef METASEQUOIA_TEST_JAPANESE_MODEL
static void RunJapaneseTests(NSString *directory)
{
    std::filesystem::copy_file(
        METASEQUOIA_TEST_JAPANESE_MODEL,
        [directory stringByAppendingPathComponent:@"dict_japanese.dat"].fileSystemRepresentation);
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *previous = [defaults volatileDomainForName:NSArgumentDomain];
    NSMutableDictionary *values = [previous mutableCopy];
    values[@"MetasequoiaImeEnglishInputMode"] = @NO;
    values[MetasequoiaInputBehaviorKey] = @{@"japaneseMode" : @1};
    [defaults setVolatileDomain:values forName:NSArgumentDomain];
    const NSInteger chineseScheme = [MetasequoiaPreferencesWindowController storedScheme];
    Require(ReadSessionPreferences().scheme == SchemeType::JapaneseRomaji,
            "Japanese mode did not select the Engine scheme.");
    RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
    PaginationTestController *controller = [PaginationTestController alloc];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:panel];
    for (char ch : std::string("nihon"))
        Press(controller, kVK_ANSI_A, [NSString stringWithFormat:@"%c", ch]);
    bool found = false;
    for (NSUInteger index = 0; index < [controller testCandidateCount]; ++index)
        found = found || [[controller testCandidateAtIndex:index] isEqualToString:@"日本"];
    Require(found, "Published Japanese model did not produce 日本 from nihon.");
    Require([MetasequoiaPreferencesWindowController storedScheme] == chineseScheme,
            "Japanese mode overwrote the independent Chinese scheme preference.");
    Press(controller, kVK_Space, @" ");
    Require(controller.testClient.committed.length > 0, "Japanese candidate was not committed to the client.");
    [controller prepareForLearnedDataReset:nil];
    [defaults setVolatileDomain:previous forName:NSArgumentDomain];
}
#endif

@interface DeferredVoiceService : NSObject <MetasequoiaVoiceService>
@property(nonatomic) BOOL active;
@property(nonatomic) BOOL recording;
@property(nonatomic, copy) MetasequoiaVoiceCompletion pending;
@end
@implementation DeferredVoiceService
- (void)startWithCompletion:(MetasequoiaVoiceCompletion)completion
{
    self.active = YES;
    self.recording = YES;
    self.pending = completion;
}
- (void)stop
{
    self.recording = NO;
}
- (void)cancel
{
    self.active = NO;
    self.recording = NO;
} // Deliberately retain stale callback to exercise host defenses.
@end
@interface VoiceInputClient : RecordingInputClient
@property(nonatomic) NSRange range;
@end
@implementation VoiceInputClient
- (NSRange)selectedRange
{
    return self.range;
}
@end
@interface MetasequoiaInputController (VoiceTestFixture)
- (void)prepareVoiceFixture:(id<MetasequoiaVoiceService>)service;
@end
@implementation MetasequoiaInputController (VoiceTestFixture)
- (void)prepareVoiceFixture:(id<MetasequoiaVoiceService>)service
{
    [self cancelVoiceInput];
    _voiceService = service;
    _serverActive = YES;
    _session.reset();
}
@end
@interface VoiceTestController : PaginationTestController
@property(nonatomic, strong) NSError *voiceError;
@end
@implementation VoiceTestController
- (void)showVoiceError:(NSError *)error
{
    self.voiceError = error;
}
@end
static void RunVoiceTests()
{
    VoiceTestController *controller = [VoiceTestController new];
    VoiceInputClient *first = [VoiceInputClient new];
    first.range = NSMakeRange(10, 0);
    VoiceInputClient *second = [VoiceInputClient new];
    second.range = NSMakeRange(10, 0);
    DeferredVoiceService *voice = [DeferredVoiceService new];
    controller.testClient = first;
    [controller prepareVoiceFixture:voice];
    [controller toggleVoiceInput:nil];
    Require(voice.active && voice.recording, "Voice entry did not start the service.");
    [controller toggleVoiceInput:nil];
    Require(voice.active && !voice.recording, "Voice entry did not finish recording.");
    voice.pending(@"水杉 voice", nil);
    Require([first.committed isEqualToString:@"水杉 voice"],
            "Voice output was not committed through the input client.");
    first.committed = nil;

    [controller toggleVoiceInput:nil];
    MetasequoiaVoiceCompletion stale = voice.pending;
    [controller cancelVoiceInput];
    stale(@"取消后的文本", nil);
    Require(first.committed == nil, "Cancelled voice committed stale text.");

    [controller toggleVoiceInput:nil];
    stale = voice.pending;
    [controller cancelVoiceInput];
    [controller toggleVoiceInput:nil];
    stale(@"旧请求", nil);
    Require(first.committed == nil && voice.active, "An old callback affected a newer request.");
    voice.pending(@"新请求", nil);
    Require([first.committed isEqualToString:@"新请求"], "The active request did not commit.");
    first.committed = nil;

    [controller toggleVoiceInput:nil];
    first.range = NSMakeRange(11, 0);
    voice.pending(@"位置已变化", nil);
    Require(first.committed == nil, "Voice output ignored a moved insertion point.");

    [controller toggleVoiceInput:nil];
    stale = voice.pending;
    controller.testClient = second;
    stale(@"错误窗口", nil);
    Require(first.committed == nil && second.committed == nil, "Voice output crossed input clients.");
    [controller cancelVoiceInput];
    controller.testClient = first;

    [controller toggleVoiceInput:nil];
    stale = voice.pending;
    // The IMK superclass requires a registered server. Exercise our real
    // deactivation work without invoking that external framework boundary.
    [controller prepareForDeactivation:first];
    stale(@"失去焦点", nil);
    Require(first.committed == nil && !voice.active, "Deactivation did not cancel voice output.");
    [controller prepareVoiceFixture:voice];

    NSEvent *toggle = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:NSEventModifierFlagControl | NSEventModifierFlagOption
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                     characters:@"v"
                    charactersIgnoringModifiers:@"v"
                                      isARepeat:NO
                                        keyCode:9];
    Require([controller handleEvent:toggle client:first] && voice.recording, "Voice shortcut did not start recording.");
    stale = voice.pending;
    NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                     characters:@""
                    charactersIgnoringModifiers:@""
                                      isARepeat:NO
                                        keyCode:53];
    Require([controller handleEvent:escape client:first] && !voice.active, "Escape did not cancel voice.");
    stale(@"Esc 后的文本", nil);
    Require(first.committed == nil, "Escape allowed a late result.");

    [controller toggleVoiceInput:nil];
    stale = voice.pending;
    NSEvent *navigation = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                           location:NSZeroPoint
                                      modifierFlags:0
                                          timestamp:0
                                       windowNumber:0
                                            context:nil
                                         characters:@""
                        charactersIgnoringModifiers:@""
                                          isARepeat:NO
                                            keyCode:kVK_LeftArrow];
    [controller handleEvent:navigation client:first];
    stale(@"键盘移动后", nil);
    Require(first.committed == nil && !voice.active, "Keyboard navigation did not invalidate voice.");

    [controller toggleVoiceInput:nil];
    voice.pending(nil, [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]);
    Require(controller.voiceError != nil && first.committed == nil, "Voice failure inserted text or lost its error.");
    [controller cancelVoiceInput];
    voice.pending = nil;
}

// Full-width mode used to convert every letter before the engine saw it, which made Chinese input
// impossible while it was on, and 启用本地输入模式 was only ever applied to a session at the moment
// it was constructed, so toggling it did nothing to the session the user was already typing in.
static void RunFullWidthAndLocalModeTests()
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *baseDefaults = @{
        @"MetasequoiaImeFullWidthInputEnabled" : @YES,
        @"MetasequoiaImeCandidateLearning" : @NO,
        @"MetasequoiaImeHelpcodeEnabled" : @NO,
        @"MetasequoiaImeCandidatePageSize" : @9
    };
    [defaults setVolatileDomain:baseDefaults forName:NSArgumentDomain];

    PaginationTestController *controller = [PaginationTestController new];
    RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:panel];

    for (NSString *letter in @[ @"n", @"i", @"h", @"a", @"o" ])
    {
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:0
                                         timestamp:0
                                      windowNumber:0
                                           context:nil
                                        characters:letter
                       charactersIgnoringModifiers:letter
                                         isARepeat:NO
                                           keyCode:kVK_ANSI_N];
        Require([controller handleEvent:event client:controller.testClient],
                "Full-width mode did not route a letter into the session.");
    }
    Require([controller testHasComposition],
            "Full-width mode swallowed the letters instead of starting a composition.");
    Require(controller.testClient.committed == nil,
            "Full-width mode committed a letter that should have been composed.");
    Require(panel.visible && panel.data.count > 0, "Full-width mode suppressed the candidate window.");

    NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:0
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                     characters:@""
                    charactersIgnoringModifiers:@""
                                      isARepeat:NO
                                        keyCode:53];
    Require([controller handleEvent:escape client:controller.testClient] && ![controller testHasComposition],
            "Escape did not cancel the full-width composition fixture.");
    controller.testClient.committed = nil;

    // A capital is not composable, so it still comes back through the post-engine fallback and is
    // the character full-width mode is actually meant to convert.
    NSEvent *capital = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                        location:NSZeroPoint
                                   modifierFlags:NSEventModifierFlagShift
                                       timestamp:0
                                    windowNumber:0
                                         context:nil
                                      characters:@"U"
                     charactersIgnoringModifiers:@"U"
                                       isARepeat:NO
                                         keyCode:kVK_ANSI_U];
    Require([controller handleEvent:capital client:controller.testClient] &&
                [controller.testClient.committed isEqualToString:@"Ｕ"],
            "Full-width mode did not convert a capital the session declined.");
    controller.testClient.committed = nil;

    // Flipped after the session exists. It used to take effect only on the next rebuild, so the
    // trigger stayed dead in the window the user had just changed the setting for.
    NSMutableDictionary *withLocalModes = [baseDefaults mutableCopy];
    withLocalModes[@"MetasequoiaImeLocalInputModesEnabled"] = @YES;
    [defaults setVolatileDomain:withLocalModes forName:NSArgumentDomain];
    Require([controller handleEvent:capital client:controller.testClient] && controller.testClient.committed == nil,
            "Enabling 启用本地输入模式 did not reach the running session.");

    [defaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

// The engine's handle_punctuation switch and the controller's dispatch whitelist have to agree.
// ` $ ^ _ were added to the engine alongside < > and only the latter pair was picked up here, so
// those four kept inserting ASCII while 中文标点 was on.
static void RunChinesePunctuationTests()
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setVolatileDomain:@{
        @"MetasequoiaImeChinesePunctuation" : @YES,
        @"MetasequoiaImeCandidateLearning" : @NO,
        @"MetasequoiaImeHelpcodeEnabled" : @NO
    }
                        forName:NSArgumentDomain];

    PaginationTestController *controller = [PaginationTestController new];
    RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:panel];

    NSDictionary<NSString *, NSString *> *expected = @{
        @"`" : @"·",
        @"$" : @"￥",
        @"^" : @"……",
        @"_" : @"——",
        @"," : @"，",
        @"\\" : @"、",
    };
    for (NSString *typed in expected)
    {
        controller.testClient.committed = nil;
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                          location:NSZeroPoint
                                     modifierFlags:0
                                         timestamp:0
                                      windowNumber:0
                                           context:nil
                                        characters:typed
                       charactersIgnoringModifiers:typed
                                         isARepeat:NO
                                           keyCode:kVK_ANSI_Grave];
        Require([controller handleEvent:event client:controller.testClient],
                "The controller did not handle a Chinese punctuation key.");
        Require([controller.testClient.committed isEqualToString:expected[typed]],
                "A punctuation key did not produce the engine's Chinese punctuation.");
    }

    // With the preference off the engine declines them, and the ASCII passthrough stays in charge.
    [defaults setVolatileDomain:@{
        @"MetasequoiaImeChinesePunctuation" : @NO,
        @"MetasequoiaImeCandidateLearning" : @NO,
        @"MetasequoiaImeHelpcodeEnabled" : @NO
    }
                        forName:NSArgumentDomain];
    controller.testClient.committed = nil;
    NSEvent *dollar = [NSEvent keyEventWithType:NSEventTypeKeyDown
                                       location:NSZeroPoint
                                  modifierFlags:NSEventModifierFlagShift
                                      timestamp:0
                                   windowNumber:0
                                        context:nil
                                     characters:@"$"
                    charactersIgnoringModifiers:@"4"
                                      isARepeat:NO
                                        keyCode:kVK_ANSI_4];
    Require(![controller handleEvent:dollar client:controller.testClient] && controller.testClient.committed == nil,
            "A punctuation key was consumed while 中文标点转换 was off.");

    [defaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

static void RunHelpcodeIsolationTests(NSString *directory)
{
    // Add these candidates after the pagination fixtures, whose expected list has 12 entries.
    sqlite3 *database = nullptr;
    Require(sqlite3_open([directory stringByAppendingPathComponent:@"msime.db"].fileSystemRepresentation, &database) ==
                SQLITE_OK,
            "Cannot open helpcode fixture.");
    const int result = sqlite3_exec(database,
                                    "CREATE TABLE tbl_1_n(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                                    "INSERT INTO tbl_1_n VALUES('ni','n','你',100),('ni','n','妮',90)",
                                    nullptr, nullptr, nullptr);
    sqlite3_close(database);
    Require(result == SQLITE_OK, "Cannot create helpcode fixture.");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSMutableDictionary *preferences = [@{
        @"MetasequoiaImeInputScheme" : @0,
        @"MetasequoiaImeHelpcodeEnabled" : @YES,
        @"MetasequoiaImeCandidateLearning" : @NO,
        @"MetasequoiaImeQuanpinHelpcodeSchema" : @0,
    } mutableCopy];
    [defaults setVolatileDomain:preferences forName:NSArgumentDomain];
    PaginationTestController *first = [[PaginationTestController alloc] init];
    [first prepareEmptyTestPanel:[[RecordingCandidatePanel alloc] init]];
    [first prepareHelpcodeProbe];
    Require([first testCandidateCount] > 0 && [[first testCandidateAtIndex:0] isEqualToString:@"你"],
            "The first controller did not apply its Lantian helpcodes.");

    preferences[@"MetasequoiaImeQuanpinHelpcodeSchema"] = @1;
    [defaults setVolatileDomain:preferences forName:NSArgumentDomain];
    PaginationTestController *second = [[PaginationTestController alloc] init];
    [second prepareEmptyTestPanel:[[RecordingCandidatePanel alloc] init]];
    [second prepareHelpcodeProbe];
    Require([second testCandidateCount] > 0 && [[second testCandidateAtIndex:0] isEqualToString:@"妮"],
            "The second controller did not apply its Ziranma helpcodes.");

    [first refreshHelpcodeProbe];
    Require([[first testCandidateAtIndex:0] isEqualToString:@"你"],
            "Reloading preferences changed the first controller's live composition schema.");
    [second refreshHelpcodeProbe];
    Require([[second testCandidateAtIndex:0] isEqualToString:@"妮"],
            "Another controller changed this session's helpcodes.");

    [first prepareEmptyTestPanel:[[RecordingCandidatePanel alloc] init]];
    [first prepareHelpcodeProbe];
    Require([[first testCandidateAtIndex:0] isEqualToString:@"妮"],
            "A new composition did not pick up the updated schema preference.");
    [defaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

static void RunDictionarySwitchTests(NSString *directory)
{
    NSURL *user = [NSURL fileURLWithPath:directory];
    NSURL *resources =
        [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSFileManager *manager = NSFileManager.defaultManager;
    Require([manager createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil],
            "Cannot create snapshot resources.");
    @try
    {
        Require([manager copyItemAtURL:[user URLByAppendingPathComponent:@"msime.db"]
                                 toURL:[resources URLByAppendingPathComponent:@"msime.db"]
                                 error:nil],
                "Cannot copy snapshot fixture.");
        sqlite3 *database = nullptr;
        Require(sqlite3_open([resources URLByAppendingPathComponent:@"english.db"].fileSystemRepresentation,
                             &database) == SQLITE_OK,
                "Cannot create English fixture.");
        Require(sqlite3_exec(database, "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER)", nullptr,
                             nullptr, nullptr) == SQLITE_OK,
                "Cannot create English schema.");
        sqlite3_close(database);
        __block BOOL emitted = NO;
        NSError *error = nil;
        NSString *content = [@"" stringByPaddingToLength:128 withString:@"a" startingAtIndex:0];
        MSIMEPreparedDictionarySnapshot *prepared =
            [DictionarySnapshotBridge prepareResources:resources
                                         userDirectory:user
                                            identifier:NSUUID.UUID.UUIDString
                                     contentIdentifier:content
                                        maximumRecords:1
                                            nextRecord:^NSDictionary *(NSError **failure) {
                                              (void)failure;
                                              if (emitted)
                                                  return nil;
                                              emitted = YES;
                                              return @{
                                                  @"type" : @"overlay",
                                                  @"deleted" : @NO,
                                                  @"data" : @{
                                                      @"kind" : @"pinyin",
                                                      @"code" : @"ni'hao",
                                                      @"word" : @"你好",
                                                      @"weight" : @100000,
                                                      @"user_inserted" : @YES
                                                  }
                                              };
                                            }
                                                 error:&error];
        Require(prepared != nil && error == nil, "Cannot stage controller snapshot.");
        Class runtime = NSClassFromString(@"MSIMEMacDictionarySync");
        SEL activate = NSSelectorFromString(@"activate:");
        using Activate = NSDictionary *(*)(id, SEL, NSDictionary *);
        const auto call = reinterpret_cast<Activate>([runtime methodForSelector:activate]);
        NSString *version = [NSString
            stringWithFormat:@"local-v1::%s",
                             metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths()).c_str()];
        RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
        PaginationTestController *controller = [PaginationTestController alloc];
        controller.testClient = [RecordingInputClient new];
        [controller prepareTestPanel:panel];
        NSDictionary *request = @{@"prepared" : prepared, @"version" : version};
        Require([call(runtime, activate, request)[@"error"] code] == 423, "Publication interrupted composition.");
        Require([controller testHasComposition], "Rejected publication changed composition.");
        Press(controller, kVK_Escape, @"\x1b");
        Require([call(runtime, activate, @{@"prepared" : prepared, @"version" : @"stale"})[@"error"] code] == 409,
                "Stale local state was replaced.");
        NSDictionary *result = call(runtime, activate, request);
        Require(result[@"error"] == nil, "Cannot activate idle controller snapshot.");
        [controller prepareEmptyTestPanel:panel];
        for (NSString *key in @[ @"n", @"i", @"h", @"a", @"o" ])
            Press(controller, 0, key);
        Require([[controller testCandidateAtIndex:0] isEqualToString:@"你好"],
                "Recreated controller did not use published snapshot.");
        Press(controller, kVK_Space, @" ");
        Require([controller.testClient.committed isEqualToString:@"你好"],
                "Snapshot candidate was not committed through IMK boundary.");
        [controller prepareForLearnedDataReset:nil];
    }
    @finally
    {
        [manager removeItemAtURL:resources error:nil];
    }
}

int main()
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        std::filesystem::create_directories(directory.fileSystemRepresentation);
        setenv("METASEQUOIA_IME_DATA_DIR", directory.fileSystemRepresentation, 1);
        NSString *helpcodeDirectory = [directory stringByAppendingPathComponent:@"helpcodes"];
        std::filesystem::create_directories(helpcodeDirectory.fileSystemRepresentation);
        Require([@"你=ab\n妮=cd\n" writeToFile:[helpcodeDirectory stringByAppendingPathComponent:@"helpcode.txt"]
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:nil],
                "Cannot write Lantian fixture.");
        Require([@"你=cb\n妮=ad\n"
                    writeToFile:[helpcodeDirectory stringByAppendingPathComponent:@"zrm_helpcode_big_unique.txt"]
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:nil],
                "Cannot write Ziranma fixture.");
        sqlite3 *database = nullptr;
        Require(sqlite3_open([directory stringByAppendingPathComponent:@"msime.db"].fileSystemRepresentation,
                             &database) == SQLITE_OK,
                "Cannot create fixture.");
        Require(sqlite3_exec(database, "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER)", nullptr,
                             nullptr, nullptr) == SQLITE_OK,
                "Cannot create table.");
        for (int index = 0; index < 12; ++index)
        {
            NSString *sql = [NSString
                stringWithFormat:@"INSERT INTO tbl_2_n VALUES('ni''hao','nh','候选%d',%d)", index, 120 - index];
            Require(sqlite3_exec(database, sql.UTF8String, nullptr, nullptr, nullptr) == SQLITE_OK,
                    "Cannot insert fixture.");
        }
        Require(sqlite3_exec(database,
                             "CREATE TABLE tbl_1_s(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                             "INSERT INTO tbl_1_s VALUES('shui','s','水',100);"
                             "CREATE TABLE tbl_1_l(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                             "INSERT INTO tbl_1_l VALUES('lin','l','林',100);"
                             "CREATE TABLE tbl_2_s(key TEXT,jp TEXT,value TEXT,weight INTEGER)",
                             nullptr, nullptr, nullptr) == SQLITE_OK,
                "Cannot create partial-selection fixture.");
        sqlite3_close(database);
        try
        {
            @autoreleasepool
            {
                RunTests();
                Require(sqlite3_open([directory stringByAppendingPathComponent:@"english.db"].fileSystemRepresentation,
                                     &database) == SQLITE_OK,
                        "Cannot create mixed English fixture.");
                Require(sqlite3_exec(database,
                                     "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);"
                                     "INSERT INTO english_words VALUES('hello','hello',1000)",
                                     nullptr, nullptr, nullptr) == SQLITE_OK,
                        "Cannot populate mixed English fixture.");
                sqlite3_close(database);
                RunMixedEnglishTests();
#ifdef METASEQUOIA_TEST_JAPANESE_MODEL
                RunJapaneseTests(directory);
#endif
                RunVoiceTests();
                RunFullWidthAndLocalModeTests();
                RunChinesePunctuationTests();
                RunHelpcodeIsolationTests(directory);
            }
            RunDictionarySwitchTests(directory);
        }
        catch (const std::exception &error)
        {
            fprintf(stderr, "%s\n", error.what());
            user_dictionary::close_default_user_database();
            std::filesystem::remove_all(directory.fileSystemRepresentation);
            return 1;
        }
        user_dictionary::close_default_user_database();
        std::filesystem::remove_all(directory.fileSystemRepresentation);
    }
}
