// Exercise the real controller with a recording window boundary. A headless
// IMKCandidates cannot render without a registered input-method client.
#include "../src/MetasequoiaInputController.mm"
#include "../../../vendor/MetasequoiaImeEngine/user_dictionary/user_dictionary_journal.h"
#include <sqlite3.h>
#include <filesystem>
#include <stdexcept>

static void Require(bool condition, const char *message)
{
    if (!condition) throw std::runtime_error(message);
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
- (void)setAttributes:(NSDictionary *)attributes { (void)attributes; }
- (void)setCandidateData:(NSArray *)data { self.data = data; self.selected = 0; }
- (void)show:(IMKCandidatesLocationHint)hint { (void)hint; self.visible = YES; }
- (void)hide { self.visible = NO; }
- (BOOL)isVisible { return self.visible; }
- (NSInteger)candidateIdentifierAtLineNumber:(NSInteger)line
{
    return line >= 0 && (NSUInteger)line < self.data.count ? (self.collapsedIdentifiers ? 0 : 100 + line * 3) : NSNotFound;
}
- (NSInteger)lineNumberForCandidateWithIdentifier:(NSInteger)identifier
{ return self.collapsedIdentifiers ? 0 : (identifier - 100) / 3; }
- (BOOL)selectCandidateWithIdentifier:(NSInteger)identifier
{
    const NSInteger line = self.collapsedIdentifiers ? identifier : [self lineNumberForCandidateWithIdentifier:identifier];
    if (line < 0 || (NSUInteger)line >= self.data.count) return NO;
    if (self.rejectedEngineIndex != nil && MetasequoiaCandidateIndex(self.data[line]) == self.rejectedEngineIndex.unsignedIntegerValue) return NO;
    self.selected = line;
    return YES;
}
- (NSInteger)selectedCandidate { return self.collapsedIdentifiers ? 0 : 100 + self.selected * 3; }
- (NSAttributedString *)selectedCandidateString { return self.data[self.selected]; }
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
{ (void)index; *rect = NSMakeRect(100, 400, 1, 20); return @{}; }
- (void)insertText:(id)text replacementRange:(NSRange)range { (void)range; self.committed = text; }
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement
{ self.marked = text; (void)selection; (void)replacement; }
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
@end
@implementation MetasequoiaInputController (PaginationTestFixture)
- (void)prepareTestPanel:(RecordingCandidatePanel *)panel
{
    _candidatePanel = (MetasequoiaCandidatePanel *)panel;
    _session = std::make_unique<metasequoia::InputSession>();
    [self reloadSessionFromPreferences];
    for (char character : std::string("nihao")) _session->handle_character(character);
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
- (BOOL)testHasComposition { return _session != nullptr && _session->has_composition(); }
- (void)preparePartialInput
{
    _session = std::make_unique<metasequoia::InputSession>(SchemeType::Quanpin, true, false, true, false);
    for (char character : std::string("shui'lin")) _session->handle_character(character);
    [self updateCandidatePanel];
}
- (NSUInteger)testCandidateCount { return _session->candidates().size(); }
- (NSString *)testCandidateAtIndex:(NSUInteger)index
{ return MetasequoiaStringFromUtf8(_session->candidates()[index].word); }
@end

@interface PaginationTestController : MetasequoiaInputController
@property(nonatomic, strong) RecordingInputClient *testClient;
@end
@implementation PaginationTestController
- (id)client { return self.testClient; }
@end

static void Press(PaginationTestController *controller, unsigned short code, NSString *text)
{
    NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                  timestamp:0 windowNumber:0 context:nil characters:text
                charactersIgnoringModifiers:text isARepeat:NO keyCode:code];
    Require([controller handleEvent:event client:controller.testClient], "The controller did not handle a paging test key.");
}

static void RunTests()
{
    Require([MetasequoiaInputController conformsToProtocol:@protocol(MetasequoiaFloatingToolbarDelegate)] &&
                [MetasequoiaInputController conformsToProtocol:@protocol(MetasequoiaCandidatePanelDelegate)],
            "The controller does not support both window delegate contracts.");
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    for (NSNumber *style in @[@0, @1]) for (NSNumber *size in @[@5, @7, @9])
    {
        [defaults setVolatileDomain:@{@"MetasequoiaImeCandidatePageSize":size,
            @"MetasequoiaImeCandidatePanelStyle":style,
            @"MetasequoiaImeCandidateLearning":@NO,
            @"MetasequoiaImeHelpcodeEnabled":@NO} forName:NSArgumentDomain];
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
        const NSUInteger pageSize = size.unsignedIntegerValue;
        Require([controller testCandidateCount] > pageSize, "The fixture needs multiple pages.");
        Require(panel.data.count == pageSize, "The native window received more than the configured candidates per page.");
        Require([[controller candidates:nil] count] == pageSize, "The IMK callback bypassed pagination.");
        Press(controller, kVK_PageDown, @"");
        Require(MetasequoiaCandidateIndex(panel.data[0]) == pageSize, "Page Down did not start at the next engine candidate.");
        Require(panel.data.count <= pageSize, "The second page exceeded the configured page size.");
        NSString *expected = [controller testCandidateAtIndex:pageSize];
        Press(controller, kVK_ANSI_1, @"1");
        Require([controller.testClient.committed isEqualToString:expected], "Digit 1 on page two committed the wrong engine candidate.");

        [controller prepareTestPanel:panel];
        const unsigned short forward = style.intValue == 0 ? kVK_RightArrow : kVK_DownArrow;
        const unsigned short backward = style.intValue == 0 ? kVK_LeftArrow : kVK_UpArrow;
        for (NSUInteger step = 0; step < pageSize; ++step) Press(controller, forward, @"");
        Require(MetasequoiaCandidateIndex(panel.data[0]) == pageSize, "Arrow navigation did not cross the page boundary.");
        Press(controller, backward, @"");
        Require(MetasequoiaCandidateIndex(panel.data[0]) == 0, "Reverse navigation did not return to the first page.");
        expected = [controller testCandidateAtIndex:pageSize - 1];
        Press(controller, kVK_Space, @" ");
        Require([controller.testClient.committed isEqualToString:expected], "Space committed a different candidate from the highlighted one.");

        [controller prepareTestPanel:panel];
        const NSUInteger total = [controller testCandidateCount];
        for (NSUInteger page = 1; page * pageSize < total; ++page) Press(controller, kVK_PageDown, @"");
        const NSUInteger lastPageStart = pageSize == 5 ? 10 : pageSize; // fixture has 12 candidates
        Require(total == 12 && MetasequoiaCandidateIndex(panel.data[0]) == lastPageStart,
                "The last page started at the wrong engine candidate.");
        Require(panel.data.count == total - lastPageStart, "The partial last page lost candidates.");
        NSArray *lastPage = panel.data;
        Press(controller, kVK_PageDown, @"");
        Require([panel.data isEqualToArray:lastPage], "Page Down moved beyond the last page.");
        Press(controller, kVK_PageUp, @"");
        Require(MetasequoiaCandidateIndex(panel.data[0]) == lastPageStart - pageSize, "Page Up skipped a page.");

        for (NSNumber *stripped in @[@NO, @YES])
        {
            [controller prepareTestPanel:panel];
            Press(controller, kVK_PageDown, @"");
            panel.selected = 1;
            expected = [controller testCandidateAtIndex:pageSize + 1];
            NSAttributedString *clicked = panel.data[1];
            if (stripped.boolValue) clicked = [[NSAttributedString alloc] initWithString:clicked.string];
            [controller candidateSelected:clicked];
            Require([controller.testClient.committed isEqualToString:expected], "A page-two mouse callback committed the wrong engine candidate.");
        }

        if (NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26)
        {
            panel.collapsedIdentifiers = YES;
            [controller prepareTestPanel:panel];
            Press(controller, kVK_PageDown, @"");
            Press(controller, forward, @"");
            Require(panel.selected == 1, "Collapsed native identifiers used a global index instead of a page-local ordinal.");
            expected = [controller testCandidateAtIndex:pageSize + 1];
            Press(controller, kVK_Space, @" ");
            Require([controller.testClient.committed isEqualToString:expected], "Collapsed identifiers lost the global engine selection.");
            [controller prepareTestPanel:panel];
            Press(controller, kVK_PageDown, @"");
            panel.selected = 1;
            expected = [controller testCandidateAtIndex:pageSize + 1];
            [controller candidateSelected:[[NSAttributedString alloc] initWithString:[panel.data[1] string]]];
            Require([controller.testClient.committed isEqualToString:expected], "A stripped mouse callback with collapsed identifiers lost its page offset.");
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
        Require([controller.testClient.committed isEqualToString:expected], "Failed page navigation changed the engine selection.");
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
- (void)startWithCompletion:(MetasequoiaVoiceCompletion)completion { self.active=YES; self.recording=YES; self.pending=completion; }
- (void)stop { self.recording=NO; }
- (void)cancel { self.active=NO; self.recording=NO; } // Deliberately retain stale callback to exercise host defenses.
@end
@interface VoiceInputClient : RecordingInputClient
@property(nonatomic) NSRange range;
@end
@implementation VoiceInputClient
- (NSRange)selectedRange { return self.range; }
@end
@interface MetasequoiaInputController (VoiceTestFixture)
- (void)prepareVoiceFixture:(id<MetasequoiaVoiceService>)service;
@end
@implementation MetasequoiaInputController (VoiceTestFixture)
- (void)prepareVoiceFixture:(id<MetasequoiaVoiceService>)service {
    [self cancelVoiceInput]; _voiceService=service; _serverActive=YES; _session.reset();
}
@end
@interface VoiceTestController : PaginationTestController
@property(nonatomic, strong) NSError *voiceError;
@end
@implementation VoiceTestController
- (void)showVoiceError:(NSError *)error { self.voiceError=error; }
@end
static void RunVoiceTests() {
    VoiceTestController *controller = [VoiceTestController new];
    VoiceInputClient *first = [VoiceInputClient new]; first.range=NSMakeRange(10,0);
    VoiceInputClient *second = [VoiceInputClient new]; second.range=NSMakeRange(10,0);
    DeferredVoiceService *voice = [DeferredVoiceService new];
    controller.testClient=first;
    [controller prepareVoiceFixture:voice];
    [controller toggleVoiceInput:nil];
    Require(voice.active && voice.recording, "Voice entry did not start the service.");
    [controller toggleVoiceInput:nil];
    Require(voice.active && !voice.recording, "Voice entry did not finish recording.");
    voice.pending(@"水杉 voice", nil);
    Require([first.committed isEqualToString:@"水杉 voice"], "Voice output was not committed through the input client.");
    first.committed=nil;

    [controller toggleVoiceInput:nil];
    MetasequoiaVoiceCompletion stale=voice.pending;
    [controller cancelVoiceInput];
    stale(@"取消后的文本", nil);
    Require(first.committed == nil, "Cancelled voice committed stale text.");

    [controller toggleVoiceInput:nil]; stale=voice.pending;
    [controller cancelVoiceInput]; [controller toggleVoiceInput:nil];
    stale(@"旧请求", nil);
    Require(first.committed == nil && voice.active, "An old callback affected a newer request.");
    voice.pending(@"新请求", nil);
    Require([first.committed isEqualToString:@"新请求"], "The active request did not commit.");
    first.committed=nil;

    [controller toggleVoiceInput:nil];
    first.range=NSMakeRange(11,0);
    voice.pending(@"位置已变化", nil);
    Require(first.committed == nil, "Voice output ignored a moved insertion point.");

    [controller toggleVoiceInput:nil]; stale=voice.pending;
    controller.testClient=second;
    stale(@"错误窗口", nil);
    Require(first.committed == nil && second.committed == nil, "Voice output crossed input clients.");
    [controller cancelVoiceInput]; controller.testClient=first;

    [controller toggleVoiceInput:nil]; stale=voice.pending;
    // The IMK superclass requires a registered server. Exercise our real
    // deactivation work without invoking that external framework boundary.
    [controller prepareForDeactivation:first];
    stale(@"失去焦点", nil);
    Require(first.committed == nil && !voice.active, "Deactivation did not cancel voice output.");
    [controller prepareVoiceFixture:voice];

    NSEvent *toggle = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
        modifierFlags:NSEventModifierFlagControl | NSEventModifierFlagOption timestamp:0 windowNumber:0 context:nil
        characters:@"v" charactersIgnoringModifiers:@"v" isARepeat:NO keyCode:9];
    Require([controller handleEvent:toggle client:first] && voice.recording, "Voice shortcut did not start recording.");
    stale=voice.pending;
    NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:53];
    Require([controller handleEvent:escape client:first] && !voice.active, "Escape did not cancel voice.");
    stale(@"Esc 后的文本", nil);
    Require(first.committed == nil, "Escape allowed a late result.");

    [controller toggleVoiceInput:nil]; stale=voice.pending;
    NSEvent *navigation = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0 timestamp:0
        windowNumber:0 context:nil characters:@"" charactersIgnoringModifiers:@"" isARepeat:NO keyCode:kVK_LeftArrow];
    [controller handleEvent:navigation client:first]; stale(@"键盘移动后", nil);
    Require(first.committed == nil && !voice.active, "Keyboard navigation did not invalidate voice.");

    [controller toggleVoiceInput:nil];
    voice.pending(nil, [NSError errorWithDomain:@"fixture" code:1 userInfo:nil]);
    Require(controller.voiceError != nil && first.committed == nil, "Voice failure inserted text or lost its error.");
    [controller cancelVoiceInput]; voice.pending=nil;
}

// Full-width mode used to convert every letter before the engine saw it, which made Chinese input
// impossible while it was on, and 启用本地输入模式 was only ever applied to a session at the moment
// it was constructed, so toggling it did nothing to the session the user was already typing in.
static void RunFullWidthAndLocalModeTests()
{
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    NSDictionary *baseDefaults = @{@"MetasequoiaImeFullWidthInputEnabled": @YES,
                                   @"MetasequoiaImeCandidateLearning": @NO,
                                   @"MetasequoiaImeHelpcodeEnabled": @NO,
                                   @"MetasequoiaImeCandidatePageSize": @9};
    [defaults setVolatileDomain:baseDefaults forName:NSArgumentDomain];

    PaginationTestController *controller = [PaginationTestController new];
    RecordingCandidatePanel *panel = [RecordingCandidatePanel new];
    controller.testClient = [RecordingInputClient new];
    [controller prepareEmptyTestPanel:panel];

    for (NSString *letter in @[@"n", @"i", @"h", @"a", @"o"])
    {
        NSEvent *event = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                         timestamp:0 windowNumber:0 context:nil characters:letter
                       charactersIgnoringModifiers:letter isARepeat:NO keyCode:kVK_ANSI_N];
        Require([controller handleEvent:event client:controller.testClient],
                "Full-width mode did not route a letter into the session.");
    }
    Require([controller testHasComposition],
            "Full-width mode swallowed the letters instead of starting a composition.");
    Require(controller.testClient.committed == nil,
            "Full-width mode committed a letter that should have been composed.");
    Require(panel.visible && panel.data.count > 0, "Full-width mode suppressed the candidate window.");

    NSEvent *escape = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint modifierFlags:0
                                      timestamp:0 windowNumber:0 context:nil characters:@""
                    charactersIgnoringModifiers:@"" isARepeat:NO keyCode:53];
    Require([controller handleEvent:escape client:controller.testClient] && ![controller testHasComposition],
            "Escape did not cancel the full-width composition fixture.");
    controller.testClient.committed = nil;

    // A capital is not composable, so it still comes back through the post-engine fallback and is
    // the character full-width mode is actually meant to convert.
    NSEvent *capital = [NSEvent keyEventWithType:NSEventTypeKeyDown location:NSZeroPoint
                                   modifierFlags:NSEventModifierFlagShift timestamp:0 windowNumber:0
                                         context:nil characters:@"U" charactersIgnoringModifiers:@"U"
                                       isARepeat:NO keyCode:kVK_ANSI_U];
    Require([controller handleEvent:capital client:controller.testClient] &&
                [controller.testClient.committed isEqualToString:@"Ｕ"],
            "Full-width mode did not convert a capital the session declined.");
    controller.testClient.committed = nil;

    // Flipped after the session exists. It used to take effect only on the next rebuild, so the
    // trigger stayed dead in the window the user had just changed the setting for.
    NSMutableDictionary *withLocalModes = [baseDefaults mutableCopy];
    withLocalModes[@"MetasequoiaImeLocalInputModesEnabled"] = @YES;
    [defaults setVolatileDomain:withLocalModes forName:NSArgumentDomain];
    Require([controller handleEvent:capital client:controller.testClient] &&
                controller.testClient.committed == nil,
            "Enabling 启用本地输入模式 did not reach the running session.");

    [defaults setVolatileDomain:@{} forName:NSArgumentDomain];
}

int main()
{
    @autoreleasepool
    {
        [NSApplication sharedApplication];
        NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        std::filesystem::create_directories(directory.fileSystemRepresentation);
        setenv("METASEQUOIA_IME_DATA_DIR", directory.fileSystemRepresentation, 1);
        sqlite3 *database = nullptr;
        Require(sqlite3_open([directory stringByAppendingPathComponent:@"msime.db"].fileSystemRepresentation, &database) == SQLITE_OK, "Cannot create fixture.");
        Require(sqlite3_exec(database, "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER)", nullptr, nullptr, nullptr) == SQLITE_OK, "Cannot create table.");
        for (int index = 0; index < 12; ++index)
        {
            NSString *sql = [NSString stringWithFormat:@"INSERT INTO tbl_2_n VALUES('ni''hao','nh','候选%d',%d)", index, 120-index];
            Require(sqlite3_exec(database, sql.UTF8String, nullptr, nullptr, nullptr) == SQLITE_OK, "Cannot insert fixture.");
        }
        Require(sqlite3_exec(database,
            "CREATE TABLE tbl_1_s(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
            "INSERT INTO tbl_1_s VALUES('shui','s','水',100);"
            "CREATE TABLE tbl_1_l(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
            "INSERT INTO tbl_1_l VALUES('lin','l','林',100);"
            "CREATE TABLE tbl_2_s(key TEXT,jp TEXT,value TEXT,weight INTEGER)",
            nullptr, nullptr, nullptr) == SQLITE_OK, "Cannot create partial-selection fixture.");
        sqlite3_close(database);
        try { RunTests(); RunVoiceTests(); RunFullWidthAndLocalModeTests(); }
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
