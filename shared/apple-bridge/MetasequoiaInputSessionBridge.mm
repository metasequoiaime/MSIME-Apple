#import "MetasequoiaInputSessionBridge.h"

#include "InputSessionAdapter.h"
#include "ShuangpinKeymap.h"

#include <cstdlib>
#include <memory>
#include <string>
#include <utility>

namespace
{
NSString *StringFromUTF8(const std::string &value)
{
    NSString *string = [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
    return string == nil ? @"" : string;
}

BOOL InstallBundledDatabase(NSFileManager *fileManager, NSURL *dataDirectory, NSString *name)
{
    NSBundle *bundle = [NSBundle bundleForClass:MetasequoiaInputSessionBridge.class];
    NSURL *bundledDictionary = [bundle URLForResource:name withExtension:nil];
    NSURL *bundledDigest = [bundle URLForResource:name withExtension:@"sha256"];
    if (bundledDictionary == nil || bundledDigest == nil)
    {
        return NO;
    }

    NSString *expectedDigest = [NSString stringWithContentsOfURL:bundledDigest
                                                        encoding:NSASCIIStringEncoding
                                                           error:nil];
    expectedDigest = [expectedDigest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSURL *installedDictionary = [dataDirectory URLByAppendingPathComponent:name];
    NSURL *installedDigest = [dataDirectory URLByAppendingPathComponent:[name stringByAppendingString:@".sha256"]];
    NSString *currentDigest = [NSString stringWithContentsOfURL:installedDigest
                                                       encoding:NSASCIIStringEncoding
                                                          error:nil];
    currentDigest = [currentDigest stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (expectedDigest.length > 0 && [expectedDigest isEqualToString:currentDigest] &&
        [fileManager fileExistsAtPath:installedDictionary.path])
    {
        return YES;
    }

    NSURL *stagingDictionary =
        [dataDirectory URLByAppendingPathComponent:[name stringByAppendingString:@".installing"]];
    [fileManager removeItemAtURL:stagingDictionary error:nil];
    if (![fileManager copyItemAtURL:bundledDictionary toURL:stagingDictionary error:nil])
    {
        return NO;
    }

    BOOL installed = NO;
    if ([fileManager fileExistsAtPath:installedDictionary.path])
    {
        installed = [fileManager replaceItemAtURL:installedDictionary
                                    withItemAtURL:stagingDictionary
                                   backupItemName:nil
                                          options:0
                                 resultingItemURL:nil
                                            error:nil];
    }
    else
    {
        installed = [fileManager moveItemAtURL:stagingDictionary toURL:installedDictionary error:nil];
    }
    if (!installed)
    {
        [fileManager removeItemAtURL:stagingDictionary error:nil];
        return NO;
    }

    return [expectedDigest writeToURL:installedDigest atomically:YES encoding:NSASCIIStringEncoding error:nil];
}

void ConfigureDataDirectory()
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSFileManager *fileManager = NSFileManager.defaultManager;
      NSURL *applicationSupport = [fileManager URLForDirectory:NSApplicationSupportDirectory
                                                      inDomain:NSUserDomainMask
                                             appropriateForURL:nil
                                                        create:YES
                                                         error:nil];
      NSURL *dataDirectory = [applicationSupport URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
      if (dataDirectory != nil && [fileManager createDirectoryAtURL:dataDirectory
                                        withIntermediateDirectories:YES
                                                         attributes:nil
                                                              error:nil])
      {
          for (NSString *name in @[ @"msime.db", @"english.db", @"others.db", @"dict_japanese.dat" ])
          {
              InstallBundledDatabase(fileManager, dataDirectory, name);
          }
          setenv("METASEQUOIA_IME_DATA_DIR", dataDirectory.fileSystemRepresentation, 1);
      }
    });
}
} // namespace

@interface MetasequoiaInputSnapshot ()

- (instancetype)initWithHandled:(BOOL)handled
                     commitText:(nullable NSString *)commitText
                        preedit:(NSString *)preedit
                     candidates:(NSArray<NSString *> *)candidates
                 diagnosticText:(nullable NSString *)diagnosticText;

@end

@implementation MetasequoiaInputSnapshot

- (instancetype)initWithHandled:(BOOL)handled
                     commitText:(nullable NSString *)commitText
                        preedit:(NSString *)preedit
                     candidates:(NSArray<NSString *> *)candidates
                 diagnosticText:(nullable NSString *)diagnosticText
{
    self = [super init];
    if (self != nil)
    {
        _handled = handled;
        _commitText = [commitText copy];
        _preedit = [preedit copy];
        _candidates = [candidates copy];
        _diagnosticText = [diagnosticText copy];
    }
    return self;
}

@end

@implementation MetasequoiaInputSessionBridge
{
    std::unique_ptr<metasequoia::apple::InputSessionAdapter> _adapter;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        ConfigureDataDirectory();
        _adapter = std::make_unique<metasequoia::apple::InputSessionAdapter>();
    }
    return self;
}

- (MetasequoiaInputSnapshot *)handleCharacter:(NSString *)character
{
    const char *utf8 = character.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->handle_character('\0')];
    }
    return [self snapshotFrom:_adapter->handle_character(utf8[0])];
}

- (MetasequoiaInputSnapshot *)handleCandidateKey:(NSString *)character
{
    const char *utf8 = character.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->handle_candidate_key('\0')];
    }
    return [self snapshotFrom:_adapter->handle_candidate_key(utf8[0])];
}

- (MetasequoiaInputSnapshot *)handlePunctuation:(NSString *)character
{
    const char *utf8 = character.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->handle_punctuation('\0')];
    }
    return [self snapshotFrom:_adapter->handle_punctuation(utf8[0])];
}

- (MetasequoiaInputSnapshot *)handleBackspace
{
    return [self snapshotFrom:_adapter->handle_backspace()];
}

- (MetasequoiaInputSnapshot *)commitCandidate
{
    return [self snapshotFrom:_adapter->commit_candidate()];
}

- (MetasequoiaInputSnapshot *)finishComposition
{
    return [self snapshotFrom:_adapter->finish_composition()];
}

- (MetasequoiaInputSnapshot *)commitRaw
{
    return [self snapshotFrom:_adapter->commit_raw()];
}

- (MetasequoiaInputSnapshot *)cancel
{
    return [self snapshotFrom:_adapter->cancel()];
}

- (MetasequoiaInputSnapshot *)selectCandidateAtIndex:(NSUInteger)index
{
    return [self snapshotFrom:_adapter->select_candidate(static_cast<std::size_t>(index))];
}

- (MetasequoiaInputSnapshot *)editCandidateAtIndex:(NSUInteger)index
                                      expectedWord:(NSString *)word
                                            action:(MetasequoiaCandidateAction)action
{
    using metasequoia::apple::CandidateAction;
    CandidateAction operation;
    switch (action)
    {
    case MetasequoiaCandidateActionPromote:
        operation = CandidateAction::Promote;
        break;
    case MetasequoiaCandidateActionRemove:
        operation = CandidateAction::Remove;
        break;
    case MetasequoiaCandidateActionFixFirst:
        operation = CandidateAction::FixFirst;
        break;
    case MetasequoiaCandidateActionClearPosition:
        operation = CandidateAction::ClearPosition;
        break;
    default:
        return [self snapshotFrom:_adapter->handle_character('\0')];
    }
    return [self snapshotFrom:_adapter->edit_candidate(index, word.UTF8String ?: "", operation)];
}

- (MetasequoiaInputSnapshot *)switchToShuangpin:(BOOL)usesShuangpin
{
    return [self snapshotFrom:_adapter->switch_to_shuangpin(usesShuangpin)];
}

- (MetasequoiaInputSnapshot *)switchToShuangpinProfile:(NSString *)name
{
    return [self snapshotFrom:_adapter->switch_to_shuangpin_profile(name.UTF8String ?: "")];
}

- (MetasequoiaInputSnapshot *)switchToWubi
{
    return [self snapshotFrom:_adapter->switch_to_wubi()];
}
- (MetasequoiaInputSnapshot *)switchToJapanese
{
    return [self snapshotFrom:_adapter->switch_to_japanese()];
}

- (MetasequoiaInputSnapshot *)switchToNineKey
{
    return [self snapshotFrom:_adapter->switch_to_nine_key()];
}
- (MetasequoiaInputSnapshot *)chooseNineKeySpellingAtIndex:(NSUInteger)index
{
    return [self snapshotFrom:_adapter->choose_nine_key_spelling(index)];
}
- (NSArray<NSString *> *)nineKeySpellings
{
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    for (const auto &spelling : _adapter->nine_key_spellings())
        [result addObject:StringFromUTF8(spelling)];
    return result;
}

- (MetasequoiaInputSnapshot *)openLocalMode:(NSString *)trigger
{
    const char *utf8 = trigger.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->open_local_mode('\0')];
    }
    return [self snapshotFrom:_adapter->open_local_mode(utf8[0])];
}

- (BOOL)isInLocalMode
{
    return _adapter->in_local_mode();
}

- (BOOL)isInUnicodeMode
{
    return _adapter->in_unicode_mode() ? YES : NO;
}

- (NSDictionary<NSString *, NSString *> *)shuangpinKeyHints
{
    const auto hints =
        metasequoia::apple::shuangpin_key_hints(_adapter->uses_shuangpin(), _adapter->shuangpin_profile_name());
    NSMutableDictionary<NSString *, NSString *> *result = [NSMutableDictionary dictionaryWithCapacity:hints.size()];
    for (const auto &[key, hint] : hints)
    {
        result[StringFromUTF8(key)] = StringFromUTF8(hint);
    }
    return result;
}

- (MetasequoiaInputSnapshot *)snapshotFrom:(metasequoia::apple::InputSnapshot)snapshot
{
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithCapacity:snapshot.candidates.size()];
    for (const auto &candidate : snapshot.candidates)
    {
        [candidates addObject:StringFromUTF8(candidate)];
    }

    NSString *commitText = snapshot.commit.has_value() ? StringFromUTF8(*snapshot.commit) : nil;
    NSString *diagnosticText = snapshot.diagnostic.has_value() ? StringFromUTF8(*snapshot.diagnostic) : nil;
    return [[MetasequoiaInputSnapshot alloc] initWithHandled:snapshot.handled
                                                  commitText:commitText
                                                     preedit:StringFromUTF8(snapshot.preedit)
                                                  candidates:candidates
                                              diagnosticText:diagnosticText];
}

@end
