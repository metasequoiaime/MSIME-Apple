#import "CloudFileTransfer.h"
BOOL MSIMESafelyReplaceLocalFile(NSURL *source, NSURL *destination, NSError **error) {
    if (!source.isFileURL || !destination.isFileURL) { if(error)*error=[NSError errorWithDomain:@"MSIMEFileTransfer" code:400 userInfo:nil]; return NO; }
    BOOL scoped=[destination startAccessingSecurityScopedResource]; NSURL *temporary=[destination.URLByDeletingLastPathComponent URLByAppendingPathComponent:[@"." stringByAppendingString:NSUUID.UUID.UUIDString]];
    NSError *e=nil; BOOL ok=[[NSFileManager defaultManager] copyItemAtURL:source toURL:temporary error:&e];
    if(ok) { if([[NSFileManager defaultManager] fileExistsAtPath:destination.path]) ok=[[NSFileManager defaultManager] replaceItemAtURL:destination withItemAtURL:temporary backupItemName:nil options:0 resultingItemURL:nil error:&e]; else ok=[[NSFileManager defaultManager] moveItemAtURL:temporary toURL:destination error:&e]; }
    [[NSFileManager defaultManager] removeItemAtURL:temporary error:nil]; if(scoped)[destination stopAccessingSecurityScopedResource]; if(!ok&&error)*error=e; return ok;
}
