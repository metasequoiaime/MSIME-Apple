#pragma once

namespace msime::linux_host {

// What the panel shows for the input method, following the Windows language bar (LanguageBar.cpp): CapsLock outranks everything, because letters then reach the editor as capitals whichever mode is on; Japanese is shown only while conversion is on, since direct input with the Japanese scheme selected is plain English typing. Each host draws these with its own symbols.
enum class InputModeIndicator { Chinese, English, Japanese, CapsLock };

inline InputModeIndicator input_mode_indicator(bool input_enabled, bool japanese_scheme,
                                               bool caps_lock) {
  if (caps_lock) return InputModeIndicator::CapsLock;
  if (!input_enabled) return InputModeIndicator::English;
  return japanese_scheme ? InputModeIndicator::Japanese : InputModeIndicator::Chinese;
}

}  // namespace msime::linux_host
