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
- (NSTimeInterval)currentTime { return NSProcessInfo.processInfo.systemUptime; }
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
    _request = [self requestForDescriptor:item[@"request"] completion:^(NSData *body) {
        MSIMECustomTranslationBatch *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_completion || sequence != strongSelf->_nextIndex) return;
        // The main queue may be busy when the deadline timer becomes due.
        if ([strongSelf currentTime] >= strongSelf->_deadline) { [strongSelf finish]; return; }
        NSString *translation = body ? [MSIMEClientSession parseCustomTranslationResponse:body error:nil] : nil;
        if ([strongSelf currentTime] >= strongSelf->_deadline) { [strongSelf finish]; return; }
        if (translation.length) [strongSelf->_results addObject:@{@"text":text, @"translation":translation}];
        strongSelf->_request = nil;
        [strongSelf advance];
    }];
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
