# iOS 键盘扩展宿主

`KeyboardViewController.mm` 是 iOS `UIInputViewController` 适配层，复用 `shared/apple` 会话和文本提交边界。它不实现输入状态机，也不依赖 macOS 或 Windows 端代码。

当前 CMake 目标只用于 iPhoneOS SDK 编译检查，默认读取 `target/ios/device/libmsime_host_api.a`；签名、Containing App、Bundle Identifier 和 Xcode 扩展工程尚未接入。

先准备包含 iOS 版 Boost 的依赖前缀，再运行 `MSIME_IOS_DEPS=<依赖前缀> bash platforms/ios/build-native.sh device`（或 `simulator`），然后将 `target/ios/<variant>/libmsime_host_api.a` 传给 CMake 的 `MSIME_HOST_LIBRARY`。构建脚本会自动识别依赖前缀下唯一的版本化 `BoostConfig.cmake` 与 `boost_headers-config.cmake`；如果依赖前缀有多个版本，可以分别用 `MSIME_BOOST_DIR` 和 `MSIME_BOOST_HEADERS_DIR` 指定包含对应配置文件的目录。
