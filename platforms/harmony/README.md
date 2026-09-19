# HarmonyOS 输入宿主预览

OpenHarmony 适配保留 ArkTS/ArkUI 应用入口与 NAPI 原生边界。共享输入算法、组合状态、配置校验和资源准备继续由 Rust Host API 与 C++ Engine 提供；`platforms/harmony/native/client_napi.cpp` 只负责 NAPI 注册和 C ABI 转发，不复制候选分页或输入状态机。

Harmony 设置页也暴露共享的模糊拼音规则。设置保存到同一个 `PreferencesStore`，键盘宿主在准备 Engine 会话时读取并应用启用的规则；这项能力不依赖桌面窗口或设备专属 API。

手写方案使用 HarmonyOS Core Vision Kit 的 `textRecognition`：键盘内的 ArkUI Canvas 记录受界限约束的笔画，组件快照转换为 `PixelMap` 后交给系统 OCR，候选结果仍由共享 Engine 会话提交到编辑器。OCR 服务不可用时保留明确提示，不回退到伪造的 Engine 手写模型；该路径需要设备提供 `SystemCapability.AI.OCR.TextRecognition`。

语音输入使用 HarmonyOS Core Speech Kit 的 `speechRecognizer` 离线短语音模式。工具面板可以开始、停止或取消识别，最终文字经过长度和控制字符边界检查后通过当前 `KeyboardSession` 提交；原始音频始终留在系统服务内，不写入文件、不进入日志，也不复制到 Engine。该路径需要 `SystemCapability.AI.SpeechRecognizer` 和用户授予 `ohos.permission.MICROPHONE`，单次录音受系统 60 秒上限约束。

云联想与 AI 联想复用 Engine 的 `online_query` 代际契约：Harmony NAPI 只传递有界查询和结果，ArkTS 通过系统 HTTPS 栈异步访问云候选或用户配置的 Chat Completions 服务，结果再交回 Engine 做会话、偏好和 generation 校验。请求防抖、超时、响应大小、重复候选和控制字符检查均在宿主边界完成，失败只丢弃可选展示结果，不阻塞本地输入，也不把查询或响应写入日志。

候选翻译复用共享 `translation_query` 与 `apply_translations` 代际契约。Harmony 原生边界负责把 Tencent TMT、NiuTrans 和 DeepLX 兼容自定义 provider 的签名/请求描述器及响应解析暴露给 ArkTS，网络传输仍由 Harmony HTTPS 栈完成；本地英文词典释义先在 Engine 侧解析，在线结果只补齐缺失项。多语言释义合并为有界的 ` / ` 展示文本，按 provider、目标语言和词条缓存，过期或 generation 不匹配的结果不会污染当前候选页。英文目标的成功释义通过共享 ABI 写入用户词典覆盖层，凭据只存在于当前请求内，不写日志。

共享设置中的“顶部语音入口”现在也会驱动 Harmony 触屏键盘：开启后，快捷栏会显示麦克风入口并直接打开系统识别；`voice_input.enabled` 关闭时，顶部入口和“工具”面板卡片都会隐藏，保持平台特性与 Windows 的可选语音开关一致。

共享设置中的“语音面板主题”也由 Harmony 消费：`dark`/`light` 覆盖全局主题，`follow` 继承全局主题；语音面板使用当前键盘皮肤的对应明暗调色板。

共享设置中的自定义触摸键盘皮肤也由 Harmony 消费：选择 `custom` 时读取共享设计的颜色、圆角、边框、透明度和键面字体属性；原生皮肤选择器会展示同一份设计，避免设置页保存了设计但键盘仍绘制默认皮肤。

共享设置中的触摸输入方案启用列表也由 Harmony 消费：输入方案选择器只展示启用的方案，切换当前方案时保留其余启用/禁用状态，不会因为一次选择把用户隐藏的方案重新打开。

## 目录结构

- `entry/src/`：ArkTS 应用与键盘宿主源码。
- `native/`：NAPI/C++ 适配层。
- `tests/`：不依赖设备的 TypeScript 键盘逻辑测试。
- `AppScope/`、`entry/src/main/resources/`：应用元数据和资源。
- `build-native.sh`、`stage-resources.sh`：共享 Host API、NAPI 库和固定资源的构建/暂存入口。

设置页的本地词库管理复用共享设置 UI 和 `msime_client_dictionary`：可分页查看、编辑、导入、导出和处理失败队列。ArkTS 设置桥只接受操作 JSON；引擎资源和状态目录始终由宿主从应用沙盒准备，WebView 不能提交路径。词库写操作需要 Engine 独占维护窗口：空闲时会短暂重建会话并恢复语言、九键和焦点状态；正在组合输入时会返回忙碌错误，不会替用户取消输入。读取操作可与活动会话并行。

## 本地构建

准备 DevEco Studio 提供的 OpenHarmony NDK，或设置 `MSIME_OHOS_NDK` 指向包含 `build/cmake/ohos.toolchain.cmake` 的 NDK。先安装依赖（根目录 `pnpm install --frozen-lockfile`），准备对应 Rust target、目标 ABI 的 SQLite 前缀和 Boost/fmt/spdlog CMake 配置目录。非 Homebrew 布局需显式设置 `MSIME_BOOST_DIR`、`MSIME_BOOST_HEADERS_DIR`、`MSIME_FMT_DIR` 和 `MSIME_SPDLOG_DIR`，再运行：

```sh
resource_dir="$(cargo run --quiet -p msime-client-core --example install_resources --locked -- target/resources)"
bash platforms/harmony/stage-resources.sh "$resource_dir"
MSIME_OHOS_NDK=/absolute/openharmony/native \
MSIME_OHOS_DEPS=/absolute/ohos-deps/arm64-v8a \
bash platforms/harmony/build-native.sh arm64-v8a
cd platforms/harmony
# 使用 DevEco SDK 配套且已加入 PATH 的 hvigorw
hvigorw assembleHap
```

支持 `arm64-v8a`、`armeabi-v7a` 和 `x86_64`。原生库暂存到 `entry/libs/<abi>/`，这些目录是构建产物，不提交到仓库。资源准备仍使用根目录固定的 `resources/desktop-dictionary.lock.json`，不得把本机路径、凭据或用户输入放入 HAP。

## 验证边界

不依赖设备的逻辑回归：

```sh
bash platforms/harmony/tests/run.sh
```

该命令编译并运行 `tests/keyboard-logic.test.ts`。`build-native.sh` 只证明指定 OpenHarmony NDK 下的 Rust/C++/NAPI 交叉构建和 ELF 导出检查；`hvigorw assembleHap` 只证明 HAP 打包。当前没有 HarmonyOS 真机或模拟器运行证据，未完成系统输入法注册、焦点/选区、生命周期、签名、麦克风授权流程、Core Speech Kit 实际识别和设备编辑器验收，因此不能把交叉构建描述为平台接入完成。
本切片已完成主机边界与 HAP 打包验证，但仍需在 HarmonyOS 真机或模拟器上确认设置页的文件选择、沙盒资源暂存、编辑器焦点恢复以及实际词库读写；设备验证前不宣称完成平台接入。
