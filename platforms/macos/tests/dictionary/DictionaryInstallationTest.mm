#include "DictionaryInstallation.h"
#include <cassert>
#include <stdexcept>

// The guards around which dictionary generation is live. Publishing a snapshot swaps the
// dictionaries a running keyboard reads, so the identifier bookkeeping is what stands between a
// staged generation and a half-applied one: an unreadable marker must stop preparation rather
// than be treated as "no snapshot", a publication whose expected identifier no longer matches
// must lose to whoever got there first, and the active generation must never be discarded.
//
// The bridge sources are shared with the Apple client unchanged; this covers the parts that
// need no Engine session, so it can run in the ordinary macOS test configuration.

namespace
{
using namespace metasequoia::apple;

NSURL *TemporaryRoot()
{
    NSURL *root =
        [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    assert([NSFileManager.defaultManager createDirectoryAtURL:root
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil]);
    return root;
}

void WriteMarker(NSURL *user, NSString *value)
{
    assert([value writeToURL:[user URLByAppendingPathComponent:@"active-user-generation"]
                  atomically:YES
                    encoding:NSUTF8StringEncoding
                       error:nil]);
}

template <typename Operation> bool Throws(Operation operation)
{
    try
    {
        operation();
    }
    catch (const std::exception &)
    {
        return true;
    }
    return false;
}

void TestActiveIdentifierRejectsAnythingButAUUID()
{
    NSURL *user = TemporaryRoot();
    // No marker at all is the original on-device journal, not an error.
    assert([ActiveDictionarySnapshotIdentifier(user) isEqualToString:@""]);

    NSString *identifier = NSUUID.UUID.UUIDString;
    WriteMarker(user, identifier);
    assert([ActiveDictionarySnapshotIdentifier(user) isEqualToString:identifier]);

    // A truncated or corrupted marker must not read as "no snapshot": that would silently
    // return the user to the pre-upgrade dictionaries with their learning left behind.
    for (NSString *broken in @[ @"", @"not-a-uuid", [identifier substringToIndex:35],
                                [identifier stringByAppendingString:@"0"],
                                [identifier lowercaseString].uppercaseString.lowercaseString ])
    {
        if ([broken isEqualToString:identifier])
            continue;
        WriteMarker(user, broken);
        assert(Throws([&] { ActiveDictionarySnapshotIdentifier(user); }));
    }
    assert([NSFileManager.defaultManager removeItemAtURL:user error:nil]);
}

void TestSnapshotDirectoryCreatesOnlyItsParent()
{
    NSURL *user = TemporaryRoot();
    assert(Throws([&] { DictionarySnapshotDirectory(user, @"not-a-uuid"); }));

    NSString *identifier = NSUUID.UUID.UUIDString;
    const auto directory = DictionarySnapshotDirectory(user, identifier);
    // Engine staging creates the generation directory exclusively, so this helper must leave it
    // absent; creating it here would turn that exclusive create into a silent reuse.
    assert(!std::filesystem::exists(directory));
    assert(std::filesystem::is_directory(directory.parent_path()));
    assert(directory.filename().string() == identifier.UTF8String);
    assert([NSFileManager.defaultManager removeItemAtURL:user error:nil]);
}

void TestTheActiveGenerationCannotBeDiscarded()
{
    NSURL *user = TemporaryRoot();
    NSString *active = NSUUID.UUID.UUIDString;
    NSString *stale = NSUUID.UUID.UUIDString;
    WriteMarker(user, active);

    const auto activeDirectory = DictionarySnapshotDirectory(user, active);
    const auto staleDirectory = DictionarySnapshotDirectory(user, stale);
    std::filesystem::create_directories(activeDirectory / "user");
    std::filesystem::create_directories(staleDirectory / "user");

    assert(!DiscardInactiveDictionarySnapshot(user, active));
    assert(std::filesystem::exists(activeDirectory));

    assert(DiscardInactiveDictionarySnapshot(user, stale));
    assert(!std::filesystem::exists(staleDirectory));
    assert(std::filesystem::exists(activeDirectory));
    assert([NSFileManager.defaultManager removeItemAtURL:user error:nil]);
}

void TestPublicationLosesToACompetingOne()
{
    NSURL *user = TemporaryRoot();
    NSString *published = NSUUID.UUID.UUIDString;
    NSString *ours = NSUUID.UUID.UUIDString;
    WriteMarker(user, published);

    const auto generation = DictionarySnapshotDirectory(user, ours);
    metasequoia::RuntimePaths paths{generation / "resources", generation / "user", generation / "cache",
                                    generation / "user" / "dictionaries" / "content"};

    // Someone else published while this generation was being prepared. Expecting the empty
    // identifier - what was active when preparation started - must lose rather than overwrite.
    assert(Throws([&] { PublishDictionaryInstallation(user, ours, paths, @""); }));
    assert([ActiveDictionarySnapshotIdentifier(user) isEqualToString:published]);

    // With the right expectation the identity check passes, and the readiness check is what
    // stops an unfinished generation: nothing has been staged under it.
    assert(Throws([&] { PublishDictionaryInstallation(user, ours, paths, published); }));
    assert([ActiveDictionarySnapshotIdentifier(user) isEqualToString:published]);
    assert([NSFileManager.defaultManager removeItemAtURL:user error:nil]);
}
} // namespace

int main()
{
    @autoreleasepool
    {
        TestActiveIdentifierRejectsAnythingButAUUID();
        TestSnapshotDirectoryCreatesOnlyItsParent();
        TestTheActiveGenerationCannotBeDiscarded();
        TestPublicationLosesToACompetingOne();
    }
    return 0;
}
