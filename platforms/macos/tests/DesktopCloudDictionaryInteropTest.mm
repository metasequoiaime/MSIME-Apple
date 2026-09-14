#import "../DesktopCloudClipboard.h"
#include <cassert>

@interface SyntheticDictionaryProvider : NSObject <MSIMEDesktopCloudClipboardProvider>
@property(nonatomic) unsigned calls;
@property(nonatomic, strong) NSURL *exportDirectory;
@end
@implementation SyntheticDictionaryProvider
- (NSProgress *)request:(NSDictionary *)request completion:(void (^)(NSDictionary *))completion {
    assert(NSThread.isMainThread);
    ++self.calls;
    NSString *operation = request[@"operation"];
    if ([operation isEqual:@"update"]) { completion(@{@"ok":@NO,@"error":@"conflict"}); return [NSProgress progressWithTotalUnitCount:1]; }
    NSDictionary *result;
    if ([operation isEqual:@"import"]) {
        assert([request[@"text"] length] == 65536);
        result = @{@"imported":@1};
    } else if ([operation isEqual:@"export"]) {
        self.exportDirectory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[@"msime-export-" stringByAppendingString:NSUUID.UUID.UUIDString]]];
        assert([NSFileManager.defaultManager createDirectoryAtURL:self.exportDirectory withIntermediateDirectories:NO attributes:@{NSFilePosixPermissions:@0700} error:nil]);
        NSMutableString *text = [NSMutableString new];
        for (int i = 0; i < 150000; ++i) [text appendString:@"synthetic\t合成\t100\n"];
        NSData *bytes = [text dataUsingEncoding:NSUTF8StringEncoding];
        NSURL *file = [self.exportDirectory URLByAppendingPathComponent:@"dictionary-pinyin.tsv"];
        assert([NSFileManager.defaultManager createFileAtPath:file.path contents:bytes attributes:@{NSFilePosixPermissions:@0600}]);
        result = @{@"export_file":@{@"path":file.path,@"bytes":@(bytes.length)}};
    } else result = @{@"offset":request[@"offset"]};
    completion(@{@"ok":@YES,@"value":result});
    return [NSProgress progressWithTotalUnitCount:1];
}
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        SyntheticDictionaryProvider *provider = [SyntheticDictionaryProvider new];
        MSIMEDesktopCloudClipboardSession *session = [[MSIMEDesktopCloudClipboardSession alloc] initWithProvider:provider dictionary:YES];
        assert(session && session.launchEnvironment[@"MSIME_CLIENT_CLOUD_DICTIONARY_SESSION"]);
        NSTask *probe = [NSTask new];
        probe.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        probe.environment = session.launchEnvironment;
        NSPipe *gate = [NSPipe pipe]; probe.standardInput = gate;
        assert([probe launchAndReturnError:nil]);
        [session authorizePID:probe.processIdentifier stillValid:^BOOL { return probe.running; }];
        const char ready = 1;
        [gate.fileHandleForWriting writeData:[NSData dataWithBytes:&ready length:1]];
        [gate.fileHandleForWriting closeFile];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:15];
        while (probe.running && deadline.timeIntervalSinceNow > 0)
            [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
        assert(!probe.running && probe.terminationStatus == 0 && provider.calls == 4);
        [session stop];
        assert([NSFileManager.defaultManager removeItemAtURL:provider.exportDirectory error:nil]);
    }
}
