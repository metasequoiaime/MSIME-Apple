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
