#include "../CandidatePageSize.h"
#include <cassert>
int main() { using namespace metasequoia::mac; assert(NormalizeCandidatePageSize(5)==5); assert(NormalizeCandidatePageSize(7)==7); assert(NormalizeCandidatePageSize(9)==9); assert(NormalizeCandidatePageSize(6)==9); assert(CandidatePageSizeOptionIndex(7)==1); assert(CandidatePageSizeForOptionIndex(0)==5); return 0; }
