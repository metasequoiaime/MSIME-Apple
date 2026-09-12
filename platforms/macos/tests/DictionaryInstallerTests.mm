#import "../src/DictionaryInstaller.h"

#import <CommonCrypto/CommonDigest.h>

#include "../../../vendor/MetasequoiaImeEngine/user_dictionary/user_dictionary_journal.h"

#include <sqlite3.h>

#include <cstdlib>
#include <stdexcept>
#include <string>

namespace
{
void Require(bool condition, const char *message)
{
    if (!condition)
    {
        throw std::runtime_error(message);
    }
}

void WriteString(NSString *value, NSURL *url)
{
    NSError *error = nil;
    Require([value writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:&error],
            error.localizedDescription.UTF8String);
}

std::string ReadString(NSURL *url)
{
    NSError *error = nil;
    NSString *value = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&error];
    Require(value != nil, error.localizedDescription.UTF8String);
    return value.UTF8String;
}

NSString *SHA256Fingerprint(NSURL *url)
{
    NSError *error = nil;
    NSData *data = [NSData dataWithContentsOfURL:url options:0 error:&error];
    Require(data != nil, error.localizedDescription.UTF8String);
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    Require(CC_SHA256(data.bytes, static_cast<CC_LONG>(data.length), digest) != nullptr,
            "Failed to hash test dictionary.");
    NSMutableString *fingerprint = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (unsigned char byte : digest)
    {
        [fingerprint appendFormat:@"%02x", byte];
    }
    return fingerprint;
}

void ExecuteSql(NSURL *url, const char *sql)
{
    sqlite3 *database = nullptr;
    Require(sqlite3_open(url.fileSystemRepresentation, &database) == SQLITE_OK, "Failed to open test database.");
    char *message = nullptr;
    const int result = sqlite3_exec(database, sql, nullptr, nullptr, &message);
    const std::string error = message == nullptr ? "SQLite statement failed." : message;
    sqlite3_free(message);
    sqlite3_close(database);
    Require(result == SQLITE_OK, error.c_str());
}

std::int64_t ReadWeight(NSURL *url, const char *word)
{
    sqlite3 *database = nullptr;
    Require(sqlite3_open_v2(url.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK,
            "Failed to open installed dictionary.");
    sqlite3_stmt *statement = nullptr;
    Require(sqlite3_prepare_v2(database, "SELECT weight FROM tbl_2_n WHERE value=?1", -1, &statement, nullptr) ==
                SQLITE_OK,
            "Failed to prepare weight query.");
    Require(sqlite3_bind_text(statement, 1, word, -1, SQLITE_TRANSIENT) == SQLITE_OK, "Failed to bind weight query.");
    Require(sqlite3_step(statement) == SQLITE_ROW, "Installed dictionary word was missing.");
    const std::int64_t weight = sqlite3_column_int64(statement, 0);
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return weight;
}

bool ContainsUserDictionaryOperation(NSURL *url, const char *value)
{
    sqlite3 *database = nullptr;
    Require(sqlite3_open_v2(url.fileSystemRepresentation, &database, SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK,
            "Failed to open the user dictionary journal.");
    sqlite3_stmt *statement = nullptr;
    Require(sqlite3_prepare_v2(database, "SELECT 1 FROM user_dictionary_operations WHERE value=?1 LIMIT 1", -1,
                               &statement, nullptr) == SQLITE_OK,
            "Failed to prepare the user dictionary journal query.");
    Require(sqlite3_bind_text(statement, 1, value, -1, SQLITE_TRANSIENT) == SQLITE_OK,
            "Failed to bind the user dictionary journal query.");
    const bool found = sqlite3_step(statement) == SQLITE_ROW;
    sqlite3_finalize(statement);
    sqlite3_close(database);
    return found;
}

void WriteResetMarker(NSURL *directory, NSString *identifier, NSString *phase, NSArray<NSString *> *originalFileNames)
{
    NSDictionary *marker = @{
        @"version" : @1,
        @"identifier" : identifier,
        @"phase" : phase,
        @"originalFileNames" : originalFileNames,
    };
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:marker
                                                              format:NSPropertyListBinaryFormat_v1_0
                                                             options:0
                                                               error:&error];
    Require(data != nil, error.localizedDescription.UTF8String);
    NSURL *markerURL = [directory URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"];
    Require([data writeToURL:markerURL options:0 error:&error], error.localizedDescription.UTF8String);
}

NSURL *ResetBackup(NSURL *directory, NSString *fileName, NSString *identifier)
{
    return [directory
        URLByAppendingPathComponent:[NSString stringWithFormat:@".%@.reset-backup.%@", fileName, identifier]];
}

NSURL *CreateDirectory(NSURL *root, NSString *name)
{
    NSURL *directory = [root URLByAppendingPathComponent:name isDirectory:YES];
    NSError *error = nil;
    Require([[NSFileManager defaultManager] createDirectoryAtURL:directory
                                     withIntermediateDirectories:YES
                                                      attributes:nil
                                                           error:&error],
            error.localizedDescription.UTF8String);
    return directory;
}
} // namespace

int main()
{
    @autoreleasepool
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *root = [[NSURL fileURLWithPath:NSTemporaryDirectory() isDirectory:YES]
            URLByAppendingPathComponent:[@"metasequoia-dictionary-installer-"
                                            stringByAppendingString:NSUUID.UUID.UUIDString]
                            isDirectory:YES];
        NSError *error = nil;
        Require([fileManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:&error],
                error.localizedDescription.UTF8String);

        NSURL *helpcodeSource = CreateDirectory(root, @"bundled-helpcodes");
        NSURL *englishSource = [root URLByAppendingPathComponent:@"bundled-english.db"];
        WriteString(@"verified English fixture", englishSource);
        NSURL *englishData = CreateDirectory(root, @"english-data");
        Require(!InstallMetasequoiaEnglishDictionary(englishSource, englishData, @"bad", &error),
                "English installation accepted an invalid digest.");
        Require(![fileManager fileExistsAtPath:[englishData URLByAppendingPathComponent:@"english.db"].path],
                "Failed English installation left a published file.");
        error = nil;
        Require(
            InstallMetasequoiaEnglishDictionary(englishSource, englishData, SHA256Fingerprint(englishSource), &error),
            "English dictionary was not seeded.");
        NSURL *englishInstalled = [englishData URLByAppendingPathComponent:@"english.db"];
        WriteString(@"preserved learned data", englishInstalled);
        Require(
            InstallMetasequoiaEnglishDictionary(englishSource, englishData, SHA256Fingerprint(englishSource), &error) &&
                ReadString(englishInstalled) == "preserved learned data",
            "English dictionary installation overwrote user data.");
        NSArray<NSString *> *helpcodeNames = @[
            @"helpcode.txt", @"zrm_helpcode_big_unique.txt", @"shouyou2_0_helpcode.txt", @"shouyouplus_helpcode.txt",
            @"xiaohe_helpcode.txt"
        ];
        for (NSString *name in helpcodeNames)
        {
            WriteString([@"你=rx\n" stringByAppendingString:name], [helpcodeSource URLByAppendingPathComponent:name]);
        }
        NSURL *helpcodeData = CreateDirectory(root, @"helpcode-data");
        Require(InstallMetasequoiaHelpCodes(helpcodeSource, helpcodeData, &error),
                error.localizedDescription.UTF8String);
        for (NSString *name in helpcodeNames)
        {
            Require(ReadString([[helpcodeData URLByAppendingPathComponent:@"helpcodes" isDirectory:YES]
                        URLByAppendingPathComponent:name]) == [@"你=rx\n" stringByAppendingString:name].UTF8String,
                    "A bundled helpcode table was not installed.");
        }
        NSURL *incompleteHelpcodeSource = CreateDirectory(root, @"incomplete-helpcodes");
        WriteString(@"你=rx\n", [incompleteHelpcodeSource URLByAppendingPathComponent:@"helpcode.txt"]);
        error = nil;
        Require(!InstallMetasequoiaHelpCodes(incompleteHelpcodeSource, helpcodeData, &error) && error != nil,
                "An incomplete helpcode resource set was accepted.");
        Require(ReadString([[helpcodeData URLByAppendingPathComponent:@"helpcodes" isDirectory:YES]
                    URLByAppendingPathComponent:@"xiaohe_helpcode.txt"]) == [@"你=rx\nxiaohe_helpcode.txt" UTF8String],
                "A rejected helpcode update damaged the installed resource set.");

        NSURL *sameSizeDirectory = CreateDirectory(root, @"same-size");
        NSURL *sameSizeSource = [root URLByAppendingPathComponent:@"same-size-source.db"];
        NSURL *sameSizeDestination = [sameSizeDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(sameSizeSource, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                   "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',100);");
        ExecuteSql(sameSizeDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                        "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',200);");
        Require([[fileManager attributesOfItemAtPath:sameSizeSource.path error:&error] fileSize] ==
                    [[fileManager attributesOfItemAtPath:sameSizeDestination.path error:&error] fileSize],
                "The same-size update fixture dictionaries have different sizes.");
        NSString *sameSizeFingerprint = SHA256Fingerprint(sameSizeSource);
        Require(InstallMetasequoiaDictionary(sameSizeSource, sameSizeDirectory, sameSizeFingerprint, &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(sameSizeDestination, "拟好") == 100,
                "A same-size dictionary update was incorrectly skipped.");

        ExecuteSql(sameSizeDestination, "UPDATE tbl_2_n SET weight=999 WHERE value='拟好';");
        WriteString(@"unused corrupt source", sameSizeSource);
        Require(InstallMetasequoiaDictionary(sameSizeSource, sameSizeDirectory, sameSizeFingerprint, &error),
                "A matching dictionary fingerprint did not use the no-update fast path.");
        Require(ReadWeight(sameSizeDestination, "拟好") == 999,
                "A matching dictionary fingerprint overwrote learned data.");

        NSURL *firstInstallDirectory = CreateDirectory(root, @"first-install");
        NSURL *largeSource = [root URLByAppendingPathComponent:@"large-source.db"];
        ExecuteSql(largeSource, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                "INSERT INTO tbl_2_n VALUES('ni''hao','nh','首次安装',111);"
                                "CREATE TABLE hash_stream_padding(value BLOB);"
                                "INSERT INTO hash_stream_padding VALUES(zeroblob(131072));");
        Require([[fileManager attributesOfItemAtPath:largeSource.path error:&error] fileSize] > 64 * 1024,
                "The fingerprint stream fixture does not span multiple reads.");
        NSString *largeSourceFingerprint = SHA256Fingerprint(largeSource);
        Require(InstallMetasequoiaDictionary(largeSource, firstInstallDirectory, largeSourceFingerprint, &error),
                error.localizedDescription.UTF8String);
        NSURL *firstInstallDestination = [firstInstallDirectory URLByAppendingPathComponent:@"msime.db"];
        Require(ReadWeight(firstInstallDestination, "首次安装") == 111 &&
                    ReadString([firstInstallDirectory URLByAppendingPathComponent:@"msime.db.sha256"]) ==
                        largeSourceFingerprint.UTF8String,
                "A valid multi-read dictionary did not install with its fingerprint.");

        NSURL *firstInstallMismatchDirectory = CreateDirectory(root, @"first-install-mismatch");
        error = nil;
        Require(!InstallMetasequoiaDictionary(largeSource, firstInstallMismatchDirectory,
                                              @"0000000000000000000000000000000000000000000000000000000000000000",
                                              &error),
                "A first-install dictionary with a mismatched fingerprint unexpectedly installed.");
        Require(
            error != nil &&
                ![fileManager
                    fileExistsAtPath:[firstInstallMismatchDirectory URLByAppendingPathComponent:@"msime.db"].path] &&
                ![fileManager
                    fileExistsAtPath:[firstInstallMismatchDirectory URLByAppendingPathComponent:@"msime.db.sha256"]
                                         .path],
            "A rejected first-install dictionary left persistent files behind.");
        NSArray<NSURL *> *firstInstallMismatchContents =
            [fileManager contentsOfDirectoryAtURL:firstInstallMismatchDirectory
                       includingPropertiesForKeys:nil
                                          options:0
                                            error:&error];
        Require(firstInstallMismatchContents.count == 0,
                "A rejected first-install dictionary left a temporary file behind.");

        NSURL *partialCopySource = CreateDirectory(root, @"partial-copy-source.db");
        NSURL *unreadableCopySource = [partialCopySource URLByAppendingPathComponent:@"unreadable"];
        WriteString(@"cannot-copy", unreadableCopySource);
        Require([fileManager setAttributes:@{
                    NSFilePosixPermissions : @0
                }
                              ofItemAtPath:unreadableCopySource.path
                                     error:&error],
                error.localizedDescription.UTF8String);
        NSURL *partialInstallDirectory = CreateDirectory(root, @"partial-install");
        error = nil;
        Require(
            !InstallMetasequoiaDictionary(partialCopySource, partialInstallDirectory, largeSourceFingerprint, &error),
            "A partially copied dictionary unexpectedly installed.");
        NSArray<NSURL *> *partialInstallContents = [fileManager contentsOfDirectoryAtURL:partialInstallDirectory
                                                              includingPropertiesForKeys:nil
                                                                                 options:0
                                                                                   error:&error];
        Require(partialInstallContents != nil, error.localizedDescription.UTF8String);
        for (NSURL *remainingFile in partialInstallContents)
        {
            Require(![remainingFile.lastPathComponent hasPrefix:@".msime.db.installing."],
                    "A failed dictionary copy left a partial install file behind.");
        }

        NSURL *partialResetDirectory = CreateDirectory(root, @"partial-reset");
        error = nil;
        Require(!ResetMetasequoiaLearnedData(partialCopySource, partialResetDirectory, largeSourceFingerprint, &error),
                "A partially copied dictionary unexpectedly reset learned data.");
        NSArray<NSURL *> *partialResetContents = [fileManager contentsOfDirectoryAtURL:partialResetDirectory
                                                            includingPropertiesForKeys:nil
                                                                               options:0
                                                                                 error:&error];
        Require(partialResetContents != nil, error.localizedDescription.UTF8String);
        for (NSURL *remainingFile in partialResetContents)
        {
            Require(![remainingFile.lastPathComponent hasPrefix:@".msime.db.resetting."],
                    "A failed dictionary copy left a partial reset file behind.");
        }
        Require([fileManager setAttributes:@{
                    NSFilePosixPermissions : @0600
                }
                              ofItemAtPath:unreadableCopySource.path
                                     error:&error],
                error.localizedDescription.UTF8String);

        NSURL *replayDirectory = CreateDirectory(root, @"replay");
        NSURL *replaySource = [root URLByAppendingPathComponent:@"replay-source.db"];
        NSURL *replayDestination = [replayDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(replaySource, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                 "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',200);"
                                 "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',100);");
        ExecuteSql(replayDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                      "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',200);"
                                      "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',201);");
        const std::string userDatabase =
            [replayDirectory URLByAppendingPathComponent:@"msime_user.db"].fileSystemRepresentation;
        Require(user_dictionary::record_upsert(userDatabase, user_dictionary::DictionaryKind::Pinyin, "ni'hao", "拟好",
                                               999),
                "Failed to create the user dictionary journal fixture.");
        WriteString(@"old-fingerprint", [replayDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        // A rollback journal left by an unclean shutdown belongs to the dictionary being replaced,
        // not to the one being installed, and SQLite would replay it onto whatever now sits at the
        // msime.db path. Planted here so the swap has to discard all three sidecars.
        for (NSString *sidecar in @[ @"msime.db-journal", @"msime.db-wal", @"msime.db-shm" ])
        {
            WriteString(@"stale-sidecar", [replayDirectory URLByAppendingPathComponent:sidecar]);
        }
        Require(InstallMetasequoiaDictionary(replaySource, replayDirectory, SHA256Fingerprint(replaySource), &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(replayDestination, "拟好") == 999,
                "The user dictionary journal was not replayed onto the upgraded dictionary.");
        for (NSString *sidecar in @[ @"msime.db-journal", @"msime.db-wal", @"msime.db-shm" ])
        {
            Require(![fileManager fileExistsAtPath:[replayDirectory URLByAppendingPathComponent:sidecar].path],
                    "Installing a new dictionary left a stale SQLite sidecar beside it.");
        }

        NSURL *resetDirectory = CreateDirectory(root, @"reset-learning");
        NSURL *resetSource = [root URLByAppendingPathComponent:@"reset-source.db"];
        NSURL *resetDestination = [resetDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(resetSource, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',200);"
                                "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',100);");
        ExecuteSql(resetDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                     "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',200);"
                                     "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',999);");
        WriteString(@"old-fingerprint", [resetDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        Require(setenv("METASEQUOIA_IME_DATA_DIR", resetDirectory.fileSystemRepresentation, 1) == 0,
                "Failed to set the reset test data directory.");
        const std::string resetUserDatabase = user_dictionary::default_user_db_path();
        Require(user_dictionary::record_upsert(resetUserDatabase, user_dictionary::DictionaryKind::Pinyin, "ni'hao",
                                               "旧学习", 999),
                "Failed to keep the default user database open before reset.");
        WriteString(@"journal-wal", [resetDirectory URLByAppendingPathComponent:@"msime_user.db-wal"]);
        WriteString(@"journal-rollback", [resetDirectory URLByAppendingPathComponent:@"msime_user.db-journal"]);
        WriteString(@"english", [resetDirectory URLByAppendingPathComponent:@"msime_english.db"]);
        WriteString(@"modern English learning", [resetDirectory URLByAppendingPathComponent:@"english.db"]);
        WriteString(@"decoder-learning", [resetDirectory URLByAppendingPathComponent:@"user_dict.dat"]);
        error = nil;
        NSString *resetFingerprint = SHA256Fingerprint(resetSource);
        Require(ResetMetasequoiaLearnedData(resetSource, resetDirectory, resetFingerprint, &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(resetDestination, "拟好") == 100,
                "Resetting learned data did not restore the bundled candidate weight.");
        Require(ReadString([resetDirectory URLByAppendingPathComponent:@"msime.db.sha256"]) ==
                    resetFingerprint.UTF8String,
                "Resetting learned data did not install the bundled dictionary fingerprint.");
        for (NSString *learnedFile in @[
                 @"msime_user.db", @"msime_user.db-wal", @"msime_user.db-journal", @"msime_english.db", @"english.db",
                 @"user_dict.dat"
             ])
        {
            Require(![fileManager fileExistsAtPath:[resetDirectory URLByAppendingPathComponent:learnedFile].path],
                    "Resetting learned data left a learned-data file behind.");
        }
        Require(user_dictionary::record_upsert(user_dictionary::default_user_db_path(),
                                               user_dictionary::DictionaryKind::Pinyin, "ni'hao", "重新学习", 200),
                "The default user database did not reopen after reset.");
        user_dictionary::close_default_user_database();
        NSURL *reopenedUserDatabase = [resetDirectory URLByAppendingPathComponent:@"msime_user.db"];
        Require(ContainsUserDictionaryOperation(reopenedUserDatabase, "重新学习") &&
                    !ContainsUserDictionaryOperation(reopenedUserDatabase, "旧学习"),
                "Learning after reset used the database handle from before reset.");
        NSArray<NSURL *> *remainingFiles = [fileManager contentsOfDirectoryAtURL:resetDirectory
                                                      includingPropertiesForKeys:nil
                                                                         options:0
                                                                           error:&error];
        Require(remainingFiles != nil, error.localizedDescription.UTF8String);
        for (NSURL *remainingFile in remainingFiles)
        {
            Require([remainingFile.lastPathComponent rangeOfString:@"reset-backup"].location == NSNotFound &&
                        [remainingFile.lastPathComponent rangeOfString:@"resetting"].location == NSNotFound,
                    "Resetting learned data left a temporary or backup file behind.");
        }

        NSString *preparedIdentifier = @"1516EAA2-7229-44D3-90F5-930475E184E3";
        NSURL *preparedDirectory = CreateDirectory(root, @"reset-learning-prepared-recovery");
        NSURL *preparedDestination = [preparedDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(preparedDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                        "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',100);");
        ExecuteSql(ResetBackup(preparedDirectory, @"msime.db", preparedIdentifier),
                   "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                   "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',555);");
        WriteString(@"new-fingerprint", [preparedDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        WriteString(@"prepared-old", ResetBackup(preparedDirectory, @"msime.db.sha256", preparedIdentifier));
        WriteString(@"old-journal", ResetBackup(preparedDirectory, @"msime_user.db", preparedIdentifier));
        WriteString(@"temporary",
                    [preparedDirectory URLByAppendingPathComponent:[@".msime.db.resetting."
                                                                       stringByAppendingString:preparedIdentifier]]);
        WriteResetMarker(preparedDirectory, preparedIdentifier, @"prepared",
                         @[ @"msime.db", @"msime.db.sha256", @"msime_user.db" ]);
        error = nil;
        Require(PrepareMetasequoiaDictionary(resetSource, preparedDirectory, @"prepared-old", &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(preparedDestination, "拟好") == 555 &&
                    ReadString([preparedDirectory URLByAppendingPathComponent:@"msime_user.db"]) == "old-journal",
                "Startup recovery did not roll back an interrupted prepared reset.");
        Require(
            ![fileManager
                fileExistsAtPath:[preparedDirectory URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]
                                     .path] &&
                ![fileManager fileExistsAtPath:ResetBackup(preparedDirectory, @"msime.db", preparedIdentifier).path],
            "Prepared reset recovery left transaction artifacts behind.");

        NSString *missingBackupIdentifier = @"85DF9BC5-E4DF-4EC1-A84F-FCB50E8E029C";
        NSURL *missingBackupDirectory = CreateDirectory(root, @"reset-learning-missing-durable-backup");
        NSURL *missingBackupDestination = [missingBackupDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(missingBackupDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                             "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',600);");
        WriteString(@"new-before-crash", [missingBackupDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        WriteResetMarker(missingBackupDirectory, missingBackupIdentifier, @"backed-up",
                         @[ @"msime.db", @"msime.db.sha256" ]);
        error = nil;
        Require(!PrepareMetasequoiaDictionary(resetSource, missingBackupDirectory, @"new-before-crash", &error),
                "Recovery accepted a post-backup reset whose durable backup was missing.");
        Require(error != nil && ReadWeight(missingBackupDestination, "拟好") == 600 &&
                    [fileManager fileExistsAtPath:[missingBackupDirectory
                                                      URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]
                                                      .path],
                "Missing-backup recovery modified data or discarded its recovery marker.");

        NSString *partialRollbackIdentifier = @"6102874A-C0DC-4F89-825A-6303C797841C";
        NSURL *partialRollbackDirectory = CreateDirectory(root, @"reset-learning-partial-rollback");
        NSURL *partialRollbackDestination = [partialRollbackDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(partialRollbackDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                               "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',650);");
        WriteString(@"new-fingerprint", [partialRollbackDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        WriteString(@"partial-old",
                    ResetBackup(partialRollbackDirectory, @"msime.db.sha256", partialRollbackIdentifier));
        WriteString(@"partial-journal",
                    ResetBackup(partialRollbackDirectory, @"msime_user.db", partialRollbackIdentifier));
        WriteResetMarker(partialRollbackDirectory, partialRollbackIdentifier, @"rolling-back",
                         @[ @"msime.db", @"msime.db.sha256", @"msime_user.db" ]);
        error = nil;
        Require(PrepareMetasequoiaDictionary(resetSource, partialRollbackDirectory, @"partial-old", &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(partialRollbackDestination, "拟好") == 650 &&
                    ReadString([partialRollbackDirectory URLByAppendingPathComponent:@"msime_user.db"]) ==
                        "partial-journal" &&
                    ![fileManager fileExistsAtPath:[partialRollbackDirectory
                                                       URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]
                                                       .path],
                "A partially completed rollback could not resume idempotently.");

        NSString *committedIdentifier = @"E2E812BF-E105-4FC4-A15D-340C2A49B09B";
        NSURL *committedDirectory = CreateDirectory(root, @"reset-learning-committed-recovery");
        NSURL *committedDestination = [committedDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(committedDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                         "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',100);");
        ExecuteSql(ResetBackup(committedDirectory, @"msime.db", committedIdentifier),
                   "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                   "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',666);");
        WriteString(@"committed-new", [committedDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        WriteString(@"committed-old", ResetBackup(committedDirectory, @"msime.db.sha256", committedIdentifier));
        WriteString(@"old-journal", ResetBackup(committedDirectory, @"msime_user.db", committedIdentifier));
        WriteResetMarker(committedDirectory, committedIdentifier, @"committed",
                         @[ @"msime.db", @"msime.db.sha256", @"msime_user.db" ]);
        error = nil;
        Require(PrepareMetasequoiaDictionary(resetSource, committedDirectory, @"committed-new", &error),
                error.localizedDescription.UTF8String);
        Require(
            ReadWeight(committedDestination, "拟好") == 100 &&
                ![fileManager fileExistsAtPath:[committedDirectory URLByAppendingPathComponent:@"msime_user.db"].path],
            "Startup recovery did not finish cleanup for a committed reset.");
        Require(
            ![fileManager
                fileExistsAtPath:[committedDirectory URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]
                                     .path] &&
                ![fileManager fileExistsAtPath:ResetBackup(committedDirectory, @"msime.db", committedIdentifier).path],
            "Committed reset recovery left transaction artifacts behind.");

        NSString *retryIdentifier = @"80557816-5344-46AA-A085-01CBB6382E20";
        NSURL *retryDirectory = CreateDirectory(root, @"reset-learning-cleanup-retry");
        NSURL *retryDestination = [retryDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(retryDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                     "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',700);");
        WriteString(@"retry-current", [retryDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        NSURL *retryBackup = ResetBackup(retryDirectory, @"msime_user.db", retryIdentifier);
        WriteString(@"deferred-cleanup", retryBackup);
        Require([fileManager setAttributes:@{
                    NSFileImmutable : @YES
                }
                              ofItemAtPath:retryBackup.path
                                     error:&error],
                error.localizedDescription.UTF8String);
        WriteResetMarker(retryDirectory, retryIdentifier, @"committed", @[ @"msime_user.db" ]);
        error = nil;
        Require(!PrepareMetasequoiaDictionary(resetSource, retryDirectory, @"retry-current", &error),
                "Committed reset cleanup unexpectedly removed an immutable backup.");
        Require(error != nil && [fileManager fileExistsAtPath:retryBackup.path] &&
                    [fileManager fileExistsAtPath:[retryDirectory
                                                      URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]
                                                      .path],
                "Failed committed cleanup did not retain enough state to retry.");
        Require([fileManager setAttributes:@{
                    NSFileImmutable : @NO
                }
                              ofItemAtPath:retryBackup.path
                                     error:&error],
                error.localizedDescription.UTF8String);
        error = nil;
        Require(PrepareMetasequoiaDictionary(resetSource, retryDirectory, @"retry-current", &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(retryDestination, "拟好") == 700 && ![fileManager fileExistsAtPath:retryBackup.path] &&
                    ![fileManager fileExistsAtPath:[retryDirectory
                                                       URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]
                                                       .path],
                "Startup recovery did not retry deferred committed cleanup.");

        NSURL *orphanDirectory = CreateDirectory(root, @"reset-learning-orphan-cleanup");
        NSURL *orphanDestination = [orphanDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(orphanDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                      "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',777);");
        WriteString(@"orphan-current", [orphanDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        NSURL *orphanTemporary =
            [orphanDirectory URLByAppendingPathComponent:@".msime.db.resetting.65DB8CE4-0550-4D9B-BB94-AE347215465A"];
        WriteString(@"orphan", orphanTemporary);
        error = nil;
        Require(PrepareMetasequoiaDictionary(resetSource, orphanDirectory, @"orphan-current", &error),
                error.localizedDescription.UTF8String);
        Require(ReadWeight(orphanDestination, "拟好") == 777 && ![fileManager fileExistsAtPath:orphanTemporary.path],
                "Startup recovery did not remove an orphaned pre-transaction temporary file.");

        NSURL *invalidMarkerDirectory = CreateDirectory(root, @"reset-learning-invalid-marker");
        NSURL *invalidMarkerDestination = [invalidMarkerDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(invalidMarkerDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                             "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',888);");
        WriteString(@"invalid-marker-current", [invalidMarkerDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        WriteString(@"not-a-property-list",
                    [invalidMarkerDirectory URLByAppendingPathComponent:@".metasequoia-learning-reset.plist"]);
        error = nil;
        Require(!PrepareMetasequoiaDictionary(resetSource, invalidMarkerDirectory, @"invalid-marker-current", &error),
                "A corrupt reset marker was ignored during startup recovery.");
        Require(error != nil && ReadWeight(invalidMarkerDestination, "拟好") == 888,
                "A corrupt reset marker changed the working dictionary.");

        NSURL *resetFailureDirectory = CreateDirectory(root, @"reset-learning-failure");
        NSURL *resetFailureDestination = [resetFailureDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(resetFailureDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                            "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',321);");
        NSURL *resetFailureJournal = [resetFailureDirectory URLByAppendingPathComponent:@"msime_user.db"];
        WriteString(@"keep-journal", resetFailureJournal);
        NSURL *resetFailureFingerprint = [resetFailureDirectory URLByAppendingPathComponent:@"msime.db.sha256"];
        WriteString(@"keep-fingerprint", resetFailureFingerprint);
        NSURL *invalidResetSource = [root URLByAppendingPathComponent:@"invalid-reset-source.db"];
        WriteString(@"not-a-dictionary", invalidResetSource);
        error = nil;
        Require(!ResetMetasequoiaLearnedData(invalidResetSource, resetFailureDirectory,
                                             SHA256Fingerprint(invalidResetSource), &error),
                "A corrupt bundled dictionary unexpectedly reset learned data.");
        Require(error != nil, "A rejected learned-data reset did not return an error.");
        Require(ReadWeight(resetFailureDestination, "拟好") == 321,
                "A failed learned-data reset changed the working dictionary.");
        Require(ReadString(resetFailureJournal) == "keep-journal" &&
                    ReadString(resetFailureFingerprint) == "keep-fingerprint",
                "A failed learned-data reset removed persistent learning metadata.");
        error = nil;
        Require(!ResetMetasequoiaLearnedData(resetSource, resetFailureDirectory,
                                             @"0000000000000000000000000000000000000000000000000000000000000000",
                                             &error),
                "A fingerprint-mismatched bundled dictionary unexpectedly reset learned data.");
        Require(error != nil && ReadWeight(resetFailureDestination, "拟好") == 321 &&
                    ReadString(resetFailureJournal) == "keep-journal" &&
                    ReadString(resetFailureFingerprint) == "keep-fingerprint",
                "A fingerprint-mismatched learned-data reset changed persistent data.");

        NSURL *rollbackDirectory = CreateDirectory(root, @"reset-learning-rollback");
        NSURL *rollbackDestination = [rollbackDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(rollbackDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                        "INSERT INTO tbl_2_n VALUES('ni''hao','nh','拟好',444);");
        NSURL *rollbackFingerprint = [rollbackDirectory URLByAppendingPathComponent:@"msime.db.sha256"];
        WriteString(@"rollback-fingerprint", rollbackFingerprint);
        NSURL *immutableJournal = [rollbackDirectory URLByAppendingPathComponent:@"msime_user.db"];
        WriteString(@"immutable-journal", immutableJournal);
        Require([fileManager setAttributes:@{
                    NSFileImmutable : @YES
                }
                              ofItemAtPath:immutableJournal.path
                                     error:&error],
                error.localizedDescription.UTF8String);
        error = nil;
        Require(!ResetMetasequoiaLearnedData(resetSource, rollbackDirectory, resetFingerprint, &error),
                "A learned-data reset unexpectedly ignored an immutable journal.");
        Require([fileManager setAttributes:@{
                    NSFileImmutable : @NO
                }
                              ofItemAtPath:immutableJournal.path
                                     error:&error],
                error.localizedDescription.UTF8String);
        Require(ReadWeight(rollbackDestination, "拟好") == 444 &&
                    ReadString(rollbackFingerprint) == "rollback-fingerprint" &&
                    ReadString(immutableJournal) == "immutable-journal",
                "A mid-reset failure did not roll back the working dictionary and learning metadata.");

        NSURL *failureDirectory = CreateDirectory(root, @"failure");
        NSURL *failureDestination = [failureDirectory URLByAppendingPathComponent:@"msime.db"];
        WriteString(@"keep-me", failureDestination);
        error = nil;
        NSURL *missingSource = [root URLByAppendingPathComponent:@"missing.db"];
        Require(!InstallMetasequoiaDictionary(missingSource, failureDirectory, @"missing", &error),
                "A missing bundled dictionary unexpectedly succeeded.");
        Require(ReadString(failureDestination) == "keep-me", "A failed update removed the working dictionary.");
        error = nil;
        Require(!PrepareMetasequoiaDictionary(missingSource, failureDirectory, @"missing", &error),
                "A corrupt existing dictionary was accepted as an update fallback.");
        Require(error != nil, "A rejected dictionary fallback did not preserve the update error.");

        NSURL *corruptSourceDirectory = CreateDirectory(root, @"corrupt-source");
        NSURL *corruptSource = [root URLByAppendingPathComponent:@"corrupt-source.db"];
        NSURL *preservedDestination = [corruptSourceDirectory URLByAppendingPathComponent:@"msime.db"];
        WriteString(@"not a SQLite dictionary", corruptSource);
        ExecuteSql(preservedDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                         "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',321);");
        WriteString(@"old-fingerprint", [corruptSourceDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        error = nil;
        Require(!InstallMetasequoiaDictionary(corruptSource, corruptSourceDirectory, SHA256Fingerprint(corruptSource),
                                              &error),
                "A nonempty corrupt bundled dictionary unexpectedly replaced the working dictionary.");
        Require(ReadWeight(preservedDestination, "你好") == 321,
                "A corrupt bundled dictionary damaged the working dictionary.");
        error = nil;
        Require(PrepareMetasequoiaDictionary(corruptSource, corruptSourceDirectory, @"new-fingerprint", &error),
                "A valid working dictionary was not used after bundled dictionary validation failed.");
        Require(error == nil, "A successful corrupt-source fallback leaked the validation error.");
        Require(ReadWeight(preservedDestination, "你好") == 321,
                "Corrupt-source fallback did not preserve the working dictionary.");

        NSURL *fingerprintMismatchDirectory = CreateDirectory(root, @"fingerprint-mismatch");
        NSURL *fingerprintMismatchSource = [root URLByAppendingPathComponent:@"fingerprint-mismatch-source.db"];
        NSURL *fingerprintMismatchDestination = [fingerprintMismatchDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(fingerprintMismatchSource, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                              "INSERT INTO tbl_2_n VALUES('ni''hao','nh','替换内容',100);");
        ExecuteSql(fingerprintMismatchDestination,
                   "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                   "INSERT INTO tbl_2_n VALUES('ni''hao','nh','保留内容',456);");
        WriteString(@"old-fingerprint", [fingerprintMismatchDirectory URLByAppendingPathComponent:@"msime.db.sha256"]);
        error = nil;
        Require(!InstallMetasequoiaDictionary(fingerprintMismatchSource, fingerprintMismatchDirectory,
                                              @"0000000000000000000000000000000000000000000000000000000000000000",
                                              &error),
                "A bundled dictionary with mismatched content fingerprint unexpectedly installed.");
        Require(ReadWeight(fingerprintMismatchDestination, "保留内容") == 456,
                "A fingerprint-mismatched bundled dictionary replaced the working dictionary.");

        NSURL *replayFailureDirectory = CreateDirectory(root, @"replay-failure");
        NSURL *replayFailureSource = [root URLByAppendingPathComponent:@"replay-failure-source.db"];
        NSURL *replayFailureDestination = [replayFailureDirectory URLByAppendingPathComponent:@"msime.db"];
        ExecuteSql(replayFailureSource, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                        "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',200);");
        ExecuteSql(replayFailureDestination, "CREATE TABLE tbl_2_n(key TEXT, jp TEXT, value TEXT, weight INTEGER);"
                                             "INSERT INTO tbl_2_n VALUES('ni''hao','nh','你好',321);");
        const std::string invalidUserDatabase =
            [replayFailureDirectory URLByAppendingPathComponent:@"msime_user.db"].fileSystemRepresentation;
        Require(user_dictionary::record_upsert(invalidUserDatabase, user_dictionary::DictionaryKind::Pinyin, "wo'ai",
                                               "我爱", 999),
                "Failed to create the invalid replay fixture.");
        error = nil;
        NSString *replayFailureFingerprint = SHA256Fingerprint(replayFailureSource);
        Require(!InstallMetasequoiaDictionary(replayFailureSource, replayFailureDirectory, replayFailureFingerprint,
                                              &error),
                "An invalid user dictionary replay unexpectedly succeeded.");
        Require(ReadWeight(replayFailureDestination, "你好") == 321,
                "A failed journal replay replaced the working dictionary.");
        error = nil;
        Require(
            PrepareMetasequoiaDictionary(replayFailureSource, replayFailureDirectory, replayFailureFingerprint, &error),
            "A valid existing dictionary was not used after an update failure.");
        Require(error == nil, "A successful dictionary fallback leaked the update error.");
        Require(ReadWeight(replayFailureDestination, "你好") == 321,
                "Dictionary fallback did not preserve the existing working database.");

        Require([fileManager removeItemAtURL:root error:&error], error.localizedDescription.UTF8String);
    }
    return 0;
}
