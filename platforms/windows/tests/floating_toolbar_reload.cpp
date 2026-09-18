#include "../src/FloatingToolbarSettings.h"
#include <cassert>
#include <thread>
using namespace msime::windows;
int main() {
  const auto defaults = floating_toolbar_settings(nlohmann::json::object());
  assert(defaults && defaults->scale_percent == 100 && defaults->font_size == 24);
  assert(!defaults->items[4]);
  nlohmann::json preferences = {{"floating_toolbar", {
    {"scale_percent", 125}, {"font_size", 28}, {"character_set", false},
    {"punctuation", false}, {"fullwidth", false}, {"emoji", false},
    {"screen_keyboard", true}, {"settings", false}}}};
  auto settings = floating_toolbar_settings(preferences);
  assert(settings && settings->scale_percent == 125 && settings->font_size == 28);
  assert((settings->items == std::array<bool, 6>{false, false, false, false, true, false}));
  for (const auto &invalid : {nlohmann::json(-1), nlohmann::json(74),
                            nlohmann::json(151), nlohmann::json(1ULL << 40),
                            nlohmann::json(100.5), nlohmann::json("100")}) {
    auto bad = preferences;
    bad["floating_toolbar"]["scale_percent"] = invalid;
    assert(!floating_toolbar_settings(bad));
  }
  for (int size : {15, 29}) {
    auto bad = preferences;
    bad["floating_toolbar"]["font_size"] = size;
    assert(!floating_toolbar_settings(bad));
  }
  for (int percent : {75, 150}) {
    preferences["floating_toolbar"]["scale_percent"] = percent;
    assert(floating_toolbar_settings(preferences));
  }
  preferences["floating_toolbar"]["emoji"] = "false";
  assert(!floating_toolbar_settings(preferences));
  assert(!floating_toolbar_settings(nullptr));
  FloatingToolbarMailbox mailbox;
  assert(!mailbox.take());
  assert(mailbox.publish(1, *defaults));
  std::thread publisher([&] { assert(mailbox.publish(3, *settings)); });
  publisher.join();
  assert(!mailbox.publish(2, *defaults));
  assert(mailbox.take()->scale_percent == 125);
  assert(!mailbox.take());
  assert(!mailbox.publish(3, *defaults));
  auto invalid = *settings;
  invalid.font_size = 0;
  assert(!mailbox.publish(4, invalid));
  assert(mailbox.publish(4, *defaults));
  assert(mailbox.take()->font_size == 24);
}
