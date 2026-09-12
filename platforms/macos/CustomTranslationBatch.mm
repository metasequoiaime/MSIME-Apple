#import "CustomTranslationBatch.h"
#import "CloudCandidateRequest.h"
#import "MSIMEClientSession.h"

@implementation MSIMECustomTranslationBatch {
    NSArray<NSDictionary *> *_items;
    NSURLSessionConfiguration *_configuration;
    void (^_completion)(NSArray<NSDictionary *> *);
    NSMutableArray<NSDictionary *> *_results;
    MSIMECloudCandidateRequest *_request;
    NSTimer *_timer;
    NSTimeInterval _deadline;
    NSUInteger _nextIndex;
    BOOL _started;
    BOOL _tencent;
}
- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items
                configuration:(NSURLSessionConfiguration *)configuration
                   completion:(void (^)(NSArray<NSDictionary *> *))completion {
    if ((self = [super init])) {
        _completion = [completion copy];
        _configuration = [configuration copy];
        _results = [NSMutableArray array];
        if (![items isKindOfClass:NSArray.class] || items.count > 9 ||
            ![NSJSONSerialization isValidJSONObject:items]) return self;
        for (id item in items) {
            if (![item isKindOfClass:NSDictionary.class] || ![item[@"text"] isKindOfClass:NSString.class] ||
                ![item[@"text"] length] || [item[@"text"] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096 ||
                ![item[@"request"] isKindOfClass:NSDictionary.class]) return self;
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:items options:0 error:nil];
        if (data.length && data.length <= 262144)
            _items = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    }
    return self;
}
- (instancetype)initWithTencentItems:(NSArray<NSDictionary *> *)items
                               config:(NSDictionary *)config
                        configuration:(NSURLSessionConfiguration *)configuration
                           completion:(void (^)(NSArray<NSDictionary *> *))completion {
    self = [self initWithItems:@[] configuration:configuration completion:completion];
    if (!self) return nil;
    _tencent = YES;
    if (![items isKindOfClass:NSArray.class] || items.count > 9 ||
        ![config isKindOfClass:NSDictionary.class]) return self;
    NSDictionary *input = @{@"items":items, @"config":config};
    if (![NSJSONSerialization isValidJSONObject:input]) return self;
    NSData *data = [NSJSONSerialization dataWithJSONObject:input options:0 error:nil];
    if (!data.length || data.length > 65536) return self;
    input = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    NSMutableArray<NSMutableDictionary *> *groups = [NSMutableArray array];
    for (id item in input[@"items"]) {
        if (![item isKindOfClass:NSDictionary.class]) return self;
        for (NSString *field in @[@"text", @"key", @"source_language", @"target_language"]) {
            if (![item[field] isKindOfClass:NSString.class] || ![item[field] length] ||
                [item[field] lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 4096) return self;
        }
        NSMutableDictionary *group = nil;
        for (NSMutableDictionary *candidate in groups) {
            if ([candidate[@"source_language"] isEqual:item[@"source_language"]] &&
                [candidate[@"target_language"] isEqual:item[@"target_language"]]) { group = candidate; break; }
        }
        if (!group) {
            group = [@{@"source_language":item[@"source_language"], @"target_language":item[@"target_language"],
                @"config":input[@"config"], @"texts":[NSMutableArray array], @"originals":[NSMutableArray array]} mutableCopy];
            [groups addObject:group];
        }
        [group[@"texts"] addObject:item[@"key"]];
        [group[@"originals"] addObject:item[@"text"]];
    }
    _items = [groups copy];
    return self;
}
- (NSTimeInterval)currentTime { return NSProcessInfo.processInfo.systemUptime; }
- (NSTimeInterval)unixTime { return NSDate.date.timeIntervalSince1970; }
- (MSIMECloudCandidateRequest *)tencentRequestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion {
    return [[MSIMECloudCandidateRequest alloc] initWithTencentDescriptor:descriptor
        configuration:_configuration completion:completion];
}
- (MSIMECloudCandidateRequest *)requestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion {
    return [[MSIMECloudCandidateRequest alloc] initWithTranslationDescriptor:descriptor
        configuration:_configuration completion:completion];
}
- (void)start {
    NSAssert(NSThread.isMainThread, @"Translation batch must run on main thread");
    if (_started || !_completion) return;
    _started = YES;
    _deadline = [self currentTime] + 6;
    __weak MSIMECustomTranslationBatch *weakSelf = self;
    _timer = [NSTimer timerWithTimeInterval:6 repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        [weakSelf finish];
    }];
    [NSRunLoop.mainRunLoop addTimer:_timer forMode:NSRunLoopCommonModes];
    [self advance];
}
- (void)advance {
    if (!_completion) return;
    if (_nextIndex >= _items.count || [self currentTime] >= _deadline) { [self finish]; return; }
    NSDictionary *item = _items[_nextIndex++];
    NSString *text = item[@"text"];
    NSUInteger sequence = _nextIndex;
    __weak MSIMECustomTranslationBatch *weakSelf = self;
    void (^reply)(NSData *) = ^(NSData *body) {
        MSIMECustomTranslationBatch *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_completion || sequence != strongSelf->_nextIndex) return;
        // The main queue may be busy when the deadline timer becomes due.
        if ([strongSelf currentTime] >= strongSelf->_deadline) { [strongSelf finish]; return; }
        NSArray *translations = nil;
        NSString *translation = nil;
        if (strongSelf->_tencent) {
            translations = body ? [MSIMEClientSession parseTencentTranslationResponse:body
                expectedCount:[item[@"originals"] count] error:nil] : nil;
        } else {
            translation = body ? [MSIMEClientSession parseCustomTranslationResponse:body error:nil] : nil;
        }
        if ([strongSelf currentTime] >= strongSelf->_deadline) { [strongSelf finish]; return; }
        for (NSUInteger i = 0; i < translations.count; ++i) {
            id gloss = translations[i];
            if ([gloss isKindOfClass:NSString.class] && [gloss length])
                [strongSelf->_results addObject:@{@"text":item[@"originals"][i], @"translation":gloss}];
        }
        if (translation.length) [strongSelf->_results addObject:@{@"text":text, @"translation":translation}];
        strongSelf->_request = nil;
        [strongSelf advance];
    };
    if (_tencent) {
        NSDictionary *descriptor = [MSIMEClientSession tencentTranslationHTTPRequest:@{
            @"config":item[@"config"], @"texts":item[@"texts"],
            @"source_language":item[@"source_language"], @"target_language":item[@"target_language"],
            @"timestamp":@((long long)[self unixTime])} error:nil];
        if (!descriptor) { reply(nil); return; }
        if ([self currentTime] >= _deadline) { [self finish]; return; }
        _request = [self tencentRequestForDescriptor:descriptor completion:reply];
    } else {
        _request = [self requestForDescriptor:item[@"request"] completion:reply];
    }
    [_request start];
}
- (void)finish {
    void (^completion)(NSArray<NSDictionary *> *) = _completion;
    NSArray<NSDictionary *> *results = [_results copy];
    [self cancel];
    if (completion) completion(results);
}
- (void)cancel {
    NSAssert(NSThread.isMainThread, @"Translation batch must run on main thread");
    _completion = nil;
    [_timer invalidate];
    _timer = nil;
    [_request cancel];
    _request = nil;
    _items = nil;
    _configuration = nil;
    _results = nil;
}
- (void)dealloc {
    [_timer invalidate];
    [_request cancel];
}
@end
