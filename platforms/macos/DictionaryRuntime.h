#pragma once
#import <Foundation/Foundation.h>
#include <metasequoia/session.h>

// Resolve a published snapshot without replaying or modifying a live journal.
metasequoia::RuntimePaths MetasequoiaCurrentDictionaryPaths();
NSURL *MetasequoiaDictionaryUserDirectory();
