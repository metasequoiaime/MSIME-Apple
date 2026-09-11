#import "ChineseTextConversion.h"
#include <cassert>
int main() { @autoreleasepool { NSString *s=@"汉马龙"; assert([MetasequoiaChineseOutputString(s, NO) isEqual:s]); NSString *t=MetasequoiaChineseOutputString(s, YES); assert(t.length==s.length && ![t isEqual:s]); assert([MetasequoiaChineseOutputString(@"", YES) isEqual:@""]); } return 0; }
