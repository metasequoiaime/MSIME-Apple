#include "VoiceHotkeyPolicy.h"

#include <iostream>
#include <stdexcept>
#include <string>

using namespace msime::windows;
namespace {
void require(bool value, int line) {
  if (!value)
    throw std::runtime_error("voice hotkey policy failed at line " + std::to_string(line));
}
#define REQUIRE(value) require((value), __LINE__)

constexpr VoiceHotkeyBindings all_on{true, true, true, true, true};
constexpr VoiceHotkeyBindings all_off{false, false, false, false, false};
} // namespace

int main() {
  try {
    // Modifier bookkeeping. An event that is neither a press nor a release says
    // nothing about the key, so it must not be read as a release - a modifier
    // wrongly marked up ends a hold the user is still holding.
    VoiceModifierState state;
    state = voice_modifier_state_after(state, voice_key_ralt, true, false);
    REQUIRE(state.ralt);
    state = voice_modifier_state_after(state, voice_key_ralt, false, false);
    REQUIRE(state.ralt);
    state = voice_modifier_state_after(state, voice_key_ralt, false, true);
    REQUIRE(!state.ralt);
    // Either side counts for ctrl and win; neither side counts for the other.
    state = voice_modifier_state_after(VoiceModifierState{}, voice_key_lcontrol, true, false);
    REQUIRE(state.ctrl() && !state.rctrl && !state.win());
    state = voice_modifier_state_after(state, voice_key_rwin, true, false);
    REQUIRE(state.win() && !state.lwin);
    // A key the policy does not track leaves everything alone.
    const auto untouched = voice_modifier_state_after(state, voice_key_f9, true, false);
    REQUIRE(untouched.ctrl() && untouched.win() && !untouched.ralt);

    // Activation, and the order between the shortcuts. With both RCtrl+RAlt and
    // RAlt enabled, pressing RAlt while RCtrl is down is the two-key shortcut -
    // otherwise the one-key one would swallow it and the two-key one could
    // never fire.
    VoiceModifierState rctrl_then_ralt;
    rctrl_then_ralt.rctrl = true;
    rctrl_then_ralt.ralt = true;
    REQUIRE(voice_hold_activation(voice_key_ralt, all_on, rctrl_then_ralt) ==
            VoiceHoldShortcut::RCtrlRAlt);
    // Without the right control it is the plain RAlt shortcut.
    VoiceModifierState ralt_only;
    ralt_only.ralt = true;
    REQUIRE(voice_hold_activation(voice_key_ralt, all_on, ralt_only) ==
            VoiceHoldShortcut::RAlt);
    // The left control does not stand in for the right one here; that asymmetry
    // against Ctrl+Win below is deliberate.
    VoiceModifierState lctrl_then_ralt;
    lctrl_then_ralt.lctrl = true;
    lctrl_then_ralt.ralt = true;
    REQUIRE(voice_hold_activation(voice_key_ralt, all_on, lctrl_then_ralt) ==
            VoiceHoldShortcut::RAlt);
    // Ctrl+Win takes either control.
    VoiceModifierState lctrl_then_win;
    lctrl_then_win.lctrl = true;
    lctrl_then_win.lwin = true;
    REQUIRE(voice_hold_activation(voice_key_lwin, all_on, lctrl_then_win) ==
            VoiceHoldShortcut::CtrlWin);
    VoiceModifierState rctrl_then_win;
    rctrl_then_win.rctrl = true;
    rctrl_then_win.rwin = true;
    REQUIRE(voice_hold_activation(voice_key_rwin, all_on, rctrl_then_win) ==
            VoiceHoldShortcut::CtrlWin);
    // Win alone is the Start menu, not a shortcut.
    VoiceModifierState win_only;
    win_only.lwin = true;
    REQUIRE(voice_hold_activation(voice_key_lwin, all_on, win_only) ==
            VoiceHoldShortcut::None);
    // Every switch off means no shortcut, whatever is held.
    REQUIRE(voice_hold_activation(voice_key_ralt, all_off, rctrl_then_ralt) ==
            VoiceHoldShortcut::None);
    // Each switch gates only its own shortcut.
    VoiceHotkeyBindings ralt_only_binding{true, false, false, false, false};
    REQUIRE(voice_hold_activation(voice_key_ralt, ralt_only_binding, rctrl_then_ralt) ==
            VoiceHoldShortcut::RAlt);
    VoiceHotkeyBindings pair_only{false, false, false, true, false};
    REQUIRE(voice_hold_activation(voice_key_ralt, pair_only, ralt_only) ==
            VoiceHoldShortcut::None);

    // Holding. Losing any part of a two-key shortcut ends it.
    REQUIRE(voice_hold_held(VoiceHoldShortcut::RCtrlRAlt, rctrl_then_ralt));
    REQUIRE(!voice_hold_held(VoiceHoldShortcut::RCtrlRAlt, ralt_only));
    REQUIRE(voice_hold_held(VoiceHoldShortcut::CtrlWin, lctrl_then_win));
    REQUIRE(!voice_hold_held(VoiceHoldShortcut::CtrlWin, lctrl_then_ralt));
    REQUIRE(voice_hold_held(VoiceHoldShortcut::RAlt, ralt_only));
    REQUIRE(!voice_hold_held(VoiceHoldShortcut::None, rctrl_then_ralt));

    // Suppression. A modifier used to start a shortcut must not also reach the
    // application, or RAlt opens a menu every time the user dictates.
    REQUIRE(voice_hold_suppresses_ralt(VoiceHoldShortcut::RAlt));
    REQUIRE(voice_hold_suppresses_ralt(VoiceHoldShortcut::RCtrlRAlt));
    REQUIRE(!voice_hold_suppresses_ralt(VoiceHoldShortcut::CtrlWin));
    REQUIRE(voice_hold_suppresses_win(VoiceHoldShortcut::CtrlWin));
    REQUIRE(!voice_hold_suppresses_win(VoiceHoldShortcut::RAlt));
    // The latch applies to its own key and to nothing else.
    REQUIRE(voice_key_is_suppressed(voice_key_ralt, true, false));
    REQUIRE(!voice_key_is_suppressed(voice_key_ralt, false, true));
    REQUIRE(voice_key_is_suppressed(voice_key_lwin, false, true));
    REQUIRE(voice_key_is_suppressed(voice_key_rwin, false, true));
    REQUIRE(!voice_key_is_suppressed(voice_key_space, true, true));
    // Only the release clears it: clearing on the press would let the release
    // through unmatched.
    REQUIRE(voice_key_clears_ralt_latch(voice_key_ralt, true));
    REQUIRE(!voice_key_clears_ralt_latch(voice_key_ralt, false));
    REQUIRE(!voice_key_clears_ralt_latch(voice_key_lwin, true));
    REQUIRE(voice_key_clears_win_latch(voice_key_lwin, true));
    REQUIRE(voice_key_clears_win_latch(voice_key_rwin, true));
    REQUIRE(!voice_key_clears_win_latch(voice_key_ralt, true));

    // Space locks a hold, and only a hold.
    REQUIRE(voice_space_locks_hold(voice_key_space, VoiceHoldShortcut::RAlt, all_on));
    REQUIRE(!voice_space_locks_hold(voice_key_space, VoiceHoldShortcut::None, all_on));
    // With the setting off, space is an ordinary space even while holding.
    REQUIRE(!voice_space_locks_hold(voice_key_space, VoiceHoldShortcut::RAlt, all_off));
    REQUIRE(!voice_space_locks_hold(voice_key_f9, VoiceHoldShortcut::RAlt, all_on));

    // Escape cancels while recording and does nothing otherwise.
    REQUIRE(voice_escape_cancels(voice_key_escape, true));
    REQUIRE(!voice_escape_cancels(voice_key_escape, false));
    REQUIRE(!voice_escape_cancels(voice_key_space, true));

    std::cout << "Windows voice hotkey policy checks passed\n";
    return 0;
  } catch (const std::exception &error) {
    std::cerr << error.what() << '\n';
    return 1;
  }
}
