# Windows WinUI 3 设置

`MSIME.Settings.vcxproj` 是 Windows 设置窗口的原生宿主。它使用 Windows App SDK 的 WinUI 3 控件，不启动 Tauri，也不拥有 TSF 或输入会话。

设置窗口通过 `msime_client_load_preferences` 和 `msime_client_save_preferences` 读取、校验并以 compare-and-swap 方式保存共享偏好。Server 启动它时注入 `MSIME_CLIENT_STATE_DIR`，所以设置和输入法宿主使用同一个数据目录；从开始菜单直接启动时回落到 `%LOCALAPPDATA%\MSIME-Client`。

「AI 助手」页即共享设置页的「连接 AI 助手」：通过 `msime_client_mcp_status` 和 `msime_client_mcp_install` 显示与 `msime-client-settings.exe` 同目录的 `msime-mcp.exe`、可复制的 MCP 配置，并把它写入 Claude Desktop 或 Cursor 的配置文件。服务器指向的运行时选项取自 Server 注入的 `MSIME_CLIENT_HOST_OPTIONS`，直接启动时取数据目录下的 `runtime-options.json`；两者都没有时说明输入法尚未初始化，不提供配置。写入逻辑与 Tauri 外壳共用 host-api 的 `mcp_clients`。

Windows 的表情、手写和屏幕键盘面板仍由共享 Tauri 外壳提供。Server 将设置路由发送给 `msime-client-settings.exe`，将面板路由发送给 `MSIME.exe`。

在 Visual Studio 开发者命令行中构建：

```powershell
msbuild MSIME.Settings.vcxproj /p:Configuration=RelWithDebInfo /p:Platform=x64 `
  /p:HostApiLibrary=C:\path\to\msime_host_api.dll.lib
```

Windows App SDK 版本由 `WindowsAppSDKVersion` 属性控制，默认值与项目文件固定，发布构建使用 self-contained unpackaged 模式。
