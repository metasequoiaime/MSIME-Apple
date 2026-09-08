#import "MetasequoiaInputSessionBridge.h"

#include "InputSessionAdapter.h"
#include "DictionaryInstallation.h"
#include "PersonalDictionaryBridge.h"
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

const metasequoia::apple::DictionaryInstallation &ConfigureDataDirectory()
{
    static metasequoia::apple::DictionaryInstallation installation;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      NSFileManager *manager = NSFileManager.defaultManager;
      NSURL *support = [manager URLForDirectory:NSApplicationSupportDirectory
                                       inDomain:NSUserDomainMask
                              appropriateForURL:nil
                                         create:YES
                                          error:nil];
      NSURL *cache = [manager URLForDirectory:NSCachesDirectory
                                     inDomain:NSUserDomainMask
                            appropriateForURL:nil
                                       create:YES
                                        error:nil];
      NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
      support = support ?: [home URLByAppendingPathComponent:@"Library/Application Support" isDirectory:YES];
      cache = cache ?: [home URLByAppendingPathComponent:@"Library/Caches" isDirectory:YES];
      NSURL *user = [support URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
      NSURL *resources = [NSBundle bundleForClass:MetasequoiaInputSessionBridge.class].resourceURL;
      installation = metasequoia::apple::PrepareDictionaryInstallation(
          resources, user, [cache URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES]);
    });
    return installation;
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
        const auto &installation = ConfigureDataDirectory();
        _adapter = std::make_unique<metasequoia::apple::InputSessionAdapter>(installation.paths);
    }
    return self;
}

- (BOOL)applyPersonalPrevious:(NSDictionary<NSString *, id> *)previous
                  replacement:(NSDictionary<NSString *, id> *)replacement
                    requestID:(NSString *)requestID
                        error:(NSError **)error
{
    auto oldEntry = previous ? metasequoia::apple::DecodePersonalWord(previous, error) : std::nullopt;
    auto newEntry = replacement ? metasequoia::apple::DecodePersonalWord(replacement, error) : std::nullopt;
    if ((previous && !oldEntry) || (replacement && !newEntry))
        return NO;
    const auto result = _adapter->edit_personal_word(oldEntry, newEntry, requestID.UTF8String ?: "");
    if (!result.success)
        metasequoia::apple::PersonalDictionaryError(error, result.error);
    return result.success;
}
- (NSDictionary<NSString *, id> *)personalEntriesAtOffset:(NSUInteger)offset error:(NSError **)error
{
    const auto page = _adapter->personal_words(offset, 100);
    if (!page.error.empty())
    {
        metasequoia::apple::PersonalDictionaryError(error, page.error);
        return nil;
    }
    NSMutableArray *entries = [NSMutableArray array];
    for (const auto &entry : page.entries)
        [entries addObject:metasequoia::apple::EncodePersonalWord(entry)];
    return @{@"entries" : entries, @"hasMore" : @(page.has_more)};
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

- (BOOL)setLearningEnabled:(BOOL)enabled
{
    return _adapter->set_learning_enabled(enabled);
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
    const auto &diagnostic = snapshot.diagnostic ? snapshot.diagnostic : ConfigureDataDirectory().diagnostic;
    NSString *diagnosticText = diagnostic ? StringFromUTF8(*diagnostic) : nil;
    return [[MetasequoiaInputSnapshot alloc] initWithHandled:snapshot.handled
                                                  commitText:commitText
                                                     preedit:StringFromUTF8(snapshot.preedit)
                                                  candidates:candidates
                                              diagnosticText:diagnosticText];
}

@end
