#import "DictionaryInstaller.h"

#import <CommonCrypto/CommonDigest.h>

#include "../../../vendor/MetasequoiaImeEngine/user_dictionary/user_dictionary_journal.h"
#include "../../../vendor/MetasequoiaImeEngine/googlepinyinime-rev/src/include/pinyinime.h"

#include <sqlite3.h>

#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <unistd.h>

namespace
{
NSString *const MetasequoiaDictionaryErrorDomain = @"com.houko.inputmethod.MetasequoiaIME.dictionary";
NSString *const MetasequoiaResetMarkerName = @".metasequoia-learning-reset.plist";
NSString *const MetasequoiaResetPreparedPhase = @"prepared";
NSString *const MetasequoiaResetBackedUpPhase = @"backed-up";
NSString *const MetasequoiaResetRollingBackPhase = @"rolling-back";
NSString *const MetasequoiaResetCommittedPhase = @"committed";

NSArray<NSString *> *MutableDictionaryFileNames()
{
    static NSArray<NSString *> *fileNames = @[
        @"msime.db", @"msime.db-wal", @"msime.db-shm", @"msime.db-journal", @"msime.db.sha256",
        @"msime_user.db", @"msime_user.db-wal", @"msime_user.db-shm", @"msime_user.db-journal",
        @"msime_english.db", @"msime_english.db-wal", @"msime_english.db-shm",
        @"msime_english.db-journal", @"user_dict.dat",
    ];
    return fileNames;
}

NSArray<NSString *> *HelpcodeFileNames()
{
    static NSArray<NSString *> *fileNames = @[
        @"helpcode.txt", @"zrm_helpcode_big_unique.txt", @"shouyou2_0_helpcode.txt",
        @"shouyouplus_helpcode.txt", @"xiaohe_helpcode.txt"
    ];
    return fileNames;
}

BOOL Fail(NSError **error, NSInteger code, NSString *description)
{
    if (error != nullptr)
    {
        *error = [NSError errorWithDomain:MetasequoiaDictionaryErrorDomain
                                     code:code
                                 userInfo:@{NSLocalizedDescriptionKey: description}];
    }
    return NO;
}

BOOL FailWithErrno(NSError **error, int errorNumber)
{
    if (error != nullptr)
    {
        *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errorNumber userInfo:nil];
    }
    return NO;
}

BOOL DictionaryMatchesFingerprint(NSURL *dictionary, NSString *fingerprint)
{
    if (fingerprint.length != CC_SHA256_DIGEST_LENGTH * 2)
    {
        return NO;
    }

    NSString *normalizedFingerprint = fingerprint.lowercaseString;
    NSCharacterSet *nonHexadecimal = [[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"]
        invertedSet];
    if ([normalizedFingerprint rangeOfCharacterFromSet:nonHexadecimal].location != NSNotFound)
    {
        return NO;
    }

    const int descriptor = open(dictionary.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (descriptor < 0)
    {
        return NO;
    }

    CC_SHA256_CTX context;
    BOOL succeeded = CC_SHA256_Init(&context) == 1;
    unsigned char buffer[64 * 1024];
    while (succeeded)
    {
        const ssize_t bytesRead = read(descriptor, buffer, sizeof(buffer));
        if (bytesRead > 0)
        {
            succeeded = CC_SHA256_Update(&context, buffer, static_cast<CC_LONG>(bytesRead)) == 1;
            continue;
        }
        if (bytesRead == 0)
        {
            break;
        }
        if (errno != EINTR)
        {
            succeeded = NO;
        }
    }
    close(descriptor);
    if (!succeeded)
    {
        return NO;
    }

    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    if (CC_SHA256_Final(digest, &context) != 1)
    {
        return NO;
    }
    NSMutableString *actualFingerprint = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (unsigned char byte : digest)
    {
        [actualFingerprint appendFormat:@"%02x", byte];
    }
    return [actualFingerprint isEqualToString:normalizedFingerprint];
}

std::string FileSystemPath(NSURL *url)
{
    const char *path = url.fileSystemRepresentation;
    return path == nullptr ? std::string{} : std::string(path);
}

BOOL IsUsableDictionary(NSURL *dictionary)
{
    const std::string path = FileSystemPath(dictionary);
    if (path.empty())
    {
        return NO;
    }

    sqlite3 *database = nullptr;
    if (sqlite3_open_v2(path.c_str(), &database, SQLITE_OPEN_READONLY, nullptr) != SQLITE_OK)
    {
        sqlite3_close(database);
        return NO;
    }

    sqlite3_stmt *integrityStatement = nullptr;
    BOOL integrityValid = sqlite3_prepare_v2(database, "PRAGMA quick_check(1)", -1, &integrityStatement, nullptr) ==
                              SQLITE_OK &&
                          sqlite3_step(integrityStatement) == SQLITE_ROW;
    if (integrityValid)
    {
        const unsigned char *result = sqlite3_column_text(integrityStatement, 0);
        integrityValid = result != nullptr && std::string(reinterpret_cast<const char *>(result)) == "ok";
    }
    sqlite3_finalize(integrityStatement);

    sqlite3_stmt *schemaStatement = nullptr;
    BOOL schemaValid = integrityValid &&
                       sqlite3_prepare_v2(database,
                                          "SELECT 1 FROM sqlite_master WHERE type='table' AND name GLOB 'tbl_*' "
                                          "LIMIT 1",
                                          -1, &schemaStatement, nullptr) == SQLITE_OK &&
                       sqlite3_step(schemaStatement) == SQLITE_ROW;
    sqlite3_finalize(schemaStatement);
    sqlite3_close(database);
    return schemaValid;
}

NSString *ResetBackupName(NSString *fileName, NSString *identifier)
{
    return [NSString stringWithFormat:@".%@.reset-backup.%@", fileName, identifier];
}

NSURL *ResetTemporaryDictionary(NSURL *dataDirectory, NSString *identifier)
{
    return [dataDirectory URLByAppendingPathComponent:
                              [@".msime.db.resetting." stringByAppendingString:identifier]];
}

NSURL *ResetTemporaryFingerprint(NSURL *dataDirectory, NSString *identifier)
{
    return [dataDirectory URLByAppendingPathComponent:
                              [@".msime.db.sha256.resetting." stringByAppendingString:identifier]];
}

BOOL SyncURL(NSURL *url, BOOL directory, NSError **error)
{
    int flags = O_RDONLY | O_CLOEXEC;
#ifdef O_DIRECTORY
    if (directory)
    {
        flags |= O_DIRECTORY;
    }
#else
    (void)directory;
#endif
    const int descriptor = open(url.fileSystemRepresentation, flags);
    if (descriptor < 0)
    {
        return FailWithErrno(error, errno);
    }
    int result = fcntl(descriptor, F_FULLFSYNC);
    int errorNumber = errno;
    if (result != 0 && (errorNumber == EINVAL || errorNumber == ENOTSUP))
    {
        result = fsync(descriptor);
        errorNumber = errno;
    }
    close(descriptor);
    return result == 0 ? YES : FailWithErrno(error, errorNumber);
}

BOOL RemoveIfPresent(NSFileManager *fileManager, NSURL *url, NSError **error)
{
    return ![fileManager fileExistsAtPath:url.path] || [fileManager removeItemAtURL:url error:error];
}

BOOL WriteResetMarker(NSURL *dataDirectory, NSString *identifier, NSString *phase,
                      NSArray<NSString *> *originalFileNames, NSError **error)
{
    NSDictionary *marker = @{
        @"version": @1,
        @"identifier": identifier,
        @"phase": phase,
        @"originalFileNames": originalFileNames,
    };
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:marker
                                                               format:NSPropertyListBinaryFormat_v1_0
                                                              options:0
                                                                error:error];
    if (data == nil)
    {
        return NO;
    }

    NSURL *markerURL = [dataDirectory URLByAppendingPathComponent:MetasequoiaResetMarkerName];
    NSURL *temporaryMarker = [dataDirectory
        URLByAppendingPathComponent:[@".metasequoia-learning-reset.tmp." stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![data writeToURL:temporaryMarker options:0 error:error] || !SyncURL(temporaryMarker, NO, error))
    {
        [[NSFileManager defaultManager] removeItemAtURL:temporaryMarker error:nil];
        return NO;
    }
    if (rename(temporaryMarker.fileSystemRepresentation, markerURL.fileSystemRepresentation) != 0)
    {
        const int errorNumber = errno;
        [[NSFileManager defaultManager] removeItemAtURL:temporaryMarker error:nil];
        return FailWithErrno(error, errorNumber);
    }
    return SyncURL(dataDirectory, YES, error);
}

NSDictionary *ReadResetMarker(NSURL *markerURL, NSError **error)
{
    NSData *data = [NSData dataWithContentsOfURL:markerURL options:0 error:error];
    if (data == nil)
    {
        return nil;
    }
    id marker = [NSPropertyListSerialization propertyListWithData:data
                                                          options:NSPropertyListImmutable
                                                           format:nil
                                                            error:error];
    if (![marker isKindOfClass:[NSDictionary class]])
    {
        Fail(error, 7, @"The learned-data reset recovery marker is invalid.");
        return nil;
    }
    return marker;
}

BOOL ValidateResetMarker(NSDictionary *marker, NSString **identifier, NSString **phase,
                         NSArray<NSString *> **originalFileNames, NSError **error)
{
    id version = marker[@"version"];
    id markerIdentifier = marker[@"identifier"];
    id markerPhase = marker[@"phase"];
    id names = marker[@"originalFileNames"];
    if (![version isKindOfClass:[NSNumber class]] || [version integerValue] != 1 ||
        ![markerIdentifier isKindOfClass:[NSString class]] ||
        [[NSUUID alloc] initWithUUIDString:markerIdentifier] == nil ||
        ![markerPhase isKindOfClass:[NSString class]] ||
        (![markerPhase isEqualToString:MetasequoiaResetPreparedPhase] &&
         ![markerPhase isEqualToString:MetasequoiaResetBackedUpPhase] &&
         ![markerPhase isEqualToString:MetasequoiaResetRollingBackPhase] &&
         ![markerPhase isEqualToString:MetasequoiaResetCommittedPhase]) ||
        ![names isKindOfClass:[NSArray class]])
    {
        return Fail(error, 7, @"The learned-data reset recovery marker is invalid.");
    }

    NSSet<NSString *> *allowedNames = [NSSet setWithArray:MutableDictionaryFileNames()];
    NSMutableSet<NSString *> *seenNames = [NSMutableSet set];
    for (id name in names)
    {
        if (![name isKindOfClass:[NSString class]] || ![allowedNames containsObject:name] ||
            [seenNames containsObject:name])
        {
            return Fail(error, 7, @"The learned-data reset recovery marker is invalid.");
        }
        [seenNames addObject:name];
    }
    *identifier = markerIdentifier;
    *phase = markerPhase;
    *originalFileNames = names;
    return YES;
}

BOOL RecoverPreparedReset(NSFileManager *fileManager, NSURL *dataDirectory, NSString *identifier,
                          NSArray<NSString *> *originalFileNames, BOOL rollbackWasStarted, NSError **error)
{
    NSSet<NSString *> *originalNames = [NSSet setWithArray:originalFileNames];
    for (NSString *fileName in MutableDictionaryFileNames())
    {
        NSURL *original = [dataDirectory URLByAppendingPathComponent:fileName];
        NSURL *backup = [dataDirectory URLByAppendingPathComponent:ResetBackupName(fileName, identifier)];
        if ([fileManager fileExistsAtPath:backup.path])
        {
            if (!RemoveIfPresent(fileManager, original, error) ||
                ![fileManager moveItemAtURL:backup toURL:original error:error])
            {
                return NO;
            }
        }
        else if ([originalNames containsObject:fileName] &&
                 ![fileManager fileExistsAtPath:original.path])
        {
            return Fail(error, 9, rollbackWasStarted
                                      ? @"A learned-data reset rollback cannot find an original or backup file."
                                      : @"A prepared learned-data reset cannot find an original or backup file.");
        }
        else if (![originalNames containsObject:fileName] &&
                 ([fileName isEqualToString:@"msime.db"] || [fileName isEqualToString:@"msime.db.sha256"]) &&
                 !RemoveIfPresent(fileManager, original, error))
        {
            return NO;
        }
    }
    if (!RemoveIfPresent(fileManager, ResetTemporaryDictionary(dataDirectory, identifier), error) ||
        !RemoveIfPresent(fileManager, ResetTemporaryFingerprint(dataDirectory, identifier), error))
    {
        return NO;
    }
    return SyncURL(dataDirectory, YES, error);
}

BOOL CleanupCommittedReset(NSFileManager *fileManager, NSURL *dataDirectory, NSString *identifier,
                           NSArray<NSString *> *originalFileNames, NSError **error)
{
    for (NSString *fileName in originalFileNames)
    {
        NSURL *backup = [dataDirectory URLByAppendingPathComponent:ResetBackupName(fileName, identifier)];
        if (!RemoveIfPresent(fileManager, backup, error))
        {
            return NO;
        }
    }
    if (!RemoveIfPresent(fileManager, ResetTemporaryDictionary(dataDirectory, identifier), error) ||
        !RemoveIfPresent(fileManager, ResetTemporaryFingerprint(dataDirectory, identifier), error))
    {
        return NO;
    }
    return SyncURL(dataDirectory, YES, error);
}

BOOL CleanupOrphanedResetTemporaryFiles(NSFileManager *fileManager, NSURL *dataDirectory, NSError **error)
{
    NSArray<NSURL *> *contents = [fileManager contentsOfDirectoryAtURL:dataDirectory
                                             includingPropertiesForKeys:nil
                                                                options:0
                                                                  error:error];
    if (contents == nil)
    {
        return NO;
    }
    BOOL removedFile = NO;
    for (NSURL *item in contents)
    {
        NSString *name = item.lastPathComponent;
        // The install and the helpcode refresh stage under their own UUID and only unwind on the
        // error paths inside their own function, so a process killed mid-copy leaked the staged
        // file forever — a full dictionary copy in the case of .msime.db.installing. Every caller
        // reaches this sweep before staging anything of its own.
        if (![name hasPrefix:@".msime.db.resetting."] &&
            ![name hasPrefix:@".msime.db.sha256.resetting."] &&
            ![name hasPrefix:@".msime.db.installing."] &&
            ![name hasPrefix:@".helpcodes.installing."] &&
            ![name hasPrefix:@".helpcodes.backup."] &&
            ![name hasPrefix:@".metasequoia-learning-reset.tmp."])
        {
            continue;
        }
        if (![fileManager removeItemAtURL:item error:error])
        {
            return NO;
        }
        removedFile = YES;
    }
    return !removedFile || SyncURL(dataDirectory, YES, error);
}

BOOL RecoverLearningReset(NSFileManager *fileManager, NSURL *dataDirectory, NSError **error)
{
    NSURL *markerURL = [dataDirectory URLByAppendingPathComponent:MetasequoiaResetMarkerName];
    if (![fileManager fileExistsAtPath:markerURL.path])
    {
        return CleanupOrphanedResetTemporaryFiles(fileManager, dataDirectory, error);
    }

    NSDictionary *marker = ReadResetMarker(markerURL, error);
    NSString *identifier = nil;
    NSString *phase = nil;
    NSArray<NSString *> *originalFileNames = nil;
    if (marker == nil || !ValidateResetMarker(marker, &identifier, &phase, &originalFileNames, error))
    {
        return NO;
    }

    if ([phase isEqualToString:MetasequoiaResetBackedUpPhase])
    {
        for (NSString *fileName in originalFileNames)
        {
            NSURL *backup = [dataDirectory URLByAppendingPathComponent:ResetBackupName(fileName, identifier)];
            if (![fileManager fileExistsAtPath:backup.path])
            {
                return Fail(error, 9, @"A durable learned-data reset backup is missing.");
            }
        }
        if (!WriteResetMarker(dataDirectory, identifier, MetasequoiaResetRollingBackPhase,
                              originalFileNames, error))
        {
            return NO;
        }
        phase = MetasequoiaResetRollingBackPhase;
    }

    const BOOL recovered = [phase isEqualToString:MetasequoiaResetCommittedPhase]
                               ? CleanupCommittedReset(fileManager, dataDirectory, identifier,
                                                       originalFileNames, error)
                               : RecoverPreparedReset(fileManager, dataDirectory, identifier,
                                                      originalFileNames,
                                                      [phase isEqualToString:MetasequoiaResetRollingBackPhase], error);
    if (!recovered || ![fileManager removeItemAtURL:markerURL error:error] ||
        !CleanupOrphanedResetTemporaryFiles(fileManager, dataDirectory, error))
    {
        return NO;
    }
    return SyncURL(dataDirectory, YES, error);
}
} // namespace

BOOL InstallMetasequoiaDictionary(NSURL *source, NSURL *dataDirectory, NSString *dictionaryFingerprint,
                                  NSError **error)
{
    if (error != nullptr)
    {
        *error = nil;
    }
    if (source == nil || dataDirectory == nil || dictionaryFingerprint.length == 0)
    {
        return Fail(error, 1, @"The bundled dictionary metadata is incomplete.");
    }

    @synchronized([NSFileManager class])
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager createDirectoryAtURL:dataDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:error] ||
            !RecoverLearningReset(fileManager, dataDirectory, error))
        {
            return NO;
        }
        NSDictionary<NSFileAttributeKey, id> *sourceAttributes =
            [fileManager attributesOfItemAtPath:source.path error:error];
        if (sourceAttributes == nil || sourceAttributes.fileSize == 0)
        {
            if (sourceAttributes != nil)
            {
                return Fail(error, 2, @"The bundled msime.db dictionary is empty.");
            }
            return NO;
        }
        NSURL *destination = [dataDirectory URLByAppendingPathComponent:@"msime.db" isDirectory:NO];
        NSURL *fingerprintFile = [dataDirectory URLByAppendingPathComponent:@"msime.db.sha256" isDirectory:NO];
        const BOOL destinationExists = [fileManager fileExistsAtPath:destination.path];
        NSString *installedFingerprint = nil;
        if (destinationExists)
        {
            NSDictionary<NSFileAttributeKey, id> *destinationAttributes =
                [fileManager attributesOfItemAtPath:destination.path error:error];
            if (destinationAttributes == nil)
            {
                return NO;
            }

            installedFingerprint =
                [NSString stringWithContentsOfURL:fingerprintFile encoding:NSUTF8StringEncoding error:nil];
            if (destinationAttributes.fileSize > 0 && [installedFingerprint isEqualToString:dictionaryFingerprint])
            {
                return YES;
            }
        }

        NSString *temporaryName = [@".msime.db.installing." stringByAppendingString:NSUUID.UUID.UUIDString];
        NSURL *temporary = [dataDirectory URLByAppendingPathComponent:temporaryName isDirectory:NO];
        if (![fileManager copyItemAtURL:source toURL:temporary error:error])
        {
            [fileManager removeItemAtURL:temporary error:nil];
            return NO;
        }
        if (!IsUsableDictionary(temporary))
        {
            [fileManager removeItemAtURL:temporary error:nil];
            return Fail(error, 2, @"The bundled msime.db dictionary is invalid.");
        }
        if (!DictionaryMatchesFingerprint(temporary, dictionaryFingerprint))
        {
            [fileManager removeItemAtURL:temporary error:nil];
            return Fail(error, 2, @"The bundled msime.db dictionary fingerprint does not match its contents.");
        }
        if (destinationExists && installedFingerprint == nil &&
            [fileManager contentsEqualAtPath:temporary.path andPath:destination.path])
        {
            if (![fileManager removeItemAtURL:temporary error:error])
            {
                return NO;
            }
            return [dictionaryFingerprint writeToURL:fingerprintFile
                                          atomically:YES
                                            encoding:NSUTF8StringEncoding
                                               error:error];
        }

        NSURL *userDatabase = [dataDirectory URLByAppendingPathComponent:@"msime_user.db" isDirectory:NO];
        NSURL *englishDatabase = [dataDirectory URLByAppendingPathComponent:@"msime_english.db" isDirectory:NO];
        if ([fileManager fileExistsAtPath:userDatabase.path] &&
            ![fileManager fileExistsAtPath:englishDatabase.path] &&
            ![fileManager createFileAtPath:englishDatabase.path contents:nil attributes:nil])
        {
            [fileManager removeItemAtURL:temporary error:nil];
            return Fail(error, 3, @"The English user dictionary could not be prepared for replay.");
        }
        const auto replay = user_dictionary::replay(FileSystemPath(userDatabase), FileSystemPath(temporary),
                                                    FileSystemPath(englishDatabase));
        if (replay.failed != 0 || !replay.error.empty())
        {
            [fileManager removeItemAtURL:temporary error:nil];
            NSString *description = [NSString
                stringWithFormat:@"User dictionary replay failed (%d operation(s)): %s", replay.failed,
                                 replay.error.c_str()];
            return Fail(error, 3, description);
        }

        BOOL installed = NO;
        if (destinationExists)
        {
            installed = [fileManager replaceItemAtURL:destination
                                        withItemAtURL:temporary
                                       backupItemName:nil
                                              options:0
                                     resultingItemURL:nil
                                                error:error];
        }
        else
        {
            installed = [fileManager moveItemAtURL:temporary toURL:destination error:error];
        }
        if (!installed)
        {
            [fileManager removeItemAtURL:temporary error:nil];
            return NO;
        }

        // A rollback journal carries no identity of the database it belongs to, so one left behind
        // by an unclean shutdown would be replayed onto whatever now sits at the msime.db path —
        // here, a different dictionary. The reset path already discards these; the swap has to as
        // well. Removed after the swap, never before, so a failure here cannot strip a live
        // database of the journal it still needs.
        for (NSString *sidecarName in @[@"msime.db-journal", @"msime.db-wal", @"msime.db-shm"])
        {
            NSURL *sidecar = [dataDirectory URLByAppendingPathComponent:sidecarName isDirectory:NO];
            if (!RemoveIfPresent(fileManager, sidecar, error))
            {
                return NO;
            }
        }

        return [dictionaryFingerprint writeToURL:fingerprintFile
                                      atomically:YES
                                        encoding:NSUTF8StringEncoding
                                           error:error];
    }
}

BOOL ResetMetasequoiaLearnedData(NSURL *source, NSURL *dataDirectory, NSString *dictionaryFingerprint,
                                 NSError **error)
{
    if (error != nullptr)
    {
        *error = nil;
    }
    if (source == nil || dataDirectory == nil || dictionaryFingerprint.length == 0)
    {
        return Fail(error, 5, @"The bundled dictionary metadata is incomplete.");
    }
    @synchronized([NSFileManager class])
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager createDirectoryAtURL:dataDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:error] ||
            !RecoverLearningReset(fileManager, dataDirectory, error))
        {
            return NO;
        }

        NSString *identifier = NSUUID.UUID.UUIDString;
        NSURL *temporaryDictionary = ResetTemporaryDictionary(dataDirectory, identifier);
        NSURL *temporaryFingerprint = ResetTemporaryFingerprint(dataDirectory, identifier);
        if (![fileManager copyItemAtURL:source toURL:temporaryDictionary error:error])
        {
            [fileManager removeItemAtURL:temporaryDictionary error:nil];
            return NO;
        }
        if (!IsUsableDictionary(temporaryDictionary))
        {
            [fileManager removeItemAtURL:temporaryDictionary error:nil];
            return Fail(error, 6, @"The bundled dictionary cannot be used to reset learned data.");
        }
        if (!DictionaryMatchesFingerprint(temporaryDictionary, dictionaryFingerprint))
        {
            [fileManager removeItemAtURL:temporaryDictionary error:nil];
            return Fail(error, 6, @"The bundled dictionary fingerprint does not match its contents.");
        }
        if (![dictionaryFingerprint writeToURL:temporaryFingerprint
                                    atomically:YES
                                      encoding:NSUTF8StringEncoding
                                         error:error])
        {
            [fileManager removeItemAtURL:temporaryDictionary error:nil];
            return NO;
        }
        if (!SyncURL(temporaryDictionary, NO, error) || !SyncURL(temporaryFingerprint, NO, error) ||
            !SyncURL(dataDirectory, YES, error))
        {
            [fileManager removeItemAtURL:temporaryDictionary error:nil];
            [fileManager removeItemAtURL:temporaryFingerprint error:nil];
            return NO;
        }

        user_dictionary::close_default_user_database();
        ime_pinyin::im_close_decoder();

        NSMutableArray<NSString *> *originalFileNames = [NSMutableArray array];
        for (NSString *fileName in MutableDictionaryFileNames())
        {
            NSURL *original = [dataDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
            if ([fileManager fileExistsAtPath:original.path])
            {
                [originalFileNames addObject:fileName];
            }
        }
        if (!WriteResetMarker(dataDirectory, identifier, MetasequoiaResetPreparedPhase,
                              originalFileNames, error))
        {
            [fileManager removeItemAtURL:temporaryDictionary error:nil];
            [fileManager removeItemAtURL:temporaryFingerprint error:nil];
            return NO;
        }

        for (NSString *fileName in originalFileNames)
        {
            NSURL *original = [dataDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
            NSURL *backup = [dataDirectory URLByAppendingPathComponent:ResetBackupName(fileName, identifier)
                                                           isDirectory:NO];
            if (![fileManager moveItemAtURL:original toURL:backup error:error])
            {
                NSError *operationError = error == nullptr ? nil : *error;
                NSError *recoveryError = nil;
                if (!RecoverLearningReset(fileManager, dataDirectory, &recoveryError))
                {
                    return Fail(error, 8,
                                [NSString stringWithFormat:@"The learned-data reset failed and rollback could not finish: %@",
                                                           recoveryError.localizedDescription]);
                }
                if (error != nullptr)
                {
                    *error = operationError;
                }
                return NO;
            }
        }

        if (!SyncURL(dataDirectory, YES, error))
        {
            NSError *operationError = error == nullptr ? nil : *error;
            NSError *recoveryError = nil;
            if (!RecoverLearningReset(fileManager, dataDirectory, &recoveryError))
            {
                return Fail(error, 8,
                            [NSString stringWithFormat:@"The learned-data reset failed and rollback could not finish: %@",
                                                       recoveryError.localizedDescription]);
            }
            if (error != nullptr)
            {
                *error = operationError;
            }
            return NO;
        }
        if (!WriteResetMarker(dataDirectory, identifier, MetasequoiaResetBackedUpPhase,
                              originalFileNames, error))
        {
            NSError *operationError = error == nullptr ? nil : *error;
            NSError *recoveryError = nil;
            if (!RecoverLearningReset(fileManager, dataDirectory, &recoveryError))
            {
                return Fail(error, 8,
                            [NSString stringWithFormat:@"The learned-data reset failed and rollback could not finish: %@",
                                                       recoveryError.localizedDescription]);
            }
            if (error != nullptr)
            {
                *error = operationError;
            }
            return NO;
        }

        NSURL *destination = [dataDirectory URLByAppendingPathComponent:@"msime.db" isDirectory:NO];
        NSURL *fingerprintFile = [dataDirectory URLByAppendingPathComponent:@"msime.db.sha256" isDirectory:NO];
        if (![fileManager moveItemAtURL:temporaryDictionary toURL:destination error:error] ||
            ![fileManager moveItemAtURL:temporaryFingerprint toURL:fingerprintFile error:error] ||
            !SyncURL(destination, NO, error) || !SyncURL(fingerprintFile, NO, error) ||
            !SyncURL(dataDirectory, YES, error))
        {
            NSError *operationError = error == nullptr ? nil : *error;
            NSError *recoveryError = nil;
            if (!RecoverLearningReset(fileManager, dataDirectory, &recoveryError))
            {
                return Fail(error, 8,
                            [NSString stringWithFormat:@"The learned-data reset failed and rollback could not finish: %@",
                                                       recoveryError.localizedDescription]);
            }
            if (error != nullptr)
            {
                *error = operationError;
            }
            return NO;
        }

        if (!WriteResetMarker(dataDirectory, identifier, MetasequoiaResetCommittedPhase,
                              originalFileNames, error))
        {
            NSError *operationError = error == nullptr ? nil : *error;
            NSError *recoveryError = nil;
            if (!RecoverLearningReset(fileManager, dataDirectory, &recoveryError))
            {
                return Fail(error, 8,
                            [NSString stringWithFormat:@"The learned-data reset failed and rollback could not finish: %@",
                                                       recoveryError.localizedDescription]);
            }
            if (error != nullptr)
            {
                *error = operationError;
            }
            return NO;
        }

        NSError *cleanupError = nil;
        if (!RecoverLearningReset(fileManager, dataDirectory, &cleanupError))
        {
            NSLog(@"Learned-data reset committed; deferred cleanup remains pending (%@:%ld).",
                  cleanupError.domain, static_cast<long>(cleanupError.code));
        }
        return YES;
    }
}

BOOL PrepareMetasequoiaDictionary(NSURL *source, NSURL *dataDirectory, NSString *dictionaryFingerprint,
                                  NSError **error)
{
    if (dataDirectory == nil)
    {
        return Fail(error, 1, @"The bundled dictionary metadata is incomplete.");
    }
    @synchronized([NSFileManager class])
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager createDirectoryAtURL:dataDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:error] ||
            !RecoverLearningReset(fileManager, dataDirectory, error))
        {
            return NO;
        }
    }

    NSError *installError = nil;
    if (InstallMetasequoiaDictionary(source, dataDirectory, dictionaryFingerprint, &installError))
    {
        if (error != nullptr)
        {
            *error = nil;
        }
        return YES;
    }

    NSURL *existingDictionary = [dataDirectory URLByAppendingPathComponent:@"msime.db" isDirectory:NO];
    if (IsUsableDictionary(existingDictionary))
    {
        NSLog(@"Bundled dictionary update failed; continuing with the validated existing dictionary.");
        if (error != nullptr)
        {
            *error = nil;
        }
        return YES;
    }

    if (installError != nil)
    {
        if (error != nullptr)
        {
            *error = installError;
        }
        return NO;
    }
    return Fail(error, 4, @"No usable Metasequoia dictionary is available.");
}

BOOL InstallMetasequoiaHelpCodes(NSURL *sourceDirectory, NSURL *dataDirectory, NSError **error)
{
    if (error != nullptr)
    {
        *error = nil;
    }
    if (sourceDirectory == nil || dataDirectory == nil)
    {
        return Fail(error, 10, @"The bundled helpcode metadata is incomplete.");
    }

    @synchronized([NSFileManager class])
    {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *fileName in HelpcodeFileNames())
        {
            NSURL *source = [sourceDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
            NSDictionary<NSFileAttributeKey, id> *attributes =
                [fileManager attributesOfItemAtPath:source.path error:error];
            if (attributes == nil || ![attributes.fileType isEqualToString:NSFileTypeRegular] ||
                attributes.fileSize == 0)
            {
                if (attributes != nil)
                {
                    Fail(error, 10,
                         [NSString stringWithFormat:@"The bundled helpcode table %@ is invalid.", fileName]);
                }
                return NO;
            }
        }

        if (![fileManager createDirectoryAtURL:dataDirectory
                    withIntermediateDirectories:YES
                                     attributes:nil
                                          error:error])
        {
            return NO;
        }

        NSString *identifier = NSUUID.UUID.UUIDString;
        NSURL *destination = [dataDirectory URLByAppendingPathComponent:@"helpcodes" isDirectory:YES];
        NSURL *staging = [dataDirectory
            URLByAppendingPathComponent:[@".helpcodes.installing." stringByAppendingString:identifier]
                             isDirectory:YES];
        NSURL *backup = [dataDirectory
            URLByAppendingPathComponent:[@".helpcodes.backup." stringByAppendingString:identifier]
                             isDirectory:YES];
        if (![fileManager createDirectoryAtURL:staging
                    withIntermediateDirectories:NO
                                     attributes:nil
                                          error:error])
        {
            return NO;
        }
        for (NSString *fileName in HelpcodeFileNames())
        {
            NSURL *source = [sourceDirectory URLByAppendingPathComponent:fileName isDirectory:NO];
            NSURL *stagedFile = [staging URLByAppendingPathComponent:fileName isDirectory:NO];
            if (![fileManager copyItemAtURL:source toURL:stagedFile error:error])
            {
                [fileManager removeItemAtURL:staging error:nil];
                return NO;
            }
        }

        BOOL hadDestination = [fileManager fileExistsAtPath:destination.path];
        if (hadDestination && ![fileManager moveItemAtURL:destination toURL:backup error:error])
        {
            [fileManager removeItemAtURL:staging error:nil];
            return NO;
        }
        if (![fileManager moveItemAtURL:staging toURL:destination error:error])
        {
            if (hadDestination)
            {
                [fileManager moveItemAtURL:backup toURL:destination error:nil];
            }
            [fileManager removeItemAtURL:staging error:nil];
            return NO;
        }
        if (hadDestination && ![fileManager removeItemAtURL:backup error:error])
        {
            return NO;
        }
        return YES;
    }
}

BOOL EnsureMetasequoiaDictionary(NSError **error)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationSupport = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                                    inDomain:NSUserDomainMask
                                           appropriateForURL:nil
                                                      create:YES
                                                       error:error];
    if (applicationSupport == nil)
    {
        return NO;
    }

    NSURL *dataDirectory = [applicationSupport URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
    NSURL *helpcodeSource = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"helpcodes"
                                                                    isDirectory:YES];
    if (!InstallMetasequoiaHelpCodes(helpcodeSource, dataDirectory, error))
    {
        return NO;
    }
    NSURL *source = [[NSBundle mainBundle] URLForResource:@"msime" withExtension:@"db"];
    NSString *fingerprint = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"MetasequoiaDictionarySHA256"];
    return PrepareMetasequoiaDictionary(source, dataDirectory, fingerprint, error);
}

BOOL ResetMetasequoiaLearnedDataForCurrentUser(NSError **error)
{
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSURL *applicationSupport = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                                    inDomain:NSUserDomainMask
                                           appropriateForURL:nil
                                                      create:YES
                                                       error:error];
    if (applicationSupport == nil)
    {
        return NO;
    }

    NSURL *dataDirectory = [applicationSupport URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
    NSURL *source = [[NSBundle mainBundle] URLForResource:@"msime" withExtension:@"db"];
    NSString *fingerprint = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"MetasequoiaDictionarySHA256"];
    return ResetMetasequoiaLearnedData(source, dataDirectory, fingerprint, error);
}
