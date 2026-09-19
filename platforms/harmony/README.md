# HarmonyOS 输入宿主预览

OpenHarmony 适配保留 ArkTS/ArkUI 应用入口与 NAPI 原生边界。共享输入算法、组合状态、配置校验和资源准备继续由 Rust Host API 与 C++ Engine 提供；`platforms/harmony/native/client_napi.cpp` 只负责 NAPI 注册和 C ABI 转发，不复制候选分页或输入状态机。

Harmony 设置页暴露共享的模糊拼音规则、触摸输入方案启用列表、自定义触摸键盘皮肤设计和候选英文释义开关。这四项此前都只有键盘一侧在消费：`PreferencesStore` 里有值，键盘准备 Engine 会话时会读，但设置页从未开启对应的客户端开关，用户没有任何途径改动它们。它们各自只写共享偏好，不需要平台能力。

手写方案使用 HarmonyOS Core Vision Kit 的 `textRecognition`：键盘内的 ArkUI Canvas 记录受界限约束的笔画，组件快照转换为 `PixelMap` 后交给系统 OCR，候选结果仍由共享 Engine 会话提交到编辑器。OCR 服务不可用时保留明确提示，不回退到伪造的 Engine 手写模型；该路径需要设备提供 `SystemCapability.AI.OCR.TextRecognition`。

语音输入使用 HarmonyOS Core Speech Kit 的 `speechRecognizer` 离线短语音模式。工具面板可以开始、停止或取消识别，最终文字经过长度和控制字符边界检查后通过当前 `KeyboardSession` 提交；原始音频始终留在系统服务内，不写入文件、不进入日志，也不复制到 Engine。该路径需要 `SystemCapability.AI.SpeechRecognizer` 和用户授予 `ohos.permission.MICROPHONE`，单次录音受系统 60 秒上限约束。

云联想与 AI 联想复用 Engine 的 `online_query` 代际契约：Harmony NAPI 只传递有界查询和结果，ArkTS 通过系统 HTTPS 栈异步访问云候选或用户配置的 Chat Completions 服务，结果再交回 Engine 做会话、偏好和 generation 校验。请求防抖、超时、响应大小、重复候选和控制字符检查均在宿主边界完成，失败只丢弃可选展示结果，不阻塞本地输入，也不把查询或响应写入日志。

候选翻译复用共享 `translation_query` 与 `apply_translations` 代际契约。Harmony 原生边界负责把 Tencent TMT、NiuTrans 和 DeepLX 兼容自定义 provider 的签名/请求描述器及响应解析暴露给 ArkTS，网络传输仍由 Harmony HTTPS 栈完成；本地英文词典释义先在 Engine 侧解析，在线结果只补齐缺失项。多语言释义合并为有界的 ` / ` 展示文本，按 provider、目标语言和词条缓存，过期或 generation 不匹配的结果不会污染当前候选页。英文目标的成功释义通过共享 ABI 写入用户词典覆盖层，凭据只存在于当前请求内，不写日志。

录音行为的四个共享开关现在也由 Harmony 消费——设置页的说明一直写着"录音期间的提示音与静音由输入法在本机处理"，而此前本宿主一项都不做。开始与结束提示音使用 Windows 安装包同一份 `start.mp3` / `end.mp3`（同样的字节，放进模块的 `rawfile/audios/`），经 AVPlayer 播放，播放器随每次提示音创建并释放：键盘扩展不是媒体应用，为一段不到一秒的声音常驻一条音频管线不值得。`sound_enabled` 是两个提示音之上的总开关。"录音时静音其他音频"通过 `AudioSessionManager.activateAudioSession` 以 `CONCURRENCY_PAUSE_OTHERS` 实现，录音结束或取消时 `deactivateAudioSession` 归还；该项默认关闭，从正在播放的应用手里拿走音频会话是侵入性的。取消的录音不播结束音——没有识别结果可宣告。以上任何一步失败都只记日志，不影响录音本身。

2in1 硬件键盘补齐 Windows 的五个语音快捷键，各自受共享 `voice_input.hotkey_*` 开关控制：右 Alt 长按录音、Ctrl+Win 与 Ctrl+右 Alt 两个长按和弦、录音中按空格锁定（松开长按键不再结束）、Ctrl+F9 开始/停止（也用于结束已锁定的录音），录音中按 Esc 取消。设置页一直显示这五个开关，此前本宿主一个也不消费。空格与 Esc 只在录音时被占用，其余时刻仍归组合输入；长按键的重复按下不算第二次请求。录音状态由绘制识别面板的视图告知会话，识别自行结束（拿到最终结果或 provider 失败）时会清掉长按与锁定，否则下一次按下长按键会被当成一次并不存在的录音的释放。

共享设置中的“顶部语音入口”现在也会驱动 Harmony 触屏键盘：开启后，快捷栏会显示麦克风入口并直接打开系统识别；`voice_input.enabled` 关闭时，顶部入口和“工具”面板卡片都会隐藏，保持平台特性与 Windows 的可选语音开关一致。

共享设置中的“语音面板主题”也由 Harmony 消费：`dark`/`light` 覆盖全局主题，`follow` 继承全局主题；语音面板使用当前键盘皮肤的对应明暗调色板。
共享设置中的“表情面板主题”和“手写面板主题”也由 Harmony 消费：各自的 `dark`/`light` 覆盖全局主题，`follow` 继承全局主题；两个面板分别使用当前键盘皮肤的对应明暗调色板。
共享设置中的“工具栏主题”也由 Harmony 消费：`dark`/`light` 覆盖全局主题，`follow` 继承全局主题；浮动工具栏保留当前键盘皮肤和候选皮肤的安全 CSS 覆盖，但使用该主题解析出的基础明暗调色板。

共享设置中的自定义触摸键盘皮肤也由 Harmony 消费：选择 `custom` 时读取共享设计的颜色、圆角、边框、透明度和键面字体属性；原生皮肤选择器会展示同一份设计，避免设置页保存了设计但键盘仍绘制默认皮肤。

共享设置中的触摸输入方案启用列表也由 Harmony 消费：输入方案选择器只展示启用的方案，切换当前方案时保留其余启用/禁用状态，不会因为一次选择把用户隐藏的方案重新打开。

该开关此前在共享设置页写死只给 Android，Harmony 读得到却改不了；现在由 `HostCapabilities::english_suggestions` 决定，iOS 因为把同名开关放在原生 App Group 存储里而不声明该能力、继续用它自己的那个。

直接英文输入现在有只读的英文补全，与 Android / iOS 一致，并受共享 `english_suggestions` 开关控制。查询走已有的共享 C ABI `msime_client_english_completions_request`（本次由 NAPI 导出）：它不创建 Engine 会话，因此可以离开 UI 线程。光标前的词按字母向前读到边界，全角字母归一为 ASCII——用户在全角模式下打的仍然是英文单词。少于两个字母不查询：一个字母能匹配词库的大半，却要为每次按键付一次查询。补全列表画在候选条上（直接英文没有组合，候选条本来是空的），点选前重新读取光标前的词，若编辑器已经改变就放弃，避免删掉补全从未涉及的文本。回复在进入候选条之前做长度与类型校验。

悬浮工具栏的“设置”按钮现在也读共享 `floating_toolbar.settings`：此前它是唯一关不掉的按钮，使设置页那个开关在本宿主上是一个没有结果的控件。关闭后工具栏按可见按钮重新计算宽度，和其余组件一致。

2in1 硬件键盘补齐 Windows 基线的三个模式快捷键：`Ctrl+Shift+E` 切换中英文状态、`Ctrl+Shift+Space` 切换全角/半角、`Ctrl+.` 切换中英文标点。Linux 宿主同样实现这三个。它们不属于设置页可关闭的那四项绑定——Windows 把它们定死，关掉 Shift 单击并没有对 `Ctrl+Shift+E` 表态。标点走的是工具栏按钮已经在用的那条偏好写入路径，而不是另起一套 live session 开关：同一个开关两套机制正是两边开始不一致的起点。`InputModeRouting` 此前没有任何测试，本次连同原有的单击修饰键判定一起补上。

2in1 硬件键盘补齐 Windows 的维护快捷键 `Ctrl+Shift+Alt+1–8`：删除候选栏对应位置的候选词。触屏上这个动作走长按菜单，而硬件键盘没有长按这个手势，该和弦是它唯一的入口。按下后由会话校验该位置是否存在候选、以及其来源是否允许词库删除——云候选、AI、Emoji 和日语候选来自 Host API 会拒绝的来源，此时不执行；但按键仍然被占用，否则一个游离的 `1` 会落进编辑器。

共享设置中的“双拼预编辑”（`shuangpin_preedit_uses_raw`）现在也出现在 Harmony 的设置页。该偏好一直由 Engine 消费，但控件此前只给 macOS；Harmony 的组合行直接绘制 Engine 的 `editing_text`，原始双拼按键与展开拼音的区别在这里是看得见的，所以由 `HostCapabilities::shuangpin_preedit` 决定而不是平台名。设置页也补上了手写说明：手写走系统文字识别，笔迹不离开本机；设备不提供该能力时手写方案会明确提示，不回退到其他识别方式。

共享设置中的“中英文状态范围”现在也由 Harmony 消费，并由 `HostCapabilities::ime_mode_scope` 能力而非平台名决定是否出现：编辑器属性自 API 14 起带 `bundleName`，键盘据此按应用记忆中英文状态，这也是共享默认值 `app`。此前无论哪个应用都共用一个模式。`global` 保持所有输入上下文同一状态。范围在编辑器激活时读取，不在组合中途改变。密码框、地址框这类要求拉丁字母的编辑器覆盖是编辑器的选择而非用户的，不写入记忆，否则在某个应用里填过一次密码就会让之后每次进入该应用都停在英文。该映射只存在于键盘进程生命周期内，不落盘：它是一份"用户在哪些应用里打字"的记录，偏好文件没有理由携带，而忘记它的代价只是重启后多按一次切换键。最多记住 64 个应用，超出时丢弃最久未使用的。

`build-native.sh` 在本机的实际边界（2026-09-19 核实）：OpenHarmony NDK 与 Boost 具备，`msime-client-core` 对 `aarch64-unknown-linux-ohos` 的 `cargo check` 通过；但 `msime-engine-bridge` 的 build.rs 要求 `MSIME_OHOS_DEPS` 指向一个为设备编译的 sqlite3 前缀，仓库不携带 sqlite3 amalgamation，也没有获取它的固定来源。因此本机能证明的是 ArkTS 编译与 HAP 打包（`hvigorw assembleHap`）和共享 Rust 层的交叉检查，**不包括** NAPI 动态库本身。当前 HAP 不含 `entry/libs/<abi>/`，在真机上是空壳；补齐需要先按脚本提示为目标 ABI 准备 sqlite3。

按键音与振动现在也能从设置页调整，而不只是键盘内那张卡片：共享 `mobileKeyboardFeedback` 客户端读写键盘自己的 `key-feedback.json`，两个进程共用同一份文件（这项设置属于当前设备而非账号，所以不进共享偏好）。设置页是第二个写入者，改动在键盘下次启动时生效。强度预览直接振一下。共享 DTO 把最强一档叫 `strong`，键盘自己的枚举叫 `heavy`，两边由 `KeyboardFeedbackBridge` 转换——直接赋值会写入键盘不认识的值，`KeyboardFeedback.parse` 会静默回退，表现为"保存了但手感没变"。

设置页的字体输入现在能列出系统已装字体：`listFontFamilies` 桥接 ArkUI 的 `font.getSystemFontList()`，宿主只过滤掉带控制字符的名字，去重和排序留给共享页面，以免各宿主给出不同顺序的同一份列表。

共享设置中的候选窗英文字体（`candidate_english_font`）现在也由 Harmony 消费：该名字排在中文字体之前进入 ArkUI 的字体族列表，由渲染器逐字形回退，因此拉丁字母取自英文字体、汉字落到中文字体。未设置时仍是单一字体族，与此前行为相同。该控件此前在共享设置页被一串平台名挡住，Harmony 不在其中——宿主读了这个字段而用户改不到它；现在改由 `HostCapabilities::candidate_english_font` 决定。

共享设置中的录音设备选择现在也由 Harmony 提供：设置页通过 `AudioRoutingManager` 列出输入设备，保存的是设备类型加地址组成的稳定标识，而不是每次会话重新分配的 `id`。HTTP ASR 与豆包两条路径各自创建 `AudioCapturer`，因此在建流前用 `AudioSessionManager.selectMediaInputDevice` 指定所选设备；路由属于音频会话而非单条流，所以每次录音都重新指定一次。所选设备被拔掉、路由被系统拒绝、或保存的 backend 属于别的平台时，都回到系统默认设备继续录音，不中断，也不把 Windows 端点标识或 PulseAudio source 名当成 Harmony 设备重新解释。系统语音识别（Core Speech Kit）由服务自行取音，不受该选择影响。

键盘自己的输入方案选择器现在和共享设置页写同一组字段：选中日语时把被替换的中文方案记进 `last_chinese_scheme`，`scheme`、`shuangpin_profile`、`touch_keyboard_layout` 一起更新。此前只写 `scheme`，于是从键盘切到日语后，设置页的「中文」单选只能退回 quanpin，五笔或双拼用户会看到方案被忘掉。当前值按磁盘上的文档读取，设置页是第二个写入者；随后的写入仍做 revision 比对，真正的冲突照样被拒绝。

共享设置中的“中英文切换提示”现在也由 Harmony 消费，并改由 `input_mode_hud` 宿主能力而非平台名决定是否出现在设置页。2in1 上模式徽标只在该偏好开启且没有悬浮工具栏时创建；关闭后不再占用那一个 STATUS_BAR 面板名额。手机形态本来就在键面上显示模式，不声明该能力。

候选的两项可选注释现在各读各的共享偏好，不再一律显示：`wubi_code_hint` 控制五笔剩余编码提示，字段缺省时按共享 `wubi_code_hint_enabled` 的默认开启处理；`candidate_english_gloss` 控制离线英文释义，共享默认关闭，只有文档明确写 `true` 才显示。Engine 注释仍优先占用同一个提示槽位。

## 目录结构

- `entry/src/`：ArkTS 应用与键盘宿主源码。
- `native/`：NAPI/C++ 适配层。
- `tests/`：不依赖设备的 TypeScript 键盘逻辑测试。
- `AppScope/`、`entry/src/main/resources/`：应用元数据和资源。
- `build-native.sh`、`stage-resources.sh`：共享 Host API、NAPI 库和固定资源的构建/暂存入口。
- `entry/src/main/resources/rawfile/settings/index.html`：设置页的单文件打包产物，由 `apps/harmony` 生成，见下方[设置页打包](#设置页打包)。

设置页的本地词库管理复用共享设置 UI 和 `msime_client_dictionary`：可分页查看、编辑、导入、导出和处理失败队列。ArkTS 设置桥只接受操作 JSON；引擎资源和状态目录始终由宿主从应用沙盒准备，WebView 不能提交路径。词库写操作需要 Engine 独占维护窗口：空闲时会短暂重建会话并恢复语言、九键和焦点状态；正在组合输入时会返回忙碌错误，不会替用户取消输入。读取操作可与活动会话并行。

## 设置页打包

`entry/src/main/resources/rawfile/settings/index.html` 是提交进仓库的构建产物，不要手工编辑。它由 `apps/harmony` 生成：

```sh
pnpm --filter @msime/harmony build
```

之所以提交而不是在打包时生成，是因为 `hvigorw assembleHap` 不会调用 Node 工具链；HAP 打包时这个文件必须已经在 rawfile 里。它也必须是**单文件**：`resource://` 文档的 origin 为 null，WebView 会拒绝跨 origin 拉取模块脚本和样式表，所以脚本、样式和资源全部内联进 HTML，因此体积在 1 MB 以上。改动共享设置 UI（`packages/ui`）后需要重新生成并连同源码一起提交，否则 HarmonyOS 上看到的还是旧界面。

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

`hvigorw assembleHap` 是必须跑的一道门，不是可选项。ArkTS 的几条限制——`@Builder`/`build` 体内不能声明局部变量、修饰符不能挂在 `if/else` 上、对象字面量必须对应已声明的接口——都不会被 `tests/run.sh` 或任何 TypeScript 检查发现，因为那些只编译 `.ts`，不编译 `.ets`。曾经有 33 个这样的错误一路进到 develop，HAP 整段时间根本打不出来。改过 `.ets` 就跑一次打包。

不依赖设备的逻辑回归：

```sh
bash platforms/harmony/tests/run.sh
```

该命令编译并运行 `tests/keyboard-logic.test.ts`。`build-native.sh` 只证明指定 OpenHarmony NDK 下的 Rust/C++/NAPI 交叉构建和 ELF 导出检查；`hvigorw assembleHap` 只证明 HAP 打包。当前没有 HarmonyOS 真机或模拟器运行证据，未完成系统输入法注册、焦点/选区、生命周期、签名、麦克风授权流程、Core Speech Kit 实际识别和设备编辑器验收，因此不能把交叉构建描述为平台接入完成。
本切片已完成主机边界与 HAP 打包验证，但仍需在 HarmonyOS 真机或模拟器上确认设置页的文件选择、沙盒资源暂存、编辑器焦点恢复以及实际词库读写；设备验证前不宣称完成平台接入。
