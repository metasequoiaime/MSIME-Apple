#pragma once
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MetasequoiaPersonalDictionaryKind) {
    MetasequoiaPersonalDictionaryKindPinyin = 0,
    MetasequoiaPersonalDictionaryKindWubi,
    MetasequoiaPersonalDictionaryKindQuickPhrase,
    MetasequoiaPersonalDictionaryKindEnglish,
};

FOUNDATION_EXPORT NSString *MetasequoiaPersonalDictionaryKindTitle(MetasequoiaPersonalDictionaryKind kind);
// 每类对编码的写法要求不一样,加词时把规则摆在输入框旁边,而不是等引擎驳回再让人猜。
FOUNDATION_EXPORT NSString *MetasequoiaPersonalDictionaryKindKeyHint(MetasequoiaPersonalDictionaryKind kind);

@interface MetasequoiaPersonalDictionaryEntry : NSObject
@property(nonatomic) MetasequoiaPersonalDictionaryKind kind;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, copy) NSString *value;
@property(nonatomic) int64_t weight;
+ (instancetype)entryWithKind:(MetasequoiaPersonalDictionaryKind)kind
                          key:(NSString *)key
                        value:(NSString *)value
                       weight:(int64_t)weight;
@end

@interface MetasequoiaPersonalDictionaryStore : NSObject
// 引擎按 kind/key/value 稳定排序,limit 1..1000。hasMore 告诉调用方还有没有下一页。
+ (nullable NSArray<MetasequoiaPersonalDictionaryEntry *> *)entriesAtOffset:(NSUInteger)offset
                                                                      limit:(NSUInteger)limit
                                                                    hasMore:(nullable BOOL *)hasMore
                                                                      error:(NSError **)error;
+ (BOOL)addEntry:(MetasequoiaPersonalDictionaryEntry *)entry error:(NSError **)error;
+ (BOOL)removeEntry:(MetasequoiaPersonalDictionaryEntry *)entry error:(NSError **)error;
+ (BOOL)replaceEntry:(MetasequoiaPersonalDictionaryEntry *)previous
           withEntry:(MetasequoiaPersonalDictionaryEntry *)replacement
               error:(NSError **)error;
// 校验不写库:加词面板用它在提交前就说清哪里不合规。理由来自 shared/apple-bridge 那份已有的中文映射,
// 不要在这里另写一套 —— iOS 早就用它把引擎的英文错误译成人话了。
+ (BOOL)validateEntry:(MetasequoiaPersonalDictionaryEntry *)entry error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
