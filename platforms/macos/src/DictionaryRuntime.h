#pragma once
#import <Foundation/Foundation.h>
#include <metasequoia/session.h>

// Resolve a published snapshot without replaying or modifying a live journal.
metasequoia::RuntimePaths MetasequoiaCurrentDictionaryPaths();
NSURL *MetasequoiaDictionaryUserDirectory();

// A wake-up hint only: exclusivity must still be established with the file lease.
inline NSString *const MetasequoiaReleaseIdleDictionarySessionsNotification = @"app.msime.release-idle-dictionary-sessions";
void MetasequoiaRequestIdleDictionarySessions();

// Upgrade the legacy journal to the bundled main/English resources, preserving
// Engine state. Requires idle controllers and a cross-process exclusive lease.
BOOL MetasequoiaPrepareBundledDictionaryRuntime(NSURL *resources, NSError **error);
