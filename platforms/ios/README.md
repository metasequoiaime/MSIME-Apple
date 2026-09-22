# iOS App 与键盘扩展

## 目录结构与验证边界

App 业务位于 `App/Sources/<feature>/`，键盘扩展位于 `KeyboardExtension/Sources/<feature>/`，共享 SwiftUI/UIKit 位于 `SharedUI/<feature>/`；`KeyboardTests/`、`ServiceTests/`、`TransportTests/` 和 `UITests/` 分别覆盖键盘、服务、桥接和界面边界。Tauri 生成工程位于 `apps/desktop/src-tauri/gen/apple`，不在其中维护第二份键盘实现。

Swift 单元/配置测试与模拟器构建只证明源码和桥接可编译。Xcode target 签名、App Group 权限、ML Kit 真机模型、键盘扩展启用、真实编辑器和生命周期仍需设备验收；缺少 `target/ios/EngineResources` 时，构建会按文档先执行资源暂存步骤，不把失败描述为宿主接入完成。

`MSIMEClient.xcodeproj` 包含设置 App、`UIInputViewController` 键盘扩展和共享 Swift 适配层。输入算法与组合状态仍由 C++ Engine 管理；扩展只负责宿主事件、候选展示和文本提交。键盘扩展不直接使用桌面音频采集桥接。

`apps/desktop/src-tauri/gen/apple` 下的 Tauri 生成工程是共享设置界面的构建产物来源，使用 iOS 17 最低版本和同一 `group.app.msime.ios` App Group。它服务于原生宿主承载共享界面这一用途，**不作为 iOS 的产品 App 分发或启动**；当前树里它仍带着自己的 App bundle identifier 和入口，这部分正在按上面的架构纠正。原生入口只解析系统提供的共享容器 URL 并注入状态根；偏好校验、并发 revision 和首次 HostOptions 默认文档仍由 Rust 共享层负责。生成工程链接 Engine 所需的系统 SQLite，并从既有 `target/ios/EngineResources` 嵌入固定词库。

共享 Tauri 语音面板通过 `tauri-mobile-platform` 在 App 进程内使用 `AVAudioRecorder` 录制 16 kHz、单声道、PCM16 WAV，最长 60 秒；停止后把有界录音上传到当前 `PreferencesStore` 中选择的服务。OpenAI、SiliconFlow 和 Groq 使用 HTTPS multipart 批量转写；Doubao 使用 WSS、共享 `client-core` 鉴权策略和帧编解码 ABI，并按 Windows 的 200 ms PCM16 分帧发送。两种传输都禁止重定向并限制接口、模型、token、音频、消息、累计响应和识别文本大小；取消会停止录音或网络请求并删除临时文件。provider 凭据只在 Rust 与原生插件之间传递，不进入 WebView、日志或键盘扩展。

**iOS 的产品宿主是 `platforms/ios` 的原生 App（`MSIMEApp`）**，它承载应用生命周期、图标与设置界面，并嵌入 `MSIMEKeyboardExtension`。Tauri/React 在 iOS 上是**公共组件**——提供跨平台共享的功能与界面，由原生宿主按需承载——**不是产品本体，也不作为独立 App 启动**。扩展继续从 `platforms/ios` 编译唯一一份原生键盘、共享 UI、宿主桥接与平台服务源码，不依赖常驻桌面服务；App 与扩展各自打包已校验词库，并通过 App Group 共享状态。真机 target 使用锁定的 ML Kit Digital Ink 8.0.0，arm64 模拟器使用明确的无识别 fallback。

共享账户页的设置同步以 MSIME-Apple 远端 `develop@81e79abec7b53e7243fb8cbe82a42a4dde1e528f` 为固定来源，上传和应用输入方案、双拼方案、简繁、九键、按键音、触感及强度、词库学习、键盘皮肤、当前自定义皮肤，以及共享输入偏好中的调频方式、触发次数和线性步长（`input.frequency_mode`、`input.frequency_trigger_count`、`input.frequency_linear_step`）。Tauri 继续由 `BackendAccountSession` 持有 Keychain 会话；WebView 只接收有界标量设置，不接收 token。iOS 平台适配器在 App Group UserDefaults 与共享 `PreferencesStore` 间同步键盘可直接修改的状态，应用前完整校验，Rust 偏好保存失败时恢复原生快照；未知平台字段原样保留在云端。iOS 英文建议开关属于键盘扩展直接读取的 App Group 原生偏好，由移动键盘反馈接口维护，不作为账号云同步字段，避免下载旧云值覆盖设备上的原生选择。凭据、联网授权、输入内容、词库和打字统计不进入设置同步。

iOS 云剪贴板复用共享账号会话和 Tauri `CloudClipboardPanel`，只上传用户在面板中明确输入的文本，不读取系统剪贴板。列表、搜索、启停、添加和删除均由 `client-core` 校验后访问账号服务；复制动作通过 iOS 平台插件写入 `UIPasteboard`，限制为 4000 个 UTF-16 单元且拒绝 NUL。只有本地剪贴板历史已开启时，复制后的文本才会进入已有 App Group 历史。

键盘扩展与共享 Tauri 统计页都从 App Group 的 `MSIME/typing-statistics.json` 读取聚合计数，并以同一锁文件串行更新。升级时若只存在旧 Swift App 写在 App Group 根目录的统计文件，会在双端加锁并验证后原子移动到共享状态目录；迁移和日常记录都只包含分类计数，不保存实际输入文本。

键盘扩展通过共享宿主策略执行智能标点的三条规则。**重复标点转中文**：刚以 ASCII 上屏逗号、句点或冒号后两秒内再按同一个键，把它换成中文标点并结束这次手势；只在文档里确实还是第一次按下留下的那个字符时才触发，组字中、有候选、换了编辑器都不算。**空格转英文**：刚上屏一个中文标点后按空格，把它改回 ASCII 并吞掉空格——人是在改刚打出来的那个标点，不是打了标点再打空格；这一条默认关闭，因为它改写的是用户已经看着落下去的字符。两者的快照由键盘持有而不是放进会话：它们属于宿主的编辑器，而键盘收起时会话会被销毁重建，一个跨过那道缝还活着的手势是错的。editor generation 取 `documentIdentifier` 的前八个字节，不用 `hashValue`（Swift 的哈希按进程加种子）。第三条是**直出**：中文跟随模式且 Engine 空闲时，逗号、句点或冒号紧跟 ASCII 字母或数字**且共享偏好中对应的 `smart_punctuation_direct_letter` / `smart_punctuation_direct_digit` 已开启**时保留 ASCII——这两个开关默认关闭，未开启时仍走 Engine 的中文标点；锁定中文或英文优先；已有组合、日语、英文和本地模式仍交给 Engine。扩展只从 `UITextDocumentProxy.documentContextBeforeInput` 提取紧邻光标的一个 Unicode 标量，不保存或记录宿主文字；中文/日文键帽显示值会先映射回 Engine 的 ASCII 标点输入，缺失上下文安全回退到 Engine 标点。

表情浏览器以远端默认分支固定来源 `MSIME-Apple@7de60fb5c5590f33e7f515db7e595a1d7e848ad1` 为交互基线，在空闲候选工具栏和“更多”面板提供入口，按 Unicode 固定顺序显示最近、笑脸、人物、动物、食物、旅行、活动、物品、符号和旗帜，每行八项，支持删除和返回。为适配共享客户端架构，iOS 不复制 Apple 扩展内的 SQLite 读取器，而是在串行后台队列通过共享 C ABI 分页读取已验证 `others.db`；每页、游标、文本和注释均有边界校验，过期分类结果不会覆盖当前页。选择后通过正常 `UITextDocumentProxy` 路径插入并记录最多 24 项的去重最近使用；打开面板前先由 Engine 完成已有组合，不保存或记录编辑器上下文。

Apple 客户端旧版 `english.mixedCandidates` 布尔值在创建首个共享输入会话前一次性迁移到 `mixed_input.english`。迁移使用共享偏好存储的 revision CAS；成功后删除旧键，冲突或写入失败则保留旧键供下次重试。共享配置中的触发阈值、Emoji 与颜文字字段原样保留，iOS 不建立第二套偏好源，也不复制 Engine 的英文候选算法。

“更多”面板的“全角输入”开关与 Android 保持同一宿主边界：开启后，只把键盘直接输出的可打印 ASCII 与空格转换为 Unicode 全角形式；Engine 候选、组合文本、日语、手写、本地模式、剪贴板、AI、语音和表情保持原文。开关保存在 iOS App Group 的键盘偏好中，不重建 Engine，也不会中断当前组合。

键盘按宿主给出的 trait 区分手机与平板形态（`KeyboardFormFactor`），不按机型判断：只有 regular 宽度的 iPad 才画平板键盘，iPad 的浮动键盘、Slide Over 与台前调度里的窄窗口是 compact 宽度，和系统键盘一样退回手机布局，停靠与浮动切换时随 size class 变化重新布局。平板键盘更高且横屏比竖屏高，第三排字母末尾带逗号和句号（中文模式显示中文标点，仍以 ASCII 交给 Engine）。iPad 没有 Taptic Engine，键盘「更多」面板、App 的输入设置和皮肤编辑器在非 iPhone 上不显示按键振动与振动强度；存储值不被改写，设置同步仍把它原样带给用户的 iPhone。

App 的「键盘」标签页同样分形态：iPad 在 regular 宽度下是侧栏加详情的分栏（`TabletSettingsView`），我的键盘、皮肤、输入方案、按键、词库、AI 各占一栏，切换栏目时详情重建一条新的导航栈；iPhone（包括横屏时同为 regular 宽度的 Max 机型）与 iPad 的窄窗口仍是卡片首页加单栈推入。

iOS 26 会默认在滚动视图边缘叠加渐隐和模糊。键盘内的候选、拼写、方案、皮肤、工具、表情、手写、AI、语音和回复面板统一通过共享 UIKit/SwiftUI 适配关闭该效果，避免短面板首尾内容被遮盖；iOS 25 及更早版本保持原行为。

“更多”工具面板使用显式分组模型，不从中文标题推断布局或开关语义。根页是表情、剪贴板、AI、语音、本地输入五个入口，加上直接摆在同一页的「设置」分组开关——繁体输出、按键音、按键振动、全角输入和振动强度；这些开关原先藏在「键盘设置」卡片后面，打开面板只看得到六张一样的入口卡，要再点一次才知道按键音开没开。本地输入仍然是二级页：八个模式是一份列表而不是一组开关，摊到根页会把首屏内容挤出键盘高度。

手写方案在真机构建中使用锁定的 ML Kit Digital Ink 8.0.0。模型下载会为键盘扩展创建的后台 URLSession 注入 App Group 共享容器；没有完全访问或共享容器不可用时明确失败，不把模型写入扩展私有临时目录。Apple Silicon 模拟器继续编译不依赖 ML Kit 的同界面 fallback，因为该 SDK 的 arm64 slice 是 device 平台而不是 simulator 平台。fallback 不冒充识别成功，也不沉默：它在自己的状态行上写明「此版本不含手写识别，请使用真机版本」——只画笔画什么都不说，和键盘坏了无从区分。真机构建通过 CocoaPods workspace 链接 SDK。

## 按键延迟

一次按键的成本由 `KeystrokeLatencyTests` 逐键计时，共享层那一侧由 `cargo run -p msime-host-api --example keystroke_latency <verified-resources>` 单独测。两者都报分布而不是均值：掉帧来自尾部，而均值会把它藏在同一个词里那些便宜的键后面。

真机实测（iPhone 17，Release，释义按出厂默认开着）：

| | 2026-09-21 之前 | 现在 |
| --- | --- | --- |
| 普通词字母键 p50 / p95 / max | 6.78 / 16.21 / 26.89 ms | 2.91 / 5.48 / 6.59 ms |
| 高频音节（`yi`）p50 / p95 / max | 21.46 / 30.73 / 51.97 ms | 5.23 / 5.52 / 10.76 ms |
| 空格 p50 | 2.38 ms | 1.50 ms |
| 一次 ABI 往返连同解析 p50 | 0.67 ms | 0.62 ms |

共享运行时不在这条预算里：走真实 ABI 的探针是 p50 0.47ms、p95 1.06ms，并且按组合长度看是平的。

三条改动依次是：把 `local_mode` 与 `nine_key_spellings` 放进快照（此前每键三十次 C ABI 往返，其中二十六次在遍历字母键的循环里）、按输入签名门控 `updateKeyboardLayout`、以及把释义请求去抖 120ms（此前每键遍历全部候选，`yi` 有几百个）。

**测这条路径时先确认释义开关是开的。** 这套测试里别的用例会把它关掉，而设置写在 App Group 里、跨测试运行持续存在；关着测出来的 `yi` 只有 3.3ms，和普通词没区别，问题完全隐形——上面那 21.46ms 就是这么漏掉过一轮的。两个延迟用例现在都显式恢复出厂默认。

## 开发构建

准备交叉编译目标，并准备一个提供 Boost 的依赖前缀：

```sh
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
rustup component add llvm-tools
```

Engine 不再是子模块，无需手动初始化：`engine-lock.json` 记录提交与源码归档的 SHA-256，`crates/engine-bridge` 的构建脚本会在构建时校验并准备 `vendor/MSIME-Engine`。离线构建一棵已准备好的树时设 `MSIME_SKIP_ENGINE_FETCH`。

Xcode 27 的 SwiftPM 会把静态库中的 `@_cdecl` 导出内部化；当前 `swift-rs` 构建桥会使用 `llvm-tools` 中的 `llvm-objcopy` 恢复应用 package 的符号。仓库同时固定到上游 PR #79 的提交 `a83e2b2f196e3fa9605cb21c7d3b82652205c279`，使传递嵌入的 SwiftRs runtime 导出在优化构建中保持公开。缺少该组件或移除补丁时，Tauri iOS Rust 动态库会在链接阶段报告 Swift 桥符号未定义。

词库必须来自仓库固定的 `resources/desktop-dictionary.lock.json`。安装器下载并校验发布文件，暂存脚本再次检查名称、长度与 SHA-256，只把允许的六个运行资源复制到 `target/ios/EngineResources`：

```sh
resource_dir="$(cargo run --quiet -p msime-client-core --example install_resources -- target/resources)"
platforms/ios/stage-resources.sh "$resource_dir"
```

只构建 Rust/C++ 宿主库时运行：

```sh
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  platforms/ios/build-native.sh simulator
```

Engine 只用到 Boost 的头文件（`find_package(Boost REQUIRED)` 之后链接 `Boost::headers`），所以依赖前缀不需要为 iOS 交叉编译过的 Boost 二进制，任何提供完整头文件与 CMake 配置的前缀都可以，例如 Homebrew 的 `/opt/homebrew/Cellar/boost/<version>`。

`device` 目标产出 `target/ios/device/libmsime_host_api.a`，`simulator` 目标产出 arm64 的 `target/ios/simulator/libmsime_host_api.a`。脚本会自动识别依赖前缀下唯一的版本化 `BoostConfig.cmake` 与 `boost_headers-config.cmake`；有多个版本时，分别用 `MSIME_BOOST_DIR` 和 `MSIME_BOOST_HEADERS_DIR` 指向对应配置目录。

一条命令完成资源暂存、键盘扩展 native 构建，并构建 iOS 的产品宿主 `MSIMEApp`（同时嵌入键盘扩展）。要改为单独构建 Tauri/React 这个公共组件，在同一条命令前加 `MSIME_IOS_TAURI_COMPONENT=1`：

```sh
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  platforms/ios/build-app.sh "$resource_dir" simulator
```

## 真机签名构建

产品宿主 `MSIMEApp` 的装机走 XcodeGen 工程加 CocoaPods workspace，不经过 Tauri CLI。`build-app.sh … device` 固定 `CODE_SIGNING_ALLOWED=NO`，只验证编译与打包，产物装不上真机；要装机就直接调 `xcodebuild` 并允许签名：

```sh
resource_dir="$(cargo run --quiet -p msime-client-core --example install_resources -- target/resources)"
platforms/ios/stage-resources.sh "$resource_dir"
MSIME_IOS_DEPS=/opt/homebrew/Cellar/boost/<version> platforms/ios/build-native.sh device
cd platforms/ios && xcodegen generate -s project.yml -p . && pod install --deployment && cd -
xcodebuild -workspace platforms/ios/MSIMEClient.xcworkspace -scheme MSIMEApp \
  -sdk iphoneos -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath target/ios/derived-device -allowProvisioningUpdates \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES DEVELOPMENT_TEAM=LXCL4Z68GU build
xcrun devicectl device install app --device <udid> \
  target/ios/derived-device/Build/Products/Release-iphoneos/MSIMEApp.app
```

`-allowProvisioningUpdates` 是必须的：键盘扩展的描述文件要由 Xcode 联网刷新，新设备也在这一步注册进去。App 与 `MSIMEKeyboardExtension` 都以 team `LXCL4Z68GU` 的 Apple Development 证书签名，扩展侧带全部已校验词库，App bundle 约 241 MB。

下面这条是 Tauri/React 公共组件的签名构建，不是 iOS 的产品宿主装机路径：

```sh
cd apps/desktop/src-tauri/gen/apple && pod install --deployment && cd -
APPLE_DEVELOPMENT_TEAM=LXCL4Z68GU MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  pnpm --filter @msime/desktop tauri ios build --target aarch64 --ci
```

Tauri CLI 只把 `APPLE_DEVELOPMENT_TEAM` 应用到它自己的 App target，内嵌的 `MSIMEKeyboardExtension` 与 `MSIMESwiftRsRuntimeExports` 不会继承，签名构建会停在 `Signing for "MSIMEKeyboardExtension" requires a development team`。因此工程里为这两个 target 固定了 `DEVELOPMENT_TEAM`；`--no-sign` 构建不受影响（`CODE_SIGNING_ALLOWED=NO` 时该设置不参与）。需要换团队时在 `xcodebuild` 命令行覆盖同名设置。

首次签名构建前需要在 Xcode 的 Settings → Accounts 里登录该团队的 Apple ID：App 的开发描述文件（含 `group.app.msime.ios` App Group，且已包含目标设备）本机已有，但键盘扩展的 `com.metasequoiaime.client.keyboard` 还没有，必须由 Xcode 联网创建。没有登录账号时构建会报 `No Accounts: Add a new account in Accounts settings`，并退回到不含 App Groups 能力的通配描述文件。本机的 Xcode 现已登录该团队，`app.msime.ios` 与 `app.msime.ios.keyboard` 的开发描述文件都在本地且包含目标设备，原生宿主的签名构建与装机已按上面那条路径执行；Tauri 公共组件这条路径仍未做过签名构建。

2026-09-21 在 iPhone 17（`00008150-00061D123478401C`）上重跑了一次这条路径：`BUILD SUCCEEDED`，产物 229 MB，`PlugIns/MSIMEKeyboardExtension.appex` 内嵌全部十个已校验运行资源，App 由 `Apple Development: PENG HU (8D3N5Y5T7G)` 签名，`devicectl device install app` 成功，设备上 `devicectl device info apps` 能查到「水杉输入法 / app.msime.ios / 1.0.0」。

**验收到此为止，再往下需要设备解锁。** `devicectl device process launch` 被 `SBMainWorkspace` 以 `Locked` 拒绝（`FBSOpenApplicationErrorDomain error 7`），所以启动、抓屏、在系统设置里启用键盘扩展、以及在真实编辑器里打字都没有做。按 [ARCHITECTURE.md](../../ARCHITECTURE.md) 的证据分级，这次到达的是第 5 级里的「安装与签名」，不含「真实编辑器验收」。

确认改动真的进了产物不要用 `strings`：键面提示是运行时从引擎的 profile 表拼出来的，二进制里没有 `ing uai` 这样的字面量；`@_silgen_name` 引用的 C ABI 名也在链接时解析掉了。用 `nm` 查符号——`MetasequoiaInputSessionBridge.shuangpinKeyHints` 下应当挂着一个 `withUnsafeBytes` 闭包，`msime_client_shuangpin_key_hints` 与 `msime_engine_bridge::ffi::ShuangpinKeyHint` 应当出现在 Rust 侧的 mangled 符号里，而旧的 `makeShuangpinHints` 应当是 0 个。

真机产物把最后一个参数改为 `device`。真机构建会在 `apps/desktop/src-tauri/gen/apple` 执行锁定的 CocoaPods 安装，再调用 Tauri CLI；模拟器使用 `aarch64-sim` 并保留手写 fallback。无签名构建只验证源码、链接和 bundle 内容，不代表键盘扩展已经安装、授权或完成真机宿主验证。

真机目标当前产出 `apps/desktop/src-tauri/gen/apple/build/arm64/水杉输入法.ipa`：arm64 单架构，`Payload/水杉输入法.app` 内嵌 `PlugIns/MSIMEKeyboardExtension.appex`，扩展侧带锁定 ML Kit Digital Ink 的资源包，App 与扩展各自打包同一份已校验 EngineResources。这只说明真机目标能完整编译和打包；签名、安装、键盘启用与真实编辑器验收仍未执行。

模拟器 bundle 默认不带签名，因此没有 App Group 授权：进程一启动就会在共享容器查找上拿到 `client is not entitled`。要在模拟器里真正安装并观察它，用 ad-hoc 签名把既有 entitlements 附上去（模拟器不校验 provisioning，这一步不需要任何开发者证书，也不改变真机的签名边界）：

```sh
app="apps/desktop/src-tauri/gen/apple/build/arm64-sim/水杉输入法.app"
codesign -f -s - --entitlements platforms/ios/KeyboardExtension/Resources/MSIMEKeyboardExtension.entitlements "$app/PlugIns/MSIMEKeyboardExtension.appex"
codesign -f -s - --entitlements apps/desktop/src-tauri/gen/apple/msime-desktop_iOS/msime-desktop_iOS.entitlements "$app"
xcrun simctl install booted "$app"
```

签名后 App Group 查找成功（日志里 `container_create_or_lookup…: success`），但 iOS 27 模拟器上进程仍会在启动时 SIGTRAP，release 与 debug 构建一致，`simctl erase` 后的干净设备上同样复现。崩溃报告里实测到的调用链是 `+[NSBundle bundleWithIdentifier:]` → `_CFBundleGetBundleWithIdentifier` → `_CFBundleEnsureBundleExistsForImagePath` → `__CFBundleCopyFrameworkURLForExecutablePath` → `CFRelease` 的空指针陷阱；应用侧的调用者帧未符号化。据此推断调用方为 `wry::platform_webview_version`：它是依赖树里唯一调用 `bundleWithIdentifier` 的位置，`tauri-runtime-wry` 在 `Wry::init` 中无条件执行 `wry::webview_version().is_ok()`，且 `com.apple.WebKit` 与该函数的错误字符串都能在产物二进制里找到；wry 0.57 的同一函数未改动。结论是这条路径在仓库代码之外，未修改任何 vendored crate；在它解决之前，模拟器只能验证到构建、打包与安装，界面与键盘扩展的运行仍需真机。

## 运行 iOS Swift 测试

`KeyboardTests/`、`ServiceTests/` 与 `TransportTests/` 通过遗留 Xcode 工程的测试宿主在模拟器上运行。准备好 `target/ios/EngineResources` 与模拟器原生库之后：

```sh
xcodegen generate -s platforms/ios/project.yml -p platforms/ios
xcodebuild test -project platforms/ios/MSIMEClient.xcodeproj -scheme MSIMEClientTests \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro Max' \
  -derivedDataPath target/ios/derived-tests \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=YES
```

必须允许签名。测试宿主带 App Group entitlement，被测键盘要靠它读共享偏好；用 `CODE_SIGNING_ALLOWED=NO` 构建会剥掉 entitlement，宿主在套件中途被杀，后面的用例全部不报告。模拟器上 `CODE_SIGN_IDENTITY=-` 即 ad-hoc 签名，不需要任何开发者证书。

当前结果为 **229 通过、1 跳过、0 失败**（`MSIMEKeyboardTests` 176 含 1 跳过、`MSIMESharedTests` 38、`MSIMEServiceTests` 16；Xcode 27 / iOS 27.0 模拟器）。**先 `xcodegen generate`**：提交在仓库里的工程会漏掉后加的源文件（2026-09-21 实测漏 `KeyboardAppLauncher.swift`，整套编译不过），所以它不是权威来源，`project.yml` 才是。

跑之前建一台干净模拟器再删掉，不要用手边那台：测试宿主带 App Group，读的是共享容器里的偏好，上一次运行留下的值会改变结果。

```sh
device=$(xcrun simctl create msime-parity-check \
  com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro-Max com.apple.CoreSimulator.SimRuntime.iOS-27-0)
xcrun simctl boot "$device"
# …在上面的 xcodebuild 命令里用 -destination "platform=iOS Simulator,id=$device"…
xcrun simctl delete "$device"
```
这个数字要跟着改动更新：该套件不接入 `verify-local.sh`，没有自动基线，所以这一行是它唯一的基线，写错了就没有别的东西会发现。唯一跳过的是 `CandidateTranslationTests.testCandidateLongPressOffersGlossInsertion` 的「开启释义」分支：固定词库发布里没有该候选的英文释义来源（`translation-glosses.db` 是用户编辑后的覆盖层），取不到释义时跳过而不是报成产品失败，一旦有释义就自动恢复断言。

该套件目前不接入 `scripts/verify-local.sh`：它需要模拟器和已暂存的词库资源，单次运行约十分钟。

## 界面测试与键盘扩展的真机验收

`MSIMEClientUITests` 走 `xcodebuild test -scheme MSIMEClientUITests`，需要 `ARCHS=arm64 ONLY_ACTIVE_ARCH=YES`——原生库只有 arm64 切片，不加这两个设置时模拟器目标会按 x86_64 链接并在扩展上报未定义符号。

`KeyboardExtensionEditorUITests` 是唯一把键盘扩展当成系统键盘来用的一组用例：其余所有套件都直接在测试宿主里构造 `KeyboardViewController`，那条路覆盖不到只在运行期才存在的部分——系统是否真的加载这个扩展、扩展进程能否读到 App Group 共享容器、上屏文本是否真的到达别人的 `UITextDocumentProxy`。它要求键盘已在「设置」里启用；没启用时跳过而不是失败，并在跳过信息里带上当时键面上有什么。

**在 iOS 27 模拟器上，键盘能装上但切不过去。** 这两件事要分开说，我一开始混为一谈并写错过结论：

- **启用是成功的。** 往 `.GlobalPreferences` 写 `AppleKeyboards`（加上扩展 bundle id `app.msime.ios.keyboard`）并重启模拟器之后，设置 → 通用 → 键盘 → 键盘 里确实列着「水杉输入法 · 中文」。用一条临时 UI 测试走 Settings 把每一层的单元格文案打出来才看清这一点——此前只凭「键盘环里没有它」就断定写入无效，是错的。
- **切换是失败的。** XCUITest 到不了它。`app.buttons["Next keyboard"]` 点下去落在 shift 上（键面在 Q/q 之间来回，始终是同一个 `UIKeyboardLayoutStar`），长按它弹出的是单手键盘的「默认/右手/左手」菜单，里面一个键盘名字都没有——连已启用的简体拼音和英语都没有。`app.keyboards.buttons` 只有 `shift` / `emoji` / `Return` 三个。

把扩展排到 `AppleKeyboards` 数组第一位也不会让它成为默认键盘：新编辑框打开的仍是第一个**系统**键盘（实测是简体拼音），iOS 不会为第三方键盘做默认。所以模拟器上到不了「真实编辑器」这一级，差的就是那一下人手切换。

另外两条与启用无关，试过也无效，不必再走：`pluginkit -e use -i app.msime.ios.keyboard`（扩展本来就注册为 `com.apple.keyboard-service`，置 `+` 能跨重装保持，但和键盘环无关），以及 `App-prefs:General&path=Keyboard` 深链（命令返回成功，界面停在设置首页不跳转）。

真机上就是正常在 设置 → 键盘 里添加一次，之后这组用例会自己跑起来。

补回 `reachSettingsLink`、让这个目标重新编译之后，第一次完整运行是 39 执行、2 跳过、6 失败；那六条随后逐条查清并修好，**当前结果为 39 执行、2 跳过、0 失败**（917 秒）。两条跳过是上面那组键盘验收，等键盘在设置里启用后才会真正执行。

那六条都不是产品坏了，分三类，记在这里因为同样的坑很容易再踩：

- **断言了不存在的导航栏标题。** 首页、我的、打字统计都是 `navigationTitle("")`，名字有意放进了内容里。要判断「在哪一屏」，用选中的标签页加上只有那一屏才有的元素，不要用导航栏标题。
- **入口搬了家。** `voiceSettingsLink` 不在首页，活路径是 首页 → 按键 → 语音设置。同名标识符还留在 `KeyboardSettingsView` 上，而那个页面已经没有任何地方实例化——它是 `ce4a76844` 把入口搬到首页时留下的孤儿，朝它伸手会让「搬家」看起来像「缺失」。
- **滚动没有真的发生。** SwiftUI 的 `Form` 是惰性列表，折线以下的行不在无障碍树里，所以「先 `waitForExistence` 再滚」永远等不到也永远不滚；而 `app.swipeUp()` 从屏幕中心起手，在 键盘设置 页那是键盘预览，那块把上下拖动解释成**改行间距**——表单不动，还顺手改掉了马上要读的设置。要边滚边看，并且用坐标拖拽把起点压在预览以下、标签栏以上。

`MSIMEApp` 是 iOS 的产品宿主，装机与设备验收都以它为准，也是 `build-app.sh` 的默认产物，不需要任何开关。要单独构建 Tauri/React 这个公共组件时用 `MSIME_IOS_TAURI_COMPONENT=1` 显式选择。此前该脚本默认产出 Tauri 包、把原生宿主锁在 `MSIME_IOS_LEGACY_APP=1` 后面，并由一条测试固化，这与架构相反，已纠正。

**上面那条 SIGTRAP 只挡 Tauri 宿主，不挡这个。** `MSIMEApp` 不加载 WebView，在 iOS 27 模拟器上界面能正常起来，键盘扩展也随它一起装进去，所以要在模拟器上看界面就走这条路：

```sh
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix platforms/ios/build-native.sh simulator
xcodebuild -project platforms/ios/MSIMEClient.xcodeproj -scheme MSIMEApp \
  -destination 'platform=iOS Simulator,name=<设备名>' \
  -derivedDataPath target/ios/derived-sim CODE_SIGNING_ALLOWED=NO build
xcrun simctl install booted target/ios/derived-sim/Build/Products/Debug-iphonesimulator/MSIMEApp.app
xcrun simctl launch booted app.msime.ios
```

需要 `target/ios/EngineResources` 已按上面的暂存步骤就位，否则运行时找不到词库。

共享 Tauri iOS 工程的 CocoaPods workspace 与 `Pods` 目录只为真机 ML Kit 构建生成，不提交到仓库；模拟器从干净的 XcodeGen 工程直接构建 fallback。真机目标需要先安装锁定的 CocoaPods 依赖，然后从 Tauri CLI 启动构建；CLI 会为 Xcode 中的 Rust 构建脚本建立本地控制通道，因此不要直接用独立的 `xcodebuild` 命令代替：

```sh
cd apps/desktop/src-tauri/gen/apple
pod install --deployment
cd ../../../../..
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  pnpm --filter @msime/desktop tauri ios build --target aarch64 --no-sign --ci
```
