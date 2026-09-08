#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>
#include "DictionaryInstallation.h"
#include "DictionarySessionLease.h"
#include <metasequoia/dictionary_state.h>
#include <metasequoia/personal_dictionary.h>
#include <sqlite3.h>
#include <stdexcept>
#include <iostream>

namespace
{
void Require(bool condition)
{
    if (!condition)
        throw std::runtime_error("Desktop snapshot runtime assertion failed");
}
void Seed(NSURL *directory, NSString *name, const char *sql)
{
    NSURL *file = [directory URLByAppendingPathComponent:name];
    sqlite3 *database = nullptr;
    Require(sqlite3_open(file.fileSystemRepresentation, &database) == SQLITE_OK);
    const int result = sqlite3_exec(database, sql, nullptr, nullptr, nullptr);
    sqlite3_close(database);
    Require(result == SQLITE_OK);
    NSData *data = [NSData dataWithContentsOfURL:file];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, static_cast<CC_LONG>(data.length), digest);
    NSMutableString *text = [NSMutableString string];
    for (auto byte : digest)
        [text appendFormat:@"%02x", byte];
    Require([text writeToURL:[directory URLByAppendingPathComponent:[name stringByAppendingString:@".sha256"]]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil]);
}
} // namespace

int main()
{
    @autoreleasepool
    {
        NSURL *root =
            [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
        NSURL *resources = [root URLByAppendingPathComponent:@"resources"];
        NSURL *user = [root URLByAppendingPathComponent:@"user"];
        NSURL *cache = [root URLByAppendingPathComponent:@"cache"];
        NSFileManager *manager = NSFileManager.defaultManager;
        try
        {
            Require([manager createDirectoryAtURL:resources withIntermediateDirectories:YES attributes:nil error:nil]);
            Seed(resources, @"msime.db",
                 "CREATE TABLE quick_parases(key TEXT,value TEXT,weight INTEGER);"
                 "INSERT INTO quick_parases VALUES('fixture','基础短语',100);");
            Seed(resources, @"english.db", "CREATE TABLE english_words(word TEXT,display TEXT,weight INTEGER);");
            using namespace metasequoia;
            using namespace metasequoia::apple;
            auto profile = DictionaryResourceProfile::MainAndEnglish;
            const auto first = PrepareDictionaryInstallation(resources, user, cache, profile);
            Require(!first.diagnostic);
            // The mobile/default contract must still require its additional resources.
            Require(PrepareDictionaryInstallation(resources, user, cache).diagnostic.has_value());
            NSString *identifier = NSUUID.UUID.UUIDString;
            bool emitted = false;
            const auto prepared = stage_dictionary_state(
                resources.fileSystemRepresentation, DictionarySnapshotDirectory(user, identifier),
                first.paths.dictionaries.filename().string(), [&](DictionaryStateRecord &record) {
                    if (emitted)
                        return false;
                    emitted = true;
                    DictionaryStateEntry entry;
                    entry.kind = PersonalDictionaryKind::QuickPhrase;
                    entry.key = "cloudfixture";
                    entry.value = "云端短语";
                    entry.weight = 100000;
                    entry.user_inserted = true;
                    record = entry;
                    return true;
                });
            DictionarySessionLease publisher(user);
            {
                DictionarySessionLease input(user);
                Require(
                    !publisher.exclusively([&] { PublishDictionaryInstallation(user, identifier, prepared, @""); }));
                Require(ActiveDictionarySnapshotIdentifier(user).length == 0);
            }
            Require(publisher.exclusively([&] { PublishDictionaryInstallation(user, identifier, prepared, @""); }));
            Require([ActiveDictionarySnapshotIdentifier(user) isEqualToString:identifier]);
            const auto reopened = PrepareDictionaryInstallation(resources, user, cache, profile);
            Require(!reopened.diagnostic && reopened.paths.user_data == prepared.user_data);
            const auto page = personal_dictionary_entries(reopened.paths);
            Require(page.error.empty() && page.entries.size() == 1 && page.entries[0].value == "云端短语");
            {
                SessionOptions options;
                options.paths = reopened.paths;
                options.learning = false;
                Session input(options);
                Require(input.character('K', true).handled);
                for (char character : std::string("cloudfixture"))
                    Require(input.character(character).handled);
                Require(!input.snapshot().candidates.empty());
                Require(input.snapshot().candidates.front().word == "云端短语");
                Require(input.select(0).commit == "云端短语");
            }
            bool staleRejected = false;
            try
            {
                PublishDictionaryInstallation(user, identifier, prepared, @"");
            }
            catch (const std::exception &)
            {
                staleRejected = true;
            }
            Require(staleRejected);
            Require(!DiscardInactiveDictionarySnapshot(user, identifier));
            // Corrupt a new bundle without updating its digest: the active snapshot survives.
            [manager removeItemAtURL:[NSURL fileURLWithFileSystemRepresentation:prepared.cache.c_str()
                                                                    isDirectory:YES
                                                                  relativeToURL:nil]
                               error:nil];
            Require([[@"damaged" dataUsingEncoding:NSUTF8StringEncoding]
                writeToURL:[resources URLByAppendingPathComponent:@"english.db"]
                atomically:YES]);
            const auto fallback = PrepareDictionaryInstallation(resources, user, cache, profile);
            Require(fallback.diagnostic.has_value() && fallback.paths.dictionaries == prepared.dictionaries);
            Require(personal_dictionary_entries(fallback.paths).entries.size() == 1);
            [manager removeItemAtURL:root error:nil];
            std::cout << "PASS: desktop snapshot staging, reader exclusion, restart, stale publication and corrupt "
                         "bundle recovery\n";
            return 0;
        }
        catch (const std::exception &error)
        {
            [manager removeItemAtURL:root error:nil];
            std::cerr << error.what() << '\n';
            return 1;
        }
    }
}
