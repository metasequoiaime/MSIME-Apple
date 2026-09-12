#import "../apple-bridge/MSIMEBackendClient.h"
#include <stdlib.h>
static void Require(BOOL condition) { if (!condition) abort(); }
static NSString *reply;
static NSUInteger calls;
@interface BackendProtocol : NSURLProtocol @end
@implementation BackendProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { return [request.URL.host isEqual:@"backend.example"]; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    ++calls;
    Require([[self.request valueForHTTPHeaderField:@"Authorization"] isEqual:@"Bearer synthetic-token"]);
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:[reply dataUsingEncoding:NSUTF8StringEncoding]];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
@interface TestBackend : MSIMEBackendClient @end
@implementation TestBackend
- (void)reloadConfiguration {
    [self cancel];
    [self setValue:@"https://backend.example" forKey:@"baseURL"];
    [self setValue:@"synthetic-token" forKey:@"token"];
    [self setValue:@YES forKey:@"enabled"];
}
- (NSURLSessionConfiguration *)sessionConfiguration {
    NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
    configuration.protocolClasses = @[BackendProtocol.class];
    return configuration;
}
@end
static void Pump(NSTimeInterval seconds) {
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:seconds];
    while (end.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
}
int main(void) { @autoreleasepool {
    Require([MSIMEBackendClient isValidBaseURL:@"https://backend.example/prefix"]);
    for (NSString *url in @[@"http://backend.example", @"https://user:token@backend.example", @"https://backend.example?query", @"https://backend.example/#fragment"])
        Require(![MSIMEBackendClient isValidBaseURL:url]);
    TestBackend *client = [TestBackend new];
    reply = @"{\"candidates\":[\"你好\"]}";
    __block BOOL completed = NO;
    [client cloudCandidateForText:@"ni hao" japanese:NO completion:^(NSString *candidate) {
        Require(NSThread.isMainThread); Require([candidate isEqual:@"你好"]); completed = YES;
    }];
    Pump(0.8); Require(completed && calls == 1);
    [client cloudCandidateForText:@"cancel" japanese:NO completion:^(NSString *candidate) {
        (void)candidate; Require(0 && "cancelled request completed");
    }];
    [client cancel]; Pump(0.6); Require(calls == 1);
    reply = @"{\"candidates\":[\"bad\\ntext\"]}"; completed = NO;
    [client cloudCandidateForText:@"test" japanese:NO completion:^(NSString *candidate) {
        Require(candidate == nil); completed = YES;
    }];
    Pump(0.8); Require(completed && calls == 2);
    [client cancel];
} return 0; }
