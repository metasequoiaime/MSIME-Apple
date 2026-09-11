#include "../WubiCommitPolicy.h"
#include <cassert>
int main(){using namespace metasequoia::mac; assert(ShouldAutoCommitUniqueWubiCandidate(true,SchemeType::Wubi,4,1,false)); assert(!ShouldAutoCommitUniqueWubiCandidate(false,SchemeType::Wubi,4,1,false)); assert(!ShouldAutoCommitUniqueWubiCandidate(true,SchemeType::Quanpin,4,1,false)); assert(!ShouldAutoCommitUniqueWubiCandidate(true,SchemeType::Wubi,3,1,false)); assert(!ShouldAutoCommitUniqueWubiCandidate(true,SchemeType::Wubi,4,2,false));}
