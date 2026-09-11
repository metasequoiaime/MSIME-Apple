#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Foundation adapter for macOS input controllers and iOS keyboard extensions.
/// Construct and use on the main thread. No Tauri process is required.
@interface MSIMEClientSession : NSObject
- (nullable instancetype)initWithOptions:(NSDictionary<NSString *, id> *)options error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;
- (nullable NSDictionary<NSString *, id> *)setFocused:(BOOL)focused error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)setEnglishMode:(BOOL)enabled error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)setChinesePunctuationEnabled:(BOOL)enabled error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)setCharacterWidthFull:(BOOL)fullwidth error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)typeASCII:(uint8_t)character shift:(BOOL)shift error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)command:(uint32_t)command error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)selectGeneration:(uint64_t)generation index:(NSUInteger)index error:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)viewWithError:(NSError **)error;
- (nullable NSDictionary<NSString *, id> *)updatePreferencesSnapshot:(NSDictionary<NSString *, id> *)snapshot error:(NSError **)error;
/// Start on main thread; disk/lock work runs in background, completion on main.
- (void)reloadPreferencesDirectory:(NSString *)directory completion:(void (^)(NSDictionary * _Nullable result, NSError * _Nullable error))completion;
- (BOOL)closeWithError:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
