#pragma once
#include <algorithm>
#include <cmath>
#include <cstddef>
#include <limits>

namespace msime::voice {
// Display-only RMS mapping from MSIME-Windows develop bc5e86fa AudioCallback.
// Never alter recognition samples. Layout and integer scaling belong to hosts.
template <typename Sample>
float input_level(const Sample *const *channels, std::size_t channel_count,
                  std::size_t frames, std::size_t stride, double scale = 1) {
  if (!channels || !channel_count || !frames || !stride ||
      frames > std::numeric_limits<std::size_t>::max() / stride ||
      !std::isfinite(scale) || scale <= 0) return 0;
  double sum = 0;
  for (std::size_t channel = 0; channel < channel_count; ++channel) {
    if (!channels[channel]) return 0;
    for (std::size_t frame = 0; frame < frames; ++frame) {
      const double sample = static_cast<double>(channels[channel][frame * stride]) * scale;
      if (!std::isfinite(sample)) return 0;
      const double bounded = std::clamp(sample, -1.0, 1.0);
      sum += bounded * bounded;
    }
  }
  const float rms = static_cast<float>(std::sqrt(sum / (static_cast<double>(frames) * channel_count)));
  const float speech = std::max(0.0f, rms - 0.004f);
  return std::pow(std::min(1.0f, speech * 14.0f), 0.55f);
}
inline float input_level(const float *samples, std::size_t frames) {
  return input_level(&samples, 1, frames, 1);
}
} // namespace msime::voice
