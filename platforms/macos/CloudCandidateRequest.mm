#import "CloudCandidateRequest.h"

static const NSUInteger MaximumBodyBytes = 262144;

@implementation MSIMECloudCandidateRequest {
    NSURL *_url;
    NSURLSessionConfiguration *_configuration;
    NSURLSession *_session;
    NSMutableData *_body;
    void (^_completion)(NSData *);
    BOOL _started;
    BOOL _accepted;
}
- (instancetype)initWithURL:(NSURL *)url configuration:(NSURLSessionConfiguration *)configuration
                 completion:(void (^)(NSData *))completion {
    if ((self = [super init])) {
        _url = [url copy];
        _configuration = [configuration copy];
        _completion = [completion copy];
    }
    return self;
}
- (void)start {
    NSAssert(NSThread.isMainThread, @"Cloud transport must run on main thread");
    if (_started || !_completion) return;
    _started = YES;
    if (![_url.scheme isEqual:@"https"] || ![_url.host isEqual:@"inputtools.google.com"] ||
        _url.user || _url.password || (_url.port && _url.port.integerValue != 443)) {
        [self finish:nil]; return;
    }
    _configuration.URLCache = nil;
    _configuration.HTTPCookieStorage = nil;
    _configuration.URLCredentialStorage = nil;
    _configuration.HTTPShouldSetCookies = NO;
    _configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    _configuration.timeoutIntervalForRequest = 2;
    _configuration.timeoutIntervalForResource = 2;
    _body = [NSMutableData data];
    _session = [NSURLSession sessionWithConfiguration:_configuration delegate:self delegateQueue:NSOperationQueue.mainQueue];
    [[_session dataTaskWithURL:_url] resume];
}
- (void)cancel {
    _completion = nil;
    [_session invalidateAndCancel];
    _session = nil;
    _body = nil;
}
- (void)finish:(NSData *)body {
    void (^completion)(NSData *) = _completion;
    [self cancel];
    if (completion) completion(body);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task
 didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    (void)session; (void)task;
    _accepted = _completion && [response isKindOfClass:NSHTTPURLResponse.class] &&
        [(NSHTTPURLResponse *)response statusCode] == 200 && response.expectedContentLength <= (int64_t)MaximumBodyBytes;
    completionHandler(_accepted ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
    if (!_accepted) [self finish:nil];
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    (void)session; (void)task;
    if (!_completion || !_accepted) return;
    if (data.length > MaximumBodyBytes - _body.length) { [self finish:nil]; return; }
    [_body appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)session; (void)task;
    [self finish:!error && _accepted && _body.length ? [_body copy] : nil];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    completionHandler(nil);
    [self finish:nil];
}
@end
