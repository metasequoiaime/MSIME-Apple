#import "MetasequoiaInputSessionBridge.h"

#include "InputSessionAdapter.h"
#include "DictionaryInstallation.h"
#include "DictionarySnapshotBridge.h"
#include "DictionarySessionLease.h"
#include "PersonalDictionaryBridge.h"
#include "ShuangpinKeymap.h"

#include <cstdlib>
#include <memory>
#include <mutex>
#include <string>
#include <utility>

namespace
{
NSString *StringFromUTF8(const std::string &value)
{
    NSString *string = [[NSString alloc] initWithBytes:value.data() length:value.size() encoding:NSUTF8StringEncoding];
    return string == nil ? @"" : string;
}

NSURL *UserDataRoot()
{
    NSFileManager *manager = NSFileManager.defaultManager;
    NSURL *support = [manager URLForDirectory:NSApplicationSupportDirectory
                                     inDomain:NSUserDomainMask
                            appropriateForURL:nil
                                       create:YES
                                        error:nil];
    NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
    support = support ?: [home URLByAppendingPathComponent:@"Library/Application Support" isDirectory:YES];
    return [support URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES];
}
metasequoia::apple::DictionaryInstallation ConfigureDataDirectory(bool refresh = false)
{
    static std::mutex mutex;
    std::lock_guard<std::mutex> guard(mutex);
    static metasequoia::apple::DictionaryInstallation installation;
    static dispatch_once_t onceToken;
    const auto prepare = [] {
        NSURL *cache = [NSFileManager.defaultManager URLForDirectory:NSCachesDirectory
                                                            inDomain:NSUserDomainMask
                                                   appropriateForURL:nil
                                                              create:YES
                                                               error:nil];
        NSURL *home = [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
        cache = cache ?: [home URLByAppendingPathComponent:@"Library/Caches" isDirectory:YES];
        return metasequoia::apple::PrepareDictionaryInstallation(
            [NSBundle bundleForClass:MetasequoiaInputSessionBridge.class].resourceURL, UserDataRoot(),
            [cache URLByAppendingPathComponent:@"metasequoiaime" isDirectory:YES]);
    };
    dispatch_once(&onceToken, ^{
      installation = prepare();
    });
    if (!refresh)
        return installation;
    // A process may outlive all its keyboard controllers while another process
    // publishes a new generation. Its next bridge must not reuse cached old paths.
    try
    {
        NSString *active = metasequoia::apple::ActiveDictionarySnapshotIdentifier(UserDataRoot());
        const auto root = std::filesystem::path(UserDataRoot().fileSystemRepresentation);
        const auto expected = active.length ? root / "snapshot-generations" / active.UTF8String / "user" : root;
        if (installation.paths.user_data != expected)
            installation = prepare();
    }
    catch (const std::exception &)
    {
        installation = prepare();
    }
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
    std::unique_ptr<metasequoia::apple::DictionarySessionLease> _sessionLease;
    std::unique_ptr<metasequoia::apple::InputSessionAdapter> _adapter;
    std::optional<std::string> _installationDiagnostic;
    bool _suspended;
    bool _requestedLearning;
}

- (instancetype)init
{
    self = [super init];
    if (self != nil)
    {
        try
        {
            _sessionLease = std::make_unique<metasequoia::apple::DictionarySessionLease>(UserDataRoot());
        }
        catch (const std::exception &)
        { /* Keep typing available with learning and edits disabled. */
        }
        const auto &installation = ConfigureDataDirectory(true);
        _adapter = std::make_unique<metasequoia::apple::InputSessionAdapter>(installation.paths);
        _installationDiagnostic = installation.diagnostic;
    }
    return self;
}

- (BOOL)suspendDictionarySession
{
    if (_suspended)
        return YES;
    if (!_adapter->idle())
        return NO;
    try
    {
        if (!_adapter->set_learning_enabled(false))
            return NO;
        _suspended = true;
        _sessionLease.reset();
        return YES;
    }
    catch (const std::exception &)
    {
        return NO;
    }
}

- (BOOL)resumeDictionarySessionWithError:(NSError **)error
{
    if (_sessionLease && !_suspended)
        return YES;
    try
    {
        if (!_sessionLease)
            _sessionLease = std::make_unique<metasequoia::apple::DictionarySessionLease>(UserDataRoot());
        const auto installation = ConfigureDataDirectory(true);
        if (!_adapter->activate_dictionary_generation(installation.paths, [] {}) ||
            !_adapter->set_learning_enabled(_requestedLearning))
            throw std::runtime_error("Cannot resume dictionary session");
        _installationDiagnostic = installation.diagnostic;
        _suspended = false;
        return YES;
    }
    catch (const std::exception &)
    {
        _sessionLease.reset();
        try
        {
            _suspended = !_adapter->set_learning_enabled(false);
        }
        catch (const std::exception &)
        {
            _suspended = true;
        }
        if (error)
            *error =
                [NSError errorWithDomain:@"app.msime.snapshot"
                                    code:2
                                userInfo:@{NSLocalizedDescriptionKey : @"词库会话恢复未完成，请重新打开键盘后重试。"}];
        return NO;
    }
}

- (MetasequoiaInputSnapshot *)suspendedSnapshot
{
    return [[MetasequoiaInputSnapshot alloc] initWithHandled:NO
                                                  commitText:nil
                                                     preedit:@""
                                                  candidates:@[]
                                              diagnosticText:nil];
}

- (NSString *)localDictionaryStateVersionWithError:(NSError **)error
{
    try
    {
        const auto paths = _adapter->runtime_paths();
        std::string generation = "legacy";
        if (paths.user_data.filename() == "user" &&
            paths.user_data.parent_path().parent_path().filename() == "snapshot-generations")
            generation = paths.user_data.parent_path().filename().string();
        return StringFromUTF8("local-v1:" + generation + ":" + metasequoia::apple::DictionaryStateRevision(paths));
    }
    catch (const std::exception &)
    {
        if (error)
            *error = [NSError errorWithDomain:@"app.msime.snapshot"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey : @"无法读取本地词库版本，请稍后重试。"}];
        return nil;
    }
}

- (NSDictionary<NSString *, id> *)dictionarySnapshotContextWithError:(NSError **)error
{
    try
    {
        if (!_sessionLease)
            throw std::runtime_error("Dictionary lease unavailable");
        const auto paths = _adapter->runtime_paths();
        NSString *version = [self localDictionaryStateVersionWithError:error];
        if (!version)
            return nil;
        return @{
            @"resources" : [NSURL fileURLWithFileSystemRepresentation:paths.resources.c_str()
                                                          isDirectory:YES
                                                        relativeToURL:nil],
            @"user" : UserDataRoot(),
            @"contentIdentifier" : StringFromUTF8(paths.dictionaries.filename().string()),
            @"localVersion" : version
        };
    }
    catch (const std::exception &)
    {
        if (error)
            *error = [NSError errorWithDomain:@"app.msime.snapshot"
                                         code:2
                                     userInfo:@{NSLocalizedDescriptionKey : @"本地词库尚未准备完成，请稍后重试。"}];
        return nil;
    }
}

- (BOOL)activateDictionarySnapshot:(MSIMEPreparedDictionarySnapshot *)snapshot
                   expectedVersion:(NSString *)expectedVersion
                             error:(NSError **)error
{
    NSError *failure = nil;
    bool activated = false;
    try
    {
        if (!_sessionLease)
            throw std::runtime_error("Dictionary lease unavailable");
        const bool exclusive = _sessionLease->exclusively([&] {
            NSString *active = metasequoia::apple::ActiveDictionarySnapshotIdentifier(UserDataRoot());
            if ([active isEqualToString:snapshot.identifier])
            {
                activated = true;
                return;
            }
            NSString *version = [self localDictionaryStateVersionWithError:&failure];
            if (!version || ![version isEqualToString:expectedVersion])
            {
                if (!failure)
                    failure = [NSError
                        errorWithDomain:@"app.msime.snapshot"
                                   code:409
                               userInfo:@{NSLocalizedDescriptionKey : @"本地词库已变化，请重新确认后再应用。"}];
                return;
            }
            // Allocate everything before publishing; the adapter swaps ownership
            // only after publication. New bridges resolve the durable pointer.
            auto replacement = snapshot.runtimePaths;
            activated = _adapter->activate_dictionary_generation(replacement, [&] {
                metasequoia::apple::PublishDictionaryInstallation(UserDataRoot(), snapshot.identifier, replacement,
                                                                  active);
            });
            if (activated)
            {
                _installationDiagnostic.reset();
            }
        });
        if ((!exclusive || !activated) && !failure)
            failure = [NSError errorWithDomain:@"app.msime.snapshot"
                                          code:423
                                      userInfo:@{NSLocalizedDescriptionKey : @"键盘会话正在使用词库，空闲后将重试。"}];
    }
    catch (const std::exception &)
    {
        failure = [NSError errorWithDomain:@"app.msime.snapshot"
                                      code:1
                                  userInfo:@{NSLocalizedDescriptionKey : @"词库切换未完成，已保留原有数据。"}];
    }
    if (!activated && error)
        *error = failure;
    return activated;
}

- (BOOL)applyPersonalPrevious:(NSDictionary<NSString *, id> *)previous
                  replacement:(NSDictionary<NSString *, id> *)replacement
                    requestID:(NSString *)requestID
                        error:(NSError **)error
{
    if (!_sessionLease)
    {
        metasequoia::apple::PersonalDictionaryError(error, "词库锁暂不可用，请重新打开键盘后重试。");
        return NO;
    }
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
    if (_suspended)
        return [self suspendedSnapshot];
    const char *utf8 = character.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->handle_character('\0')];
    }
    return [self snapshotFrom:_adapter->handle_character(utf8[0])];
}

- (MetasequoiaInputSnapshot *)handleCandidateKey:(NSString *)character
{
    if (_suspended)
        return [self suspendedSnapshot];
    const char *utf8 = character.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->handle_candidate_key('\0')];
    }
    return [self snapshotFrom:_adapter->handle_candidate_key(utf8[0])];
}

- (MetasequoiaInputSnapshot *)handlePunctuation:(NSString *)character
{
    if (_suspended)
        return [self suspendedSnapshot];
    const char *utf8 = character.UTF8String;
    if (utf8 == nullptr || utf8[0] == '\0' || utf8[1] != '\0')
    {
        return [self snapshotFrom:_adapter->handle_punctuation('\0')];
    }
    return [self snapshotFrom:_adapter->handle_punctuation(utf8[0])];
}

- (MetasequoiaInputSnapshot *)handleBackspace
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->handle_backspace()];
}

- (MetasequoiaInputSnapshot *)commitCandidate
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->commit_candidate()];
}

- (MetasequoiaInputSnapshot *)finishComposition
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->finish_composition()];
}

- (MetasequoiaInputSnapshot *)commitRaw
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->commit_raw()];
}

- (MetasequoiaInputSnapshot *)cancel
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->cancel()];
}

- (MetasequoiaInputSnapshot *)selectCandidateAtIndex:(NSUInteger)index
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->select_candidate(static_cast<std::size_t>(index))];
}

- (BOOL)setFuzzyPinyinRules:(uint32_t)rules
{
    return _adapter->set_fuzzy_pinyin_rules(rules);
}

- (void)setWubiMixedPinyin:(BOOL)enabled
{
    _adapter->set_wubi_mixed_pinyin(enabled);
}

- (BOOL)setLearningEnabled:(BOOL)enabled
{
    _requestedLearning = enabled;
    if (enabled && !_sessionLease)
        return NO;
    return _adapter->set_learning_enabled(enabled);
}

- (MetasequoiaInputSnapshot *)editCandidateAtIndex:(NSUInteger)index
                                      expectedWord:(NSString *)word
                                            action:(MetasequoiaCandidateAction)action
{
    if (_suspended)
        return [self suspendedSnapshot];
    if (!_sessionLease)
        return [self snapshotFrom:_adapter->handle_character('\0')];
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
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->switch_to_shuangpin(usesShuangpin)];
}

- (MetasequoiaInputSnapshot *)switchToShuangpinProfile:(NSString *)name
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->switch_to_shuangpin_profile(name.UTF8String ?: "")];
}

- (MetasequoiaInputSnapshot *)switchToWubi
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->switch_to_wubi()];
}
- (MetasequoiaInputSnapshot *)switchToJapanese
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->switch_to_japanese()];
}

- (MetasequoiaInputSnapshot *)switchToNineKey
{
    if (_suspended)
        return [self suspendedSnapshot];
    return [self snapshotFrom:_adapter->switch_to_nine_key()];
}
- (MetasequoiaInputSnapshot *)chooseNineKeySpellingAtIndex:(NSUInteger)index
{
    if (_suspended)
        return [self suspendedSnapshot];
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
    if (_suspended)
        return [self suspendedSnapshot];
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
    if (_suspended)
        return [self suspendedSnapshot];
    if (!_sessionLease)
        snapshot.diagnostic = "词库锁暂不可用，已暂停学习和词库修改。";
    NSMutableArray<NSString *> *candidates = [NSMutableArray arrayWithCapacity:snapshot.candidates.size()];
    for (const auto &candidate : snapshot.candidates)
    {
        [candidates addObject:StringFromUTF8(candidate)];
    }

    NSString *commitText = snapshot.commit.has_value() ? StringFromUTF8(*snapshot.commit) : nil;
    const auto &diagnostic = snapshot.diagnostic ? snapshot.diagnostic : _installationDiagnostic;
    NSString *diagnosticText = diagnostic ? StringFromUTF8(*diagnostic) : nil;
    return [[MetasequoiaInputSnapshot alloc] initWithHandled:snapshot.handled
                                                  commitText:commitText
                                                     preedit:StringFromUTF8(snapshot.preedit)
                                                  candidates:candidates
                                              diagnosticText:diagnosticText];
}

@end
