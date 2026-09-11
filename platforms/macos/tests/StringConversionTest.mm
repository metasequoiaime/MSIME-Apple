#include "../StringConversion.h"
#include <cassert>

int main() { @autoreleasepool {
    NSArray *values = @[ @"a", @"b", @"a" ];
    assert(MetasequoiaUniqueStringIndex(values, @"b") == 1);
    assert(MetasequoiaUniqueStringIndex(values, @"a") == NSNotFound);
    NSAttributedString *candidate = MetasequoiaIndexedCandidateString(@"候选", 3);
    assert(MetasequoiaCandidateIndex(candidate) == 3);
    assert(MetasequoiaCandidateIndex([[NSAttributedString alloc] initWithString:@"plain"]) == NSNotFound);
} return 0; }
