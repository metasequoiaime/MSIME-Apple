# iOS App 与键盘扩展

`MSIMEClient.xcodeproj` 包含设置 App、`UIInputViewController` 键盘扩展和共享 Swift 适配层。输入算法与组合状态仍由 C++ Engine 管理；扩展只负责宿主事件、候选展示和文本提交。键盘扩展不直接使用桌面音频采集桥接。

共享 Tauri/React 设置宿主生成在 `apps/desktop/src-tauri/gen/apple`，使用正式 App bundle identifier、iOS 16 最低版本和同一 `group.app.msime.ios` App Group。原生入口只解析系统提供的共享容器 URL 并注入状态根；偏好校验、并发 revision 和首次 HostOptions 默认文档仍由 Rust 共享层负责。生成工程链接 Engine 所需的系统 SQLite，并从既有 `target/ios/EngineResources` 嵌入固定词库。

共享 Tauri 语音面板通过 `tauri-mobile-platform` 在 App 进程内使用 `AVAudioRecorder` 录制 16 kHz、单声道、PCM16 WAV，最长 60 秒；停止后才把有界录音以 multipart 上传到当前 `PreferencesStore` 中选择的 OpenAI、SiliconFlow 或 Groq HTTPS 批量转写接口。请求禁止重定向，并限制接口、模型、token、音频、响应体和识别文本大小；取消会停止录音或网络请求并删除临时文件。provider token 只在 Rust 与原生插件之间传递，不进入 WebView、日志或键盘扩展。Doubao 的 WebSocket 协议尚未接入这一原生链路，保留为后续独立迁移切片。

Tauri App 现直接依赖并嵌入既有 `MSIMEKeyboardExtension` target。扩展继续从 `platforms/ios` 编译唯一一份原生键盘、共享 UI、宿主桥接与平台服务源码，不依赖常驻桌面服务；App 与扩展各自打包已校验词库，并通过 App Group 共享状态。真机 target 仍使用锁定的 ML Kit Digital Ink 8.0.0，arm64 模拟器使用明确的无识别 fallback。既有 `MSIMEClient.xcodeproj` 暂时保留为原生测试和剩余 SwiftUI 设置页面的构建入口，后续页面迁移不再建立第二份键盘实现。

共享账户页的设置同步以 MSIME-Apple 远端 `develop@81e79abec7b53e7243fb8cbe82a42a4dde1e528f` 为固定来源，上传和应用输入方案、双拼方案、简繁、九键、按键音、触感及强度、词库学习、键盘皮肤与当前自定义皮肤。Tauri 继续由 `BackendAccountSession` 持有 Keychain 会话；WebView 只接收有界标量设置，不接收 token。iOS 平台适配器在 App Group UserDefaults 与共享 `PreferencesStore` 间同步键盘可直接修改的状态，应用前完整校验，Rust 偏好保存失败时恢复原生快照；未知平台字段原样保留在云端。凭据、联网授权、输入内容、词库和打字统计不进入设置同步。

iOS 云剪贴板复用共享账号会话和 Tauri `CloudClipboardPanel`，只上传用户在面板中明确输入的文本，不读取系统剪贴板。列表、搜索、启停、添加和删除均由 `client-core` 校验后访问账号服务；复制动作通过 iOS 平台插件写入 `UIPasteboard`，限制为 4000 个 UTF-16 单元且拒绝 NUL。只有本地剪贴板历史已开启时，复制后的文本才会进入已有 App Group 历史。

键盘扩展与共享 Tauri 统计页都从 App Group 的 `MSIME/typing-statistics.json` 读取聚合计数，并以同一锁文件串行更新。升级时若只存在旧 Swift App 写在 App Group 根目录的统计文件，会在双端加锁并验证后原子移动到共享状态目录；迁移和日常记录都只包含分类计数，不保存实际输入文本。

键盘扩展通过共享宿主策略执行智能标点：中文跟随模式且 Engine 空闲时，逗号、句点或冒号紧跟 ASCII 字母/数字会保留 ASCII，锁定中文或英文优先；已有组合、日语、英文和本地模式仍交给 Engine。扩展只从 `UITextDocumentProxy.documentContextBeforeInput` 提取紧邻光标的一个 Unicode 标量，不保存或记录宿主文字；中文/日文键帽显示值会先映射回 Engine 的 ASCII 标点输入，缺失上下文安全回退到 Engine 标点。

表情浏览器以远端默认分支固定来源 `MSIME-Apple@7de60fb5c5590f33e7f515db7e595a1d7e848ad1` 为交互基线，在空闲候选工具栏和“更多”面板提供入口，按 Unicode 固定顺序显示最近、笑脸、人物、动物、食物、旅行、活动、物品、符号和旗帜，每行八项，支持删除和返回。为适配共享客户端架构，iOS 不复制 Apple 扩展内的 SQLite 读取器，而是在串行后台队列通过共享 C ABI 分页读取已验证 `others.db`；每页、游标、文本和注释均有边界校验，过期分类结果不会覆盖当前页。选择后通过正常 `UITextDocumentProxy` 路径插入并记录最多 24 项的去重最近使用；打开面板前先由 Engine 完成已有组合，不保存或记录编辑器上下文。

Apple 客户端旧版 `english.mixedCandidates` 布尔值在创建首个共享输入会话前一次性迁移到 `mixed_input.english`。迁移使用共享偏好存储的 revision CAS；成功后删除旧键，冲突或写入失败则保留旧键供下次重试。共享配置中的触发阈值、Emoji 与颜文字字段原样保留，iOS 不建立第二套偏好源，也不复制 Engine 的英文候选算法。

“更多”面板的“全角输入”开关与 Android 保持同一宿主边界：开启后，只把键盘直接输出的可打印 ASCII 与空格转换为 Unicode 全角形式；Engine 候选、组合文本、日语、手写、本地模式、剪贴板、AI、语音和表情保持原文。开关保存在 iOS App Group 的键盘偏好中，不重建 Engine，也不会中断当前组合。

iOS 26 会默认在滚动视图边缘叠加渐隐和模糊。键盘内的候选、拼写、方案、皮肤、工具、表情、手写、AI、语音和回复面板统一通过共享 UIKit/SwiftUI 适配关闭该效果，避免短面板首尾内容被遮盖；iOS 25 及更早版本保持原行为。

“更多”工具面板使用显式分组模型，不从中文标题推断布局或开关语义。根页保留表情、剪贴板、AI、语音、本地输入和键盘设置六个入口；本地模式与键盘开关使用各自二级页，避免新增功能把首屏内容挤出键盘高度。

手写方案在真机构建中使用锁定的 ML Kit Digital Ink 8.0.0。模型下载会为键盘扩展创建的后台 URLSession 注入 App Group 共享容器；没有完全访问或共享容器不可用时明确失败，不把模型写入扩展私有临时目录。Apple Silicon 模拟器继续编译不依赖 ML Kit 的同界面 fallback，因为该 SDK 的 arm64 slice 是 device 平台而不是 simulator 平台；fallback 不冒充识别成功。真机构建通过 CocoaPods workspace 链接 SDK。

## 开发构建

先初始化固定的 Engine gitlink 与递归子模块，并准备一个提供 Boost 的依赖前缀：

```sh
git submodule update --init --recursive
rustup target add aarch64-apple-ios aarch64-apple-ios-sim
rustup component add llvm-tools
```

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

一条命令完成资源暂存、native 构建、XcodeGen 工程刷新和无签名 arm64 构建：

```sh
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  platforms/ios/build-app.sh "$resource_dir" simulator
```

真机产物把最后一个参数改为 `device`。无签名构建只验证源码、链接和 bundle 内容，不代表键盘扩展已经安装、授权或完成真机宿主验证。

共享 Tauri iOS 工程的 CocoaPods workspace 与 `Pods` 目录只为真机 ML Kit 构建生成，不提交到仓库；模拟器从干净的 XcodeGen 工程直接构建 fallback。真机目标需要先安装锁定的 CocoaPods 依赖，然后从 Tauri CLI 启动构建；CLI 会为 Xcode 中的 Rust 构建脚本建立本地控制通道，因此不要直接用独立的 `xcodebuild` 命令代替：

```sh
cd apps/desktop/src-tauri/gen/apple
pod install --deployment
cd ../../../../..
MSIME_IOS_DEPS=/absolute/ios/dependency-prefix \
  pnpm --filter @msime/desktop tauri ios build --target aarch64 --no-sign --ci
```
