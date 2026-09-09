# Android 输入宿主预览

`NativeClient` 提供 Java/Kotlin 到共享运行时的 JNI 传输。UTF-8 字节数组保留非 BMP 字符，避免 JNI modified UTF-8 损坏候选或资源路径。JNI 负责释放 C API 响应；上层解析 ok/value，负责会话线程和生命周期。

`MSIMEInputService` 提供实际 InputMethodService 源码、系统 manifest 和输入法元数据；最小 Android 28，编译目标 35。软键盘、硬件 ASCII 键、候选点击和翻页调用同一 JNI；Engine 提交与剩余编辑串通过 `EditorBridge` 按顺序映射到 InputConnection。宿主不实现输入算法或分页规则。密码、非文本和无建议字段直接输入，不创建 Engine；IME_FLAG_NO_PERSONALIZED_LEARNING 关闭当前会话学习。没有输入日志或网络权限。

配置缺失、原生库不可用或输入连接错误会显示状态并退回直接输入。服务从应用私有 files 目录读取 `runtime-options.json`，路径必须指向已在设备上准备的词库与私有用户目录，不能复制 macOS 的配置路径。开发 APK 的启动页提供首次资源准备；源码、打包与签名检查通过不代表设备运行通过。

本地检查：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/check-host.sh`。需要 JDK 17+、Android API 35 和 build-tools 35.0.0。脚本编译全部服务 Java、执行不依赖 Android 运行时的文本/敏感字段策略测试，并校验 manifest/resource；中间资源包随临时目录清理，不作为 APK 交付。

桌面 JVM/JNI 冒烟仍只证明跨语言消费。后续需设备上的资源准备、焦点/选区/编辑器动作和生命周期验收，以及移动设置页接入。当前键盘和首次准备页是原生预览布局，不代表 React 移动管理界面已完成。

## 原生库交叉构建

固定 NDK r28c (`28.2.13676358`)、Android API 28 与 vcpkg `ef7dbf94b9198bc58f45951adcf1f041fcbc5ea0`。vcpkg manifest 固定 Boost/fmt/spdlog/SQLite 来源；依赖和构建产物放在忽略的 target 下，不修改 Engine 子模块。需要先自行安装对应 SDK/NDK 和 Rust Android 目标；脚本不自动接受许可或启用 CI。

```sh
git clone --depth 1 --branch 2025.06.13 https://github.com/microsoft/vcpkg.git target/tooling/vcpkg
target/tooling/vcpkg/bootstrap-vcpkg.sh -disableMetrics
rustup target add aarch64-linux-android x86_64-linux-android
ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-native.sh arm64-v8a
ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-native.sh x86_64
```

可用 `MSIME_VCPKG_ROOT`、`MSIME_ANDROID_NDK` 指定绝对路径。脚本校验固定版本后安装锁定依赖，构建 release Rust/C++ 宿主和 JNI，SQLite 静态链接；产物为 `target/android/jniLibs/<abi>/{libmsime_host_api.so,libmsime_android.so,libc++_shared.so}`。验证脚本检查 ELF 架构、16 KB LOAD 对齐、动态依赖白名单与宿主/JNI 导出。NDK 和 vcpkg 声明复制到 `target/android/notices/<abi>`，正式分发还需汇总 Rust/Engine 与词库许可材料。

当前提供 arm64-v8a 与 x86_64 构建路径；没有 32 位 ABI、Windows 构建脚本或设备运行保证。原生库不能直接当作 APK，需使用下述脚本打包并进行运行验收。

## 开发 APK 与首次准备

本地构建：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-apk.sh <已锁定词库目录>`。需要前述 NDK/vcpkg/JDK/Rust 工具及 zip；脚本先通过共享 ResourceStore 校验资源，再构建双 ABI 库，用 SDK aapt2/d8/zipalign/apksigner 生成并验证 `target/android/msime-client-preview.apk`。APK 含六份锁定资源和原生许可声明；仅供本地开发测试，完整分发许可审计仍未完成，不发布到应用商店。签名前进行 16 KB zip 对齐，签名后再验证。

开发密钥在忽略的 `target/android/development.keystore`，不得用于正式发行；清理该文件会改变后续开发签名，不能直接覆盖安装由旧密钥签名的包。构建临时文件留在 target/android 便于排查，不触碰任何设备。

用户打开启动页并点击“准备词库”后，后台任务在私有目录解包资源，调用共享 Rust/C++ 校验与工作数据准备，成功后通过 AtomicFile 发布配置。已有配置一律不覆盖，失败可重试；不支持在线升级已运行的词库。解包和工作词库复制需要额外存储空间。启动页只提供手动进入系统设置/选择器的按钮，不自动启用或切换输入法。

本地已验证 APK 包结构、双 ABI、启动 Activity、IME 声明、签名与对齐；尚未验证安装、资源准备按钮或系统输入交互。工具契约参考 [d8](https://developer.android.com/tools/d8)、[zipalign](https://developer.android.com/tools/zipalign) 与 [apksigner](https://developer.android.com/tools/apksigner)。

系统契约参考：[InputMethodService](https://developer.android.com/reference/android/inputmethodservice/InputMethodService) 与 [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)。
