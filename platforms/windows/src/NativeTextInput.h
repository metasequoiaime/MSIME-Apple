#pragma once

#ifdef _WIN32
#include <Windows.h>

#include <string_view>
#include <vector>

namespace msimeui {

// Text panels are non-activating windows. Capture the editor that was in the
// foreground before the panel was opened and only inject while that same
// top-level window is still foreground. This keeps a late click from writing
// into an unrelated application after the user changes focus.
class NativeTextInputTarget final {
public:
    static NativeTextInputTarget Capture(HWND excluded = nullptr)
    {
        const HWND foreground = GetForegroundWindow();
        if (!foreground || (excluded && SameRoot(foreground, excluded)))
            return NativeTextInputTarget(nullptr);
        return NativeTextInputTarget(GetAncestor(foreground, GA_ROOT));
    }

    bool Insert(std::wstring_view text, HWND excluded = nullptr) const
    {
        constexpr size_t kMaxTextUnits = 4000;
        if (target_ == nullptr || text.empty() || text.size() > kMaxTextUnits ||
            !IsWindow(target_))
            return false;

        const HWND foreground = GetForegroundWindow();
        if (!foreground || (excluded && SameRoot(foreground, excluded)) ||
            !SameRoot(foreground, target_))
            return false;

        std::vector<INPUT> inputs;
        inputs.reserve(text.size() * 2);
        for (const wchar_t unit : text)
        {
            INPUT down{};
            down.type = INPUT_KEYBOARD;
            down.ki.wScan = static_cast<WORD>(unit);
            down.ki.dwFlags = KEYEVENTF_UNICODE;
            down.ki.dwExtraInfo = GetMessageExtraInfo();
            inputs.push_back(down);

            INPUT up = down;
            up.ki.dwFlags |= KEYEVENTF_KEYUP;
            inputs.push_back(up);
        }

        return SendInput(static_cast<UINT>(inputs.size()), inputs.data(), sizeof(INPUT)) ==
               static_cast<UINT>(inputs.size());
    }

    bool valid() const noexcept { return target_ != nullptr; }

private:
    explicit NativeTextInputTarget(HWND target) : target_(target) {}

    static bool SameRoot(HWND left, HWND right) noexcept
    {
        return left != nullptr && right != nullptr &&
               GetAncestor(left, GA_ROOT) == GetAncestor(right, GA_ROOT);
    }

    HWND target_ = nullptr;
};

} // namespace msimeui
#endif
