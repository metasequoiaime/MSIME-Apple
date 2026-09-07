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
// Call before creating sessions. Resources are the immutable, signed bundle; user data remains
// in the extension's private directory, so learning does not require Full Access.
DictionaryInstallation PrepareDictionaryInstallation(NSURL *resources, NSURL *user, NSURL *cache);
} // namespace metasequoia::apple
