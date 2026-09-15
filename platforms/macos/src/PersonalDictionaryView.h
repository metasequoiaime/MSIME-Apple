#pragma once

#import <AppKit/AppKit.h>

// 用户词库的管理界面:分页列出引擎记下的词条,并允许新增、编辑、删除和导出。
@interface MetasequoiaPersonalDictionaryView : NSView
- (void)reload;
@end
