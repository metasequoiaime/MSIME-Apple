#include "core/online_request_guard.h"

#include <iostream>
#include <stdexcept>

namespace {
void require(bool value, const char *message) {
  if (!value)
    throw std::runtime_error(message);
}

metasequoia::OnlineQuery query(std::uint64_t generation,
                               std::string text) {
  metasequoia::OnlineQuery value;
  value.scheme = SchemeType::Quanpin;
  value.generation = generation;
  value.identity = "quanpin:" + text;
  value.query_text = std::move(text);
  value.cache_key = value.query_text;
  value.pinyin_segments = {value.query_text};
  value.cloud_eligible = true;
  value.ai_eligible = true;
  return value;
}
} // namespace

int main() {
  try {
    metasequoia::OnlineRequestGuard guard;
    auto first = query(0, "ni");
    guard.stamp(first);
    require(guard.matches(first, first), "the stamped request was not accepted");

    // A response queued for an earlier request must remain stale even when a
    // later request returns to the same text.
    guard.invalidate();
    auto newer = query(0, "hao");
    guard.stamp(newer);
    guard.invalidate();
    auto repeated = query(0, "ni");
    guard.stamp(repeated);
    require(!guard.matches(first, first),
            "an invalidated request was accepted after a repeated query");
    require(guard.matches(repeated, repeated),
            "the current repeated query was rejected");
    require(!guard.matches(repeated, newer),
            "a different query identity was accepted");

    auto changed = repeated;
    changed.identity += ":stale";
    require(!guard.matches(repeated, changed),
            "a mismatched engine identity was accepted");

    std::cout << "Windows online request guard checks passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
