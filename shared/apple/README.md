# Apple 共用原生桥接

`MSIMEClientSession` 是 Foundation / Objective-C++ 适配器，可通过桥接头被 Swift 调用。它不依赖 AppKit、UIKit、Tauri 或旧 Apple 产品仓。会话创建和动作在主线程执行；响应复制为 Foundation 值并立即释放 C 缓冲区。关闭后操作报错；非主线程释放对象时将句柄销毁派发回主线程。

macOS InputMethodKit 控制器与 iOS 键盘扩展负责创建资源路径和配置、调用本适配器、处理返回的 handled/commit/view，以及系统文本提交。macOS 目标由 `platforms/macos/CMakeLists.txt` 构建，iOS 键盘扩展由 `platforms/ios/project.yml` 注册为 `com.apple.keyboard-service`；本目录只实现两端共用的原生消费边界，安装、签名和资源准备各自留在对应平台目录。

macOS 验证（先构建 msime-host-api）：

```sh
clang++ -std=c++17 -fobjc-arc -Wall -Wextra -Werror -framework Foundation \
  shared/apple/MSIMEClientSession.mm shared/apple/tests/session_smoke.mm \
  -Ishared/apple -Icrates/host-api/include -Ltarget/debug -lmsime_host_api \
  -Wl,-rpath,"$PWD/target/debug" -o target/debug/apple-session-smoke
target/debug/apple-session-smoke
```

iOS 侧用的是交叉编译出来的 Rust/C++ 静态库（`platforms/ios/build-native.sh`），不能拿 macOS dylib 顶替。
