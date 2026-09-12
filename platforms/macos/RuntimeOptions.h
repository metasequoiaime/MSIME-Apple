#import <Foundation/Foundation.h>

static inline NSDictionary *MSIMELoadRuntimeOptions(void) {
    NSString *path = [NSBundle.mainBundle pathForResource:@"runtime-options" ofType:@"json"];
    if (!path) {
        NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory inDomains:NSUserDomainMask] firstObject];
        path = [[support URLByAppendingPathComponent:@"app.msime.client.preview/runtime-options.json"] path];
    }
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    id options = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [options isKindOfClass:NSDictionary.class] ? options : nil;
}
