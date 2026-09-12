#import "../CustomTranslationBatch.h"
#import "../CloudCandidateRequest.h"
#include <cassert>

@interface MSIMECustomTranslationBatch (TestSeams)
- (NSTimeInterval)currentTime;
- (MSIMECloudCandidateRequest *)requestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion;
- (MSIMECloudCandidateRequest *)AIRequestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion;
@end

@interface SyntheticTranslationRequest : MSIMECloudCandidateRequest
@property(nonatomic, copy) void (^reply)(NSData *);
@property(nonatomic) BOOL started;
@property(nonatomic) BOOL cancelled;
@end
@implementation SyntheticTranslationRequest
- (void)start { assert(!_started); _started = YES; }
// Keep the reply deliberately, to simulate an already-enqueued late callback.
- (void)cancel { _cancelled = YES; }
@end

@interface SyntheticTranslationBatch : MSIMECustomTranslationBatch
@property(nonatomic) NSTimeInterval now;
@property(nonatomic) NSTimeInterval wallTime;
@property(nonatomic, strong) NSMutableArray<SyntheticTranslationRequest *> *requests;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *descriptors;
@end
@implementation SyntheticTranslationBatch
- (NSTimeInterval)currentTime { return _now; }
- (NSTimeInterval)unixTime { return _wallTime; }
- (MSIMECloudCandidateRequest *)tencentRequestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion {
    return [self requestForDescriptor:descriptor completion:completion];
}
- (MSIMECloudCandidateRequest *)AIRequestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion {
    return [self requestForDescriptor:descriptor completion:completion];
}
- (MSIMECloudCandidateRequest *)requestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion {
    if (!_requests) _requests = [NSMutableArray array];
    if (!_descriptors) _descriptors = [NSMutableArray array];
    SyntheticTranslationRequest *request = [SyntheticTranslationRequest new];
    request.reply = completion;
    [_requests addObject:request];
    [_descriptors addObject:descriptor];
    return request;
}
@end

static NSData *Response(NSString *translation) {
    return [NSJSONSerialization dataWithJSONObject:@{@"translation":translation} options:0 error:nil];
}
static NSDictionary *Item(NSString *text) {
    return @{@"text":text, @"request":@{@"url":@"https://translation.invalid/api", @"method":@"POST",
        @"headers":@{@"Content-Type":@"application/json"}, @"body":@{@"text":text, @"source_lang":@"EN", @"target_lang":@"ZH"},
        @"timeout_ms":@2500, @"max_response_bytes":@1048576}};
}
static SyntheticTranslationBatch *Batch(NSArray *items, void (^completion)(NSArray *)) {
    return [[SyntheticTranslationBatch alloc] initWithItems:items configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:completion];
}
static void AssertReleased(MSIMECustomTranslationBatch *batch) {
    for (NSString *key in @[@"items", @"request", @"timer", @"configuration", @"results", @"completion"])
        assert(![batch valueForKey:key]);
}
static void TestSequentialResults() {
    __block NSUInteger calls = 0;
    SyntheticTranslationBatch *batch = Batch(@[Item(@"one"), Item(@"two"), Item(@"three"), Item(@"four")], ^(NSArray *results) {
        assert(NSThread.isMainThread && ++calls == 1);
        assert(([results isEqual:@[@{@"text":@"one", @"translation":@"一"}, @{@"text":@"four", @"translation":@"四"}]]));
    });
    batch.now = 100;
    [batch start]; [batch start];
    assert(batch.requests.count == 1 && batch.requests[0].started);
    batch.requests[0].reply(Response(@"一"));
    assert(batch.requests.count == 2 && calls == 0);
    batch.requests[0].reply(Response(@"stale"));
    assert(batch.requests.count == 2);
    batch.requests[1].reply(nil);
    assert(batch.requests.count == 3);
    batch.requests[2].reply([@"malformed" dataUsingEncoding:NSUTF8StringEncoding]);
    assert(batch.requests.count == 4);
    batch.requests[3].reply(Response(@"四"));
    assert(calls == 1);
    [batch start]; [batch cancel];
    batch.requests[3].reply(Response(@"late"));
    assert(calls == 1 && batch.requests.count == 4);
    AssertReleased(batch);
}
static void TestDeadline() {
    for (NSNumber *useTimer in @[@NO, @YES]) {
        __block NSUInteger calls = 0;
        SyntheticTranslationBatch *batch = Batch(@[Item(@"one"), Item(@"two"), Item(@"three")], ^(NSArray *results) {
            assert(++calls == 1);
            assert(([results isEqual:@[@{@"text":@"one", @"translation":@"一"}]]));
        });
        batch.now = 50;
        [batch start];
        NSTimer *timer = [batch valueForKey:@"timer"];
        // Non-repeating Foundation timers report a zero repeat interval.
        assert(timer.valid && timer.fireDate.timeIntervalSinceNow > 5 && timer.fireDate.timeIntervalSinceNow <= 6);
        batch.now = 55.9;
        batch.requests[0].reply(Response(@"一"));
        assert(batch.requests.count == 2);
        batch.now = 56;
        if (useTimer.boolValue) [timer fire];
        else batch.requests[1].reply(Response(@"too late"));
        assert(calls == 1 && batch.requests.count == 2 && batch.requests[1].cancelled && !timer.valid);
        batch.requests[1].reply(Response(@"late again"));
        assert(calls == 1);
        AssertReleased(batch);
    }
}
static void TestCancellationAndLifetime() {
    SyntheticTranslationBatch *before = Batch(@[Item(@"one")], ^(NSArray *results) { (void)results; assert(false); });
    [before cancel]; [before start];
    assert(before.requests.count == 0);
    AssertReleased(before);
    SyntheticTranslationBatch *during = Batch(@[Item(@"one"), Item(@"two")], ^(NSArray *results) { (void)results; assert(false); });
    [during start];
    during.requests[0].reply(Response(@"一"));
    NSTimer *timer = [during valueForKey:@"timer"];
    [during cancel]; [during cancel];
    assert(during.requests[1].cancelled && !timer.valid);
    during.requests[1].reply(Response(@"二"));
    [timer fire];
    AssertReleased(during);
    __weak SyntheticTranslationBatch *weakBatch;
    SyntheticTranslationRequest *request;
    @autoreleasepool {
        SyntheticTranslationBatch *released = Batch(@[Item(@"one")], ^(NSArray *results) { (void)results; assert(false); });
        weakBatch = released;
        [released start];
        request = released.requests[0];
    }
    assert(!weakBatch && request.cancelled);
    request.reply(Response(@"late"));
}
static void TestCopiedInput() {
    NSMutableString *text = [@"one" mutableCopy];
    NSMutableDictionary *body = [@{@"text":@"one"} mutableCopy];
    NSMutableDictionary *descriptor = [Item(text)[@"request"] mutableCopy];
    descriptor[@"body"] = body;
    NSMutableArray *items = [NSMutableArray arrayWithObject:@{@"text":text, @"request":descriptor}];
    __block BOOL done = NO;
    SyntheticTranslationBatch *batch = Batch(items, ^(NSArray *results) {
        assert(([results isEqual:@[@{@"text":@"one", @"translation":@"一"}]])); done = YES;
    });
    [text setString:@"mutated"]; body[@"text"] = @"mutated"; descriptor[@"url"] = @"https://changed.invalid/"; [items removeAllObjects];
    [batch start];
    assert([batch.descriptors[0][@"body"][@"text"] isEqual:@"one"]);
    assert([batch.descriptors[0][@"url"] isEqual:@"https://translation.invalid/api"]);
    batch.requests[0].reply(Response(@"一"));
    assert(done);
}
static void TestBoundsAndEmptyResults() {
    NSMutableArray *nine = [NSMutableArray array];
    for (NSUInteger i = 0; i < 9; ++i) [nine addObject:Item([NSString stringWithFormat:@"synthetic-%lu", (unsigned long)i])];
    __block BOOL done = NO;
    SyntheticTranslationBatch *batch = Batch(nine, ^(NSArray *results) { assert(results.count == 0); done = YES; });
    [batch start];
    for (NSUInteger i = 0; i < 9; ++i) {
        assert(batch.requests.count == i + 1);
        batch.requests[i].reply(Response(@""));
    }
    assert(done);
    NSArray *ten = [nine arrayByAddingObject:Item(@"ten")];
    NSString *oversized = [@"x" stringByPaddingToLength:262145 withString:@"x" startingAtIndex:0];
    for (NSArray *invalid in @[@[], ten, @[@1], @[@{@"text":@"", @"request":@{}}],
        @[@{@"text":@"one", @"request":@1}], @[Item(oversized)], @[@{@"text":@"one", @"request":@{@"body":oversized}}]]) {
        __block NSUInteger calls = 0;
        SyntheticTranslationBatch *rejected = Batch(invalid, ^(NSArray *results) { assert(++calls == 1 && results.count == 0); });
        [rejected start];
        assert(calls == 1 && rejected.requests.count == 0);
        AssertReleased(rejected);
    }
    // Real transport rejects invalid descriptors synchronously; bounded recursion
    // must finish exactly once without ever creating a network session.
    __block NSUInteger calls = 0;
    MSIMECustomTranslationBatch *invalidTransport = [[MSIMECustomTranslationBatch alloc]
        initWithItems:@[@{@"text":@"one", @"request":@{}}, @{@"text":@"two", @"request":@{}}]
        configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:^(NSArray *results) {
            assert(++calls == 1 && results.count == 0);
        }];
    [invalidTransport start];
    assert(calls == 1);
    AssertReleased(invalidTransport);
}
static NSDictionary *TencentItem(NSString *text, NSString *key, NSString *source, NSString *target) {
    return @{@"text":text, @"key":key, @"source_language":source, @"target_language":target};
}
static SyntheticTranslationBatch *TencentBatch(NSArray *items, void (^completion)(NSArray *)) {
    return [[SyntheticTranslationBatch alloc] initWithTencentItems:items
        config:@{@"enabled":@YES, @"secret_id":@"AKIDsynthetic", @"secret_key":@"synthetic", @"region":@"ap-guangzhou"}
        configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:completion];
}
static NSData *TencentResponse(NSArray *texts) {
    return [NSJSONSerialization dataWithJSONObject:@{@"Response":@{@"TargetTextList":texts}} options:0 error:nil];
}
static void TestTencentGroups() {
    NSMutableString *original = [@"HELLO" mutableCopy];
    NSMutableArray *items = [@[TencentItem(original, @"hello", @"en", @"zh"),
        TencentItem(@"你好", @"你好", @"zh", @"ja"), TencentItem(@"World", @"world", @"en", @"zh")] mutableCopy];
    __block NSUInteger calls = 0;
    SyntheticTranslationBatch *batch = TencentBatch(items, ^(NSArray *results) {
        assert(++calls == 1);
        assert(([results isEqual:@[@{@"text":@"HELLO", @"translation":@"你好"},
            @{@"text":@"你好", @"translation":@"こんにちは"}]]));
    });
    [original setString:@"mutated"]; [items removeAllObjects];
    batch.wallTime = 1704067200;
    [batch start];
    assert(batch.requests.count == 1);
    NSDictionary *first = batch.descriptors[0];
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:[first[@"body_utf8"] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    assert(([body[@"SourceTextList"] isEqual:@[@"hello", @"world"]]));
    assert([body[@"Source"] isEqual:@"en"] && [body[@"Target"] isEqual:@"zh"]);
    assert([first[@"headers"][@"X-TC-Timestamp"] isEqual:@"1704067200"]);
    batch.wallTime += 2;
    batch.requests[0].reply(TencentResponse(@[@"  你好  ", @""]));
    assert(batch.requests.count == 2 && calls == 0);
    assert([batch.descriptors[1][@"headers"][@"X-TC-Timestamp"] isEqual:@"1704067202"]);
    batch.requests[0].reply(TencentResponse(@[@"stale", @"stale"]));
    assert(batch.requests.count == 2);
    batch.requests[1].reply(TencentResponse(@[@"こんにちは"]));
    assert(calls == 1);
    AssertReleased(batch);
}
static void TestTencentFailuresAndCancellation() {
    NSArray *items = @[TencentItem(@"Hello", @"hello", @"en", @"zh"), TencentItem(@"你好", @"你好", @"zh", @"en")];
    for (NSData *bad in @[TencentResponse(@[]), TencentResponse(@[@"one", @"two"]),
        [@"{\"Response\":{\"Error\":{}}}" dataUsingEncoding:NSUTF8StringEncoding],
        [@"malformed" dataUsingEncoding:NSUTF8StringEncoding]]) {
        __block NSUInteger calls = 0;
        SyntheticTranslationBatch *batch = TencentBatch(items, ^(NSArray *results) {
            assert(++calls == 1 && results.count == 1);
            assert([results[0][@"text"] isEqual:@"你好"]);
        });
        [batch start];
        batch.requests[0].reply(bad);
        batch.requests[1].reply(TencentResponse(@[@"hello"]));
        assert(calls == 1);
        AssertReleased(batch);
    }
    SyntheticTranslationBatch *cancelled = TencentBatch(items, ^(NSArray *results) { (void)results; assert(false); });
    [cancelled start]; [cancelled cancel];
    assert(cancelled.requests[0].cancelled);
    cancelled.requests[0].reply(TencentResponse(@[@"late"]));
    assert(cancelled.requests.count == 1);
    AssertReleased(cancelled);
    for (NSNumber *timerDriven in @[@NO, @YES]) {
        __block NSUInteger calls = 0;
        SyntheticTranslationBatch *batch = TencentBatch(items, ^(NSArray *results) { assert(++calls == 1 && results.count == 1); });
        [batch start];
        batch.requests[0].reply(TencentResponse(@[@"你好"]));
        batch.now = 6;
        if (timerDriven.boolValue) [[batch valueForKey:@"timer"] fire];
        else batch.requests[1].reply(TencentResponse(@[@"late"]));
        assert(calls == 1 && batch.requests[1].cancelled);
        AssertReleased(batch);
    }
    for (NSArray *invalid in @[@[@1], @[TencentItem(@"", @"hello", @"en", @"zh")],
        @[TencentItem(@"Hello", @"hello", @"invalid", @"zh")]]) {
        __block NSUInteger calls = 0;
        SyntheticTranslationBatch *batch = TencentBatch(invalid, ^(NSArray *results) { assert(++calls == 1 && results.count == 0); });
        [batch start];
        assert(calls == 1 && batch.requests.count == 0);
        AssertReleased(batch);
    }
    NSMutableArray *ten = [NSMutableArray array];
    for (NSUInteger i = 0; i < 10; ++i) [ten addObject:items[0]];
    __block NSUInteger calls = 0;
    SyntheticTranslationBatch *oversized = TencentBatch(ten, ^(NSArray *results) { assert(++calls == 1 && results.count == 0); });
    [oversized start];
    assert(calls == 1 && oversized.requests.count == 0);
    AssertReleased(oversized);
    [ten removeLastObject];
    __block BOOL nineDone = NO;
    SyntheticTranslationBatch *nine = TencentBatch(ten, ^(NSArray *results) { assert(results.count == 9); nineDone = YES; });
    [nine start];
    assert(nine.requests.count == 1 && [nine.descriptors[0][@"expected_count"] isEqual:@9]);
    nine.requests[0].reply(TencentResponse(@[@"一", @"二", @"三", @"四", @"五", @"六", @"七", @"八", @"九"]));
    assert(nineDone);
    AssertReleased(nine);
    for (NSDictionary *config in @[@{}, @{@"enabled":@NO},
        @{@"enabled":@YES, @"secret_id":@"AKIDsynthetic", @"secret_key":@"synthetic", @"region":@"bad\nregion"}]) {
        __block BOOL rejected = NO;
        SyntheticTranslationBatch *invalidConfig = [[SyntheticTranslationBatch alloc] initWithTencentItems:items
            config:config configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration
            completion:^(NSArray *results) { assert(results.count == 0); rejected = YES; }];
        [invalidConfig start];
        assert(rejected && invalidConfig.requests.count == 0);
        AssertReleased(invalidConfig);
    }
    __weak SyntheticTranslationBatch *weakBatch;
    SyntheticTranslationRequest *request;
    @autoreleasepool {
        SyntheticTranslationBatch *released = TencentBatch(items, ^(NSArray *results) { (void)results; assert(false); });
        weakBatch = released;
        [released start];
        request = released.requests[0];
    }
    assert(!weakBatch && request.cancelled);
    request.reply(TencentResponse(@[@"late"]));
}
static void TestAIItems() {
    NSArray *items = @[
        @{@"text":@"候选甲", @"request":@{@"url":@"https://ai.invalid/chat", @"method":@"POST", @"headers":@{@"Content-Type":@"application/json", @"Authorization":@"Bearer synthetic"}, @"body":@{@"model":@"synthetic"}, @"timeout_ms":@8000, @"connect_timeout_ms":@2500, @"max_response_bytes":@1048576}},
    ];
    __block BOOL done = NO;
    SyntheticTranslationBatch *batch = [[SyntheticTranslationBatch alloc] initWithAIItems:items configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:^(NSArray *results) {
        assert(([results isEqual:@[@{@"text":@"候选甲", @"translation":@"释义甲"}]])); done = YES;
    }];
    [batch start]; assert(batch.requests.count == 1 && batch.requests[0].started);
    NSData *body = [NSJSONSerialization dataWithJSONObject:@{@"choices":@[@{@"message":@{@"content":@"{\"candidates\":[{\"text\":\"释义甲\"}]}"}}]} options:0 error:nil];
    batch.requests[0].reply(body); assert(done);
    AssertReleased(batch);
}
int main() {
    @autoreleasepool {
        TestSequentialResults();
        TestDeadline();
        TestCancellationAndLifetime();
        TestCopiedInput();
        TestBoundsAndEmptyResults();
        TestTencentGroups();
        TestTencentFailuresAndCancellation();
        TestAIItems();
    }
    return 0;
}
