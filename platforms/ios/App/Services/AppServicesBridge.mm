#import "AppServicesBridge.h"
#include <msime/voice/provider_protocol.h>
#include <exception>
namespace {
void Report(NSError **error) {
    if (error) *error = [NSError errorWithDomain:@"app.msime.ios.services" code:1
        userInfo:@{NSLocalizedDescriptionKey: @"服务数据格式不正确，请检查模型和服务接口。"}];
}
std::string UTF8(NSString *text) { return text.UTF8String ? text.UTF8String : ""; }
}
@implementation AppServicesBridge
+ (NSData *)polishBody:(NSString *)model prompt:(NSString *)prompt text:(NSString *)text error:(NSError **)error {
    try {
        auto body = metasequoia::voice::make_polish_request(UTF8(model), UTF8(prompt), UTF8(text));
        return [NSData dataWithBytes:body.data() length:body.size()];
    } catch (const std::exception &) { Report(error); return nil; }
}
+ (NSDictionary<NSString *, id> *)transcriptionBody:(NSData *)wav model:(NSString *)model error:(NSError **)error {
    try {
        auto request = metasequoia::voice::make_transcription_request(
            std::string_view(static_cast<const char *>(wav.bytes), wav.length), UTF8(model));
        return @{@"body": [NSData dataWithBytes:request.body.data() length:request.body.size()],
                 @"contentType": [NSString stringWithUTF8String:request.content_type.c_str()]};
    } catch (const std::exception &) { Report(error); return nil; }
}
+ (NSString *)parseResponse:(NSData *)data voice:(BOOL)voice error:(NSError **)error {
    try {
        auto response = std::string_view(static_cast<const char *>(data.bytes), data.length);
        auto text = voice ? metasequoia::voice::parse_transcription(response)
                          : metasequoia::voice::parse_polished_text(response);
        return [[NSString alloc] initWithBytes:text.data() length:text.size() encoding:NSUTF8StringEncoding];
    } catch (const std::exception &) { Report(error); return nil; }
}
@end
