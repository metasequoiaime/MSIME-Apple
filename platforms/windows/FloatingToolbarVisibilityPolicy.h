#pragma once

namespace msime::windows {

// Temporary focus suspension must not hide the toolbar. Only a real IME
// deactivation or fullscreen presentation removes it.
constexpr bool ShouldShowFloatingToolbar(bool configured_enabled,
                                          bool fullscreen,
                                          bool ime_active) {
  return configured_enabled && !fullscreen && ime_active;
}

// Defer hide requests while the embedded toolbar page is receiving its first
// paint, then reconcile visibility once the page reports ready.
constexpr bool ShouldDeferFloatingToolbarHide(bool paint_grace_active) {
  return paint_grace_active;
}

}  // namespace msime::windows
