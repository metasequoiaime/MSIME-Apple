# Linux IBus 预览宿主

本目录只处理 IBus 系统入口，使用同一个 `msime-host-api` 动态库；不直接创建 C++ Engine、不复制候选分页、数字选词或配置持久化逻辑，不依赖 Tauri 常驻。按键与焦点在 GLib 主线程调用线程绑定会话，系统候选点击取当前共享视图中的代次和全局索引。预编辑采用 Engine 的 ASCII editing_text，避免把字节光标用于中文显示串。失焦、禁用和 reset 清除组合；修饰键与 key-up 透传，快捷键取消组合后透传。密码、PIN、数字与电话字段不处理输入，private/no-spellcheck 文本会话关闭学习。

共享运行时只返回当前候选页；IBus lookup table 显示该页，auxiliary text 标示共享页码。宿主读取共享 navigation 六组设置，支持减号/等号、逗号/句号、方括号、Tab/Shift+Tab、PageUp/Down 翻页及上下候选移动，也支持小键盘导航键。设置通过验证后立即更新按键分派，不等待 Engine 组合结束；按键路径不读文件。按当前键盘布局的字符映射，Shift 符号不当作未按 Shift 的物理键，保留 Unicode `U+`。关闭的标点绑定交回 Engine，关闭的 Tab/Page/上下键先完成组合再交还编辑器；空闲时透传。Panel 翻页按钮独立于键盘绑定。尚未验证各桌面 panel 对原生翻页按钮的呈现；不把当前页伪装成完整候选集自行分页。

可选的 `online_provider_socket` 顶层启动配置指定用户管理的绝对 Unix socket。宿主复制在线查询后在 GLib worker 中请求该服务，再通过 Host API 的代次校验回填候选；未配置时不发起在线请求。socket 服务负责凭据、网络和 provider 策略。

语音输入通过可选的 `voice_provider_socket` 顶层绝对 Unix socket 接入。IBus 属性中的“语音输入”只负责启动和取消 Host API 语音代次；用户管理的 socket 服务收到 `{"version":1,"kind":"voice","query":{"language":"zh-cn","generation":1}}` 后负责 PipeWire/ALSA 录音、ASR 凭据和网络，并返回 `{"text":"识别结果"}`。结果回到 GLib 主线程后再次校验会话和代次，再提交文本；空结果、过期结果和取消结果都不会上屏。响应文本最多 4096 字节，服务调用最长等待 30 秒。`preferences.voice_input.enabled` 和 `preferences.voice_input.language` 控制属性是否可用及识别语言。

同一个 socket 也承载候选翻译请求。候选视图更新后，宿主发送一行 JSON：

```json
{"version":1,"kind":"translation","query":{"generation":9,"target_language":"en","candidates":["你好","世界"]}}
```

服务应在一行内返回 `{"translations":[{"text":"你好","translation":"hello"}]}`；未知候选可以省略。宿主只接受最多 9 个候选、每项最多 4096 字节、每次响应最多 500ms，并把返回的 generation 原样交给 Host API 校验；过期视图不会被更新。服务必须由用户管理绝对 Unix socket，负责所有凭据、网络访问和日志策略，输入法不会记录原始输入或 API Key。关闭 `preferences.candidate_translations` 后不会发起该请求。

Linux 独立手写面板使用同一类用户管理 Unix socket，不把 GTK、Wayland 或某个桌面环境绑定进 IBus Engine。面板采集归一化坐标笔画后，按一行 JSON 请求发送：

```json
{"version":1,"kind":"handwriting","query":{"language":"zh-CN","strokes":[[{"x":0.2,"y":0.3},{"x":0.7,"y":0.8}]]}}
```

识别服务返回 `{"candidates":["你","好"]}`，最多 12 个候选，每项最多 4096 字节；请求和响应各自限时 500ms。模型、凭据和平台识别器由该服务负责，面板可以用 `msime-client-handwriting /absolute/socket` 复用 Host API 契约。服务不可用或响应过期时面板保留笔画，不向 IBus 会话伪造提交；候选点击应由面板在当前手写请求代次内完成。

独立 Emoji 面板也可通过该 socket 查询目录。请求使用 `kind:"emoji"`，查询包含 `search`、`category` 和 `limit`；服务返回 `{"items":[{"text":"😀","annotation":"grinning face"}]}`。搜索最多 256 字节、分类最多 128 字节、结果最多 96 项，每项文本最多 64 字节、注释最多 256 字节，调用限时 500ms。面板使用 `msime-client-emoji /absolute/socket` 获取结果；没有 provider 时可用 `msime-client-emoji --local /absolute/resource-generation` 直接查询已验证的 `others.db`。点击后把文本交给桌面剪贴板或当前输入上下文；IBus Engine 仍只负责组合中的本地 Emoji 模式，不读取系统剪贴板。

桌面 Tauri 面板在 Linux 上也接入了屏幕键盘和手写候选提交。打开面板时宿主先保存当前输入目标：X11 使用 `xdotool getactivewindow`，Sway/Wayland 使用 `swaymsg -t get_tree`；按键通过目标窗口的 `xdotool key` 或 Wayland 的 `wtype` 发送，手写候选通过同一目标提交文本。手写识别服务的绝对 Unix socket 由 `MSIME_HANDWRITING_PROVIDER_SOCKET` 提供，服务仍负责模型和凭据；缺少注入工具或服务时面板保留可见状态并返回宿主错误，不伪造提交。

桌面 Tauri Emoji 面板在 Linux 上直接读取 HostOptions `resources` 下 Engine 提供的 `others.db`，通过 Engine bridge 分页读取完整 Emoji、颜文字和符号目录，并按数据库分类聚合后交给共享 UI；读取失败时 UI 保留内置目录。面板只接收资源目录中的目录数据，不读取用户输入、凭据或私人资料。

桌面 Tauri 面板在 Linux 上也接入了屏幕键盘和手写候选提交。打开面板时宿主先保存当前输入目标：X11 使用 `xdotool getactivewindow`，Sway/Wayland 使用 `swaymsg -t get_tree`；按键通过目标窗口的 `xdotool key` 或 Wayland 的 `wtype` 发送，手写候选通过同一目标提交文本。手写识别服务的绝对 Unix socket 由 `MSIME_HANDWRITING_PROVIDER_SOCKET` 提供，服务仍负责模型和凭据；缺少注入工具或服务时面板保留可见状态并返回宿主错误，不伪造提交。

IBus 属性面板提供 `EnglishCandidates`、`EmojiCandidates` 和 `KaomojiCandidates` 三个混输开关。切换属性会结束当前组合并重建本会话的 Engine，避免把新旧混输候选规则混在同一代视图中；覆盖只作用于当前 IBus 会话，不改写共享偏好文件。Windows 的设置窗口仍负责持久化配置，Linux 桌面 panel 只负责会话级快速切换。

IBus 属性面板还提供 `TraditionalOutput`。开启后，中文方案的候选显示和提交文本通过系统 ICU 的 `Simplified-Traditional` 转换器转换为繁体；Unicode 直接输入、日语方案和英文/Emoji 文本保持原样。这个开关只覆盖当前 IBus 会话，偏好文件中的 `traditional_chinese_output` 作为新会话默认值。

## 构建与运行

候选辅助文本在页码后展示 Engine 快照提供的本地模式标签（U+、日期时间、短语、Emoji、颜文字、简拼、EN、日文）。普通或未知模式不附加标签，取消组合或没有候选时隐藏辅助文本；不从预编辑前缀推断模式。

共享 `candidate_text_color` 设置在 IBus lookup table 候选上转换为 RGB 前景属性；未设置时交由 panel 主题决定。候选字体族、字号和回退字体仍由桌面 panel 的字体栈控制。

`tsf_preedit_style` 在 Linux IBus 中映射为：`raw` 显示 Engine 的 ASCII `editing_text`，`pinyin` 显示 Engine 的 `preedit`，`empty` 隐藏预编辑；设置热重载会更新当前会话的显示样式。候选与上屏仍由 Engine 的共享状态决定。

Windows 的 `clipboard_history` 依赖独立剪贴板监听器和候选历史 UI；IBus Engine API 不提供剪贴板事件、读取或历史面板。Linux IBus 宿主不会读取或记录剪贴板内容，即使共享设置开启也保持禁用，避免把输入法进程扩展成无提示的剪贴板监视器。Linux 剪贴板历史若需实现，应由独立、明确授权的桌面服务承载。独立工具的 `get INDEX` 操作会将已存储条目写到标准输出，`remove-index INDEX` 按历史位置删除单个条目，供桌面服务或 compositor 显式接管粘贴和删除动作；它不会写入或读取系统剪贴板。

`candidate_theme` 是 Windows 候选窗口的整体深浅主题覆盖。IBus Engine 只提交 lookup table 内容与文本属性，候选 panel 的背景、边框、间距和主题切换由桌面环境控制；Linux 保留共享设置，但不伪造 panel 主题覆盖。显式 `candidate_text_color` 仍按 IBus 前景属性传递。

个人词典维护使用共享 Host API 的独立 `msime-client-dictionary` 原生入口，不由 IBus 输入线程执行。它从标准输入读取一个不超过 65536 字节的 JSON 请求并输出 JSON 响应；请求格式和 `list`/`edit` 操作见 `msime_client.h`。调用方必须在编辑前停止使用相关词典的会话，API 负责共享访问锁、请求幂等和 Engine 原子写入；错误输出不包含词条内容。该入口不替代桌面设置页，便于 GTK/Qt 前端复用同一契约。

IBus 面板注册 `InputMode` 开关：选中时按当前输入方案转换，关闭时直接透传编辑器输入。面板符号为「文」或「A」，不把日语等已配置方案误标为中文。切到直接输入前通过 Engine 完成高亮组合；再次聚焦保留当前实例的选择，关闭期间的候选点击和翻页无效。密码等受限字段及失焦时开关不可用，恢复正常字段后继续使用原选择。目前不跨输入上下文或重启持久化，不占用桌面已有的输入源切换快捷键。

共享 `word_character` 支持方括号或减号/等号选择高亮候选的首/末汉字，默认关闭；与同组翻页配置互斥，由共享配置校验拒绝冲突。启动及实时设置发布均更新绑定，活动组合保留；宿主将当前候选代次和全局索引传给 Engine，不自行切分汉字。无汉字候选走共享组合完成与标点路径，关闭功能后恢复通常的标点输入；Shift 符号不触发以词定字。

需要 Linux、Rust 1.97.1、CMake 3.25+、C++17 编译器、IBus 1.5.20+ 开发包、nlohmann-json 3.11+、Boost/fmt/spdlog/SQLite 开发包。原生构建：

```sh
cargo build -p msime-host-api --locked
cmake -S platforms/linux -B target/linux-ibus
cmake --build target/linux-ibus
cargo run -p msime-host-api --example prepare_host --locked -- /absolute/verified-resources /absolute/new-preview-state
target/linux-ibus/msime-client-ibus /absolute/new-preview-state/runtime-options.json
```

准备配置必须在没有会话使用该状态目录时执行。运行入口动态注册独立的 `msime-client-preview`，不安装系统组件、不修改旧 Linux 产品或自动切换用户输入法；关闭进程即结束本次注册。安装后的 component 通过 `msime-client-ibus-launcher` 启动，默认读取 `~/.config/msime-client/runtime-options.json`；也可用 `MSIME_IBUS_OPTIONS` 指向已准备好的绝对路径。launcher 按自身目录定位 Engine，支持自定义安装前缀。库与运行配置含开发路径，目前不是可分发安装包。宿主监听配置 JSON 的写入和原子替换事件；后续新焦点会话使用新配置，正在组合的会话保持原设置直到结束。

Linux 桌面设置保存时会先按 `PreferencesStore` 的 revision 规则写入 `preferences.json`，随后以原子替换同步同一 HostOptions 的 `preferences` 到 `MSIME_IBUS_OPTIONS`，或 `MSIME_CLIENT_HOST_OPTIONS` 指向的 `runtime-options.json`；未设置前者时，桌面应用也可直接用 `MSIME_IBUS_OPTIONS` 作为 HostOptions 来源。这样正在运行的 IBus 预览宿主可以通过已有文件监听接收新设置；同步失败会把保存命令报告为存储错误，避免界面误报已同步。

安装时可使用 `cmake --install target/linux-ibus`。安装产物包含 IBus 主程序、`msime-client-dictionary` 个人词典请求入口、`msime-client-clipboard` 剪贴板历史工具、`msime-client-handwriting` 手写识别请求入口和 `msime-client-emoji` Emoji 目录请求入口；工具与主程序使用相同的安装前缀。需要预置系统配置时，在 CMake 配置阶段传入 `-DMSIME_RUNTIME_OPTIONS_FILE=/absolute/runtime-options.json`，安装到 `${CMAKE_INSTALL_SYSCONFDIR}/msime-client/runtime-options.json`。该文件必须来自已准备且匹配安装环境的状态目录，不能直接分发开发机上的私人状态。

## 隔离验证

候选操作也通过 IBus 属性菜单提供：对当前候选页的 1–9 槽位分别注册固定和删除动作，动作携带当前视图代次调用共享 Host API；桌面 panel 不支持 Windows 式右键候选窗时仍可使用该菜单路径。

`bash platforms/linux/tests/check-container.sh /absolute/verified-resources` 创建专用 Linux 容器，源码与词库只读挂载，构建缓存仅写入本仓 target/linux。基础 Rust 镜像固定摘要，apt 开发依赖来自 Debian bookworm 仓库；不声称所有系统包字节级可复现。容器内创建独立 D-Bus 和 IBus daemon，不连接宿主桌面，不修改现有输入源，结束后移除容器并保留构建缓存。

`engine_smoke` 使用真实共享库与固定 Release 词库，通过 D-Bus 调用实际 IBusEngine：验证预编辑与候选信号、上屏、第二页全局索引点击、标点、修饰键/key-up、快捷键取消、失焦、密码隔离与私密文本恢复。另启动实际宿主可执行文件，由独立 Python IBus 输入上下文通过 daemon/factory 输入合成拼音并接收提交。共享核心/运行时/宿主 25 项 Rust 测试纳入本地脚本。

已验证 Debian bookworm arm64、IBus 1.5.27。仍需真实 GTK/Qt 编辑器、X11/Wayland 焦点与选区、panel 位置、其他架构与发行版、安装打包以及 Tauri 设置自动重读。Linux IBus 预览宿主已连接配置文件监听；不是完整 Linux 产品迁移完成。CI 保持禁用。

系统行为依据 [IBus Engine API](https://ibus.github.io/docs/ibus-1.5/IBusEngine.html) 和 [IBus InputContext API](https://ibus.github.io/docs/ibus-1.5/IBusInputContext.html)。

`candidate_follow_cursor` 是 Windows 候选窗口的定位选项。IBus Engine API 只提供候选表和输入上下文光标位置的通知，不提供由输入法宿主固定 panel 锚点的接口；候选 panel 的定位由桌面 panel 自己决定。因此 Linux 会读取并透传该共享配置，但不伪造 Windows 的固定候选窗口行为：在 Linux 上候选表始终交给 IBus panel 按当前输入上下文位置呈现。该限制属于 IBus/桌面环境边界，不影响候选内容、分页或选词。

## Windows parity gaps

The Windows mode panel exposes fullwidth/halfwidth character output. Linux now carries a session-scoped `CharacterWidth` through `input-runtime` and `msime-host-api`; the IBus panel exposes `CharacterWidth` and commit text applies fullwidth conversion for printable ASCII. The mode is ephemeral and does not rewrite preferences. The IBus smoke fixture covers fullwidth and halfwidth ASCII commits; native GTK/Qt editor validation remains environment-specific.

Container acceptance also requires the locked Engine dictionary source `googlepinyinime-rev/src/share/dictbuilder.cpp`; without it, full daemon compilation cannot be validated.

IBus 注册入口通过 launcher 启动，配置优先级为 `MSIME_IBUS_OPTIONS`、用户的 `$XDG_CONFIG_HOME/msime-client/runtime-options.json`（默认 `~/.config`）、安装时配置的系统 runtime-options。显式覆盖或已存在但不可读的用户配置会报错，不会悄悄改用系统配置。直接运行 launcher 时可用第一个参数指定系统配置回退路径。

数字选词：IBus 属性菜单中的“数字选词”控制主键盘和小键盘 `1–0` 对当前候选页的选择，默认开启；状态按输入上下文保留，候选分页仍使用 Engine 提供的全局候选身份。候选表支持左键或中键选词、右键固定候选，操作会校验会话、代次和全局索引。
