#import "TextClient.h"
#import "MSIMEClientSession.h"
#include "msime_client.h"
#include <cassert>
#include <sqlite3.h>
#include <string>

@interface FakeTextClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@property(nonatomic) NSRange selection;
@end
@implementation FakeTextClient
- (void)insertText:(id)text replacementRange:(NSRange)range { assert(range.location == NSNotFound); self.committed = text; }
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement { assert(replacement.location == NSNotFound); self.marked = text; self.selection = selection; }
@end

static NSDictionary *MaintenanceCandidate(MSIMEClientSession *session) {
    for (NSDictionary *candidate in [session viewWithError:nil][@"candidates"])
        if ([candidate[@"text"] isEqual:@"拟好"]) return candidate[@"id"];
    return nil;
}

static void TestEngineMaintenance() {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableDictionary *options = [@{@"api_version":@1, @"preferences":@{@"scheme":@"quanpin", @"candidate_page_size":@5, @"learning":@NO, @"chinese_punctuation":@YES}} mutableCopy];
    for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
        options[name] = path;
    }
    sqlite3 *database = nullptr;
    assert(sqlite3_open([[options[@"dictionaries"] stringByAppendingPathComponent:@"msime.db"] fileSystemRepresentation], &database) == SQLITE_OK);
    assert(sqlite3_exec(database, "CREATE TABLE tbl_2_n(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
        "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',10000),('ni''hao','nh','拟好',9000);", nullptr, nullptr, nullptr) == SQLITE_OK);
    assert(sqlite3_close(database) == SQLITE_OK);
    assert(sqlite3_open([[options[@"dictionaries"] stringByAppendingPathComponent:@"english.db"] fileSystemRepresentation], &database) == SQLITE_OK);
    assert(sqlite3_exec(database, "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);"
        "INSERT INTO english_words VALUES('hello','hello',100);", nullptr, nullptr, nullptr) == SQLITE_OK);
    assert(sqlite3_close(database) == SQLITE_OK);
    NSError *error = nil;
    MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
    assert(session && !error && [session setFocused:YES error:&error]);
    NSDictionary *englishView = [session setDedicatedEnglishEnabled:YES error:&error];
    assert(!error && [englishView[@"dedicated_english"] isEqual:@YES]);
    assert([session typeASCII:'h' shift:NO error:&error]);
    NSDictionary *englishTyped = [session typeASCII:'e' shift:NO error:&error];
    assert(!error && [englishTyped[@"view"][@"dedicated_english"] isEqual:@YES]);
    assert([englishTyped[@"view"][@"candidates"][0][@"text"] isEqual:@"hello"]);
    assert([[session setCharacterWidthFull:YES error:&error][@"character_width"] isEqual:@"Fullwidth"]);
    assert([[session command:MSIME_COMMIT_CANDIDATE error:&error][@"commit"] isEqual:@"ｈｅｌｌｏ"]);
    assert([[session setCharacterWidthFull:NO error:&error][@"character_width"] isEqual:@"Halfwidth"]);
    for (NSNumber *enabled in @[@YES, @NO, @YES]) {
        assert([session setEnglishMode:enabled.boolValue error:&error] && !error);
        __block NSUInteger replacements = 0;
        id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEClientSessionDidReplaceSnapshotNotification object:session queue:nil usingBlock:^(NSNotification *notification) {
            assert(notification.object == session);
            // Mode restoration must precede the notification consumed by the IMK host.
            assert([[session viewWithError:nil][@"dedicated_english"] isEqual:enabled]);
            ++replacements;
        }];
        NSError *activationError = nil;
        NSString *version = [@"" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
        assert(![MSIMEClientSession applySnapshotHandle:UINT64_MAX expectedVersion:version error:&activationError]);
        assert(activationError && replacements == 1);
        [NSNotificationCenter.defaultCenter removeObserver:observer];
        NSDictionary *restored = [session viewWithError:&error];
        assert(restored && !error && [restored[@"dedicated_english"] isEqual:enabled]);
        assert([session setFocused:YES error:&error]);
        if (enabled.boolValue) {
            assert([session typeASCII:'h' shift:NO error:&error]);
            NSDictionary *typed = [session typeASCII:'e' shift:NO error:&error];
            assert([typed[@"view"][@"candidates"][0][@"text"] isEqual:@"hello"]);
            assert([[session command:MSIME_COMMIT_CANDIDATE error:&error][@"commit"] isEqual:@"hello"]);
        }
    }
    englishView = [session setDedicatedEnglishEnabled:NO error:&error];
    assert(!error && [englishView[@"dedicated_english"] isEqual:@NO]);
    assert(![session onlineQueryWithError:&error] && !error);
    for (char key : std::string("nihao")) assert([session typeASCII:key shift:NO error:&error]);
    NSDictionary *query = [session onlineQueryWithError:&error];
    assert(query && !error);
    NSString *url = [MSIMEClientSession cloudRequestURLForQuery:query error:&error];
    assert([url hasPrefix:@"https://inputtools.google.com/"] && !error);
    NSData *body = [@"[\"SUCCESS\", [[\"nihao\", [\"云端测试候选\"]]]]" dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *beforeCloud = [session viewWithError:&error];
    NSDictionary *cloud = [session applyCloudResponse:[@"invalid" dataUsingEncoding:NSUTF8StringEncoding] query:query error:&error];
    assert(!error && [cloud[@"applied"] isEqual:@NO] && [cloud[@"view"] isEqual:beforeCloud]);
    cloud = [session applyCloudResponse:body query:query error:&error];
    assert(!error && [cloud[@"applied"] isEqual:@YES]);
    assert([cloud[@"view"][@"editing_text"] isEqual:beforeCloud[@"editing_text"]]);
    NSDictionary *afterCloud = [session viewWithError:&error];
    cloud = [session applyCloudResponse:body query:[session onlineQueryWithError:&error] error:&error];
    assert(!error && [cloud[@"applied"] isEqual:@NO] && [cloud[@"view"] isEqual:afterCloud]);
    assert([session command:MSIME_CANCEL error:&error]);
    cloud = [session applyCloudResponse:body query:query error:&error];
    assert(!error && [cloud[@"applied"] isEqual:@NO]);
    assert(![session applyCloudResponse:[NSMutableData dataWithLength:262145] query:query error:&error] && error);
    error = nil;
    assert(![MSIMEClientSession cloudRequestURLForQuery:@{@"padding":[@"x" stringByPaddingToLength:16385 withString:@"x" startingAtIndex:0]} error:&error] && error);
    error = nil;
    for (char key : std::string("nihao")) assert([session typeASCII:key shift:NO error:&error]);
    NSDictionary *identifier = MaintenanceCandidate(session);
    assert(identifier && !error);
    uint64_t generation = [identifier[@"generation"] unsignedLongLongValue];
    NSUInteger index = [identifier[@"index"] unsignedIntegerValue];
    assert(![session pinGeneration:generation + 1 index:index error:&error] && error);
    error = nil;
    NSDictionary *result = [session pinGeneration:generation index:index error:&error];
    assert(result && !error && [result[@"handled"] boolValue]);
    assert([result[@"view"][@"candidates"][0][@"text"] isEqual:@"拟好"]);
    identifier = MaintenanceCandidate(session);
    result = [session fixGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] position:2 error:&error];
    assert(result && !error && [result[@"handled"] boolValue]);
    assert([result[@"view"][@"candidates"][1][@"text"] isEqual:@"拟好"]);
    assert([result[@"view"][@"candidates"][1][@"fixed_position"] isEqual:@2]);
    identifier = MaintenanceCandidate(session);
    result = [session clearPositionGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:&error];
    assert(result && !error && [result[@"handled"] boolValue]);
    identifier = MaintenanceCandidate(session);
    result = [session removeGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] error:&error];
    assert(result && !error && [result[@"handled"] boolValue] && !MaintenanceCandidate(session));
    assert([session closeWithError:&error] && !error);
    session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
    assert(session && !error && [session setFocused:YES error:&error]);
    for (char key : std::string("nihao")) assert([session typeASCII:key shift:NO error:&error]);
    assert(!MaintenanceCandidate(session));
    assert([session closeWithError:&error] && !error);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
}

static void TestEngineEdges(FakeTextClient *client) {
    for (NSString *code in @[@"4e2d", @"20000", @"41"]) {
        for (uint8_t edge = 0; edge < 2; ++edge) {
            NSError *error = nil;
            NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
            NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"quanpin", @"candidate_page_size": @5, @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
            for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
                NSString *path = [root stringByAppendingPathComponent:name];
                assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
                options[name] = path;
            }
            MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
            assert(session && !error && [session setFocused:YES error:&error]);
            assert([session typeASCII:'U' shift:YES error:&error]);
            for (NSUInteger i = 0; i < code.length; ++i) assert([session typeASCII:[code characterAtIndex:i] shift:NO error:&error]);
            NSDictionary *view = [session viewWithError:&error];
            NSDictionary *identifier = [view[@"candidates"] firstObject][@"id"];
            assert(identifier && !error);
            assert(![session selectEdgeGeneration:[identifier[@"generation"] unsignedLongLongValue] + 1 index:[identifier[@"index"] unsignedIntegerValue] edge:edge error:&error]);
            assert(error);
            error = nil;
            assert([[[session viewWithError:&error] objectForKey:@"editing_text"] isEqual:view[@"editing_text"]]);
            NSDictionary *result = [session selectEdgeGeneration:[identifier[@"generation"] unsignedLongLongValue] index:[identifier[@"index"] unsignedIntegerValue] edge:edge error:&error];
            assert(result && !error);
            if ([code isEqual:@"41"]) {
                assert(![result[@"handled"] boolValue]);
                assert([result[@"view"][@"editing_text"] isEqual:view[@"editing_text"]]);
            } else {
                MSIMEApplyTransition(result, client);
                assert([client.committed isEqual:[code isEqual:@"4e2d"] ? @"中" : @"𠀀"]);
                assert(client.marked.length == 0);
            }
            assert([session closeWithError:&error]);
            assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
        }
    }
}

static void TestEnginePreedit(FakeTextClient *client) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"shuangpin", @"shuangpin_profile": @"microsoft", @"shuangpin_preedit_uses_raw": @YES, @"candidate_page_size": @5, @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
    for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
        options[name] = path;
    }
    NSError *error = nil;
    NSMutableDictionary *startupPreferences = [options[@"preferences"] mutableCopy];
    options[@"preferences"] = startupPreferences;
    MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
    assert(session && !error && [session setFocused:YES error:&error]);
    startupPreferences[@"scheme"] = @"quanpin";
    startupPreferences[@"shuangpin_profile"] = @"xiaohe";
    NSError *startupRecoveryError = nil;
    NSString *syntheticVersion = [@"" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
    assert(![MSIMEClientSession applySnapshotHandle:UINT64_MAX expectedVersion:syntheticVersion error:&startupRecoveryError]);
    assert(startupRecoveryError);
    NSDictionary *startupRecovered = [session viewWithError:&error];
    assert(startupRecovered && !error && [startupRecovered[@"scheme"] isEqual:@1] && [startupRecovered[@"shuangpin_profile"] isEqual:@"microsoft"]);
    assert([session setFocused:YES error:&error]);
    NSDictionary *shared = [MSIMEClientSession loadPreferencesInDirectory:root error:&error];
    assert(shared && !error);
    NSUInteger revision = 0;
    for (NSNumber *raw in @[@YES, @NO, @YES]) {
        NSMutableDictionary *preferences = [shared[@"preferences"] mutableCopy];
        preferences[@"scheme"] = @"shuangpin";
        preferences[@"shuangpin_profile"] = @"microsoft";
        preferences[@"shuangpin_preedit_uses_raw"] = raw;
        NSDictionary *snapshot = @{@"format_version": @1, @"revision": @(++revision), @"preferences": preferences};
        assert([[session updatePreferencesSnapshot:snapshot error:&error][@"deferred"] isEqual:@NO]);
        assert([session typeASCII:'b' shift:NO error:&error]);
        NSDictionary *typed = [session typeASCII:';' shift:NO error:&error];
        assert(typed && !error && [typed[@"view"][@"editing_text"] isEqual:@"b;"]);
        assert([typed[@"view"][@"preedit"] isEqual:raw.boolValue ? @"b;" : @"bing"]);
        MSIMEApplyTransition(typed, client);
        assert([client.marked isEqual:typed[@"view"][@"preedit"]] && client.selection.location == client.marked.length);
        NSDictionary *punctuationView = [session setChinesePunctuationEnabled:NO error:&error];
        assert(punctuationView && !error && !punctuationView[@"view"]);
        assert([punctuationView[@"editing_text"] isEqual:@"b;"] && [punctuationView[@"preedit"] isEqual:typed[@"view"][@"preedit"]]);
        assert([punctuationView[@"generation"] isEqual:typed[@"view"][@"generation"]]);
        MSIMEApplyTransition(@{@"view":punctuationView}, client);
        assert([client.marked isEqual:typed[@"view"][@"preedit"]]);
        assert([session setChinesePunctuationEnabled:YES error:&error] && !error);
        preferences[@"shuangpin_preedit_uses_raw"] = @(!raw.boolValue);
        assert([[MSIMEClientSession activeHostOptions][@"preferences"][@"shuangpin_preedit_uses_raw"] isEqual:raw]);
        NSDictionary *pending = @{@"format_version": @1, @"revision": @(++revision), @"preferences": preferences};
        NSDictionary *deferred = [session updatePreferencesSnapshot:pending error:&error];
        assert([deferred[@"deferred"] isEqual:@YES] && !error);
        MSIMEApplyTransition(deferred, client);
        assert([client.marked isEqual:typed[@"view"][@"preedit"]]);
        NSDictionary *cancelled = [session command:MSIME_CANCEL error:&error];
        assert(cancelled && !error);
        MSIMEApplyTransition(cancelled, client);
        assert(client.marked.length == 0 && client.selection.location == 0);
        assert([[session updatePreferencesSnapshot:pending error:&error][@"deferred"] isEqual:@NO]);
        assert([session typeASCII:'b' shift:NO error:&error]);
        NSDictionary *updated = [session typeASCII:';' shift:NO error:&error];
        assert(updated && !error);
        MSIMEApplyTransition(updated, client);
        assert([client.marked isEqual:raw.boolValue ? @"bing" : @"b;"]);
        MSIMEApplyTransition([session command:MSIME_CANCEL error:&error], client);
        assert(!error && client.marked.length == 0);
    }
    NSError *staleError = nil;
    assert((![session updatePreferencesSnapshot:@{@"format_version": @1, @"revision": @0, @"preferences": shared[@"preferences"]} error:&staleError]));
    assert(staleError && [[MSIMEClientSession activeHostOptions][@"preferences"][@"shuangpin_preedit_uses_raw"] isEqual:@NO]);
    assert([session typeASCII:'b' shift:NO error:&error]);
    __block NSUInteger replacements = 0;
    id observer = [NSNotificationCenter.defaultCenter addObserverForName:MSIMEClientSessionDidReplaceSnapshotNotification object:session queue:nil usingBlock:^(NSNotification *note) {
        assert(note.object == session && NSThread.isMainThread);
        ++replacements;
    }];
    NSString *version = [@"" stringByPaddingToLength:64 withString:@"0" startingAtIndex:0];
    // A nonexistent prepared handle forces activation failure after destruction,
    // exercising actual host recovery rather than a mocked notification.
    NSError *activationError = nil;
    assert(![MSIMEClientSession applySnapshotHandle:UINT64_MAX expectedVersion:version error:&activationError]);
    assert(activationError && replacements == 1);
    NSDictionary *recovered = [session viewWithError:&error];
    assert(recovered && !error && [recovered[@"editing_text"] length] == 0);
    assert([session setFocused:YES error:&error]);
    NSDictionary *afterRecovery = [session typeASCII:'b' shift:NO error:&error];
    assert(afterRecovery && !error && [afterRecovery[@"view"][@"editing_text"] isEqual:@"b"]);
    MSIMEApplyTransition(afterRecovery, client);
    assert([client.marked isEqual:afterRecovery[@"view"][@"preedit"]]);
    NSDictionary *expandedAfterRecovery = [session typeASCII:';' shift:NO error:&error];
    assert(expandedAfterRecovery && !error);
    // The last accepted preference was formatted display, not the raw startup value.
    assert([expandedAfterRecovery[@"view"][@"preedit"] isEqual:@"bing"]);
    [NSNotificationCenter.defaultCenter removeObserver:observer];
    NSMutableDictionary *otherOptions = [[MSIMEClientSession activeHostOptions] mutableCopy];
    NSMutableDictionary *otherPreferences = [otherOptions[@"preferences"] mutableCopy];
    otherPreferences[@"scheme"] = @"quanpin";
    otherOptions[@"preferences"] = otherPreferences;
    MSIMEClientSession *other = [[MSIMEClientSession alloc] initWithOptions:otherOptions error:&error];
    assert(other && !error);
    assert([[MSIMEClientSession activeHostOptions][@"preferences"][@"scheme"] isEqual:@"shuangpin"]);
    assert([other setFocused:YES error:&error]);
    assert([[MSIMEClientSession activeHostOptions][@"preferences"][@"scheme"] isEqual:@"quanpin"]);
    NSMutableDictionary *formattedOptions = [otherOptions mutableCopy];
    NSMutableDictionary *formattedPreferences = [otherPreferences mutableCopy];
    formattedPreferences[@"scheme"] = @"shuangpin";
    formattedPreferences[@"shuangpin_profile"] = @"microsoft";
    formattedPreferences[@"shuangpin_preedit_uses_raw"] = @NO;
    formattedOptions[@"preferences"] = formattedPreferences;
    MSIMEClientSession *formatted = [[MSIMEClientSession alloc] initWithOptions:formattedOptions error:&error];
    assert(formatted && !error && [formatted setFocused:YES error:&error]);
    for (NSString *raw in @[@"nini", @"ni'ni"]) {
        for (NSUInteger i = 0; i < raw.length; ++i)
            assert([formatted typeASCII:[raw characterAtIndex:i] shift:NO error:&error]);
        NSDictionary *segmented = [formatted viewWithError:&error];
        assert(!error && [segmented[@"preedit"] isEqual:@"ni'ni"]);
        NSArray *offsets = [raw isEqual:@"nini"] ? @[@0, @1, @2, @4, @5] : @[@0, @1, @2, @3, @4, @5];
        for (NSUInteger i = raw.length; i > 0; --i) {
            NSDictionary *moved = [formatted command:MSIME_MOVE_LEFT error:&error];
            assert(moved && !error && [moved[@"view"][@"caret_position"] unsignedIntegerValue] == i - 1);
            MSIMEApplyTransition(moved, client);
            assert([client.marked isEqual:@"ni'ni"] && client.selection.location == [offsets[i - 1] unsignedIntegerValue]);
        }
        for (NSUInteger i = 1; i <= raw.length; ++i) {
            NSDictionary *moved = [formatted command:MSIME_MOVE_RIGHT error:&error];
            assert(moved && !error && [moved[@"view"][@"caret_position"] unsignedIntegerValue] == i);
            MSIMEApplyTransition(moved, client);
            assert([client.marked isEqual:@"ni'ni"] && client.selection.location == [offsets[i] unsignedIntegerValue]);
        }
        MSIMEApplyTransition([formatted command:MSIME_CANCEL error:&error], client);
        assert(!error && !client.marked.length);
    }
    assert([formatted closeWithError:&error] && !error);
    assert([session setFocused:YES error:&error]);
    assert([[MSIMEClientSession activeHostOptions][@"preferences"][@"scheme"] isEqual:@"shuangpin"]);
    assert([session setFocused:NO error:&error]);
    assert([[MSIMEClientSession activeHostOptions][@"preferences"][@"scheme"] isEqual:@"shuangpin"]);
    assert([other closeWithError:&error]);
    NSError *closedError = nil;
    assert(![other setFocused:YES error:&closedError] && closedError);
    assert([[MSIMEClientSession activeHostOptions][@"preferences"][@"scheme"] isEqual:@"shuangpin"]);
    assert([session closeWithError:&error] && !error);
    assert([MSIMEClientSession activeHostOptions][@"error"] != nil);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
}

int main() {
    @autoreleasepool {
        FakeTextClient *client = [FakeTextClient new];
        TestEnginePreedit(client);
        TestEngineEdges(client);
        TestEngineMaintenance();
        MSIMEApplyTransition(@{@"commit": @"你好", @"view": @{@"editing_text": @"shi", @"caret_position": @1}}, client);
        assert([client.committed isEqual:@"你好"]);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 1);
        MSIMEApplyTransition(@{@"commit": NSNull.null, @"view": @{@"editing_text": @"", @"caret_position": @5}}, client);
        assert([client.committed isEqual:@"你好"] && client.marked.length == 0 && client.selection.location == 0);
        // Shuangpin full-pinyin display must not expose the raw key sequence.
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"b;", @"preedit": @"bing", @"caret_position": @2}}, client);
        assert([client.marked isEqual:@"bing"] && client.selection.location == 4);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"nihao", @"preedit": @"ni hao", @"caret_position": @2}}, client);
        assert([client.marked isEqual:@"ni hao"] && client.selection.location == 2);
        // Every raw offset, including either side of an explicit apostrophe.
        for (NSArray *fixture in @[
            @[@"nihao", @"ni'hao", @[@0, @1, @2, @4, @5, @6]],
            @[@"nihao", @"ni hao", @[@0, @1, @2, @4, @5, @6]],
            @[@"ni'hao", @"ni hao", @[@0, @1, @2, @3, @4, @5, @6]],
            @[@"ni'hao", @"nihao", @[@0, @1, @2, @2, @3, @4, @5]],
            @[@"xian", @"xi'an", @[@0, @1, @2, @4, @5]],
            @[@"nihaoma", @"ni'hao'ma", @[@0, @1, @2, @4, @5, @6, @8, @9]],
            @[@"b;", @"bing", @[@4, @4, @4]],
            @[@"shnag", @"shang", @[@5, @5, @5, @5, @5, @5]],
            @[@"nihao", @"你hao", @[@4, @4, @4, @4, @4, @4]]]) {
            NSString *raw = fixture[0], *display = fixture[1];
            NSArray *offsets = fixture[2];
            assert(offsets.count == raw.length + 1);
            for (NSUInteger offset = 0; offset <= raw.length; ++offset) {
                MSIMEApplyTransition(@{@"view": @{@"editing_text": raw, @"preedit": display, @"caret_position": @(offset)}}, client);
                assert([client.marked isEqual:display] && client.selection.location == [offsets[offset] unsignedIntegerValue]);
                assert(client.selection.length == 0);
            }
        }
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"shi", @"preedit": @"shi", @"caret_position": @1}}, client);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 1);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"x", @"preedit": @"😀", @"caret_position": @1}}, client);
        assert([client.marked isEqual:@"😀"] && client.selection.location == 2);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"shi", @"preedit": NSNull.null, @"caret_position": NSNull.null}}, client);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 3);
        MSIMEApplyTransition(@{@"commit": @"合成", @"view": @{@"editing_text": @"", @"preedit": @"", @"caret_position": @0}}, client);
        assert([client.committed isEqual:@"合成"] && client.marked.length == 0 && client.selection.location == 0);
    }
    return 0;
}
