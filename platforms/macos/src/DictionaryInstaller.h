#pragma once

#import <Foundation/Foundation.h>

BOOL EnsureMetasequoiaDictionary(NSError **error);
// Seed the legacy English dictionary exactly once. Existing mutable data is never overwritten.
BOOL InstallMetasequoiaEnglishDictionary(NSURL *source, NSURL *dataDirectory, NSString *fingerprint, NSError **error);
BOOL InstallMetasequoiaHelpCodes(NSURL *sourceDirectory, NSURL *dataDirectory, NSError **error);
BOOL PrepareMetasequoiaDictionary(NSURL *source, NSURL *dataDirectory, NSString *dictionaryFingerprint,
                                  NSError **error);
BOOL InstallMetasequoiaDictionary(NSURL *source, NSURL *dataDirectory, NSString *dictionaryFingerprint,
                                  NSError **error);
// The caller must first quiesce every input session that can hold an open dictionary handle.
BOOL ResetMetasequoiaLearnedData(NSURL *source, NSURL *dataDirectory, NSString *dictionaryFingerprint, NSError **error);
// The caller must first quiesce every input session that can hold an open dictionary handle.
BOOL ResetMetasequoiaLearnedDataForCurrentUser(NSError **error);
