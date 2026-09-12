#import "../CustomTranslationBatch.h"
#import "../CloudCandidateRequest.h"
#include <cassert>

@interface MSIMECustomTranslationBatch (TestSeams)
- (NSTimeInterval)currentTime;
- (MSIMECloudCandidateRequest *)requestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion;
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
@property(nonatomic, strong) NSMutableArray<SyntheticTranslationRequest *> *requests;
@property(nonatomic, strong) NSMutableArray<NSDictionary *> *descriptors;
@end
@implementation SyntheticTranslationBatch
- (NSTimeInterval)currentTime { return _now; }
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
int main() {
    @autoreleasepool {
        TestSequentialResults();
        TestDeadline();
        TestCancellationAndLifetime();
        TestCopiedInput();
        TestBoundsAndEmptyResults();
    }
    return 0;
}
