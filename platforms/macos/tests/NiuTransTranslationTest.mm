#import "../src/CustomTranslationBatch.h"
#import "../src/CloudCandidateRequest.h"
#import "MSIMEClientSession.h"
#include <cassert>

static NSData *Response(NSString *text) {
    return [NSJSONSerialization dataWithJSONObject:@{@"tgtText":text} options:0 error:nil];
}
static NSData *ExpectedPayload;
static NSUInteger TransportCalls;
@interface NiuTransProtocol : NSURLProtocol
@end
@implementation NiuTransProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request { (void)request; return YES; }
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request { return request; }
- (void)startLoading {
    ++TransportCalls;
    assert([self.request.URL.absoluteString isEqual:@"https://api.niutrans.com/v2/text/translate"]);
    assert([self.request.HTTPMethod isEqual:@"POST"] && !self.request.HTTPShouldHandleCookies);
    assert([[self.request valueForHTTPHeaderField:@"Content-Type"] isEqual:@"application/x-www-form-urlencoded; charset=utf-8"]);
    NSData *body = self.request.HTTPBody;
    if (!body) {
        NSInputStream *stream = self.request.HTTPBodyStream; assert(stream);
        NSMutableData *bytes = [NSMutableData data]; [stream open];
        uint8_t buffer[1024]; NSInteger count;
        while ((count = [stream read:buffer maxLength:sizeof(buffer)]) > 0) [bytes appendBytes:buffer length:(NSUInteger)count];
        [stream close]; assert(count == 0); body = bytes;
    }
    assert([body isEqual:ExpectedPayload]);
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:self.request.URL statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:Response(@"synthetic gloss")];
    [self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end

@interface NiuTransFakeRequest : MSIMECloudCandidateRequest
@property(copy) void (^reply)(NSData *);
@property BOOL cancelled;
@end
@implementation NiuTransFakeRequest
- (void)start {}
- (void)cancel { self.cancelled = YES; }
@end
@interface NiuTransFakeBatch : MSIMECustomTranslationBatch
@property NSTimeInterval now;
@property NSTimeInterval wall;
@property NSMutableArray<NiuTransFakeRequest *> *requests;
@property NSMutableArray<NSDictionary *> *descriptors;
@end
@implementation NiuTransFakeBatch
- (NSTimeInterval)currentTime { return self.now; }
- (NSTimeInterval)unixTime { return self.wall; }
- (MSIMECloudCandidateRequest *)niuTransRequestForDescriptor:(NSDictionary *)descriptor completion:(void (^)(NSData *))completion {
    if (!self.requests) { self.requests = [NSMutableArray array]; self.descriptors = [NSMutableArray array]; }
    NiuTransFakeRequest *request = [NiuTransFakeRequest new]; request.reply = completion;
    [self.requests addObject:request]; [self.descriptors addObject:descriptor]; return request;
}
@end

int main() {
    @autoreleasepool {
        NSMutableDictionary *config = [@{@"enabled":@YES, @"app_id":@"app-id", @"apikey":@"api-key"} mutableCopy];
        NSDictionary *input = @{@"config":config, @"text":@"hello", @"source_language":@"en", @"target_language":@"zh", @"timestamp":@"1704067200000"};
        NSDictionary *descriptor = [MSIMEClientSession niuTransTranslationHTTPRequest:input error:nil];
        assert([descriptor[@"body_utf8"] containsString:@"authStr=6da3515e010ef871b66e4e31ff5ba580"]);
        assert(![descriptor[@"body_utf8"] containsString:@"api-key"]);
        assert([[MSIMEClientSession parseNiuTransTranslationResponse:Response(@" hello\nworld ") error:nil] isEqual:@"hello world"]);
        assert(![MSIMEClientSession parseNiuTransTranslationResponse:[@"{\"errorCode\":\"401\",\"tgtText\":\"invalid\"}" dataUsingEncoding:NSUTF8StringEncoding] error:nil]);
        assert(![MSIMEClientSession parseNiuTransTranslationResponse:[NSMutableData dataWithLength:1048577] error:nil]);
        ExpectedPayload = [descriptor[@"body_utf8"] dataUsingEncoding:NSUTF8StringEncoding];
        NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        configuration.protocolClasses = @[NiuTransProtocol.class];
        __block BOOL done = NO;
        MSIMECloudCandidateRequest *transport = [[MSIMECloudCandidateRequest alloc] initWithNiuTransDescriptor:descriptor configuration:configuration completion:^(NSData *body) {
            assert([body isEqual:Response(@"synthetic gloss")]); done = YES;
        }];
        assert([(NSURLRequest *)[transport valueForKey:@"translationRequest"] timeoutInterval] == 2.5);
        [transport start];
        NSURLSessionConfiguration *effective = [(NSURLSession *)[transport valueForKey:@"session"] configuration];
        assert(!effective.URLCache && !effective.URLCredentialStorage && !effective.HTTPCookieStorage);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (!done && deadline.timeIntervalSinceNow > 0) [NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        assert(done && TransportCalls == 1 && ![transport valueForKey:@"translationRequest"]);
        __block BOOL refused = NO;
        MSIMECloudCandidateRequest *redirected = [[MSIMECloudCandidateRequest alloc] initWithNiuTransDescriptor:descriptor configuration:configuration completion:^(NSData *body) { assert(!body); refused = YES; }];
        NSURLSession *unusedSession = [NSURLSession sessionWithConfiguration:configuration];
        NSURL *original = [NSURL URLWithString:descriptor[@"url"]];
        NSURLSessionDataTask *unusedTask = [unusedSession dataTaskWithURL:original];
        NSHTTPURLResponse *redirectResponse = [[NSHTTPURLResponse alloc] initWithURL:original statusCode:302 HTTPVersion:@"HTTP/1.1" headerFields:@{}];
        [redirected URLSession:unusedSession task:unusedTask willPerformHTTPRedirection:redirectResponse newRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:@"https://untrusted.invalid/"]] completionHandler:^(NSURLRequest *next) { assert(!next); }];
        assert(refused && ![redirected valueForKey:@"translationRequest"]);
        [unusedSession invalidateAndCancel];
        for (NSDictionary *change in @[@{@"url":@"https://untrusted.invalid/"}, @{@"method":@"GET"},
            @{@"timeout_ms":@9000}, @{@"max_response_bytes":@99999999}, @{@"headers":@{@"Content-Type":@"application/json"}},
            @{@"body_utf8":@42}, @{@"body_utf8":[@"x" stringByPaddingToLength:16385 withString:@"x" startingAtIndex:0]}]) {
            NSMutableDictionary *invalid = [descriptor mutableCopy]; [invalid addEntriesFromDictionary:change];
            __block BOOL rejected = NO;
            MSIMECloudCandidateRequest *request = [[MSIMECloudCandidateRequest alloc] initWithNiuTransDescriptor:invalid configuration:configuration completion:^(NSData *body) { assert(!body); rejected = YES; }];
            [request start]; assert(rejected && TransportCalls == 1 && ![request valueForKey:@"session"]);
        }
        NSArray *items = @[@{@"text":@"HELLO", @"key":@"hello", @"source_language":@"en", @"target_language":@"zh"},
            @{@"text":@"世界", @"key":@"世界", @"source_language":@"zh", @"target_language":@"fr"}];
        __block NSUInteger calls = 0;
        NiuTransFakeBatch *batch = [[NiuTransFakeBatch alloc] initWithNiuTransItems:items config:config configuration:configuration completion:^(NSArray *results) {
            assert(++calls == 1 && results.count == 1 && [results[0][@"text"] isEqual:@"HELLO"]);
        }];
        config[@"app_id"] = @"mutated"; config[@"apikey"] = @"mutated";
        batch.wall = 1704067200; batch.now = 10; [batch start];
        assert(batch.requests.count == 1 && [batch.descriptors[0][@"body_utf8"] isEqual:descriptor[@"body_utf8"]]);
        batch.wall += 1; batch.requests[0].reply(Response(@"synthetic gloss"));
        assert(batch.requests.count == 2 && [batch.descriptors[1][@"body_utf8"] containsString:@"timestamp=1704067201000"]);
        batch.requests[0].reply(Response(@"duplicate")); assert(batch.requests.count == 2);
        batch.now = 16; [(NSTimer *)[batch valueForKey:@"timer"] fire];
        assert(calls == 1 && batch.requests[1].cancelled && ![batch valueForKey:@"items"]);
        batch.requests[1].reply(Response(@"late")); assert(calls == 1);
        NiuTransFakeBatch *cancelled = [[NiuTransFakeBatch alloc] initWithNiuTransItems:items config:config configuration:configuration completion:^(NSArray *results) { (void)results; assert(false); }];
        cancelled.wall = 1704067200; [cancelled start]; [cancelled cancel];
        assert(cancelled.requests[0].cancelled && ![cancelled valueForKey:@"items"]);
        cancelled.requests[0].reply(Response(@"late"));
        __block BOOL invalidDone = NO;
        NiuTransFakeBatch *invalid = [[NiuTransFakeBatch alloc] initWithNiuTransItems:items config:@{@"enabled":@YES, @"app_id":@"", @"apikey":@""} configuration:configuration completion:^(NSArray *results) { assert(!results.count); invalidDone = YES; }];
        [invalid start]; assert(invalidDone && !invalid.requests.count);
    }
}
