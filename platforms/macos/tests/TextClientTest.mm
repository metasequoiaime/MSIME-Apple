#import "TextClient.h"
#import "MSIMEClientSession.h"
#include "msime_client.h"
#include <cassert>

@interface FakeTextClient : NSObject <MSIMETextClient>
@property(nonatomic, copy) NSString *committed;
@property(nonatomic, copy) NSString *marked;
@property(nonatomic) NSRange selection;
@end
@implementation FakeTextClient
- (void)insertText:(id)text replacementRange:(NSRange)range { assert(range.location == NSNotFound); self.committed = text; }
- (void)setMarkedText:(id)text selectionRange:(NSRange)selection replacementRange:(NSRange)replacement { assert(replacement.location == NSNotFound); self.marked = text; self.selection = selection; }
@end

static void TestEnginePreedit(FakeTextClient *client) {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSMutableDictionary *options = [@{@"api_version": @1, @"preferences": @{@"scheme": @"shuangpin", @"shuangpin_profile": @"microsoft", @"shuangpin_preedit_uses_raw": @YES, @"candidate_page_size": @5, @"learning": @NO, @"chinese_punctuation": @YES}} mutableCopy];
    for (NSString *name in @[@"resources", @"user_data", @"cache", @"dictionaries"]) {
        NSString *path = [root stringByAppendingPathComponent:name];
        assert([NSFileManager.defaultManager createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil]);
        options[name] = path;
    }
    NSError *error = nil;
    MSIMEClientSession *session = [[MSIMEClientSession alloc] initWithOptions:options error:&error];
    assert(session && !error && [session setFocused:YES error:&error]);
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
        preferences[@"shuangpin_preedit_uses_raw"] = @(!raw.boolValue);
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
    assert([session closeWithError:&error] && !error);
    assert([NSFileManager.defaultManager removeItemAtPath:root error:nil]);
}

int main() {
    @autoreleasepool {
        FakeTextClient *client = [FakeTextClient new];
        TestEnginePreedit(client);
        MSIMEApplyTransition(@{@"commit": @"你好", @"view": @{@"editing_text": @"shi", @"caret_position": @1}}, client);
        assert([client.committed isEqual:@"你好"]);
        assert([client.marked isEqual:@"shi"] && client.selection.location == 1);
        MSIMEApplyTransition(@{@"commit": NSNull.null, @"view": @{@"editing_text": @"", @"caret_position": @5}}, client);
        assert([client.committed isEqual:@"你好"] && client.marked.length == 0 && client.selection.location == 0);
        // Shuangpin full-pinyin display must not expose the raw key sequence.
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"b;", @"preedit": @"bing", @"caret_position": @2}}, client);
        assert([client.marked isEqual:@"bing"] && client.selection.location == 4);
        MSIMEApplyTransition(@{@"view": @{@"editing_text": @"nihao", @"preedit": @"ni hao", @"caret_position": @2}}, client);
        assert([client.marked isEqual:@"ni hao"] && client.selection.location == 6);
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
