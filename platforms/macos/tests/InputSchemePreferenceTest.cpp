#include "../InputSchemePreference.h"
#include <cassert>
int main(){using namespace metasequoia::mac; assert(EngineSchemeForStoredPreference(0)==SchemeType::Quanpin); assert(EngineSchemeForStoredPreference(1)==SchemeType::Shuangpin); assert(EngineSchemeForStoredPreference(2)==SchemeType::Wubi); assert(EngineSchemeForStoredPreference(9)==SchemeType::Quanpin); assert(ShouldRouteSemicolonAsShuangpinInput(SchemeType::Shuangpin,"microsoft")); assert(!ShouldRouteSemicolonAsShuangpinInput(SchemeType::Quanpin,"microsoft"));}
