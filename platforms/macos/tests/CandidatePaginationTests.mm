#include "PublicSessionTestOptions.h"
// Exercise the real controller with a recording window boundary. A headless
// IMKCandidates cannot render without a registered input-method client.
#include "../src/MetasequoiaInputController.mm"
#include "../../../vendor/MetasequoiaImeEngine/user_dictionary/user_dictionary_journal.h"
#include "../../../shared/apple-bridge/DictionarySnapshotBridge.h"
#include "../../../shared/apple-bridge/DictionaryInstallation.h"
#include <sqlite3.h>
#include <metasequoia/personal_dictionary.h>
#import <CommonCrypto/CommonDigest.h>
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

@interface WritingTestClient : RecordingInputClient
@property(nonatomic, copy) NSString *document;
@property(nonatomic) NSRange selection;
@property(nonatomic) NSRange replacedRange;
@property(nonatomic) BOOL truncated;
@end
@implementation WritingTestClient
- (NSRange)selectedRange { return self.selection; }
- (NSAttributedString *)attributedSubstringFromRange:(NSRange)range
{
    if (range.location > self.document.length || range.length > self.document.length - range.location) return nil;
    NSString *text = self.truncated ? @"" : [self.document substringWithRange:range];
    return [[NSAttributedString alloc] initWithString:text];
}
- (void)insertText:(id)text replacementRange:(NSRange)range
{
    self.replacedRange = range;
    [super insertText:text replacementRange:range];
}
@end

static void RunWritingSelectionTests()
{
    WritingTestClient *client = [WritingTestClient new];
    client.document = @"前文：需要润色的文字"; client.selection = NSMakeRange(3, 7);
    auto selection = [MSIMEWritingSelection capture:(id)client];
    Require(selection && [selection.text isEqualToString:@"需要润色的文字"] && [selection matches:(id)client],
            "Native writing did not capture exact selected text.");
    WritingTestClient *other = [WritingTestClient new]; other.document = client.document; other.selection = client.selection;
    Require(![selection replace:@"结果" client:(id)other], "Writing accepted a different host client.");
    client.selection = NSMakeRange(2, 7);
    Require(![selection replace:@"结果" client:(id)client], "Writing replaced a moved selection.");
    client.selection = NSMakeRange(3, 7); client.document = @"后文：需要润色的文字";
    Require(![selection replace:@"结果" client:(id)client], "Writing accepted changed document context.");
    client.document = @"前文：需要润色的文字";
    Require([selection replace:@"润色后的文字" client:(id)client] &&
            NSEqualRanges(client.replacedRange, client.selection) &&
            [client.committed isEqualToString:@"润色后的文字"], "Writing failed to use exact native replacement range.");
    Require(![selection replace:@"再次替换" client:(id)client], "A writing result replaced the host twice.");
    selection = [MSIMEWritingSelection capture:(id)client]; selection.valid = NO;
    Require(![selection matches:(id)client], "Cancelled writing selection remained usable.");
    client.selection = NSMakeRange(NSNotFound, 0);
    Require(![MSIMEWritingSelection capture:(id)client], "Unsupported host selection was accepted.");
    client.selection = NSMakeRange(3, 7); client.truncated = YES;
    Require(![MSIMEWritingSelection capture:(id)client], "Truncated host text was accepted.");
}

// The test category is in the controller's translation unit so it can create a
// session without registering an input source or touching the installed dictionary.
@interface MetasequoiaInputController (PaginationTestFixture)
- (void)prepareTestPanel:(RecordingCandidatePanel *)panel;
- (void)prepareEmptyTestPanel:(RecordingCandidatePanel *)panel;
- (NSUInteger)testCandidateCount;
- (void)preparePartialInput;
- (NSString *)testCandidateAtIndex:(NSUInteger)index;
- (BOOL)testHasComposition;
- (NSArray<NSString *> *)testNineKeySpellings;
- (BOOL)testNineKeyEnabled;
- (void)prepareHelpcodeProbe;
- (void)refreshHelpcodeProbe;
- (NSUInteger)testFuzzyPinyinRules;
- (NSString *)testShuangpinProfile;
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
- (NSArray<NSString *> *)testNineKeySpellings
{
    NSMutableArray<NSString *> *values = [NSMutableArray array];
    for (const auto &value : _session->snapshot().nine_key_spellings) [values addObject:@(value.c_str())];
    return values;
}
- (BOOL)testNineKeyEnabled { return _nineKeyEnabled; }
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
- (NSString *)testShuangpinProfile
{
    return @(_sessionOptions.shuangpin_profile.name.c_str());
}
- (NSUInteger)testFuzzyPinyinRules
{
    return _sessionOptions.fuzzy_pinyin.rules;
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
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *recordedStatistics;
@end
@implementation PaginationTestController
- (void)recordCommittedText:(NSString *)text source:(NSString *)source
{
    if (self.recordedStatistics == nil) self.recordedStatistics = [NSMutableArray array];
    [self.recordedStatistics addObject:@{ @"text": text, @"source": source }];
}
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

static void RunTypingStatisticsTests()
{
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
        @"MetasequoiaImeInputScheme": @0, @"MetasequoiaImeCandidateLearning": @NO,
        @"MetasequoiaImeHelpcodeEnabled": @NO, @"MetasequoiaImeEnglishInputMode": @NO,
        @"MetasequoiaImeTraditionalChineseOutput": @NO
    } forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    for (NSString *letter in @[ @"n", @"i", @"h", @"a", @"o" ]) Press(controller, 0, letter);
    Require(controller.recordedStatistics.count == 0, "Preedit was counted as committed text.");
    Press(controller, kVK_Space, @" ");
    Require(controller.recordedStatistics.count == 1 &&
            [controller.recordedStatistics[0][@"text"] isEqual:controller.testClient.committed] &&
            [controller.recordedStatistics[0][@"source"] isEqual:@"quanpin"],
            "A real commit was not counted once with its input scheme.");
    Press(controller, kVK_ANSI_N, @"n");
    Press(controller, kVK_Escape, @"");
    Require(controller.recordedStatistics.count == 1, "Cancelled composition changed typing statistics.");
    [NSUserDefaults.standardUserDefaults removeVolatileDomainForName:NSArgumentDomain];
}

static void RunShuangpinProfileTests()
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSString *name in @[ @"xiaohe", @"ziranma", @"microsoft", @"shoudao" ])
    {
        NSMutableDictionary *settings = [@{
            @"MetasequoiaImeInputScheme": @1, @"MetasequoiaImeShuangpinProfile": name,
            @"MetasequoiaImeCandidateLearning": @NO, @"MetasequoiaImeHelpcodeEnabled": @NO,
            @"MetasequoiaImeEnglishInputMode": @NO, @"MetasequoiaImeFuzzyPinyinEnabled": @NO
        } mutableCopy];
        [defaults setVolatileDomain:settings forName:NSArgumentDomain];
        PaginationTestController *controller = [PaginationTestController new];
        controller.testClient = [RecordingInputClient new];
        [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
        const auto &profile = GetShuangpinProfile(name.UTF8String);
        std::string code = std::string("l") + profile.finals.at("in");
        for (char key : code) Press(controller, 0, [NSString stringWithFormat:@"%c", key]);
        bool found = false;
        for (NSUInteger index = 0; index < [controller testCandidateCount]; ++index)
            found |= [[controller testCandidateAtIndex:index] isEqualToString:@"林"];
        Require(found && [[controller testShuangpinProfile] isEqual:name], "The selected double-pinyin profile did not reach Engine.");
        NSString *next = [name isEqual:@"xiaohe"] ? @"ziranma" : @"xiaohe";
        settings[@"MetasequoiaImeShuangpinProfile"] = next;
        [defaults setVolatileDomain:settings forName:NSArgumentDomain];
        [controller reloadSessionFromPreferences];
        Require([[controller testShuangpinProfile] isEqual:name] && [controller testHasComposition],
                "Changing the double-pinyin profile altered active composition.");
        Press(controller, kVK_Space, @" ");
        Require([controller.recordedStatistics.lastObject[@"source"] isEqual:[name isEqual:@"xiaohe"] ? @"shuangpin" : name],
                "Statistics did not retain the active double-pinyin profile.");
        Press(controller, kVK_ANSI_N, @"n");
        Require([[controller testShuangpinProfile] isEqual:next], "The next composition did not use the newly selected profile.");
        Press(controller, kVK_Escape, @"");
    }
    [defaults setVolatileDomain:@{
        @"MetasequoiaImeInputScheme": @1, @"MetasequoiaImeShuangpinProfile": @"microsoft", @"MetasequoiaImeChinesePunctuation": @YES,
        @"MetasequoiaImeCandidateLearning": @NO, @"MetasequoiaImeHelpcodeEnabled": @NO,
        @"MetasequoiaImeEnglishInputMode": @NO
    } forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    Press(controller, kVK_ANSI_L, @"l");
    Press(controller, kVK_ANSI_Semicolon, @";");
    bool found = false;
    for (NSUInteger index = 0; index < [controller testCandidateCount]; ++index)
        found |= [[controller testCandidateAtIndex:index] isEqualToString:@"灵"];
    Require(found && controller.testClient.committed == nil, "Microsoft ing was treated as punctuation instead of a code key.");
    Press(controller, kVK_Escape, @"");
    Press(controller, kVK_ANSI_Semicolon, @";");
    Require([controller.testClient.committed isEqualToString:@"；"] && ![controller testHasComposition],
            "An idle Microsoft session swallowed normal semicolon punctuation.");
    [defaults removeVolatileDomainForName:NSArgumentDomain];
}

static void RunFuzzyPinyinPreferencesTests()
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    const NSUInteger rule = static_cast<NSUInteger>(metasequoia::FuzzyPinyinRule::N_L);
    for (NSNumber *scheme in @[ @0, @1 ])
    {
        NSMutableDictionary *settings = [@{
            @"MetasequoiaImeInputScheme": scheme, @"MetasequoiaImeFuzzyPinyinEnabled": @YES,
            @"MetasequoiaImeFuzzyPinyinRules": @0, @"MetasequoiaImeCandidateLearning": @NO,
            @"MetasequoiaImeHelpcodeEnabled": @NO, @"MetasequoiaImeEnglishInputMode": @NO,
            @"MetasequoiaImeQuanpinAutocorrect": @NO
        } mutableCopy];
        [defaults setVolatileDomain:settings forName:NSArgumentDomain];
        PaginationTestController *controller = [PaginationTestController new];
        controller.testClient = [RecordingInputClient new];
        [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
        Press(controller, kVK_ANSI_N, @"n");
        settings[@"MetasequoiaImeFuzzyPinyinRules"] = @(rule);
        [defaults setVolatileDomain:settings forName:NSArgumentDomain];
        Press(controller, kVK_ANSI_I, @"i");
        Require([controller testFuzzyPinyinRules] == 0, "Fuzzy rules changed during active composition.");
        Press(controller, kVK_Escape, @"");
        Press(controller, kVK_ANSI_N, @"n");
        Require([controller testFuzzyPinyinRules] == rule, "New fuzzy rules were not applied to the next composition.");
        if (scheme.integerValue == 0)
        {
            Press(controller, kVK_ANSI_I, @"i");
            Press(controller, kVK_ANSI_N, @"n");
            bool found = false;
            for (NSUInteger index = 0; index < [controller testCandidateCount]; ++index)
                found |= [[controller testCandidateAtIndex:index] isEqualToString:@"林"];
            Require(found, "Native preferences did not enable Engine's n/l fuzzy candidate.");
        }
        settings[@"MetasequoiaImeFuzzyPinyinEnabled"] = @NO;
        [defaults setVolatileDomain:settings forName:NSArgumentDomain];
        [controller reloadSessionFromPreferences];
        Require([controller testFuzzyPinyinRules] == rule, "Disabling fuzzy rules changed the active session.");
        Press(controller, kVK_Escape, @"");
        Press(controller, kVK_ANSI_N, @"n");
        Require([controller testFuzzyPinyinRules] == 0 &&
                [MetasequoiaPreferencesWindowController storedFuzzyPinyinRules] == rule,
                "Disabling fuzzy pinyin did not retain the user's selected rules.");
    }
    [defaults removeVolatileDomainForName:NSArgumentDomain];
}

static void RunTests()
{
    Require([MetasequoiaInputController conformsToProtocol:@protocol(MetasequoiaFloatingToolbarDelegate)] &&
                [MetasequoiaInputController conformsToProtocol:@protocol(MetasequoiaCandidatePanelDelegate)],
            "The controller does not support both window delegate contracts.");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSNumber *style in @[ @0, @1 ])
        for (NSNumber *size in @[ @5, @7, @9 ])
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
            const NSUInteger lastPageStart = pageSize == 5 ? 10 : pageSize; // fixture has 12 candidates
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
    Require(controller.recordedStatistics.count == 1 &&
            [controller.recordedStatistics.lastObject[@"source"] isEqual:@"voice"],
            "Voice commits were not recorded with their source.");
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
    Require(controller.recordedStatistics.count == 2,
            "Cancelled, stale or failed voice results changed typing statistics.");
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

static NSDictionary *PersonalDictionaryCall(NSString *method, NSDictionary *parameters)
{
    Class type = NSClassFromString(@"MSIMEMacPersonalDictionary");
    SEL selector = NSSelectorFromString(method);
    using Call = NSDictionary *(*)(id, SEL, NSDictionary *);
    Require(type && [type respondsToSelector:selector], "Native personal dictionary bridge is missing.");
    return reinterpret_cast<Call>([type methodForSelector:selector])(type, selector, parameters);
}

static void RunPersonalDictionaryTests()
{
    NSDictionary *word = @{@"kind": @"pinyin", @"key": @"SHUI LIN", @"value": @"水林", @"weight": @12345};
    NSDictionary *validated = PersonalDictionaryCall(@"validate:", word);
    Require([validated[@"entry"][@"key"] isEqual:@"shui'lin"], "Engine did not normalize the native word editor's pinyin.");
    Require(PersonalDictionaryCall(@"validate:", @{@"kind": @"pinyin", @"key": @"invalid", @"value": @"水林", @"weight": @1})[@"error"] != nil,
            "Invalid pinyin bypassed Engine validation.");
    NSDictionary *page = PersonalDictionaryCall(@"page:", @{@"offset": @0});
    Require(page[@"error"] == nil, "Could not list native personal dictionary.");
    NSMutableDictionary *edit = [@{@"generation": page[@"generation"], @"identifier": NSUUID.UUID.UUIDString, @"replacement": word} mutableCopy];
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] == nil, "Native word add failed.");
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] == nil, "A retried native edit was not idempotent.");
    NSDictionary *normalized = validated[@"entry"];
    page = PersonalDictionaryCall(@"page:", @{@"offset": @0});
    Require([page[@"entries"] containsObject:normalized], "Added word missing from native page.");
    @autoreleasepool
    {
        [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
            @"MetasequoiaImeInputScheme": @0, @"MetasequoiaImeEnglishInputMode": @NO,
            @"MetasequoiaImeHelpcodeEnabled": @NO, @"MetasequoiaImeCandidateLearning": @NO
        } forName:NSArgumentDomain];
        PaginationTestController *trial = [PaginationTestController new];
        trial.testClient = [RecordingInputClient new];
        [trial prepareEmptyTestPanel:[RecordingCandidatePanel new]];
        for (NSString *letter in @[ @"s", @"h", @"u", @"i", @"l", @"i", @"n" ]) Press(trial, 0, letter);
        bool found = false;
        for (NSUInteger index = 0; index < [trial testCandidateCount]; ++index)
            found |= [[trial testCandidateAtIndex:index] isEqualToString:@"水林"];
        Require(found, "A saved personal word was not available in the next native composition.");
        Press(trial, kVK_Escape, @"");
        [NSUserDefaults.standardUserDefaults removeVolatileDomainForName:NSArgumentDomain];
    }
    edit[@"identifier"] = NSUUID.UUID.UUIDString;
    edit[@"previous"] = normalized;
    edit[@"replacement"] = @{@"kind": @"pinyin", @"key": @"shui lin", @"value": @"水林", @"weight": @23456};
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] == nil, "Native word replacement failed.");
    edit[@"identifier"] = NSUUID.UUID.UUIDString;
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] != nil, "A stale native edit replaced a changed word.");
    edit[@"previous"] = edit[@"replacement"];
    [edit removeObjectForKey:@"replacement"];
    edit[@"identifier"] = NSUUID.UUID.UUIDString;
    {
        metasequoia::apple::DictionarySessionLease otherProcess(MetasequoiaDictionaryUserDirectory());
        Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] != nil, "Native editing ignored another session's lease.");
    }
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{@"MetasequoiaImeInputScheme": @0, @"MetasequoiaImeEnglishInputMode": @NO} forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    Press(controller, kVK_ANSI_N, @"n");
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] != nil && [controller testHasComposition],
            "Editing a personal word interrupted a live composition.");
    Press(controller, kVK_Escape, @"");
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] == nil, "Native word delete failed after composition ended.");
    page = PersonalDictionaryCall(@"page:", @{@"offset": @0});
    for (NSDictionary *entry in page[@"entries"])
        Require(![entry[@"value"] isEqual:@"水林"], "Deleted native word remained visible.");
    edit[@"generation"] = @"stale-generation";
    Require(PersonalDictionaryCall(@"edit:", edit)[@"error"] != nil, "Native editing crossed dictionary generations.");
    [NSUserDefaults.standardUserDefaults removeVolatileDomainForName:NSArgumentDomain];
}

static int RunDictionaryProcessChild(NSString *directory, BOOL composing, NSString *marker)
{
    setenv("METASEQUOIA_IME_DATA_DIR", directory.fileSystemRepresentation, 1);
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
        @"MetasequoiaImeInputScheme": @0, @"MetasequoiaImeEnglishInputMode": @NO,
        @"MetasequoiaImeHelpcodeEnabled": @NO, @"MetasequoiaImeCandidateLearning": @NO
    } forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    if (composing) Press(controller, kVK_ANSI_N, @"n");
    __block BOOL received = NO;
    NSDistributedNotificationCenter *center = NSDistributedNotificationCenter.defaultCenter;
    id observer = [center addObserverForName:MetasequoiaReleaseIdleDictionarySessionsNotification
        object:MetasequoiaDictionaryUserDirectory().URLByStandardizingPath.path
        queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
            (void)notification;
            received = YES;
        }];
    [@"ready" writeToFile:[marker stringByAppendingString:@".ready"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:8];
    while (![NSFileManager.defaultManager fileExistsAtPath:marker] && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
    [center removeObserver:observer];
    return received && (composing == [controller testHasComposition]) ? 0 : 4;
}

static void RunDictionaryProcessTests(NSString *directory)
{
    for (NSNumber *active in @[ @NO, @YES ])
    {
        NSString *marker = [directory stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        NSTask *child = [NSTask new];
        child.executableURL = [NSURL fileURLWithPath:NSProcessInfo.processInfo.arguments.firstObject];
        child.arguments = @[ @"--dictionary-process-child", directory, active.boolValue ? @"active" : @"idle", marker ];
        NSError *launchError = nil;
        Require([child launchAndReturnError:&launchError], "Could not launch the dictionary reader process.");
        @try
        {
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
            while (![NSFileManager.defaultManager fileExistsAtPath:[marker stringByAppendingString:@".ready"]] &&
                   child.running && deadline.timeIntervalSinceNow > 0)
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            Require([NSFileManager.defaultManager fileExistsAtPath:[marker stringByAppendingString:@".ready"]],
                    "The dictionary reader process did not become ready.");
            NSDictionary *word = @{@"kind": @"pinyin", @"key": @"shui lin", @"value": @"水林", @"weight": @34567};
            NSDictionary *request = @{@"generation": @"", @"identifier": NSUUID.UUID.UUIDString, @"replacement": word};
            BOOL applied = NO;
            for (int attempt = 0; attempt < 20; ++attempt)
            {
                NSDictionary *result = PersonalDictionaryCall(@"edit:", request);
                if (result[@"error"] == nil) { applied = YES; break; }
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            Require(applied != active.boolValue,
                    "Cross-process editing failed for an idle reader or interrupted an active composition.");
            [@"stop" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
            deadline = [NSDate dateWithTimeIntervalSinceNow:3];
            while (child.running && deadline.timeIntervalSinceNow > 0)
                [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
            Require(!child.running && child.terminationStatus == 0,
                    "The reader did not receive the native request or changed its active composition.");
            if (applied)
                Require(PersonalDictionaryCall(@"edit:", @{@"generation": @"", @"identifier": NSUUID.UUID.UUIDString,
                                                          @"previous": word})[@"error"] == nil,
                        "Cannot clean up cross-process word fixture.");
        }
        @finally
        {
            if (child.running) { [child terminate]; [child waitUntilExit]; }
            [NSFileManager.defaultManager removeItemAtPath:marker error:nil];
            [NSFileManager.defaultManager removeItemAtPath:[marker stringByAppendingString:@".ready"] error:nil];
        }
    }
}

static void RunNineKeyTests()
{
    MetasequoiaCandidatePanel *nativePanel = [[MetasequoiaCandidatePanel alloc] init];
    nativePanel.nineKeySpellings = @[ @"ni", @"mi" ];
    [nativePanel setCandidateData:@[]];
    NSPopUpButton *spellingControl = nil;
    for (NSView *view in nativePanel.window.contentView.subviews)
        if ([view isKindOfClass:NSPopUpButton.class]) spellingControl = (NSPopUpButton *)view;
    Require(spellingControl != nil && spellingControl.numberOfItems == 3 &&
            NSContainsRect(nativePanel.window.contentView.bounds, spellingControl.frame) &&
            !nativePanel.window.canBecomeKeyWindow,
            "Native spelling popup is missing, clipped, or steals key-window focus.");
    nativePanel.nineKeySpellings = @[];
    for (NSView *view in nativePanel.window.contentView.subviews)
        Require(![view isKindOfClass:NSPopUpButton.class], "Stale spelling popup survived composition clearing.");
    NSMutableDictionary *preferences = [@{@"MetasequoiaImeInputScheme": @0,
        @"MetasequoiaImeNineKeyEnabled": @YES, @"MetasequoiaImeEnglishInputMode": @NO,
        @"MetasequoiaImeHelpcodeEnabled": @NO, @"MetasequoiaImeTraditionalChineseOutput": @NO,
        @"MetasequoiaImeCandidateLearning": @NO} mutableCopy];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController alloc];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    Require([controller testNineKeyEnabled], "Nine-key preference did not configure the native session.");
    // Numeric keypad events carry NumericPad; they must still enter digits.
    NSEvent *keypad = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagNumericPad timestamp:0 windowNumber:0 context:nil
        characters:@"6" charactersIgnoringModifiers:@"6" isARepeat:NO keyCode:kVK_ANSI_Keypad6];
    Require(metasequoia::mac::ShouldPlayKeyFeedback(keypad, true) && !metasequoia::mac::ShouldPlayKeyFeedback(keypad, false),
            "Key feedback ignored the explicit local preference or numeric keypad event.");
    NSEvent *repeat = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:0 context:nil characters:@"6" charactersIgnoringModifiers:@"6" isARepeat:YES keyCode:kVK_ANSI_6];
    Require(!metasequoia::mac::ShouldPlayKeyFeedback(repeat, true), "Autorepeat would replay key feedback without a bound.");
    Require([controller handleEvent:keypad client:controller.testClient], "Numeric keypad digit was not handled.");
    Press(controller, kVK_ANSI_4, @"4");
    NSArray<NSString *> *spellings = [controller testNineKeySpellings];
    NSUInteger ni = [spellings indexOfObject:@"ni"];
    Require(ni != NSNotFound && [controller testHasComposition], "Numeric input did not expose Engine spelling choices.");
    [controller candidatePanelChooseSpelling:ni text:@"stale"];
    Require([[controller testNineKeySpellings] isEqual:spellings], "Stale spelling text mutated the composition.");
    [controller candidatePanelChooseSpelling:ni text:@"ni"];
    Require(![[controller testNineKeySpellings] isEqual:spellings], "Native spelling selection did not reach Engine.");
    preferences[@"MetasequoiaImeNineKeyEnabled"] = @NO;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    Press(controller, kVK_ANSI_4, @"4"); Press(controller, kVK_ANSI_2, @"2"); Press(controller, kVK_ANSI_6, @"6");
    Require([controller testNineKeyEnabled] && [controller testCandidateCount] > 0,
            "Changing nine-key preference interrupted active composition.");
    NSString *expected = [controller testCandidateAtIndex:0];
    Press(controller, kVK_Space, @" ");
    Require([controller.testClient.committed isEqual:expected], "Nine-key candidate did not reach native text insertion.");
    Press(controller, kVK_ANSI_N, @"n");
    Require(![controller testNineKeyEnabled], "Nine-key preference was not applied after composition ended.");
    Press(controller, kVK_Escape, @"");
    preferences[@"MetasequoiaImeNineKeyEnabled"] = @YES;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    Press(controller, kVK_ANSI_N, @"n"); Press(controller, kVK_ANSI_I, @"i");
    Require([controller testNineKeyEnabled] && [controller testCandidateCount] >= 2,
            "Letter-based pinyin did not remain available with nine-key enabled.");
    NSString *second = [controller testCandidateAtIndex:1];
    Press(controller, kVK_ANSI_2, @"2");
    Require([controller.testClient.committed isEqual:second] && ![controller testHasComposition],
            "Nine-key preference swallowed number selection in letter-based pinyin.");
    [controller prepareForLearnedDataReset:nil];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

static void RunDedicatedJapaneseTests()
{
    NSMutableDictionary *preferences = [@{
        @"MetasequoiaImeInputScheme": @3, @"MetasequoiaImeEnglishInputMode": @NO,
        @"MetasequoiaImeTraditionalChineseOutput": @YES, @"MetasequoiaImeHelpcodeEnabled": @NO,
        @"MetasequoiaImeCandidateLearning": @NO
    } mutableCopy];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController alloc];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    Require(![controller voiceOutputUsesTraditionalChinese], "Japanese voice fallback enabled Chinese conversion.");
    Press(controller, kVK_ANSI_K, @"k"); Press(controller, kVK_ANSI_A, @"a");
    bool kana = false;
    for (NSUInteger index = 0; index < [controller testCandidateCount]; ++index)
        kana |= [[controller testCandidateAtIndex:index] isEqualToString:@"か"];
    Require(kana && ![controller traditionalChineseOutputActive], "Native Japanese composition lost kana or enabled Chinese conversion.");
    NSString *expected = [controller testCandidateAtIndex:0];
    preferences[@"MetasequoiaImeInputScheme"] = @0;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    Press(controller, kVK_Space, @" ");
    Require([controller.testClient.committed isEqualToString:expected] && ![controller testHasComposition],
            "Scheme change interrupted the active Japanese composition.");
    Require([controller.recordedStatistics.lastObject[@"source"] isEqualToString:@"japanese"],
            "Japanese commit was attributed to Chinese input.");
    Press(controller, kVK_ANSI_N, @"n"); Press(controller, kVK_ANSI_I, @"i");
    Require([[controller testCandidateAtIndex:0] isEqualToString:@"你"], "New composition did not apply the deferred Chinese scheme.");
    Press(controller, kVK_Escape, @"\x1b");
    preferences[@"MetasequoiaImeInputScheme"] = @3;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    Require([[[controller menu] itemAtIndex:0].title isEqualToString:@"日语输入"] && ![[controller menu] itemAtIndex:3].enabled, "IMK menu mislabeled Japanese input.");
    Press(controller, kVK_ANSI_K, @"k"); Press(controller, kVK_ANSI_A, @"a");
    expected = [controller testCandidateAtIndex:0];
    Press(controller, kVK_Return, @"\r");
    Require([controller.testClient.committed isEqualToString:expected] && ![controller testHasComposition],
            "Japanese Return committed raw romaji instead of the candidate.");
    Press(controller, kVK_ANSI_K, @"k"); Press(controller, kVK_ANSI_A, @"a");
    Press(controller, kVK_Escape, @"\x1b");
    Require(![controller testHasComposition], "Escape did not cancel Japanese composition.");
    [controller prepareForLearnedDataReset:nil];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

static void RunDedicatedEnglishTests()
{
    const auto revision = metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths());
    NSMutableDictionary *preferences = [@{
        @"MetasequoiaImeInputScheme": @1, @"MetasequoiaImeEnglishInputMode": @YES,
        @"MetasequoiaImeFullWidthInputEnabled": @YES, @"MetasequoiaImeChinesePunctuation": @YES,
        @"MetasequoiaImeLocalInputModesEnabled": @YES, @"MetasequoiaImeHelpcodeEnabled": @NO,
        @"MetasequoiaImeCandidateLearning": @NO
    } mutableCopy];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    PaginationTestController *controller = [PaginationTestController alloc];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
    auto send = [&](unsigned short key, NSString *text, NSEventModifierFlags modifiers = 0) {
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
            modifierFlags:modifiers timestamp:0 windowNumber:0 context:nil characters:text
            charactersIgnoringModifiers:text isARepeat:NO keyCode:key];
        return [controller handleEvent:event client:controller.testClient];
    };
    Require(send(kVK_ANSI_H, @"h") && send(kVK_ANSI_E, @"e") &&
            [[controller testCandidateAtIndex:0] isEqualToString:@"hello"],
            "Dedicated English did not expose dictionary completions.");
    Require(!send(kVK_Space, @" ") && [controller.testClient.committed isEqualToString:@"he"],
            "Space replaced raw spelling or prevented the host word separator.");
    Require([controller.recordedStatistics.lastObject[@"source"] isEqualToString:@"english"],
            "Dedicated English commits were attributed to the Chinese scheme.");
    Require(send(kVK_ANSI_H, @"h") && send(kVK_ANSI_E, @"e") && send(kVK_Tab, @"\t") &&
            [controller.testClient.committed isEqualToString:@"hello"], "Tab did not accept English completion.");
    for (NSString *boundary in @[ @".", @"3", @";", @"-", @"\r" ])
    {
        Require(send(kVK_ANSI_X, @"x"), "Cannot begin literal English word.");
        Require(!send([boundary isEqualToString:@"\r"] ? kVK_Return : 0, boundary) &&
                [controller.testClient.committed isEqualToString:@"x"],
                "An English boundary selected a candidate or converted Chinese punctuation/full-width text.");
    }
    Require(send(kVK_ANSI_H, @"H", NSEventModifierFlagShift) && send(kVK_ANSI_E, @"e") &&
            !send(kVK_ANSI_C, @"c", NSEventModifierFlagCommand) &&
            [controller.testClient.committed isEqualToString:@"He"],
            "English capitalization or Command shortcut passthrough changed spelling.");
    Require(send(kVK_ANSI_Y, @"Y", NSEventModifierFlagShift) &&
            [controller.testClient.marked isEqualToString:@"Y"], "An English capital opened a local mode.");
    Require(send(kVK_Delete, @"\x7f") && ![controller testHasComposition],
            "Backspace did not clear the English composition.");
    Require(send(kVK_ANSI_H, @"h") && send(kVK_Escape, @"\x1b") && ![controller testHasComposition],
            "Escape did not cancel English preedit.");
    Require(send(kVK_ANSI_H, @"h") && send(kVK_ANSI_E, @"e"), "Cannot begin focus-loss fixture.");
    [controller commitComposition:controller.testClient];
    Require([controller.testClient.committed isEqualToString:@"he"] && ![controller testHasComposition],
            "Native focus loss changed English spelling or retained marked text.");
    Require(send(kVK_ANSI_H, @"h"), "Cannot begin English toggle fixture.");
    [controller setEnglishInputMode:NO client:controller.testClient];
    Require([controller.testClient.committed isEqualToString:@"h"] && ![controller testHasComposition],
            "Switching to Chinese lost or completed pending English text.");
    preferences[@"MetasequoiaImeEnglishInputMode"] = @NO;
    preferences[@"MetasequoiaImeInputScheme"] = @0;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    Require(send(kVK_ANSI_N, @"n") && send(kVK_ANSI_I, @"i") &&
            [[controller testCandidateAtIndex:0] isEqualToString:@"你"], "English toggle did not restore Chinese input.");
    send(kVK_Escape, @"\x1b");
    Require(metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths()) == revision,
            "English typing learned user data while learning was disabled.");
    preferences[@"MetasequoiaImeEnglishInputMode"] = @YES;
    preferences[@"MetasequoiaImeCandidateLearning"] = @YES;
    [NSUserDefaults.standardUserDefaults setVolatileDomain:preferences forName:NSArgumentDomain];
    for (char letter : std::string("msimefixtureword"))
        Require(send(0, [NSString stringWithFormat:@"%c", letter]), "Cannot type a new English word.");
    Require(!send(kVK_Space, @" "), "English learning swallowed a native separator.");
    const auto words = metasequoia::personal_dictionary_entries(MetasequoiaCurrentDictionaryPaths());
    Require(words.error.empty() && std::any_of(words.entries.begin(), words.entries.end(), [](const auto &word) {
        return word.kind == metasequoia::PersonalDictionaryKind::English && word.value == "msimefixtureword";
    }), "Enabled English learning did not reach the active user dictionary.");
    [controller prepareForLearnedDataReset:nil];
    [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

static void RunBundledMigrationTests(NSString *directory)
{
    NSURL *user = [NSURL fileURLWithPath:directory];
    NSURL *resources = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSFileManager *manager = NSFileManager.defaultManager;
    Require([manager createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil],
            "Cannot create bundled migration resources.");
    @try
    {
        Require([manager copyItemAtURL:[user URLByAppendingPathComponent:@"msime.db"]
                                 toURL:[resources URLByAppendingPathComponent:@"msime.db"] error:nil],
                "Cannot copy migration base fixture.");
        sqlite3 *database = nullptr;
        Require(sqlite3_open([resources URLByAppendingPathComponent:@"english.db"].fileSystemRepresentation,
                             &database) == SQLITE_OK, "Cannot create bundled English fixture.");
        Require(sqlite3_exec(database,
            "CREATE TABLE english_words(word TEXT PRIMARY KEY,display TEXT,weight INTEGER);"
            "INSERT INTO english_words VALUES('hello','hello',100)", nullptr, nullptr, nullptr) == SQLITE_OK,
            "Cannot seed bundled English fixture.");
        sqlite3_close(database);
        for (NSString *name in @[ @"msime.db", @"english.db" ])
        {
            NSData *data = [NSData dataWithContentsOfURL:[resources URLByAppendingPathComponent:name]];
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(data.bytes, static_cast<CC_LONG>(data.length), digest);
            NSMutableString *text = [NSMutableString string];
            for (auto byte : digest) [text appendFormat:@"%02x", byte];
            Require([text writeToURL:[resources URLByAppendingPathComponent:[name stringByAppendingString:@".sha256"]]
                          atomically:YES encoding:NSUTF8StringEncoding error:nil], "Cannot write fixture digest.");
        }
        const auto revision = metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths());
        NSError *error = nil;
        NSURL *digestURL = [resources URLByAppendingPathComponent:@"english.db.sha256"];
        NSData *digest = [NSData dataWithContentsOfURL:digestURL];
        [@"invalid" writeToURL:digestURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
        Require(!MetasequoiaPrepareBundledDictionaryRuntime(resources, &error) && error.code == 500,
                "Migration accepted a corrupt bundle digest.");
        Require(metasequoia::apple::ActiveDictionarySnapshotIdentifier(user).length == 0 &&
                metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths()) == revision,
                "Failed migration changed legacy user state.");
        Require([digest writeToURL:digestURL atomically:YES], "Cannot restore fixture digest.");
        @autoreleasepool
        {
            PaginationTestController *controller = [PaginationTestController alloc];
            controller.testClient = [RecordingInputClient new];
            [controller prepareTestPanel:[RecordingCandidatePanel new]];
            Require(!MetasequoiaPrepareBundledDictionaryRuntime(resources, &error) && error.code == 423 &&
                    [controller testHasComposition], "Migration interrupted active input.");
            Press(controller, kVK_Escape, @"\x1b");
            [controller prepareForLearnedDataReset:nil];
        }
        {
            metasequoia::apple::DictionarySessionLease reader(user);
            Require(!MetasequoiaPrepareBundledDictionaryRuntime(resources, &error) && error.code == 423,
                    "Migration bypassed another dictionary reader.");
        }
        Require(MetasequoiaPrepareBundledDictionaryRuntime(resources, &error) && error == nil,
                "Cannot migrate the legacy dictionary.");
        NSString *identifier = metasequoia::apple::ActiveDictionarySnapshotIdentifier(user);
        Require(identifier.length > 0 &&
                metasequoia::apple::DictionaryStateRevision(MetasequoiaCurrentDictionaryPaths()) == revision,
                "Migration lost journal entries, positions, or selection counts.");
        Require([manager fileExistsAtPath:[user URLByAppendingPathComponent:@"msime.db"].path],
                "Migration removed the legacy fallback.");
        Require(MetasequoiaPrepareBundledDictionaryRuntime(resources, &error) &&
                [metasequoia::apple::ActiveDictionarySnapshotIdentifier(user) isEqualToString:identifier],
                "Repeated preparation rebuilt an already published dictionary.");
        @autoreleasepool
        {
            [NSUserDefaults.standardUserDefaults setVolatileDomain:@{
                @"MetasequoiaImeInputScheme": @0, @"MetasequoiaImeEnglishInputMode": @NO,
                @"MetasequoiaImeLocalInputModesEnabled": @YES, @"MetasequoiaImeHelpcodeEnabled": @NO,
                @"MetasequoiaImeCandidateLearning": @NO
            } forName:NSArgumentDomain];
            PaginationTestController *controller = [PaginationTestController alloc];
            controller.testClient = [RecordingInputClient new];
            [controller prepareEmptyTestPanel:[RecordingCandidatePanel new]];
            NSEvent *trigger = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:0 context:nil
                characters:@"Y" charactersIgnoringModifiers:@"y" isARepeat:NO keyCode:kVK_ANSI_Y];
            Require([controller handleEvent:trigger client:controller.testClient], "Shift+Y did not open English input.");
            for (NSString *key in @[ @"h", @"e", @"l", @"l", @"o" ]) Press(controller, 0, key);
            Require([[controller testCandidateAtIndex:0] isEqualToString:@"hello"],
                    "English input did not query the migrated bundled dictionary.");
            Press(controller, kVK_Space, @" ");
            Require([controller.testClient.committed isEqualToString:@"hello"],
                    "English candidate was not committed at the native text boundary.");
            [controller prepareForLearnedDataReset:nil];
            [NSUserDefaults.standardUserDefaults setVolatileDomain:@{} forName:NSArgumentDomain];
        }
        @autoreleasepool { RunDedicatedEnglishTests(); }
        @autoreleasepool { RunDedicatedJapaneseTests(); }
        @autoreleasepool { RunNineKeyTests(); }
        Require([manager removeItemAtURL:[user URLByAppendingPathComponent:@"active-user-generation"] error:nil],
                "Cannot restore legacy test routing.");
        Require(metasequoia::apple::DiscardInactiveDictionarySnapshot(user, identifier),
                "Cannot clean migration fixture generation.");
    }
    @finally { [manager removeItemAtURL:resources error:nil]; }
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

int main(int argc, const char *argv[])
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        if (argc == 5 && std::strcmp(argv[1], "--dictionary-process-child") == 0)
            return RunDictionaryProcessChild(@(argv[2]), std::strcmp(argv[3], "active") == 0, @(argv[4]));
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
                             "INSERT INTO tbl_1_l VALUES('ling','l','灵',90);"
                             "CREATE TABLE tbl_2_s(key TEXT,jp TEXT,value TEXT,weight INTEGER)",
                             nullptr, nullptr, nullptr) == SQLITE_OK,
                "Cannot create partial-selection fixture.");
        sqlite3_close(database);
        try
        {
            @autoreleasepool
            {
                RunWritingSelectionTests();
                RunTests();
                RunFuzzyPinyinPreferencesTests();
                RunTypingStatisticsTests();
                RunShuangpinProfileTests();
                RunVoiceTests();
                RunFullWidthAndLocalModeTests();
                RunChinesePunctuationTests();
                RunHelpcodeIsolationTests(directory);
            }
            @autoreleasepool { RunPersonalDictionaryTests(); }
            @autoreleasepool { RunDictionaryProcessTests(directory); }
            RunBundledMigrationTests(directory);
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
