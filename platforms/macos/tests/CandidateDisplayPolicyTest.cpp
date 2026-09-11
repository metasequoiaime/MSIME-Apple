#include "../CandidateDisplay.h"
#include <cassert>
int main(){using namespace metasequoia::mac; using metasequoia::LocalInputMode; assert(HelpcodesAnnotateLocalMode(LocalInputMode::None)); assert(HelpcodesAnnotateLocalMode(LocalInputMode::SuperJianpin)); assert(!HelpcodesAnnotateLocalMode(LocalInputMode::Unicode)); assert(ScriptConversionAppliesToLocalMode(LocalInputMode::None)); assert(!ScriptConversionAppliesToLocalMode(LocalInputMode::Unicode));}
