# Android JNI 接入边界

`NativeClient` 提供 Java/Kotlin 到共享运行时的 JNI 传输。UTF-8 字节数组保留非 BMP 字符，避免 JNI modified UTF-8 损坏候选或资源路径。JNI 负责释放 C API 响应；上层解析 ok/value，负责会话线程和生命周期。

当前使用桌面 JVM 与本机动态库验证真实 JNI 调用和 Unicode 数据往返，尚未构建 Android APK 或输入法服务。后续需要 Android NDK 下 Rust/C++ 交叉编译、打包各 ABI 的库，并由 InputMethodService 将 commit 和 view 接到 InputConnection 与键盘 UI。桌面 JVM 测试不能替代设备验收。
