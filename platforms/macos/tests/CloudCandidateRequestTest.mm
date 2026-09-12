#import "../CloudCandidateRequest.h"
#include <cassert>

static NSInteger ResponseStatus = 200;
static NSUInteger ResponseBytes = 8;
static BOOL FailWithTimeout = NO;
@interface SyntheticCloudProtocol : NSURLProtocol
@end
@implementation SyntheticCloudProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { (void)request; return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    if (FailWithTimeout) {
        [self.client URLProtocol:self didFailWithError:[NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorTimedOut userInfo:nil]];
        return;
    }
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:ResponseStatus HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[NSMutableData dataWithLength:ResponseBytes / 2]];
    [self.client URLProtocol:self didLoadData:[NSMutableData dataWithLength:ResponseBytes - ResponseBytes / 2]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

static void Wait(BOOL (^done)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!done() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
    assert(done());
}

int main() {
    @autoreleasepool {
        for (NSNumber *bytes in @[@8, @262144, @262145]) {
            for (NSNumber *status in @[@200, @503]) {
                ResponseBytes = bytes.unsignedIntegerValue;
                ResponseStatus = status.integerValue;
                __block BOOL done = NO;
                __block NSUInteger calls = 0;
                NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
                configuration.protocolClasses = @[SyntheticCloudProtocol.class];
                MSIMECloudCandidateRequest *request = [[MSIMECloudCandidateRequest alloc] initWithURL:[NSURL URLWithString:@"https://inputtools.google.com/synthetic"] configuration:configuration completion:^(NSData *body) {
                    assert(NSThread.isMainThread);
                    ++calls;
                    assert((body != nil) == (ResponseStatus == 200 && ResponseBytes <= 262144));
                    if (body) assert(body.length == ResponseBytes);
                    done = YES;
                }];
                [request start];
                NSURLSessionConfiguration *effective = [(NSURLSession *)[request valueForKey:@"session"] configuration];
                assert(!effective.URLCache && !effective.HTTPCookieStorage && !effective.URLCredentialStorage);
                assert(!effective.HTTPShouldSetCookies && effective.timeoutIntervalForResource == 2 && effective.timeoutIntervalForRequest == 2);
                Wait(^BOOL { return done; });
                assert(calls == 1);
                [request cancel];
            }
        }
        __block NSUInteger calls = 0;
        FailWithTimeout = YES;
        NSURLSessionConfiguration *timeoutConfiguration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        timeoutConfiguration.protocolClasses = @[SyntheticCloudProtocol.class];
        __block BOOL timedOut = NO;
        MSIMECloudCandidateRequest *timeout = [[MSIMECloudCandidateRequest alloc] initWithURL:[NSURL URLWithString:@"https://inputtools.google.com/synthetic"] configuration:timeoutConfiguration completion:^(NSData *body) { assert(!body); timedOut = YES; }];
        [timeout start];
        Wait(^BOOL { return timedOut; });
        FailWithTimeout = NO;
        MSIMECloudCandidateRequest *cancelled = [[MSIMECloudCandidateRequest alloc] initWithURL:[NSURL URLWithString:@"https://inputtools.google.com/synthetic"] configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:^(NSData *body) { (void)body; ++calls; }];
        [cancelled cancel];
        [cancelled start];
        NSURL *syntheticURL = [NSURL URLWithString:@"https://invalid.example/"];
        NSURLSession *unusedSession = [NSURLSession sessionWithConfiguration:NSURLSessionConfiguration.ephemeralSessionConfiguration];
        NSURLSessionDataTask *unusedTask = [unusedSession dataTaskWithURL:syntheticURL]; // Never resumed.
        [cancelled URLSession:unusedSession task:unusedTask didCompleteWithError:nil];
        assert(calls == 0);
        for (NSString *url in @[@"http://inputtools.google.com/", @"https://invalid.example/", @"https://user@inputtools.google.com/"]) {
            MSIMECloudCandidateRequest *invalid = [[MSIMECloudCandidateRequest alloc] initWithURL:[NSURL URLWithString:url] configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:^(NSData *body) { assert(!body); ++calls; }];
            [invalid start];
        }
        assert(calls == 3);
        MSIMECloudCandidateRequest *redirect = [[MSIMECloudCandidateRequest alloc] initWithURL:nil configuration:NSURLSessionConfiguration.ephemeralSessionConfiguration completion:^(NSData *body) { assert(!body); ++calls; }];
        NSHTTPURLResponse *redirectResponse = [[NSHTTPURLResponse alloc] initWithURL:syntheticURL statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
        [redirect URLSession:unusedSession task:unusedTask willPerformHTTPRedirection:redirectResponse newRequest:[NSURLRequest requestWithURL:syntheticURL] completionHandler:^(NSURLRequest *next) { assert(!next); }];
        assert(calls == 4);
        [unusedSession invalidateAndCancel];
    }
}
