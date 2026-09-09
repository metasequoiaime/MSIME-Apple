#pragma once

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MetasequoiaCandidateAction) {
    MetasequoiaCandidateActionPromote,
    MetasequoiaCandidateActionRemove,
    MetasequoiaCandidateActionFixFirst,
    MetasequoiaCandidateActionClearPosition,
};

@interface MetasequoiaInputSnapshot : NSObject

@property(nonatomic, readonly, getter=isHandled) BOOL handled;
@property(nonatomic, copy, readonly, nullable) NSString *commitText;
@property(nonatomic, copy, readonly) NSString *preedit;
@property(nonatomic, copy, readonly) NSArray<NSString *> *candidates;
/// Set when the key was handled but something behind it failed, such as a local input mode whose
/// table is missing. Input stays usable, so a frontend reports this rather than failing.
@property(nonatomic, copy, readonly, nullable) NSString *diagnosticText;

- (instancetype)init NS_UNAVAILABLE;

@end

@class MSIMEPreparedDictionarySnapshot;

@interface MetasequoiaInputSessionBridge : NSObject

- (MetasequoiaInputSnapshot *)handleCharacter:(NSString *)character;
- (MetasequoiaInputSnapshot *)handleCandidateKey:(NSString *)character;
- (MetasequoiaInputSnapshot *)handlePunctuation:(NSString *)character;
- (MetasequoiaInputSnapshot *)handleBackspace;
- (MetasequoiaInputSnapshot *)commitCandidate;
- (MetasequoiaInputSnapshot *)finishComposition;
- (MetasequoiaInputSnapshot *)commitRaw;
- (MetasequoiaInputSnapshot *)cancel;
- (MetasequoiaInputSnapshot *)selectCandidateAtIndex:(NSUInteger)index;
- (BOOL)setLearningEnabled:(BOOL)enabled;
- (BOOL)setFuzzyPinyinRules:(uint32_t)rules;
// Answers a wubi code the table cannot spell with quanpin candidates for the same letters.
- (void)setWubiMixedPinyin:(BOOL)enabled;
- (BOOL)suspendDictionarySession;
- (BOOL)resumeDictionarySessionWithError:(NSError **)error NS_SWIFT_NAME(resumeDictionarySession());
// Call on the session-owning thread. This token describes the current logical
// journal and generation, and is used to reject stale snapshot replacements.
- (nullable NSString *)localDictionaryStateVersionWithError:(NSError **)error
    NS_SWIFT_NAME(localDictionaryStateVersion());
- (nullable NSDictionary<NSString *, id> *)dictionarySnapshotContextWithError:(NSError **)error
    NS_SWIFT_NAME(dictionarySnapshotContext());
- (BOOL)activateDictionarySnapshot:(MSIMEPreparedDictionarySnapshot *)snapshot
                   expectedVersion:(NSString *)expectedVersion
                             error:(NSError **)error NS_SWIFT_NAME(activateDictionarySnapshot(_:expectedVersion:));
- (BOOL)applyPersonalPrevious:(nullable NSDictionary<NSString *, id> *)previous
                  replacement:(nullable NSDictionary<NSString *, id> *)replacement
                    requestID:(NSString *)requestID
                        error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)personalEntriesAtOffset:(NSUInteger)offset error:(NSError **)error;

- (MetasequoiaInputSnapshot *)editCandidateAtIndex:(NSUInteger)index
                                      expectedWord:(NSString *)word
                                            action:(MetasequoiaCandidateAction)action;
- (MetasequoiaInputSnapshot *)switchToShuangpin:(BOOL)usesShuangpin;
- (MetasequoiaInputSnapshot *)switchToNineKey;
- (MetasequoiaInputSnapshot *)switchToWubi;
- (MetasequoiaInputSnapshot *)switchToShuangpinProfile:(NSString *)name;
- (MetasequoiaInputSnapshot *)switchToJapanese;
- (MetasequoiaInputSnapshot *)chooseNineKeySpellingAtIndex:(NSUInteger)index;
- (NSArray<NSString *> *)nineKeySpellings;

/// Opens one of the engine's local input modes by its trigger letter. The engine keys these off a
/// capital delivered with a shift-only modifier, which this keyboard has no way to produce, so the
/// mode is named instead. A mode that is switched off, or a letter that names none, leaves the
/// session untouched and reports itself unhandled.
- (MetasequoiaInputSnapshot *)openLocalMode:(NSString *)trigger;

/// YES while the Unicode local mode is open, when the digits are input for a code point rather than
/// candidate numbers.
@property(nonatomic, readonly, getter=isInUnicodeMode) BOOL inUnicodeMode;
/// Local utilities need alphabetic keys even when nine-key pinyin is selected.
@property(nonatomic, readonly, getter=isInLocalMode) BOOL inLocalMode;

/// Per-key double-pinyin hints for the scheme the session is actually running, keyed by uppercase
/// letter. Empty in full pinyin. Derived from the engine's own profile so a frontend never hardcodes
/// a keymap that can drift from the scheme.
- (NSDictionary<NSString *, NSString *> *)shuangpinKeyHints;

@end

NS_ASSUME_NONNULL_END
