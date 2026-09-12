# Linux IBus 预览宿主

本目录只处理 IBus 系统入口，使用同一个 `msime-host-api` 动态库；不直接创建 C++ Engine、不复制候选分页、数字选词或配置持久化逻辑，不依赖 Tauri 常驻。按键与焦点在 GLib 主线程调用线程绑定会话，系统候选点击取当前共享视图中的代次和全局索引。预编辑采用 Engine 的 ASCII editing_text，避免把字节光标用于中文显示串。失焦、禁用和 reset 清除组合；修饰键与 key-up 透传，快捷键取消组合后透传。密码、PIN、数字与电话字段不处理输入，private/no-spellcheck 文本会话关闭学习。

共享运行时只返回当前候选页；IBus lookup table 显示该页，auxiliary text 标示共享页码。宿主读取共享 navigation 六组设置，支持减号/等号、逗号/句号、方括号、Tab/Shift+Tab、PageUp/Down 翻页及上下候选移动，也支持小键盘导航键。设置通过验证后立即更新按键分派，不等待 Engine 组合结束；按键路径不读文件。按当前键盘布局的字符映射，Shift 符号不当作未按 Shift 的物理键，保留 Unicode `U+`。关闭的标点绑定交回 Engine，关闭的 Tab/Page/上下键先完成组合再交还编辑器；空闲时透传。Panel 翻页按钮独立于键盘绑定。尚未验证各桌面 panel 对原生翻页按钮的呈现；不把当前页伪装成完整候选集自行分页。

智能标点使用 IBus 提供的 surrounding text：逗号、句号和冒号前若是 ASCII 字母或数字，则保留 ASCII；否则交由 Engine 的中文标点表转换。正在组合时优先使用当前高亮候选的末字符，候选提交和标点在同一运行时转换中完成。重复输入的 ASCII 标点在短时间内可按设置替换为中文标点；失焦、删除或其他编辑动作会使该状态失效。无法取得有效 surrounding text 时按中文标点处理，不读取或记录完整编辑器内容。

候选快照同时携带 Engine 的来源编号，并与候选顺序绑定；GTK/Qt 或其他 Linux panel 可以据此区分词库、英文、Emoji、颜文字及在线候选，不需要从显示文本反推来源。来源只用于展示和交互提示，不改变候选身份、分页或提交文本。

候选注释也由 Engine 快照按候选顺序提供：启用帮助码时使用当前方案和帮助码表生成，无法生成时保留纠错提示。Linux 宿主只显示该注释，不重复实现帮助码计算。

可选的 `online_provider_socket` 顶层启动配置指定用户管理的绝对 Unix socket。宿主复制在线查询后在 GLib worker 中请求该服务，再通过 Host API 的代次校验回填候选；未配置时不发起在线请求。请求带有 `kind:"online"`，启用 AI 联想时还携带已校验的 provider、model、候选数量和提示词配置，但不携带 token；socket 服务负责凭据、网络和 provider 策略。独立入口 `msime-client-online /absolute/provider.sock` 从标准输入读取同一 OnlineQuery JSON 并输出受界限的 JSON 响应，供 GTK/Qt 面板或其他 Linux 宿主复用。也可用 `translation_provider_socket` 或 `MSIME_TRANSLATION_PROVIDER_SOCKET` 指定独立的候选翻译服务；未指定时翻译继续复用在线 socket。`MSIME_ONLINE_PROVIDER_SOCKET` 可作为在线 socket 的环境变量回退。

运行中的 IBus 会话会在配置文件热重载时同步读取新的在线、翻译和语音 provider socket；在线请求立即失效，正在使用旧语音服务的录音会被取消。未聚焦或尚未创建会话时，新焦点直接使用最新配置。

`preferences.cloud_candidates` 会随 OnlineQuery 传给 provider；关闭后宿主不发起仅云候选请求，并拒绝返回的云来源候选，但仍保留符合条件的 AI 联想。

IBus 属性菜单中的“云联想”提供当前会话覆盖；切换会立即使正在进行的 provider 请求失效，不改写共享偏好文件。

语音输入通过可选的 `voice_provider_socket` 顶层绝对 Unix socket 接入，也可用 `MSIME_VOICE_PROVIDER_SOCKET` 作为环境回退。IBus 属性中的“语音输入”只负责启动和取消 Host API 语音代次；用户管理的 socket 服务收到 `{"version":1,"kind":"voice","query":{"language":"zh-cn","generation":1,"stream":true,"options":{"sound_enabled":true,"start_sound":true,"end_sound":true,"mute_system_audio":false,"polish_enabled":false,"stream_inline_preedit":true,"doubao_boosting_table_id":""}}}` 后负责 PipeWire/ALSA 录音、提示音、静音、ASR 凭据、网络和结果润色，并按行返回 `{"text":"中间结果","type":"partial"}` 以及最终的 `{"text":"识别结果","type":"final"}`；旧版只返回 `{"text":"识别结果"}` 的服务仍按最终结果处理。取消时输入法另发 `{"version":1,"kind":"voice_cancel","query":{"generation":1}}`，provider 应停止对应录音并忽略后续结果；按住 RAlt、Ctrl+Win 或 RCtrl+RAlt 松开时则发送 `{"version":1,"kind":"voice_stop","query":{"generation":1}}`，provider 应停止录音并让原连接返回最终结果，Ctrl+F9 也使用该完成路径。`preferences.voice_input.stream_inline_preedit` 开启时中间文本更新 IBus 预编辑，关闭时只提交最终文本。`options` 只包含非敏感行为配置（包括有长度上限的润色提示词和 Doubao boosting table ID），输入法不会转发 token、app key 或其他凭据；provider 可以忽略不支持的字段。结果回到 GLib 主线程后再次校验会话和代次；空结果、过期结果和取消结果都不会上屏。每条响应文本最多 4096 字节，服务调用最长等待 30 秒。`preferences.voice_input.enabled` 和 `preferences.voice_input.language` 控制属性是否可用及识别语言。独立入口 `msime-client-voice /absolute/provider.sock` 从标准输入读取同一查询 JSON 并输出受界限的 JSON 响应；加上 `--stream` 参数时按行输出 `partial`/`final` 事件，供 GTK/Qt 面板或其他 Linux 宿主复用，不在输入法进程内保存凭据或原始音频。

同一个 socket 也承载候选翻译请求。候选视图更新后，宿主发送一行 JSON：

```json
{"version":1,"kind":"translation","query":{"generation":9,"target_language":"en","candidates":["你好","世界"]}}
```

服务应在一行内返回 `{"translations":[{"text":"你好","translation":"hello"}]}`；未知候选可以省略。独立入口 `msime-client-translation /absolute/provider.sock` 从标准输入读取同一 TranslationQuery JSON 并输出受界限的 JSON 响应，供 GTK/Qt 面板或其他 Linux 宿主复用。启用自定义翻译时，请求还会携带已验证的 `custom_translation` endpoint 和 API Key，provider 可据此调用兼容 DeepLX 的服务。宿主只接受最多 9 个候选、每项最多 4096 字节、每次响应最多 500ms，并把返回的 generation 原样交给 Host API 校验；过期视图不会被更新。服务必须由用户管理绝对 Unix socket，负责所有凭据、网络访问和日志策略，输入法不会记录原始输入或 API Key。关闭 `preferences.candidate_translations` 后不会发起该请求。候选翻译会按当前候选布局附加到 IBus 候选行。

英文候选的自定义释义沿用 Engine 的 `custom_translations.txt` sidecar。Linux 从 HostOptions 的 `user_data` 目录读取该文件，用户覆盖优先；没有用户文件时回退到已验证资源目录中的内置文件，再复制到当前可写词典代次供 Engine 加载。这样资源目录可以保持只读，用户只需在状态目录的 `user/custom_translations.txt` 中按“源词<Tab>释义”维护覆盖，重新建立输入会话后生效。

Linux 独立手写面板使用同一类用户管理 Unix socket，不把 GTK、Wayland 或某个桌面环境绑定进 IBus Engine。面板采集归一化坐标笔画后，按一行 JSON 请求发送：

```json
{"version":1,"kind":"handwriting","query":{"language":"zh-CN","strokes":[[{"x":0.2,"y":0.3},{"x":0.7,"y":0.8}]]}}
```

识别服务返回 `{"candidates":["你","好"]}`，最多 12 个候选，每项最多 4096 字节；请求和响应各自限时 500ms。模型、凭据和平台识别器由该服务负责，面板可以用 `msime-client-handwriting /absolute/socket` 复用 Host API 契约。服务不可用或响应过期时面板保留笔画，不向 IBus 会话伪造提交；候选点击应由面板在当前手写请求代次内完成。

若部署了 Engine 的可选离线手写组件，面板也可执行 `msime-client-handwriting --local /absolute/handwriting-zh_CN.model`。安装后的工具省略模型参数时会读取绝对路径环境变量 `MSIME_HANDWRITING_MODEL`，否则按自身安装前缀查找 `share/msime-client/handwriting/handwriting-zh_CN.model`。该入口把归一化笔画交给 Engine 内置的 Zinnia 识别器，模型路径必须是受信任的绝对路径；没有模型或识别失败时返回错误，不回退为伪造候选。

独立 Emoji 面板也可通过该 socket 查询目录。请求使用 `kind:"emoji"`，查询包含 `search`、`category` 和 `limit`；服务返回 `{"items":[{"text":"😀","annotation":"grinning face"}]}`。搜索最多 256 字节、分类最多 128 字节、结果最多 96 项，每项文本最多 64 字节、注释最多 256 字节，调用限时 500ms。面板使用 `msime-client-emoji /absolute/socket` 获取结果；没有 provider 时可用 `msime-client-emoji --local /absolute/resource-generation` 直接查询已验证的 `others.db`。Linux 桌面打开面板时保存当前输入目标，点击项目优先用 `xdotool type` 或 `wtype` 回填当前编辑器，目标已失效时回退到剪贴板；IBus Engine 仍只负责组合中的本地 Emoji 模式，不读取系统剪贴板。

桌面 Tauri Emoji 面板在 Linux 上直接读取 HostOptions `resources` 下 Engine 提供的 `others.db`，通过 Engine bridge 分页读取完整 Emoji、颜文字和符号目录，并按数据库分类聚合后交给共享 UI；读取失败时 UI 保留内置目录。面板只接收资源目录中的目录数据，不读取用户输入、凭据或私人资料。

桌面 Tauri 面板的系统剪贴板按 Linux 会话能力选择后端：优先使用 Wayland 的 `wl-paste` / `wl-copy`，不可用时回退到 X11 的 `xclip`；剪贴板历史仍只在用户开启设置后写入本地受限存储。桌面宿主运行期间以低频轮询捕获新的文本剪贴板内容，设置关闭后立即停止记录并清除本轮监视状态，读取失败不会伪造同步结果。

桌面 Tauri 面板在 Linux 上也接入了屏幕键盘、手写和语音提交。打开面板时宿主先保存当前输入目标：X11 使用 `xdotool getactivewindow`，Sway 使用 `swaymsg -t get_tree`；按键通过目标窗口的 `xdotool key`、Sway 的 `wtype` 或通用 Wayland 的 `ydotool` 发送。`ydotool` 仅在其 daemon 可用时启用，以 `/dev/uinput` 注入，不依赖面板重新夺取焦点；没有全局注入能力时回退到 `wtype`。手写候选和语音识别结果通过同一目标提交文本，语音面板消费 provider 的 partial/final 事件并实时显示转写，关闭面板时发送当前 generation 的取消消息。手写识别服务的绝对 Unix socket 由 `MSIME_HANDWRITING_PROVIDER_SOCKET` 提供，语音服务使用 HostOptions 的 `voice_provider_socket` 或 `MSIME_VOICE_PROVIDER_SOCKET`；服务仍负责录音、模型和凭据。缺少注入工具或服务时面板保留可见状态并返回宿主错误，不伪造提交。

桌面手写和语音面板支持 `preferences.handwriting_theme` 与 `preferences.voice_theme`，取值为 `follow`、`dark` 或 `light`；`follow` 继承全局主题。设置保存后，已打开的面板通过偏好变更事件立即更新外观。

桌面 Emoji 面板（包括颜文字、符号和剪贴板页）支持 `preferences.emoji_theme`，同样取值为 `follow`、`dark` 或 `light`；设置保存后已打开的面板实时同步主题。

屏幕键盘和手写面板在 X11 上读取活动窗口矩形，在 Sway 上读取 focused container 的 `rect`，首次创建时定位到输入窗口下方并水平居中；窗口矩形不可用时回退到屏幕默认位置。通用 Wayland 的 `wtype` 注入不提供窗口几何查询，因此保留 compositor 默认位置，不伪造坐标。

IBus 属性面板提供 `EnglishCandidates`、`EmojiCandidates` 和 `KaomojiCandidates` 三个混输开关。切换属性会结束当前组合并重建本会话的 Engine，避免把新旧混输候选规则混在同一代视图中；覆盖只作用于当前 IBus 会话，不改写共享偏好文件。Windows 的设置窗口仍负责持久化配置，Linux 桌面 panel 只负责会话级快速切换。

IBus 属性面板另提供 `EnglishMode` 独立英文输入模式。Ctrl+Shift+E 或属性开关调用 Engine 的 dedicated English 模式，保留中文输入法会话和 IBus 输入源边界；它与 `EnglishCandidates` 混输候选开关相互独立。状态按当前 IBus 会话保留，切换时由 Engine 清理正在进行的组合。

Linux IBus 会话支持 `Ctrl+Shift+Super+K` 打开屏幕键盘面板。宿主只在当前输入上下文获得焦点且不是密码等受限字段时消费该组合，并通过现有桌面面板启动器打开键盘；Super 组合是否能到达 IBus 仍由桌面环境的全局快捷键策略决定。

IBus 属性面板还提供 `TraditionalOutput`。开启后，中文方案的候选显示和提交文本通过系统 ICU 的 `Simplified-Traditional` 转换器转换为繁体；Unicode 直接输入、日语方案和英文/Emoji 文本保持原样。这个开关只覆盖当前 IBus 会话，偏好文件中的 `traditional_chinese_output` 作为新会话默认值。

当前 IBus 会话支持 `Ctrl+Shift+Alt+1` 到 `Ctrl+Shift+Alt+8` 删除候选页对应的可编辑词条。宿主只传递候选快照中的会话、代次和全局索引，由 Host API 校验来源和执行词库删除；没有对应候选或不可编辑候选时按键交回应用。`Ctrl+Shift+Alt+C` 清除当前输入法会话的 Engine 候选缓存并刷新当前视图，不会结束正在进行的组合。`Ctrl+Shift+Alt+R` 通过用户会话的 `ibus restart` 重启 IBus 服务，设置页也提供同一动作的按钮。

Linux 的 `floating_toolbar` 偏好映射为 IBus 原生属性菜单中的“工具栏”入口，不创建脱离输入上下文的伪悬浮窗口。启用后，菜单按偏好显示中英文模式、独立英文输入模式、全角字符、中文标点、繁体输出、Emoji、屏幕键盘和设置动作；模式动作复用当前 IBus 会话，面板动作通过 `msime-client-settings` 启动已有 Tauri 面板，并把当前输入目标交给面板保存。关闭工具栏或单独关闭组件后，入口会在配置热重载时同步隐藏。

## 构建与运行

候选辅助文本在页码后展示 Engine 快照提供的本地模式标签（U+、日期时间、短语、Emoji、颜文字、简拼、EN、日文）。普通或未知模式不附加标签，取消组合或没有候选时隐藏辅助文本；不从预编辑前缀推断模式。

当全拼或双拼启用辅助码候选显示时，Linux 也为 Engine 生成的整句候选按当前方案和词库映射计算辅助码；不再把整段原始预编辑拼音当作候选注释。辅助码仍是展示文本，不进入候选身份或提交内容。

候选行保留 Engine 的来源身份：本地词库和用户词库不额外标记，云候选显示 `云`，AI 候选显示 `AI`。来源标签只用于 IBus panel 展示，不进入提交文本、候选索引或异步结果校验。

共享 `candidate_text_color` 设置在 IBus lookup table 候选上转换为 RGB 前景属性；未设置时交由 panel 主题决定。候选字体族、字号和回退字体仍由桌面 panel 的字体栈控制。

`tsf_preedit_style` 在 Linux IBus 中映射为：`raw` 显示 Engine 的 ASCII `editing_text`，`pinyin` 显示 Engine 的 `preedit`，`empty` 隐藏预编辑；设置热重载会更新当前会话的显示样式。候选与上屏仍由 Engine 的共享状态决定。

`candidate_preedit_style` 在 Linux 中映射为候选面板辅助文本：`pinyin` 在页码后显示当前拼音，`empty` 只显示页码和模式标签；设置热重载立即更新现有会话。

Windows 的 `clipboard_history` 依赖独立剪贴板监听器和候选历史 UI；IBus Engine API 不提供剪贴板事件。Linux IBus 宿主只读取用户明确配置的历史文件，并通过属性菜单提供最近条目、删除和清空操作，不读取系统剪贴板，也不在输入线程监听剪贴板。Linux 桌面面板的剪贴板同步仍由独立 Tauri 服务承载。独立工具的 `get INDEX` 操作会将已存储条目写到标准输出，`remove-index INDEX` 按历史位置删除单个条目，供桌面服务或 compositor 显式接管粘贴和删除动作；它不会写入或读取系统剪贴板。

`candidate_theme` 是 Windows 候选窗口的整体深浅主题覆盖。IBus Engine 只提交 lookup table 内容与文本属性，候选 panel 的背景、边框、间距和主题切换由桌面环境控制；Linux 保留共享设置，但不伪造 panel 主题覆盖。显式 `candidate_text_color` 仍按 IBus 前景属性传递。

个人词典维护使用共享 Host API 的独立 `msime-client-dictionary` 原生入口，不由 IBus 输入线程执行。它从标准输入读取一个不超过 65536 字节的 JSON 请求并输出 JSON 响应；请求格式和 `list`/`edit` 操作见 `msime_client.h`。调用方必须在编辑前停止使用相关词典的会话，API 负责共享访问锁、请求幂等和 Engine 原子写入；错误输出不包含词条内容。该入口不替代桌面设置页，便于 GTK/Qt 前端复用同一契约。

该入口也支持本地词库批量迁移：`import` 接受不超过 64 KiB、最多 1000 行的 UTF-8 文本，`standard` 格式为 `词条<TAB>编码<TAB>权重`，`windows` 格式为 `编码<TAB>词条<TAB>权重`，`rime` 格式兼容 `userdb.txt/dict.yaml` 的 `词条<TAB>编码[<TAB>权重]`、YAML 头和 `c=… d=…` 元数据；拼音词库的 `hans` 格式则每行接受纯汉字词条，由 Engine 从已验证主词典解析最高权重的规范拼音并以 10000 导入。省略权重时使用 10000。空行和 `#` 注释会跳过。调用方提供请求 ID 前缀，入口为每行生成稳定回执，重复提交同一请求安全。`export` 按页返回相同两种格式的文本和 `has_more`，便于桌面面板保存为文件。导入取得独占维护锁，活动 IBus 会话存在时返回 busy；导出使用共享锁，不会中断用户组合。

账户云词典使用独立的 `msime-client-cloud-dictionary /absolute/provider.sock` 入口。它验证 `list`、`changes`、`add`、`update`、`delete`、`import` 和 `export` 请求后，经用户管理的 Unix socket 转发一行 `{"version":1,"kind":"cloud_dictionary","request":...}`；provider 负责登录态、凭据、网络和冲突同步，入口只输出有界 JSON 响应，不保存账户信息。Tauri 设置页通过 `cloud_dictionary_provider_socket` 或 `MSIME_CLOUD_DICTIONARY_PROVIDER_SOCKET` 接入同一 provider，提供词库选择、搜索分页、词条 CRUD，以及标准 TSV、Windows TSV 和拼音汉字自动注音导入。

云剪贴板使用独立的 `msime-client-cloud-clipboard /absolute/provider.sock` 入口。它验证列表、明确添加、删除和启停请求后，经同一类用户管理服务转发 `{"version":1,"kind":"cloud_clipboard","request":...}`；服务负责账户凭据、云端保留和冲突处理，不自动读取本地剪贴板。

桌面设置可在 HostOptions 中配置 `cloud_dictionary_provider_socket` 和 `cloud_clipboard_provider_socket` 两个绝对 Unix socket；未配置时分别回退到 `MSIME_CLOUD_DICTIONARY_PROVIDER_SOCKET` 和 `MSIME_CLOUD_CLIPBOARD_PROVIDER_SOCKET`。这两个字段会随 runtime-options 原样保留，但不会进入 Engine 选项或输入会话。

IBus 面板注册 `InputMode` 开关：选中时按当前输入方案转换，关闭时直接透传编辑器输入。面板符号为「文」或「A」，不把日语等已配置方案误标为中文。切到直接输入前通过 Engine 完成高亮组合；再次聚焦保留当前实例的选择，关闭期间的候选点击和翻页无效。密码等受限字段及失焦时开关不可用，恢复正常字段后继续使用原选择。目前不跨输入上下文或重启持久化，不占用桌面已有的输入源切换快捷键。

`ime_mode_scope` 可设为 `app` 或 `global`。按应用时每个输入上下文按 `default_ime_mode` 开始；设为全局时，当前 IBus 进程的输入上下文在获得焦点时同步同一个中英文状态。该状态保留在 IBus 进程内，不写回偏好文件，也不干预桌面环境已有的输入源切换。

共享 `word_character` 支持方括号或减号/等号选择高亮候选的首/末汉字，默认关闭；与同组翻页配置互斥，由共享配置校验拒绝冲突。启动及实时设置发布均更新绑定，活动组合保留；宿主将当前候选代次和全局索引传给 Engine，不自行切分汉字。无汉字候选走共享组合完成与标点路径，关闭功能后恢复通常的标点输入；Shift 符号不触发以词定字。

需要 Linux、Rust 1.97.1、CMake 3.25+、C++17 编译器、IBus 1.5.20+ 开发包、nlohmann-json 3.11+、Boost/fmt/spdlog/SQLite 开发包。通用 Wayland 的全局面板注入可选安装 `ydotool` 并运行 `ydotoold`；没有它时仍尝试 `wtype`。原生构建：

```sh
cargo build -p msime-host-api --locked
cmake -S platforms/linux -B target/linux-ibus
cmake --build target/linux-ibus
cargo run -p msime-host-api --example prepare_host --locked -- /absolute/verified-resources /absolute/new-preview-state
target/linux-ibus/msime-client-ibus /absolute/new-preview-state/runtime-options.json
```

准备配置必须在没有会话使用该状态目录时执行。运行入口动态注册独立的 `msime-client-preview`，不安装系统组件、不修改旧 Linux 产品或自动切换用户输入法；关闭进程即结束本次注册。安装后的 component 通过 `msime-client-ibus-launcher` 启动，默认读取 `~/.config/msime-client/runtime-options.json`；也可用 `MSIME_IBUS_OPTIONS` 指向已准备好的绝对路径。launcher 按自身目录定位 Engine，支持自定义安装前缀。库与运行配置含开发路径，目前不是可分发安装包。宿主监听配置 JSON 的写入和原子替换事件；后续新焦点会话使用新配置，正在组合的会话保持原设置直到结束。

Linux 桌面设置保存时会先按 `PreferencesStore` 的 revision 规则写入 `preferences.json`，随后以原子替换同步同一 HostOptions 的 `preferences` 到 `MSIME_IBUS_OPTIONS`，或 `MSIME_CLIENT_HOST_OPTIONS` 指向的 `runtime-options.json`；未设置前者时，桌面应用也可直接用 `MSIME_IBUS_OPTIONS` 作为 HostOptions 来源。这样正在运行的 IBus 预览宿主可以通过已有文件监听接收新设置；同步失败会把保存命令报告为存储错误，避免界面误报已同步。

Linux Tauri 设置窗口也会监视同一 `PreferencesStore` 的 revision。其他窗口或 IBus 侧写入新 revision 后，未编辑的设置页自动刷新；若当前有未保存草稿，只提示外部变更并保留草稿，用户通过“重新读取”显式解决冲突。事件只携带已验证的偏好快照，不携带输入内容或凭据。

安装时可使用 `cmake --install target/linux-ibus`。安装产物包含 IBus 主程序、`msime-client-online` 在线候选请求入口、`msime-client-translation` 候选翻译请求入口、`msime-client-dictionary` 个人词典请求入口、`msime-client-cloud-dictionary` 云词典请求入口、`msime-client-cloud-clipboard` 云剪贴板请求入口、`msime-client-clipboard` 剪贴板历史工具、`msime-client-handwriting` 手写识别请求入口、`msime-client-voice` 语音识别请求入口和 `msime-client-emoji` Emoji 目录请求入口；工具与主程序使用相同的安装前缀。需要预置系统配置时，在 CMake 配置阶段传入 `-DMSIME_RUNTIME_OPTIONS_FILE=/absolute/runtime-options.json`，安装到 `${CMAKE_INSTALL_SYSCONFDIR}/msime-client/runtime-options.json`。该文件必须来自已准备且匹配安装环境的状态目录，不能直接分发开发机上的私人状态。

Linux 安装还会在 `${CMAKE_INSTALL_DATADIR}/msime-client/handwriting` 放置 Engine 随附的离线中文模型（可用 `-DMSIME_HANDWRITING_MODEL=/absolute/model` 覆盖）。模型及其许可证随 Engine 发布，面板应只引用该受信任安装路径。

若要把 Tauri 设置窗口一并安装，可先用 `pnpm --filter @msime/desktop tauri build --no-bundle` 生成 Linux 二进制，再在 CMake 配置阶段传入 `-DMSIME_DESKTOP_BINARY=/absolute/path/to/msime-desktop`。安装会增加 `msime-client-desktop`、`msime-client-settings` 和桌面菜单项；设置启动器按 `MSIME_CLIENT_HOST_OPTIONS`、`MSIME_IBUS_OPTIONS`、用户配置路径的顺序选择绝对 runtime-options，并把它传给 Tauri 宿主，不把开发机路径写入桌面文件。设置页的“语音输入”分类可打开独立语音面板，面板调用同一 provider 并把识别结果提交到打开前捕获的编辑器。Linux 设置页的“快捷键”分类还提供“重启输入法服务”按钮，调用当前用户的 `ibus restart`；普通配置保存仍通过 runtime-options 文件热重载，不需要为了设置变更重启服务。

## 隔离验证

候选操作也通过 IBus 属性菜单提供：对当前候选页的 1–9 槽位分别注册固定和删除动作，动作携带当前视图代次调用共享 Host API；菜单只对可写入用户词典的中文/英文候选显示这些动作，云端、AI、Emoji、颜文字、快捷短语和日文候选保持只读。桌面 panel 不支持 Windows 式右键候选窗时仍可使用该菜单路径。

候选操作菜单还提供将当前词库候选固定到位置 1–5 及取消固定。固定位置由 Engine 持久化并随候选快照返回；Linux 宿主只传递候选身份和目标槽位，不复制词典写入或排序逻辑，并在 IBus 候选行显示“固定 N”状态。

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

九键输入：IBus 属性菜单中的“九键输入”只在全拼方案下可用。开启后数字键交给 Engine 组成九键拼音，候选视图中的数字选词自动让位；切换会先结束当前组合并重建会话，九键拼音候选和代次由 Engine 返回。关闭后恢复普通数字选词，设置只作用于当前 IBus 输入上下文。

九键歧义拼音：Engine 返回 `nine_key_spellings` 时，IBus 属性菜单显示当前代次的拼音选项（如 `ni`、`mi`）。选择菜单项通过 Host API 携带会话和 generation 调用 `choose_nine_key_spelling`；组合已变化或失焦后，旧菜单项会被忽略，不会改写新组合。

本地输入模式：属性菜单中的“本地输入模式”提供 Unicode、日期时间、快捷短语、Emoji、颜文字、超级简拼和临时英文/日文模式的会话级开关。切换会结束当前组合并重建 Engine 会话，开关只覆盖当前输入上下文；共享 Preferences 和设置页中的持久化开关仍作为新会话默认值。

小键盘标点：`KP_Decimal` 始终提交 ASCII `.`；`KP_Separator` 按逗号标点处理；`KP_Subtract`、`KP_Add`、`KP_Divide`、`KP_Multiply` 和 `KP_Equal` 映射为 `-`、`+`、`/`、`*`、`=`。候选或组合活动时，宿主先通过 Host API 提交高亮候选，再追加对应 ASCII 标点；空闲时算术键仍遵循 Engine 的标点策略，且不会触发减号/等号候选翻页绑定。

Microsoft 双拼：当当前方案使用 Microsoft 键位且光标所在分音节已有奇数个按键时，未修饰的分号按键作为 `ing` 输入键交给 Engine，不会被中文标点路径提前消费；其他分号仍遵循普通标点处理。

Unicode 输入：进入 Unicode 本地模式后，`Shift++` 作为 Engine 的 `+` 输入继续组成 `U+` 前缀，不会被候选标点或减号/等号翻页路径拦截。

成对标点：启用成对标点后，`(`、`[` 和 `<` 的中文开标点会由宿主追加对应闭标点，`{` 追加 ASCII `}`，并向编辑器转发一次左移以把光标留在标点中间；`<` 的嵌套层级仍由 Engine 决定。候选活动时先完成高亮候选再补成对标点；候选导航绑定优先于成对标点。
