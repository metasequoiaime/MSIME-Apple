#import <XCTest/XCTest.h>
#import <CommonCrypto/CommonDigest.h>
#include "DictionaryInstallation.h"
#include "InputSessionAdapter.h"
#include <sqlite3.h>

@interface DictionaryInstallationTests : XCTestCase
@end

@implementation DictionaryInstallationTests

- (void)testStartupUpgradeRecovery
{
    NSURL *root =
        [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *resources = [root URLByAppendingPathComponent:@"bundle"];
    NSURL *user = [root URLByAppendingPathComponent:@"user"];
    NSURL *cache = [root URLByAppendingPathComponent:@"cache"];
    NSFileManager *manager = NSFileManager.defaultManager;
    XCTAssertTrue([manager createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil]);
    auto writeDigests = [&] {
        for (NSString *name in @[ @"msime.db", @"english.db", @"others.db", @"dict_japanese.dat" ])
        {
            NSData *data = [NSData dataWithContentsOfURL:[resources URLByAppendingPathComponent:name]];
            unsigned char digest[CC_SHA256_DIGEST_LENGTH];
            CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
            NSMutableString *text = [NSMutableString string];
            for (auto byte : digest)
                [text appendFormat:@"%02x", byte];
            XCTAssertTrue([text
                writeToURL:[resources URLByAppendingPathComponent:[name stringByAppendingString:@".sha256"]]
                atomically:YES
                  encoding:NSUTF8StringEncoding
                     error:nil]);
        }
    };
    auto seed = [&](NSString *name, const char *sql) {
        sqlite3 *database = nullptr;
        XCTAssertEqual(sqlite3_open([resources URLByAppendingPathComponent:name].fileSystemRepresentation, &database),
                       SQLITE_OK);
        XCTAssertEqual(sqlite3_exec(database, sql, nullptr, nullptr, nullptr), SQLITE_OK);
        sqlite3_close(database);
    };
    seed(@"msime.db", "CREATE TABLE tbl_2_b(key TEXT,jp TEXT,value TEXT,weight INTEGER);"
                      "INSERT INTO tbl_2_b VALUES('bu''hao','bh','不好',200);"
                      "INSERT INTO tbl_2_b VALUES('bu''hao','bh','补好',100);");
    seed(@"english.db", "CREATE TABLE fixture(value TEXT);");
    seed(@"others.db", "CREATE TABLE fixture(value TEXT);");
    XCTAssertTrue([[@"fixture" dataUsingEncoding:NSUTF8StringEncoding]
        writeToURL:[resources URLByAppendingPathComponent:@"dict_japanese.dat"]
        atomically:YES]);
    writeDigests();
    auto type = [](metasequoia::apple::InputSessionAdapter &adapter) {
        metasequoia::apple::InputSnapshot snapshot;
        for (char c : std::string("buhao"))
            snapshot = adapter.handle_character(c);
        return snapshot;
    };
    auto first = metasequoia::apple::PrepareDictionaryInstallation(resources, user, cache);
    XCTAssertFalse(first.diagnostic.has_value());
    XCTAssertTrue(first.paths.dictionaries != first.paths.user_data);
    XCTAssertTrue(first.paths.resources == std::filesystem::path(resources.fileSystemRepresentation));
    {
        metasequoia::apple::InputSessionAdapter adapter(first.paths);
        XCTAssertTrue(adapter.set_learning_enabled(true));
        XCTAssertTrue(type(adapter).candidates.at(1) == "补好");
        XCTAssertTrue(adapter.select_candidate(1).commit == "补好");
    }
    // A changed bundle is verified before activation; a bad digest keeps the working generation.
    [manager removeItemAtURL:cache error:nil];
    seed(@"msime.db", "CREATE TABLE release_revision(value INTEGER);");
    auto rejected = metasequoia::apple::PrepareDictionaryInstallation(resources, user, cache);
    XCTAssertTrue(rejected.diagnostic.has_value());
    XCTAssertTrue(rejected.paths.dictionaries == first.paths.dictionaries);
    {
        metasequoia::apple::InputSessionAdapter adapter(rejected.paths);
        XCTAssertTrue(type(adapter).candidates.at(0) == "补好");
    }
    writeDigests();
    // A process killed during staging leaves this directory. It must be retried under the lock.
    NSString *mainDigest = [NSString stringWithContentsOfURL:[resources URLByAppendingPathComponent:@"msime.db.sha256"]
                                                    encoding:NSUTF8StringEncoding
                                                       error:nil];
    NSString *englishDigest =
        [NSString stringWithContentsOfURL:[resources URLByAppendingPathComponent:@"english.db.sha256"]
                                 encoding:NSUTF8StringEncoding
                                    error:nil];
    NSString *nextGeneration = [mainDigest stringByAppendingString:englishDigest];
    NSURL *incoming = [[user URLByAppendingPathComponent:@"dictionaries"]
        URLByAppendingPathComponent:[nextGeneration stringByAppendingString:@".incoming"]];
    XCTAssertTrue([manager createDirectoryAtURL:incoming withIntermediateDirectories:YES attributes:nil error:nil]);
    // Unreadable journal must not activate the new generation or lose the last-good marker.
    NSURL *journal = [user URLByAppendingPathComponent:@"msime_user.db"];
    NSURL *saved = [user URLByAppendingPathComponent:@"saved-journal"];
    XCTAssertTrue([manager moveItemAtURL:journal toURL:saved error:nil]);
    XCTAssertTrue([manager createDirectoryAtURL:journal withIntermediateDirectories:YES attributes:nil error:nil]);
    auto failed = metasequoia::apple::PrepareDictionaryInstallation(resources, user, cache);
    XCTAssertTrue(failed.diagnostic.has_value());
    XCTAssertTrue(failed.paths.dictionaries == first.paths.dictionaries);
    XCTAssertFalse([manager fileExistsAtPath:incoming.path]);
    XCTAssertTrue([manager removeItemAtURL:journal error:nil]);
    XCTAssertTrue([manager moveItemAtURL:saved toURL:journal error:nil]);
    XCTAssertTrue([manager createDirectoryAtURL:incoming withIntermediateDirectories:YES attributes:nil error:nil]);
    auto upgraded = metasequoia::apple::PrepareDictionaryInstallation(resources, user, cache);
    XCTAssertFalse(upgraded.diagnostic.has_value());
    XCTAssertTrue(upgraded.paths.dictionaries != first.paths.dictionaries);
    XCTAssertFalse([manager fileExistsAtPath:incoming.path]);
    {
        metasequoia::apple::InputSessionAdapter adapter(upgraded.paths);
        XCTAssertTrue(type(adapter).candidates.at(0) == "补好");
    }
    auto reopened = metasequoia::apple::PrepareDictionaryInstallation(resources, user, cache);
    XCTAssertFalse(reopened.diagnostic.has_value());
    XCTAssertTrue(reopened.paths.dictionaries == upgraded.paths.dictionaries);
    // Upgrade from the old on-device layout, with no generation marker.
    NSURL *legacyUser = [root URLByAppendingPathComponent:@"legacy-user"];
    XCTAssertTrue([manager createDirectoryAtURL:legacyUser withIntermediateDirectories:YES attributes:nil error:nil]);
    for (NSString *name in @[ @"msime.db", @"english.db" ])
        XCTAssertTrue([manager copyItemAtURL:[resources URLByAppendingPathComponent:name]
                                       toURL:[legacyUser URLByAppendingPathComponent:name]
                                       error:nil]);
    XCTAssertTrue([manager copyItemAtURL:journal
                                   toURL:[legacyUser URLByAppendingPathComponent:@"msime_user.db"]
                                   error:nil]);
    auto migrated = metasequoia::apple::PrepareDictionaryInstallation(
        resources, legacyUser, [root URLByAppendingPathComponent:@"legacy-cache"]);
    XCTAssertFalse(migrated.diagnostic.has_value());
    {
        metasequoia::apple::InputSessionAdapter adapter(migrated.paths);
        XCTAssertTrue(type(adapter).candidates.at(0) == "补好");
    }
    XCTAssertTrue([manager fileExistsAtPath:[legacyUser URLByAppendingPathComponent:@"msime.db"].path]);
    XCTAssertTrue([manager removeItemAtURL:root error:nil]);
}
@end
