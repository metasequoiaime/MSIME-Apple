# Android 输入宿主预览

`NativeClient` 提供 Java/Kotlin 到共享运行时的 JNI 传输。UTF-8 字节数组保留非 BMP 字符，避免 JNI modified UTF-8 损坏候选或资源路径。JNI 负责释放 C API 响应；上层解析 ok/value，负责会话线程和生命周期。

`MSIMEInputService` 提供实际 InputMethodService 源码、系统 manifest 和输入法元数据；最小 Android 28，编译目标 35。软键盘、硬件 ASCII 键、候选点击和翻页调用同一 JNI；Engine 提交与剩余编辑串通过 `EditorBridge` 按顺序映射到 InputConnection。宿主不实现输入算法或分页规则。密码、非文本和无建议字段直接输入，不创建 Engine；IME_FLAG_NO_PERSONALIZED_LEARNING 关闭当前会话学习。没有输入日志或网络权限。

软键盘的主按键区按 Apple 键盘的基础层次拆成字母层和符号层；字母层支持可见的 Shift 状态，符号层保留标点、括号和数字，两个层次均通过无障碍描述暴露当前按键。层次排列由无 Android 依赖的 `KeyboardLayout` 提供，便于在主机测试中验证布局不被宿主生命周期改变。

候选区独立显示当前组合文本、当前页和候选按钮；候选超过一个时可展开当前页的无障碍候选面板，面板内可直接选择或收起，翻页仍通过共享运行时的命令完成。Android 宿主不复制候选算法或分页规则，展开面板明确标注“当前页”，避免把当前页误报为完整候选列表。

输入服务现在消费共享 `candidate_skin` 偏好，将 fluent、wechat、graphite 和 willow_green 映射为 Android 键盘、候选区及展开面板的背景、按键色、前景色、边框圆角和等宽字体样式；设置热更新后不重建输入会话，只重新应用视觉样式。未知皮肤 ID 回退到 fluent，不把用户设置值当作颜色或资源名直接使用。

配置缺失、原生库不可用或输入连接错误会显示状态并退回直接输入。服务从应用私有 files 目录读取 `runtime-options.json`，路径必须指向已在设备上准备的词库与私有用户目录，不能复制 macOS 的配置路径。开发 APK 的启动页提供首次资源准备；源码、打包与签名检查通过不代表设备运行通过。

本地检查：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/check-host.sh`。需要 JDK 17+、Android API 35 和 build-tools 35.0.0。脚本编译全部服务 Java、执行不依赖 Android 运行时的文本/敏感字段策略测试，并校验 manifest/resource；中间资源包随临时目录清理，不作为 APK 交付。

桌面 JVM/JNI 冒烟仍只证明跨语言消费。后续需真机上的焦点/选区/编辑器动作和完整生命周期验收。当前键盘和首次准备页是原生预览布局；React 设置页的 Android 合包与验证见下文。

## Tauri + React 共享设置合包

推荐本地构建入口：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-client-apk.sh <已锁定词库目录> [arm64-v8a|x86_64]`。默认 arm64-v8a，产物仍为 target/android/msime-client-preview.apk；需要先完成根目录 pnpm install --frozen-lockfile，准备 JDK 21、Android API 36、build-tools 35、固定 NDK/vcpkg 与 Rust Android target。Gradle 8.14.3 使用官方分发摘要固定，AGP/Kotlin 版本由项目固定。参数 --ci 仅用于 Tauri CLI 的非交互模式，不运行 GitHub CI。

apps/desktop/src-tauri/src/lib.rs 是桌面与移动共用的 Tauri commands/入口，Android 调用同一个 client-core PreferencesStore，指向应用私有 files/bootstrap/state，与 bootstrap 和 IME 监控目录一致。packages/ui 的 React 页没有 Android 副本。生成的 Android 工程已纳入源码，Gradle 直接引用 platforms/android/java、共享图标与暂存的锁定资源；不把原生宿主代码复制到 gen。不要重复执行 tauri android init 覆盖本仓定制。gen 中的本机路径、生成 Kotlin 绑定、native symlink、构建输出和本机配置仍忽略。

应用首次启动、缺少运行配置时进入已有 SetupActivity，准备成功后点击“打开共享设置”；不会自动启用或选择输入法。系统输入法设置入口也可打开共享设置页。Tauri 使用主进程，InputMethodService 使用同 UID 的独立 :ime 进程，通过文件锁和 revision 协作，不依赖设置窗口存活。这样 Tauri 退出最后一个窗口不会结束输入服务；不是通过让隐藏设置窗口常驻来维持输入。

此合包是本地开发产物，使用原开发签名和 versionCode 1，便于覆盖安装同一预览包，不代表正式发行的版本策略；不得发布开发密钥。原 build-apk.sh 保留为不含管理 UI 的原生宿主测试包入口。合包 arm64 已构建并设备验证；x86_64 合包入口尚未验收，不用以前的原生 x86_64 构建冒充 Tauri 合包证据。分发前还需完整 Rust/Tauri/Gradle/Engine/词库许可审计。

在专用 AVD 上运行 `ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/tests/device/smoke.sh emulator-5580 --settings`：保留原有输入与配置热更新测试，并在真实 Tauri WebView 中操作 React 表单，验证保存、共享 revision、重新读取与另一个进程中的实际标点上屏；测试不是直接调用保存 command 代替表单行为。独立控制端还连续两次打开/关闭设置，验证 :ime PID 不变且仍能上屏。测试中使用合成内容，并恢复原偏好文件；instrumentation 的强制停止与普通设置窗口关闭分开处理。

移动入口布局依据 [Tauri 移动应用入口约定](https://v2.tauri.app/start/migrate/from-tauri-1/#preparing-for-mobile)。本地观察到最后一个 Tauri 窗口关闭时主进程正常退出，故使用 :ime 隔离；不依赖在同进程中禁止退出后的未验证窗口重建行为。

## 共享设置热更新

新 bootstrap 配置包含绝对路径 `preferences_directory`。输入会话启动后，Android 后台读取该目录的共享 PreferencesStore，之后每秒重试；不在输入主线程等待文件锁，不重叠读取，切换编辑器或结束输入后丢弃旧读取结果并停止旧轮询。已有配置没有目录字段时保留原行为，不猜测其他应用的数据目录。

JNI `loadPreferences` 只读取共享层，快照回到会话主线程后调用同一个 `updatePreferences`；revision 校验、组词期间延迟应用和重建失败保护仍在 Rust 中。更新只刷新候选视图，不用空预编辑覆盖现有编辑器内容。相同视图和状态不反复重建键盘控件。密码等直接输入字段不启动配置轮询；禁止个性化学习的编辑器在创建和每次快照应用时均强制关闭学习。

读取或应用失败保留当前输入会话，显示非阻断提示，后续继续重试；不写入默认值覆盖坏文件。共享 React 设置页在上述 Tauri 合包中使用同一个存储；完整移动产品、真机与其他平台仍待验收。

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

8 项测试在 Android 上通过，包含独立 PreferencesStore 的并发冲突和资源失败保护。Android 标准库文件锁不可用，共享锁封装在该目标使用 rustix 安全 flock，其他目标保留标准库锁；不放宽共享核心的 unsafe 禁令。Android 15 的启动页和软键盘均应用系统栏 inset，避免操作被 ActionBar 或导航栏遮挡。后续仍需真机、其他 Android 版本、旋转/系统回收后的完整进程重建、外部选区及候选翻页验收。

系统契约参考：[InputMethodService](https://developer.android.com/reference/android/inputmethodservice/InputMethodService) 与 [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)。
