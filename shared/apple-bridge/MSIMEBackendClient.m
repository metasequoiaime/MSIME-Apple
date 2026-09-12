#import "MSIMEBackendClient.h"
#import <Security/Security.h>
#import <TargetConditionals.h>

static NSUserDefaults *BackendDefaults(void) {
#if TARGET_OS_IPHONE
    return [[NSUserDefaults alloc] initWithSuiteName:@"group.app.msime.ios"];
#else
    return NSUserDefaults.standardUserDefaults;
#endif
}
static NSMutableDictionary *CredentialQuery(NSString *endpoint) {
    NSMutableDictionary *query = [@{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:@"app.msime.backend", (__bridge id)kSecAttrAccount:endpoint} mutableCopy];
#if TARGET_OS_IPHONE
    NSString *group = [NSBundle.mainBundle objectForInfoDictionaryKey:@"MSIMEKeychainAccessGroup"];
    if (group.length) query[(__bridge id)kSecAttrAccessGroup] = group;
#endif
    return query;
}
static NSString *ReadToken(NSString *endpoint) {
    NSMutableDictionary *query = CredentialQuery(endpoint);
    query[(__bridge id)kSecReturnData] = @YES;
    query[(__bridge id)kSecMatchLimit] = (__bridge id)kSecMatchLimitOne;
    CFTypeRef result = NULL;
    if (SecItemCopyMatching((__bridge CFDictionaryRef)query, &result) != errSecSuccess) return @"";
    NSString *value = [[NSString alloc] initWithData:CFBridgingRelease(result) encoding:NSUTF8StringEncoding];
    return value ? value : @"";
}
@implementation MSIMEBackendClient {
    NSString *_baseURL;
    NSString *_token;
    BOOL _enabled;
    NSUInteger _generation;
    NSURLSession *_session;
    NSMutableData *_data;
    void (^_completion)(NSString *);
}
+ (NSString *)baseURL { NSString *value = [BackendDefaults() stringForKey:@"backendBaseURL"]; return value ? value : @""; }
+ (BOOL)isEnabled { return [BackendDefaults() boolForKey:@"backendEnabled"]; }
+ (BOOL)isValidBaseURL:(NSString *)baseURL {
    NSURLComponents *url = [NSURLComponents componentsWithString:baseURL];
    return baseURL.length <= 2048 && [url.scheme isEqual:@"https"] && url.host.length > 0 &&
        !url.user && !url.password && !url.query && !url.fragment &&
        [baseURL rangeOfCharacterFromSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].location == NSNotFound;
}
+ (BOOL)saveBaseURL:(NSString *)baseURL token:(NSString *)token enabled:(BOOL)enabled {
    if (baseURL.length && ![self isValidBaseURL:baseURL]) return NO;
    if (enabled && !baseURL.length) return NO;
    if (token.length > 4096 || [token rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    if (token.length) {
        NSMutableDictionary *query = CredentialQuery(baseURL);
        NSData *data = [token dataUsingEncoding:NSUTF8StringEncoding];
        OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                        (__bridge CFDictionaryRef)@{(__bridge id)kSecValueData:data});
        if (status == errSecItemNotFound) {
            query[(__bridge id)kSecValueData] = data;
            query[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;
            status = SecItemAdd((__bridge CFDictionaryRef)query, NULL);
        }
        if (status != errSecSuccess) return NO;
    }
    // Credentials are scoped by destination. Blank never copies an old endpoint's credential.
    if (enabled && !ReadToken(baseURL).length) return NO;
    NSUserDefaults *defaults = BackendDefaults();
    [defaults setObject:baseURL forKey:@"backendBaseURL"];
    [defaults setBool:enabled forKey:@"backendEnabled"];
    return YES;
}
- (instancetype)init {
    if ((self = [super init])) [self reloadConfiguration];
    return self;
}
- (void)reloadConfiguration {
    [self cancel];
    _baseURL = [MSIMEBackendClient baseURL];
    _enabled = [MSIMEBackendClient isEnabled] && [MSIMEBackendClient isValidBaseURL:_baseURL];
    _token = _enabled ? ReadToken(_baseURL) : @"";
}
- (void)cancel {
    ++_generation;
    [_session invalidateAndCancel];
    _session = nil; _data = nil; _completion = nil;
}
- (NSURLSessionConfiguration *)sessionConfiguration { return NSURLSessionConfiguration.ephemeralSessionConfiguration; }
- (void)cloudCandidateForText:(NSString *)text japanese:(BOOL)japanese completion:(void (^)(NSString *))completion {
    [self cancel];
    if (!_enabled || !_token.length || !text.length || [text lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 256) return;
    NSUInteger generation = _generation;
    MSIMEBackendClient *weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 500 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        MSIMEBackendClient *self = weakSelf;
        if (!self || self->_generation != generation) return;
        NSString *base = self->_baseURL;
        while ([base hasSuffix:@"/"]) base = [base substringToIndex:base.length - 1];
        NSURLComponents *url = [NSURLComponents componentsWithString:[base stringByAppendingString:@"/v1/cloud/candidates"]];
        url.queryItems = @[[NSURLQueryItem queryItemWithName:@"text" value:text],
                           [NSURLQueryItem queryItemWithName:@"scheme" value:japanese ? @"japanese" : @"pinyin"],
                           [NSURLQueryItem queryItemWithName:@"limit" value:@"1"]];
        NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url.URL];
        [request setValue:[@"Bearer " stringByAppendingString:self->_token] forHTTPHeaderField:@"Authorization"];
        NSURLSessionConfiguration *config = [self sessionConfiguration];
        config.timeoutIntervalForRequest = 3; config.timeoutIntervalForResource = 5;
        config.URLCache = nil; config.HTTPCookieStorage = nil;
        self->_completion = [completion copy]; self->_data = [NSMutableData data];
        self->_session = [NSURLSession sessionWithConfiguration:config delegate:self delegateQueue:NSOperationQueue.mainQueue];
        [[self->_session dataTaskWithRequest:request] resume];
    });
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task
 willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request
 completionHandler:(void (^)(NSURLRequest *))completionHandler {
    (void)session; (void)task; (void)response; (void)request;
    completionHandler(nil);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveResponse:(NSURLResponse *)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    (void)task;
    BOOL valid = session == _session && [response isKindOfClass:NSHTTPURLResponse.class] &&
        ((NSHTTPURLResponse *)response).statusCode == 200 && response.expectedContentLength <= 256 * 1024;
    completionHandler(valid ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}
- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)task didReceiveData:(NSData *)data {
    if (session != _session) return;
    if (_data.length + data.length > 256 * 1024) { [task cancel]; return; }
    [_data appendData:data];
}
- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error {
    (void)task;
    if (session != _session) return;
    NSString *candidate = nil;
    if (!error) {
        id root = [NSJSONSerialization JSONObjectWithData:_data options:0 error:NULL];
        id values = [root isKindOfClass:NSDictionary.class] ? root[@"candidates"] : nil;
        id first = [values isKindOfClass:NSArray.class] && [values count] ? values[0] : nil;
        if ([first isKindOfClass:NSString.class] && [first lengthOfBytesUsingEncoding:NSUTF8StringEncoding] <= 512 &&
            [first rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location == NSNotFound) {
            candidate = [first stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            if (!candidate.length) candidate = nil;
        }
    }
    void (^callback)(NSString *) = _completion;
    [self cancel];
    if (callback) callback(candidate);
}
@end
