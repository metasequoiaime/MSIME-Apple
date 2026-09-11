#include "../FrequencyAdjustmentPreference.h"
#include <cassert>
#include <cstring>

int main()
{
    using namespace metasequoia::mac;
    assert(NormalizeFrequencyAdjustmentCount(1) == 1);
    assert(NormalizeFrequencyAdjustmentCount(6) == 6);
    assert(NormalizeFrequencyAdjustmentCount(0) == 1);
    assert(NormalizeFrequencyAdjustmentCount(7) == 1);
    assert(std::strcmp(NormalizeFrequencyAdjustmentMode(nullptr), "promote") == 0);
    assert(std::strcmp(NormalizeFrequencyAdjustmentMode("unknown"), "promote") == 0);
    assert(std::strcmp(NormalizeFrequencyAdjustmentMode("pin"), "pin") == 0);
    assert(FrequencyAdjustmentModeOptionIndex("pin") == 0);
    assert(FrequencyAdjustmentModeOptionIndex("halve") == 1);
    assert(FrequencyAdjustmentModeOptionIndex("linear") == 2);
    assert(FrequencyAdjustmentModeOptionIndex("promote") == 3);
    assert(std::strcmp(FrequencyAdjustmentModeForOptionIndex(0), "pin") == 0);
    assert(std::strcmp(FrequencyAdjustmentModeForOptionIndex(99), "promote") == 0);
    assert(EngineFrequencyOptions(false, "pin", 3, 4).mode == FrequencyAdjustmentMode::Disabled);
    const auto options = EngineFrequencyOptions(true, "linear", 3, 4);
    assert(options.mode == FrequencyAdjustmentMode::Linear);
    assert(options.trigger_count == 3 && options.linear_step == 4);
    return 0;
}
