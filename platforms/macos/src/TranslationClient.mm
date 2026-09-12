#import "TranslationClient.h"
#import <CommonCrypto/CommonCrypto.h>

static NSData *MsimeHmac(NSData *key, NSData *message)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256, key.bytes, key.length, message.bytes, message.length, digest);
    return [NSData dataWithBytes:digest length:sizeof(digest)];
}
static NSString *MsimeHex(NSData *data)
{
    const unsigned char *bytes = (const unsigned char *)data.bytes;
    NSMutableString *result = [NSMutableString string];
    for (NSUInteger i = 0; i < data.length; ++i)
        [result appendFormat:@"%02x", bytes[i]];
    return result;
}
static NSString *MsimeShaHex(NSData *data)
{
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    return MsimeHex([NSData dataWithBytes:digest length:sizeof(digest)]);
}
@implementation MetasequoiaDeepLXClient
- (NSURLSessionDataTask *)translateText:(NSString *)text
                         targetLanguage:(NSString *)targetLanguage
                               endpoint:(NSString *)endpoint
                             completion:(MetasequoiaTranslationCompletion)completion
{
    NSString *safeEndpoint = endpoint ? endpoint : @"";
    NSURL *base = [NSURL URLWithString:safeEndpoint];
    if (!base || !base.scheme.length || !base.host.length || !text.length)
    {
        if (completion)
            completion(nil, [NSError errorWithDomain:@"MetasequoiaTranslation" code:1 userInfo:nil]);
        return nil;
    }
    NSURL *url = [base.path hasSuffix:@"/translate"] ? base : [base URLByAppendingPathComponent:@"translate"];
    NSMutableURLRequest *r = [NSMutableURLRequest requestWithURL:url];
    r.HTTPMethod = @"POST";
    [r setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    r.HTTPBody =
        [NSJSONSerialization dataWithJSONObject:@{@"text" : @[ text ], @"target_lang" : targetLanguage.uppercaseString}
                                        options:0
                                          error:nil];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:r
          completionHandler:^(NSData *d, NSURLResponse *resp, NSError *e) {
            (void)resp;
            if (e)
            {
                if (completion)
                    completion(nil, e);
                return;
            }
            NSDictionary *j = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            NSString *out = [j[@"text"] isKindOfClass:NSString.class] ? j[@"text"] : nil;
            NSArray *translations = [j[@"translations"] isKindOfClass:NSArray.class] ? j[@"translations"] : nil;
            NSDictionary *first =
                translations.count && [translations[0] isKindOfClass:NSDictionary.class] ? translations[0] : nil;
            if (!out)
                out = [first[@"text"] isKindOfClass:NSString.class] ? first[@"text"] : nil;
            if (completion)
                completion(out, out ? nil : [NSError errorWithDomain:@"MetasequoiaTranslation" code:3 userInfo:nil]);
          }];
    [task resume];
    return task;
}
@end

@implementation MetasequoiaTencentTmtClient
- (NSURLSessionDataTask *)translateText:(NSString *)text
                         targetLanguage:(NSString *)targetLanguage
                                 region:(NSString *)region
                               secretId:(NSString *)secretId
                              secretKey:(NSString *)secretKey
                             completion:(MetasequoiaTranslationCompletion)completion
{
    if (!text.length || !targetLanguage.length || !secretId.length || !secretKey.length)
    {
        if (completion)
            completion(nil, [NSError errorWithDomain:@"MetasequoiaTranslation" code:10 userInfo:nil]);
        return nil;
    }
    NSString *host = @"tmt.tencentcloudapi.com", *service = @"tmt", *action = @"TextTranslateBatch",
             *timestamp = [NSString stringWithFormat:@"%lld", (long long)[NSDate date].timeIntervalSince1970];
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    formatter.dateFormat = @"yyyy-MM-dd";
    NSString *date = [formatter stringFromDate:[NSDate date]];
    NSDictionary *body = @{
        @"Source" : @"auto",
        @"Target" : targetLanguage.lowercaseString,
        @"ProjectId" : @0,
        @"SourceTextList" : @[ text ]
    };
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
    NSString *canonical = [NSString
        stringWithFormat:@"POST\n/\n\ncontent-type:application/json; "
                         @"charset=utf-8\nhost:%@\nx-tc-action:texttranslatebatch\n\ncontent-type;host;x-tc-action\n%@",
                         host, MsimeShaHex(payloadData)];
    NSString *scope = [NSString stringWithFormat:@"%@/%@/tc3_request", date, service];
    NSString *toSign = [NSString stringWithFormat:@"TC3-HMAC-SHA256\n%@\n%@\n%@", timestamp, scope,
                                                  MsimeShaHex([canonical dataUsingEncoding:NSUTF8StringEncoding])];
    NSData *kDate = MsimeHmac([[NSString stringWithFormat:@"TC3%@", secretKey] dataUsingEncoding:NSUTF8StringEncoding],
                              [date dataUsingEncoding:NSUTF8StringEncoding]);
    NSData *kService = MsimeHmac(kDate, [service dataUsingEncoding:NSUTF8StringEncoding]);
    NSData *kSigning = MsimeHmac(kService, [@"tc3_request" dataUsingEncoding:NSUTF8StringEncoding]);
    NSString *authorization = [NSString
        stringWithFormat:@"TC3-HMAC-SHA256 Credential=%@/%@, SignedHeaders=content-type;host;x-tc-action, Signature=%@",
                         secretId, scope,
                         MsimeHex(MsimeHmac(kSigning, [toSign dataUsingEncoding:NSUTF8StringEncoding]))];
    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://tmt.tencentcloudapi.com"]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = payloadData;
    [request setValue:host forHTTPHeaderField:@"Host"];
    [request setValue:@"application/json; charset=utf-8" forHTTPHeaderField:@"Content-Type"];
    [request setValue:action forHTTPHeaderField:@"X-TC-Action"];
    [request setValue:timestamp forHTTPHeaderField:@"X-TC-Timestamp"];
    [request setValue:@"2018-03-21" forHTTPHeaderField:@"X-TC-Version"];
    [request setValue:(region.length ? region : @"ap-guangzhou") forHTTPHeaderField:@"X-TC-Region"];
    [request setValue:authorization forHTTPHeaderField:@"Authorization"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession]
        dataTaskWithRequest:request
          completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            (void)response;
            if (error)
            {
                if (completion)
                    completion(nil, error);
                return;
            }
            NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
            NSString *out = json[@"Response"][@"TargetTextList"][0];
            if (completion)
                completion([out isKindOfClass:NSString.class] ? out : nil,
                           out ? nil : [NSError errorWithDomain:@"MetasequoiaTranslation" code:11 userInfo:nil]);
          }];
    [task resume];
    return task;
}
@end
