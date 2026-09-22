#pragma once

namespace msime::linux_host {

// A physical Backspace hold that started while the IME owned a composition
// keeps belonging to the IME after its repeats erase the last preedit byte.
class BackspaceHoldPolicy {
 public:
  // The first composing press still goes to the shared runtime. Only a later
  // press after composition became empty is swallowed locally.
  bool press(bool composing) {
    if (!armed_) {
      armed_ = composing;
      return false;
    }
    return !composing;
  }

  bool armed() const { return armed_; }
  void release() { armed_ = false; }
  void reset() { armed_ = false; }

 private:
  bool armed_ = false;
};

}  // namespace msime::linux_host
