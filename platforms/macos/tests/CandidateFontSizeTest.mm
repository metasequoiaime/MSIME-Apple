#include "../CandidateFontSize.h"
#include <cassert>
int main(){using namespace metasequoia::mac; assert(NormalizeCandidateFontSize(16)==16); assert(NormalizeCandidateFontSize(18)==18); assert(NormalizeCandidateFontSize(20)==20); assert(NormalizeCandidateFontSize(19)==18); assert(CandidateFontSizeOptionIndex(20)==2); assert(CandidateFontSizeForOptionIndex(9)==18);}
