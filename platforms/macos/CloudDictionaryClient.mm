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
