#import "ClientDictionaryRuntime.h"
#import "MSIMEClientSession.h"

static NSString *const MSIMEDictionaryRuntimeError = @"app.msime.client.dictionary-runtime";
static NSURL *AbsoluteDirectory(NSDictionary *options, NSString *key, NSError **error) {
    id value = options[key];
    if (![value isKindOfClass:NSString.class] || ![value isAbsolutePath]) {
        if (error) *error = [NSError errorWithDomain:MSIMEDictionaryRuntimeError code:1 userInfo:@{NSLocalizedDescriptionKey: @"词典运行目录配置无效"}];
        return nil;
    }
    return [NSURL fileURLWithPath:value isDirectory:YES];
}
@implementation MSIMEDictionaryRuntime {
    NSURL *_resourcesDirectory; NSURL *_userDataDirectory; NSURL *_cacheDirectory; NSURL *_dictionariesDirectory;
}
+ (void)prepareResourcesDirectory:(NSString *)resourcesDirectory stateRoot:(NSString *)stateRoot completion:(MSIMEDictionaryPrepareCompletion)completion {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        NSError *error = nil;
        NSDictionary *options = [MSIMEClientSession prepareHostWithResourcesDirectory:resourcesDirectory stateRoot:stateRoot error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(options, error); });
    });
}
- (instancetype)initWithHostOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error {
    self = [super init]; if (!self) return nil;
    _resourcesDirectory = AbsoluteDirectory(options, @"resources", error); if (!_resourcesDirectory) return nil;
    _userDataDirectory = AbsoluteDirectory(options, @"user_data", error); if (!_userDataDirectory) return nil;
    _cacheDirectory = AbsoluteDirectory(options, @"cache", error); if (!_cacheDirectory) return nil;
    _dictionariesDirectory = AbsoluteDirectory(options, @"dictionaries", error); if (!_dictionariesDirectory) return nil;
    return self;
}
- (NSURL *)resourcesDirectory { return _resourcesDirectory; }
- (NSURL *)userDataDirectory { return _userDataDirectory; }
- (NSURL *)cacheDirectory { return _cacheDirectory; }
- (NSURL *)dictionariesDirectory { return _dictionariesDirectory; }
@end
