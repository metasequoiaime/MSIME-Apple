#pragma once

#import <Foundation/Foundation.h>
#include <metasequoia/session.h>
#include <optional>

namespace metasequoia::apple
{
struct DictionaryInstallation
{
    RuntimePaths paths;
    std::optional<std::string> diagnostic;
};
// Each snapshot lives in a separate private root. Engine staging exclusively
// creates the returned directory; this helper only creates its parent.
std::filesystem::path DictionarySnapshotDirectory(NSURL *user, NSString *identifier);
// Empty means the original on-device journal. Invalid markers throw.
NSString *ActiveDictionarySnapshotIdentifier(NSURL *user);
bool DiscardInactiveDictionarySnapshot(NSURL *user, NSString *identifier);
// The caller quiesces writers and checks its local-state version before publishing.
// Compare the expected active identifier to reject competing publications. The
// adapter invokes this only after it has successfully constructed the new session.
void PublishDictionaryInstallation(NSURL *user, NSString *identifier, const RuntimePaths &paths,
                                   NSString *expectedIdentifier);
// Call before creating sessions. Resources are the immutable, signed bundle; user data remains
// in the extension's private directory, so learning does not require Full Access.
DictionaryInstallation PrepareDictionaryInstallation(NSURL *resources, NSURL *user, NSURL *cache);
} // namespace metasequoia::apple
