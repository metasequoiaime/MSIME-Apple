#pragma once
#import <Foundation/Foundation.h>
FOUNDATION_EXPORT NSString *MetasequoiaChineseOutputString(NSString *text, BOOL traditionalOutput);
#define MSIMEChineseOutputString MetasequoiaChineseOutputString
// The first or last Han character of text, or nil when it has none. Non-Han characters are skipped and a non-BMP character is returned whole. The Han ranges are the reference server's IsHanCodePoint (candidate_text_policy.h), which word-to-character ([ ]) applies to the phrase after output conversion.
FOUNDATION_EXPORT NSString *MetasequoiaEdgeHanCharacter(NSString *text, BOOL first);
#define MSIMEEdgeHanCharacter MetasequoiaEdgeHanCharacter
