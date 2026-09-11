#import "CloudDictionaryClient.h"
void MSIMEFetchCloudDictionary(NSString *kind, NSString *search, NSUInteger offset, NSString *bearerToken, MSIMECloudDictionaryCompletion completion) {
    if (kind.length == 0 || search.length > 1024 || offset > 1000000 || bearerToken.length == 0) { if (completion) completion(nil, 400, [NSError errorWithDomain:@"MSIMECloud" code:400 userInfo:nil]); return; }
    NSURLComponents *components = [NSURLComponents componentsWithString:@"https://api.msime.app/v1/users/me/dictionaries"];
    components.path = [components.path stringByAppendingPathComponent:kind];
    components.queryItems = @[[NSURLQueryItem queryItemWithName:@"q" value:search], [NSURLQueryItem queryItemWithName:@"offset" value:[NSString stringWithFormat:@"%lu", (unsigned long)offset]], [NSURLQueryItem queryItemWithName:@"limit" value:@"100"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:components.URL];
    [request setValue:[@"Bearer " stringByAppendingString:bearerToken] forHTTPHeaderField:@"Authorization"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) { NSInteger status = [(NSHTTPURLResponse *)response statusCode]; dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(data, status, error); }); }] resume];
}

void MSIMEMutateCloudDictionary(NSString *method, NSString *kind, NSString *entryID, NSData *body, NSString *bearerToken, MSIMECloudDictionaryCompletion completion) {
    if (![@[@"POST", @"PUT", @"DELETE"] containsObject:method] || kind.length == 0 || bearerToken.length == 0 || (entryID.length == 0 && ![method isEqualToString:@"POST"])) { if (completion) completion(nil, 400, [NSError errorWithDomain:@"MSIMECloud" code:400 userInfo:nil]); return; }
    NSString *path = [NSString stringWithFormat:@"https://api.msime.app/v1/users/me/dictionaries/%@%@", kind, entryID.length ? [@"/" stringByAppendingString:entryID] : @""];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:path]]; request.HTTPMethod = method; request.HTTPBody = body;
    [request setValue:[@"Bearer " stringByAppendingString:bearerToken] forHTTPHeaderField:@"Authorization"]; [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [[[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) { NSInteger status = [(NSHTTPURLResponse *)response statusCode]; dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(data, status, error); }); }] resume];
}

NSString *MSIMEReadDictionaryImportFile(NSURL *url, NSError **error) {
    if (!url || ![url isFileURL]) { if (error) *error = [NSError errorWithDomain:@"MSIMECloud" code:400 userInfo:nil]; return nil; }
    NSData *data = [NSData dataWithContentsOfURL:url options:NSDataReadingMappedIfSafe error:error];
    if (!data || data.length == 0 || data.length > 65536) { if (error && !*error) *error = [NSError errorWithDomain:@"MSIMECloud" code:400 userInfo:nil]; return nil; }
    NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (!text.length || [text rangeOfString:@"\0"].location != NSNotFound) { if (error) *error = [NSError errorWithDomain:@"MSIMECloud" code:400 userInfo:nil]; return nil; }
    return text;
}

BOOL MSIMESaveDictionaryExportFile(NSData *data, NSURL *url, NSError **error) {
    return data && url && [url isFileURL] && data.length <= 384 * 1024 * 1024 && [data writeToURL:url options:NSDataWritingAtomic error:error];
}
