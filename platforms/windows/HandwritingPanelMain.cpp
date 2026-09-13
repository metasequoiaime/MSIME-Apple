#include "HandwritingPanel.h"

#include "msimeui/Application.h"
#include "msimeui/Scene.h"
#include "msimeui/Theme.h"
#include "msimeui/Window.h"

#include <memory>
#include <string>

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR commandLine, int nCmdShow)
{
    if (commandLine && std::wstring(commandLine) == L"--help")
        return 0;

    HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\MSIMEClientHandwritingPanel.SingleInstance");
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

    msimeui::Theme theme = msimeui::ThemeManager::GetCurrent();
    theme.windowBackground = D2D1::ColorF(0x202027);
    theme.surface = D2D1::ColorF(0x292A31);
    theme.borderStrong = D2D1::ColorF(0x45454F);
    theme.primary = D2D1::ColorF(0x8C55A2);
    theme.primaryFocusStrong = D2D1::ColorF(0xD88BDE);
    theme.textPrimary = D2D1::ColorF(0xF5F5F7);
    theme.textSecondary = D2D1::ColorF(0xB8B8C0);
    msimeui::ThemeManager::SetCurrent(std::move(theme));

    msimeui::Window window(L"MSIMEClient.HandwritingPanel", L"水杉手写识别板", 980, 650);
    window.SetWindowStyle(WS_POPUP, WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_TOPMOST);
    window.SetDragRegionHeight(38.0f);
    window.SetRoundedCorners(true);
    window.SetInitialPlacement(msimeui::WindowInitialPlacement::BottomCenter, 12);
    if (!window.Create())
    {
        msimeui::Application::Shutdown();
        CloseHandle(mutex);
        return -1;
    }

    auto scene = std::make_unique<msimeui::Scene>();
    scene->SetRoot(std::make_shared<msimeui::HandwritingPanel>());
    window.SetScene(std::move(scene));
    const int result = window.Run(nCmdShow);
    msimeui::Application::Shutdown();
    CloseHandle(mutex);
    return result;
}
