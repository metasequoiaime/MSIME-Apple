#include "EmojiPanel.h"

#include "msimeui/Application.h"
#include "msimeui/Scene.h"
#include "msimeui/Theme.h"
#include "msimeui/Window.h"

#include <shellapi.h>
#include <shlobj.h>
#include <memory>
#include <filesystem>

namespace
{
constexpr wchar_t kWindowClassName[] = L"MSIMEClient.EmojiPanel";

std::filesystem::path StateDirectory(int argc, wchar_t **argv)
{
    for (int index = 1; index + 1 < argc; ++index)
    {
        if (std::wstring(argv[index]) == L"--state-root")
        {
            const std::filesystem::path value(argv[++index]);
            if (value.is_absolute())
                return value;
        }
    }
    wchar_t buffer[32768] = {};
    const DWORD length = GetEnvironmentVariableW(L"MSIME_CLIENT_STATE_DIR", buffer,
                                                   static_cast<DWORD>(std::size(buffer)));
    if (length > 0 && length < std::size(buffer))
    {
        const std::filesystem::path value(buffer);
        if (value.is_absolute())
            return value;
    }
    PWSTR appData = nullptr;
    if (SUCCEEDED(SHGetKnownFolderPath(FOLDERID_LocalAppData, 0, nullptr, &appData)))
    {
        const auto value = std::filesystem::path(appData) / L"MSIME-Client";
        CoTaskMemFree(appData);
        return value;
    }
    return {};
}

void ApplyResourceOverride(int argc, wchar_t **argv)
{
    for (int index = 1; index + 1 < argc; ++index)
    {
        if (std::wstring(argv[index]) == L"--resources")
        {
            const std::filesystem::path value(argv[++index]);
            if (value.is_absolute())
                SetEnvironmentVariableW(L"MSIME_CLIENT_RESOURCES", value.c_str());
            return;
        }
    }
}
} // namespace

int WINAPI wWinMain(HINSTANCE, HINSTANCE, PWSTR, int)
{
    int argc = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    if (argc == 2 && std::wstring(argv[1]) == L"--help")
    {
        if (argv)
            LocalFree(argv);
        return 0;
    }
    ApplyResourceOverride(argc, argv);
    const auto stateRoot = StateDirectory(argc, argv);
    if (argv)
        LocalFree(argv);

    HANDLE mutex = CreateMutexW(nullptr, FALSE, L"Local\\MSIMEClientEmojiPanel.SingleInstance");
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
    theme.windowBackground = D2D1::ColorF(0x202027);
    theme.surface = D2D1::ColorF(0x202027);
    theme.borderStrong = D2D1::ColorF(0x45454F);
    theme.primary = D2D1::ColorF(0x8C55A2);
    theme.primaryFocusStrong = D2D1::ColorF(0xD88BDE);
    theme.textPrimary = D2D1::ColorF(0xF5F5F7);
    theme.textSecondary = D2D1::ColorF(0xC9C9D0);
    msimeui::ThemeManager::SetCurrent(std::move(theme));

    msimeui::Window window(kWindowClassName, L"Emoji and more", 550, 610);
    window.SetWindowStyle(WS_POPUP, WS_EX_TOOLWINDOW | WS_EX_TOPMOST);
    window.SetDragRegionHeight(56.0f * 2.0f / 3.0f);
    window.SetRoundedCorners(true);
    window.SetInitialPlacement(msimeui::WindowInitialPlacement::BottomCenter, 12);
    if (!window.Create())
    {
        msimeui::Application::Shutdown();
        CloseHandle(mutex);
        return -1;
    }

    auto scene = std::make_unique<msimeui::Scene>();
    scene->SetRoot(std::make_shared<msimeui::EmojiPanel>(false, stateRoot));
    window.SetScene(std::move(scene));
    window.Relayout();
    const int result = window.Run(SW_SHOWNOACTIVATE);
    msimeui::Application::Shutdown();
    CloseHandle(mutex);
    return result;
}

