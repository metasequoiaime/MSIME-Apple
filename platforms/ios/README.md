# iOS 键盘扩展宿主

`KeyboardViewController.mm` 是 iOS `UIInputViewController` 适配层，复用 `shared/apple` 会话和文本提交边界。它不实现输入状态机，也不依赖 macOS 或 Windows 端代码。

当前 CMake 目标只用于 iPhoneOS SDK 编译检查；签名、Containing App、Bundle Identifier 和 Xcode 扩展工程尚未接入。
