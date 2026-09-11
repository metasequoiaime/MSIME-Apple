#pragma once
#include <metasequoia/session.h>
#include <cstring>
namespace metasequoia::mac {
inline int NormalizeFrequencyAdjustmentCount(int value) { return value >= 1 && value <= 6 ? value : 1; }
inline const char *NormalizeFrequencyAdjustmentMode(const char *value) { return value && (std::strcmp(value,"pin")==0 || std::strcmp(value,"halve")==0 || std::strcmp(value,"linear")==0) ? value : "promote"; }
inline int FrequencyAdjustmentModeOptionIndex(const char *value) { value=NormalizeFrequencyAdjustmentMode(value); return std::strcmp(value,"pin")==0?0:std::strcmp(value,"halve")==0?1:std::strcmp(value,"linear")==0?2:3; }
inline const char *FrequencyAdjustmentModeForOptionIndex(int index) { return index==0?"pin":index==1?"halve":index==2?"linear":"promote"; }
inline FrequencyAdjustmentOptions EngineFrequencyOptions(bool learning, const char *mode, int trigger, int step) {
    FrequencyAdjustmentOptions options; if (!learning) return options; const char *normalized=NormalizeFrequencyAdjustmentMode(mode);
    options.mode=std::strcmp(normalized,"pin")==0?FrequencyAdjustmentMode::Pin:std::strcmp(normalized,"halve")==0?FrequencyAdjustmentMode::Halve:std::strcmp(normalized,"linear")==0?FrequencyAdjustmentMode::Linear:FrequencyAdjustmentMode::Promote;
    options.trigger_count=NormalizeFrequencyAdjustmentCount(trigger); options.linear_step=NormalizeFrequencyAdjustmentCount(step); return options;
}
}
