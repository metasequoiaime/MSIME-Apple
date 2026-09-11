#import "DictionaryInstaller.h"
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>
static NSString *const MSIMEInstallerError = @"app.msime.client.dictionary-installer";
static BOOL Fail(NSError **e, NSString *s) { if (e) *e=[NSError errorWithDomain:MSIMEInstallerError code:1 userInfo:@{NSLocalizedDescriptionKey:s}]; return NO; }
BOOL MSIMEInstallDictionary(NSURL *source, NSURL *directory, NSString *expected, NSError **error) {
    if (!source.isFileURL || !directory.isFileURL || expected.length != CC_SHA256_DIGEST_LENGTH * 2) return Fail(error,@"词典参数无效");
    NSData *data=[NSData dataWithContentsOfURL:source options:0 error:error]; if (!data) return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(data.bytes,(CC_LONG)data.length,digest); NSMutableString *actual=[NSMutableString string]; for (NSUInteger i=0;i<sizeof(digest);i++) [actual appendFormat:@"%02x",digest[i]]; if (![actual isEqualToString:expected.lowercaseString]) return Fail(error,@"词典指纹不匹配");
    sqlite3 *db=NULL; if (sqlite3_open_v2(source.fileSystemRepresentation,&db,SQLITE_OPEN_READONLY,NULL)!=SQLITE_OK) { sqlite3_close(db); return Fail(error,@"词典无法打开"); } sqlite3_stmt *stmt=NULL; BOOL valid=sqlite3_prepare_v2(db,"PRAGMA quick_check(1)",-1,&stmt,NULL)==SQLITE_OK && sqlite3_step(stmt)==SQLITE_ROW && strcmp((const char *)sqlite3_column_text(stmt,0),"ok")==0; sqlite3_finalize(stmt); sqlite3_close(db); if (!valid) return Fail(error,@"词典完整性校验失败");
    NSFileManager *fm=NSFileManager.defaultManager; if (![fm createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:error]) return NO; NSURL *temp=[directory URLByAppendingPathComponent:@".msime.db.installing"]; [fm removeItemAtURL:temp error:nil]; if (![data writeToURL:temp options:NSDataWritingAtomic error:error]) return NO; NSURL *target=[directory URLByAppendingPathComponent:@"msime.db"]; [fm removeItemAtURL:target error:nil]; return [fm moveItemAtURL:temp toURL:target error:error];
}
