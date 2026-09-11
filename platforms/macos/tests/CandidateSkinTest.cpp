#include "../CandidateSkin.h"

#include <cassert>

int main()
{
    const auto &entries = msime::mac::BuiltInSkinEntries();
    assert(entries.size() == 4);
    assert(msime::mac::IsBuiltInSkinId("fluent"));
    assert(msime::mac::IsBuiltInSkinId("willow_green"));
    assert(!msime::mac::IsBuiltInSkinId("../escape"));
    assert(msime::mac::NormalizeSkinId("external-demo") == "external-demo");
    assert(msime::mac::NormalizeSkinId("../escape") == "fluent");

    const auto fluent = msime::mac::BuiltInSkinTokens("fluent", false);
    const auto wechat = msime::mac::BuiltInSkinTokens("wechat", false);
    const auto graphite = msime::mac::BuiltInSkinTokens("graphite", true);
    const auto willow = msime::mac::BuiltInSkinTokens("willow_green", false);
    assert(fluent.showSelectedBar);
    assert(wechat.accent.g > wechat.accent.r);
    assert(graphite.radius < fluent.radius);
    assert(willow.radius > fluent.radius);
    assert(willow.selected.g > willow.selected.r);
    return 0;
}
