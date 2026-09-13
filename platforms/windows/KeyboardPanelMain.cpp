#include "KeyboardPanel.h"

#include "msimeui/Application.h"
#include "msimeui/Scene.h"
#include "msimeui/Theme.h"
#include "msimeui/Window.h"

#include <memory>

namespace
{
constexpr wchar_t kWindowClassName[] = L"MSIMEClient.KeyboardPanel";
}
int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int nCmdShow)
{
    HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\MSIMEClientKeyboardPanel.SingleInstance");
    if (!mutex || GetLastError() == ERROR_ALREADY_EXISTS)
    {
        if (mutex)
            CloseHandle(mutex);
        return 0;
    }
    if (!msimeui::Application::Initialize())
    {
        CloseHandle(mutex);
        return -1;
    }

    msimeui::Theme theme;
    theme.windowBackground = D2D1::ColorF(0x17181D);
    theme.surface = D2D1::ColorF(0x17181D);
    theme.textPrimary = D2D1::ColorF(0xF1F1F3);
    theme.textSecondary = D2D1::ColorF(0xAEB0B7);
    msimeui::ThemeManager::SetCurrent(std::move(theme));

    msimeui::Window window(kWindowClassName, L"Touch keyboard", 1100, 400);
    window.SetWindowStyle(WS_POPUP, WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST);
    window.SetDragRegionHeight(28.0f);
    window.SetRoundedCorners(true);
    window.SetInitialPlacement(msimeui::WindowInitialPlacement::BottomCenter, 12);
    if (!window.Create())
    {
        msimeui::Application::Shutdown();
        CloseHandle(mutex);
        return -1;
    }

    auto scene = std::make_unique<msimeui::Scene>();
    scene->SetRoot(std::make_shared<msimeui::KeyboardPanel>(false));
    window.SetScene(std::move(scene));
    const int result = window.Run(nCmdShow);
    msimeui::Application::Shutdown();
    CloseHandle(mutex);
    return result;
}

