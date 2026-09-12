#pragma once
#include <xkbcommon/xkbcommon-compose.h>
#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <initializer_list>

namespace msime::linux_host {
// Delegate native layout composition to the system Compose table. No IME
// spelling or candidate logic lives here; that remains in Engine.
class NativeCompose {
  std::unique_ptr<xkb_context, decltype(&xkb_context_unref)> context_{
      xkb_context_new(XKB_CONTEXT_NO_FLAGS), xkb_context_unref};
  std::unique_ptr<xkb_compose_table, decltype(&xkb_compose_table_unref)> table_{
      nullptr, xkb_compose_table_unref};
  std::unique_ptr<xkb_compose_state, decltype(&xkb_compose_state_unref)> state_{
      nullptr, xkb_compose_state_unref};

public:
  NativeCompose() {
    const char *locale = nullptr;
    for (const char *name : {"LC_ALL", "LC_CTYPE", "LANG"}) {
      const char *value = std::getenv(name);
      if (value && *value) { locale = value; break; }
    }
    if (context_)
      table_.reset(xkb_compose_table_new_from_locale(
          context_.get(), locale ? locale : "C.UTF-8", XKB_COMPOSE_COMPILE_NO_FLAGS));
    if (table_)
      state_.reset(xkb_compose_state_new(table_.get(), XKB_COMPOSE_STATE_NO_FLAGS));
  }
  void reset() {
    if (state_) xkb_compose_state_reset(state_.get());
  }
  std::optional<std::string> feed(xkb_keysym_t key) {
    if (!state_) return std::nullopt;
    const bool pending = xkb_compose_state_get_status(state_.get()) == XKB_COMPOSE_COMPOSING;
    xkb_compose_state_feed(state_.get(), key);
    const auto status = xkb_compose_state_get_status(state_.get());
    if (status == XKB_COMPOSE_COMPOSED) {
      const int size = xkb_compose_state_get_utf8(state_.get(), nullptr, 0);
      std::string text(static_cast<size_t>(size) + 1, '\0');
      xkb_compose_state_get_utf8(state_.get(), text.data(), text.size());
      text.resize(static_cast<size_t>(size));
      reset();
      return text;
    }
    if (status == XKB_COMPOSE_CANCELLED) reset();
    if (pending || status == XKB_COMPOSE_COMPOSING) return std::string{};
    return std::nullopt;
  }
};
} // namespace msime::linux_host
