#pragma once

namespace msime::tsf {
class HostFocusState {
public:
    template<class Send>
    bool update(bool focused, bool contextChanged, Send send) {
        if (known_ && focused_ == focused && (!focused || !contextChanged)) return true;
        // A failed runtime focus call may already have cancelled composition.
        // Do not cache success; a later notification must retry.
        known_ = false;
        if (!send(focused)) return false;
        focused_ = focused;
        known_ = true;
        return true;
    }
private:
    bool known_ = false;
    bool focused_ = false;
};
}
