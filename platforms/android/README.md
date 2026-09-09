# Android 输入宿主预览

`NativeClient` 提供 Java/Kotlin 到共享运行时的 JNI 传输。UTF-8 字节数组保留非 BMP 字符，避免 JNI modified UTF-8 损坏候选或资源路径。JNI 负责释放 C API 响应；上层解析 ok/value，负责会话线程和生命周期。

`MSIMEInputService` 提供实际 InputMethodService 源码、系统 manifest 和输入法元数据；最小 Android 28，编译目标 35。软键盘、硬件 ASCII 键、候选点击和翻页调用同一 JNI；Engine 提交与剩余编辑串通过 `EditorBridge` 按顺序映射到 InputConnection。宿主不实现输入算法或分页规则。密码、非文本和无建议字段直接输入，不创建 Engine；IME_FLAG_NO_PERSONALIZED_LEARNING 关闭当前会话学习。没有输入日志或网络权限。

配置缺失、原生库不可用或输入连接错误会显示状态并退回直接输入。服务从应用私有 files 目录读取 `runtime-options.json`，路径必须指向已在设备上准备的词库与私有用户目录，不能复制 macOS 的配置路径。开发 APK 的启动页提供首次资源准备；源码、打包与签名检查通过不代表设备运行通过。

本地检查：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/check-host.sh`。需要 JDK 17+、Android API 35 和 build-tools 35.0.0。脚本编译全部服务 Java、执行不依赖 Android 运行时的文本/敏感字段策略测试，并校验 manifest/resource；中间资源包随临时目录清理，不作为 APK 交付。

桌面 JVM/JNI 冒烟仍只证明跨语言消费。后续需设备上的资源准备、焦点/选区/编辑器动作和生命周期验收，以及移动设置页接入。当前键盘和首次准备页是原生预览布局，不代表 React 移动管理界面已完成。

## 共享设置热更新

新 bootstrap 配置包含绝对路径 `preferences_directory`。输入会话启动后，Android 后台读取该目录的共享 PreferencesStore，之后每秒重试；不在输入主线程等待文件锁，不重叠读取，切换编辑器或结束输入后丢弃旧读取结果并停止旧轮询。已有配置没有目录字段时保留原行为，不猜测其他应用的数据目录。

JNI `loadPreferences` 只读取共享层，快照回到会话主线程后调用同一个 `updatePreferences`；revision 校验、组词期间延迟应用和重建失败保护仍在 Rust 中。更新只刷新候选视图，不用空预编辑覆盖现有编辑器内容。相同视图和状态不反复重建键盘控件。密码等直接输入字段不启动配置轮询；禁止个性化学习的编辑器在创建和每次快照应用时均强制关闭学习。

读取或应用失败保留当前输入会话，显示非阻断提示，后续继续重试；不写入默认值覆盖坏文件。React 移动管理页尚未接入，本阶段验证的是共享文件到系统 IME 的自动应用，不代表完整移动设置产品已完成。

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

本地已验证 APK 包结构、双 ABI、启动 Activity、IME 声明、签名与对齐；Android 15 arm64 专用模拟器已验证安装、首次准备、已有配置不覆盖，以及软键盘通过系统 InputConnection 上屏、退格和密码直接输入。x86_64 仍只有交叉构建证据，不代表真机或完整生命周期验收。工具契约参考 [d8](https://developer.android.com/tools/d8)、[zipalign](https://developer.android.com/tools/zipalign) 与 [apksigner](https://developer.android.com/tools/apksigner)。

## 专用模拟器验收（仅本地）

预先安装 `system-images;android-35;default;arm64-v8a`，在一个终端运行 `ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/tests/device/start-emulator.sh`。脚本在忽略的 target/android/avd-home 中创建 msime-client-test，固定 emulator-5580，不使用已有个人 AVD；目标端口属于其他 AVD 时拒绝运行。需要额外磁盘空间，测试结束后应停止该专用模拟器以释放内存；脚本不会下载系统镜像、自动接受许可或启动 CI。

完成上述 APK 构建、等待系统启动后，在另一终端运行 `ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/tests/device/smoke.sh emulator-5580`。该命令会安装预览包和独立合成编辑器、准备资源，并在专用 AVD 上启用和选择 MSIME；拒绝非模拟器或名称不符的设备，不对现有真机执行操作。测试不会清空应用数据，重复执行覆盖已有配置路径而非重新模拟首次安装。

独立 instrumentation 读取编辑器与输入法的交互窗口，等待窗口稳定后重新定位并注入触摸，断言“你好”提交、退格、“直接输入”状态和密码框字符长度；不记录编辑器原文。普通 uiautomator dump 只用于准备 Activity，不能用它缺少输入法节点推断键盘未显示。APK fixture 不随产品打包。

同一 smoke 脚本还执行同开发签名的 PreferencesDeviceSmoke，instrumentation 以预览应用为目标，直接在其私有测试目录原子发布合成设置，无需给产品增加导出的测试写接口。目标进程重启后重新绑定专用 AVD 的 IME；测试组词延迟、提交保留、页大小与标点生效、损坏文件保护以及恢复重试。结束时恢复原偏好文件（原本不存在则删除测试文件），不清空资源和用户数据。该测试必须经专用 AVD 检查的 smoke 脚本执行，不安装在个人设备。

共享核心单元测试也可在该 AVD 实际执行（从仓库根运行，以下工具链为 macOS 主机）：

```sh
export ANDROID_SDK_ROOT=<SDK绝对路径>
android_toolchain="$ANDROID_SDK_ROOT/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin"
CC_aarch64_linux_android="$android_toolchain/aarch64-linux-android28-clang" \
AR_aarch64_linux_android="$android_toolchain/llvm-ar" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$android_toolchain/aarch64-linux-android28-clang" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_RUNNER="bash $PWD/platforms/android/tests/device/run-core-test.sh" \
cargo test -p msime-client-core --lib --target aarch64-linux-android --locked
```

8 项测试在 Android 上通过，包含独立 PreferencesStore 的并发冲突和资源失败保护。Android 标准库文件锁不可用，共享锁封装在该目标使用 rustix 安全 flock，其他目标保留标准库锁；不放宽共享核心的 unsafe 禁令。Android 15 的启动页和软键盘均应用系统栏 inset，避免操作被 ActionBar 或导航栏遮挡。后续仍需真机、其他 Android 版本、旋转/进程重建、外部选区、候选翻页及 React 移动设置页验收。

系统契约参考：[InputMethodService](https://developer.android.com/reference/android/inputmethodservice/InputMethodService) 与 [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)。
