#import "HandwritingDownloadSession.h"
#import <objc/runtime.h>

static NSString *MSIMEBackgroundContainer;

@interface NSURLSessionConfiguration (MSIMEHandwriting)
+ (NSURLSessionConfiguration *)msime_handwritingBackgroundWithIdentifier:(NSString *)identifier;
@end

@implementation NSURLSessionConfiguration (MSIMEHandwriting)
+ (NSURLSessionConfiguration *)msime_handwritingBackgroundWithIdentifier:(NSString *)identifier {
  // Calls the original factory after the exchange below.
  NSURLSessionConfiguration *configuration = [self msime_handwritingBackgroundWithIdentifier:identifier];
  if (configuration.sharedContainerIdentifier == nil) {
    configuration.sharedContainerIdentifier = MSIMEBackgroundContainer;
  }
  return configuration;
}
@end

@implementation HandwritingDownloadSession
+ (BOOL)configureSharedContainer:(NSString *)identifier {
  if (NSBundle.mainBundle.infoDictionary[@"NSExtension"] == nil) return YES;
  if ([NSFileManager.defaultManager containerURLForSecurityApplicationGroupIdentifier:identifier] == nil) return NO;
  static dispatch_once_t once;
  static BOOL installed;
  dispatch_once(&once, ^{
    // ML Kit's downloader has no session-configuration injection point and creates background
    // sessions even when allowsBackgroundDownloading is false. iOS rejects extension background
    // sessions without a shared container. Supply the extension's default on the public factory;
    // preserve explicitly configured containers and leave foreground sessions/host apps untouched.
    Method original = class_getClassMethod(NSURLSessionConfiguration.class,
      @selector(backgroundSessionConfigurationWithIdentifier:));
    Method replacement = class_getClassMethod(NSURLSessionConfiguration.class,
      @selector(msime_handwritingBackgroundWithIdentifier:));
    if (original != NULL && replacement != NULL) {
      MSIMEBackgroundContainer = identifier.copy;
      method_exchangeImplementations(original, replacement);
      installed = YES;
    }
  });
  return installed;
}
@end
