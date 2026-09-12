# Linux IBus 预览宿主

本目录只处理 IBus 系统入口，使用同一个 `msime-host-api` 动态库；不直接创建 C++ Engine、不复制候选分页、数字选词或配置持久化逻辑，不依赖 Tauri 常驻。按键与焦点在 GLib 主线程调用线程绑定会话，系统候选点击取当前共享视图中的代次和全局索引。预编辑采用 Engine 的 ASCII editing_text，避免把字节光标用于中文显示串。失焦、禁用和 reset 清除组合；修饰键与 key-up 透传，快捷键取消组合后透传。密码、PIN、数字与电话字段不处理输入，private/no-spellcheck 文本会话关闭学习。

共享运行时只返回当前候选页；IBus lookup table 显示该页，auxiliary text 标示共享页码。宿主读取共享 navigation 六组设置，支持减号/等号、逗号/句号、方括号、Tab/Shift+Tab、PageUp/Down 翻页及上下候选移动，也支持小键盘导航键。设置通过验证后立即更新按键分派，不等待 Engine 组合结束；按键路径不读文件。按当前键盘布局的字符映射，Shift 符号不当作未按 Shift 的物理键，保留 Unicode `U+`。关闭的标点绑定交回 Engine，关闭的 Tab/Page/上下键先完成组合再交还编辑器；空闲时透传。Panel 翻页按钮独立于键盘绑定。尚未验证各桌面 panel 对原生翻页按钮的呈现；不把当前页伪装成完整候选集自行分页。

智能标点使用 IBus 提供的 surrounding text：逗号、句号和冒号前若是 ASCII 字母或数字，则保留 ASCII；否则交由 Engine 的中文标点表转换。正在组合时优先使用当前高亮候选的末字符，候选提交和标点在同一运行时转换中完成。重复输入的 ASCII 标点在短时间内可按设置替换为中文标点；失焦、删除或其他编辑动作会使该状态失效。无法取得有效 surrounding text 时按中文标点处理，不读取或记录完整编辑器内容。

候选快照同时携带 Engine 的来源编号，并与候选顺序绑定；GTK/Qt 或其他 Linux panel 可以据此区分词库、英文、Emoji、颜文字及在线候选，不需要从显示文本反推来源。来源只用于展示和交互提示，不改变候选身份、分页或提交文本。

候选注释也由 Engine 快照按候选顺序提供：启用帮助码时使用当前方案和帮助码表生成，无法生成时保留纠错提示。Linux 宿主只显示该注释，不重复实现帮助码计算。

可选的 `online_provider_socket` 顶层启动配置指定用户管理的绝对 Unix socket。宿主复制在线查询后在 GLib worker 中请求该服务，再通过 Host API 的代次校验回填候选；未配置时不发起在线请求。请求带有 `kind:"online"`，启用 AI 联想时还携带已校验的 provider、model、候选数量和提示词配置，但不携带 token；socket 服务负责凭据、网络和 provider 策略。独立入口 `msime-client-online /absolute/provider.sock` 从标准输入读取同一 OnlineQuery JSON 并输出受界限的 JSON 响应，供 GTK/Qt 面板或其他 Linux 宿主复用。也可用 `translation_provider_socket` 或 `MSIME_TRANSLATION_PROVIDER_SOCKET` 指定独立的候选翻译服务；未指定时翻译继续复用在线 socket。`MSIME_ONLINE_PROVIDER_SOCKET` 可作为在线 socket 的环境变量回退。

当 JSON 和环境变量都没有指定 provider socket 时，宿主仅在 socket 已存在的前提下尝试 `$XDG_RUNTIME_DIR/msime-client/online.sock` 与 `voice.sock`；显式 JSON 路径和环境变量始终优先，不会自动启动服务或连接不存在的路径。

运行中的 IBus 会话会在配置文件热重载时同步读取新的在线、翻译和语音 provider socket；在线请求立即失效，正在使用旧语音服务的录音会被取消。未聚焦或尚未创建会话时，新焦点直接使用最新配置。

`preferences.cloud_candidates` 会随 OnlineQuery 传给 provider；关闭后宿主不发起仅云候选请求，并拒绝返回的云来源候选，但仍保留符合条件的 AI 联想。

IBus 属性菜单中的“云联想”提供当前会话覆盖；切换会立即使正在进行的 provider 请求失效，不改写共享偏好文件。

IBus 属性菜单中的“候选翻译”提供当前会话覆盖；关闭后不会发起翻译 provider 请求，切换会使正在进行的请求失效，不改写共享偏好文件。

“翻译目标语言”菜单可在当前会话选择英语、法语、日语、西班牙语、俄语、德语或韩语；切换会使旧语言的请求失效并按当前候选重新请求，不改写共享偏好文件。

语音输入通过可选的 `voice_provider_socket` 顶层绝对 Unix socket 接入，也可用 `MSIME_VOICE_PROVIDER_SOCKET` 作为环境回退。IBus 属性中的“语音输入”只负责启动和取消 Host API 语音代次；用户管理的 socket 服务收到 `{"version":1,"kind":"voice","query":{"language":"zh-cn","generation":1,"stream":true,"options":{"sound_enabled":true,"start_sound":true,"end_sound":true,"mute_system_audio":false,"polish_enabled":false,"stream_inline_preedit":true,"doubao_boosting_table_id":""}}}` 后负责 PipeWire/ALSA 录音、提示音、静音、ASR 凭据、网络和结果润色，并按行返回 `{"text":"中间结果","type":"partial"}` 以及最终的 `{"text":"识别结果","type":"final"}`；旧版只返回 `{"text":"识别结果"}` 的服务仍按最终结果处理。取消时输入法另发 `{"version":1,"kind":"voice_cancel","query":{"generation":1}}`，provider 应停止对应录音并忽略后续结果；按住 RAlt、Ctrl+Win 或 RCtrl+RAlt 松开时则发送 `{"version":1,"kind":"voice_stop","query":{"generation":1}}`，provider 应停止录音并让原连接返回最终结果，Ctrl+F9 也使用该完成路径。`preferences.voice_input.stream_inline_preedit` 开启时中间文本更新 IBus 预编辑，关闭时只提交最终文本。`options` 只包含非敏感行为配置（包括有长度上限的润色提示词和 Doubao boosting table ID），输入法不会转发 token、app key 或其他凭据；provider 可以忽略不支持的字段。结果回到 GLib 主线程后再次校验会话和代次；空结果、过期结果和取消结果都不会上屏。每条响应文本最多 4096 字节，服务调用最长等待 730 秒（包含录音及识别），每 100ms 检查取消，整行响应最多 16 KiB。`preferences.voice_input.enabled` 和 `preferences.voice_input.language` 控制属性是否可用及识别语言。独立入口 `msime-client-voice /absolute/provider.sock` 从标准输入读取同一查询 JSON 并输出受界限的 JSON 响应；加上 `--stream` 参数时按行输出 `partial`/`final` 事件，供 GTK/Qt 面板或其他 Linux 宿主复用，不在输入法进程内保存凭据或原始音频。

同一个 socket 也承载候选翻译请求。候选视图更新后，宿主发送一行 JSON：

```json
{"version":1,"kind":"translation","query":{"generation":9,"target_language":"en","candidates":["你好","世界"]}}
```

服务应在一行内返回 `{"translations":[{"text":"你好","translation":"hello"}]}`；未知候选可以省略。独立入口 `msime-client-translation /absolute/provider.sock` 从标准输入读取同一 TranslationQuery JSON 并输出受界限的 JSON 响应，供 GTK/Qt 面板或其他 Linux 宿主复用。启用自定义翻译时，请求还会携带已验证的 `custom_translation` endpoint 和 API Key，provider 可据此调用兼容 DeepLX 的服务。宿主只接受最多 9 个候选、每项最多 4096 字节、每次完整响应最多 8 秒、128 KiB，并把返回的 generation 原样交给 Host API 校验；过期视图不会被更新。服务必须由用户管理绝对 Unix socket，负责所有凭据、网络访问和日志策略，输入法不会记录原始输入或 API Key。关闭 `preferences.candidate_translations` 后不会发起该请求。候选翻译会按当前候选布局附加到 IBus 候选行。

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

屏幕键盘使用共享的 `touch_key_spacing_tenths` 和 `touch_row_spacing_tenths` 设置实时调整键位与行间距；启用 `touch_voice_shortcut` 时，键盘标题栏提供“语音”入口并复用已保存的输入目标打开语音面板。设置变化只影响当前面板布局，不改变 IBus Engine 组合状态。

IBus 属性面板提供 `EnglishCandidates`、`EmojiCandidates` 和 `KaomojiCandidates` 三个混输开关。切换属性会结束当前组合并重建本会话的 Engine，避免把新旧混输候选规则混在同一代视图中；覆盖只作用于当前 IBus 会话，不改写共享偏好文件。Windows 的设置窗口仍负责持久化配置，Linux 桌面 panel 只负责会话级快速切换。

IBus 属性面板另提供 `EnglishMode` 独立英文输入模式。Ctrl+Shift+E 或属性开关调用 Engine 的 dedicated English 模式，保留中文输入法会话和 IBus 输入源边界；它与 `EnglishCandidates` 混输候选开关相互独立。状态按当前 IBus 会话保留，切换时由 Engine 清理正在进行的组合。

Linux IBus 会话支持 `Ctrl+Shift+Super+K` 打开屏幕键盘面板。宿主只在当前输入上下文获得焦点且不是密码等受限字段时消费该组合，并通过现有桌面面板启动器打开键盘；Super 组合是否能到达 IBus 仍由桌面环境的全局快捷键策略决定。

IBus 属性面板还提供 `TraditionalOutput`。开启后，中文方案的候选显示和提交文本通过系统 ICU 的 `Simplified-Traditional` 转换器转换为繁体；Unicode 直接输入、日语方案和英文/Emoji 文本保持原样。这个开关只覆盖当前 IBus 会话，偏好文件中的 `traditional_chinese_output` 作为新会话默认值。

当前 IBus 会话支持 `Ctrl+Shift+Alt+1` 到 `Ctrl+Shift+Alt+8` 删除候选页对应的可编辑词条。宿主只传递候选快照中的会话、代次和全局索引，由 Host API 校验来源和执行词库删除；没有对应候选或不可编辑候选时按键交回应用。`Ctrl+Shift+Alt+C` 清除当前输入法会话的 Engine 候选缓存并刷新当前视图，不会结束正在进行的组合。`Ctrl+Shift+Alt+R` 通过用户会话的 `ibus restart` 重启 IBus 服务，设置页也提供同一动作的按钮。

`Ctrl+Shift+Alt+T` 立即退出当前 Linux IBus 预览服务进程，快捷键由宿主消费，不会停止用户正在运行的其他 IBus 服务。

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

CMake 配置时可传入 `-DMSIME_EMOJI_RESOURCES=/absolute/emoji-resources`，安装会将该受信任目录复制到 `${CMAKE_INSTALL_DATADIR}/msime-client/emoji`，供 `msime-client-emoji --local` 自动发现；未提供时不会从未验证的相邻仓库或网络下载资源。

Emoji 本地 CLI 的 `msime-client-emoji --local` 会按显式资源目录、其中包含 `others.db` 的 `MSIME_EMOJI_RESOURCES`、`$XDG_DATA_HOME/msime-client/emoji`、`$XDG_DATA_DIRS/*/msime-client/emoji`、安装前缀和系统数据目录顺序查找资源。显式传入路径优先；未找到时返回错误，不访问网络。这样发行版安装后的 Emoji 面板不要求用户手工复制 Windows 风格资源路径。

`msime-client-handwriting --local` 也会按显式模型路径、`MSIME_HANDWRITING_MODEL`、`$XDG_DATA_HOME`、`$XDG_DATA_DIRS`、安装前缀和系统目录自动查找模型；未找到模型时不访问网络。

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

AI 联想请求可携带 `ai_context`：当前焦点会话最近经共享提交路径上屏的文本，最多 1024 个 UTF-8 字节，按字符边界截断。分段选词和整句候选各追加本次提交，不重复追加已提交前缀；使用最终简繁/全角转换后的文本。仅启用 AI 联想且查询符合条件时发送，私密字段不记录，失焦、reset 和会话关闭时清空；不落盘、不写日志。provider 应将该字段仅用于 AI 联想上下文。

IBus 的语音识别、剪贴板历史选取、空闲全角输入和直接标点提交也通过统一上屏入口更新 AI 上下文。重复智能标点替换会先移除上下文中的旧字符，再记录替换文本，避免把已删除标点重复发送给联想服务。

在线候选在输入停顿 500ms 后请求；Google 响应严格按 Windows 的 `SUCCESS` 首候选协议解析，与 Windows 的云候选空闲延迟一致。GLib 主循环定时器随连续输入重新计时，到期时才读取最新 Engine 查询；失焦、会话关闭或 provider 配置变化时取消待发请求。网络工作继续在后台线程执行，结果仍按会话和代次校验。

在线 provider 支持批量响应 `{"candidates":[{"text":"云候选","source":0},{"text":"AI候选","source":1}]}`，也兼容原来的单项 `{"text":"候选","source":0}`。每次最多两个候选，每个来源各一个，对应 Engine 当前的云/AI 槽位；Linux 依次用原查询身份回填后统一刷新显示。传输层限制整行 16 KiB、单项 4096 字节，并过滤已禁用或不符合查询条件的来源。Windows `ai_assistant.cpp` 同样只回填模型结果中的第一条，`candidate_limit` 用于模型请求。

启用且符合查询条件的 AI 请求允许 provider 在 8 秒内返回完整结果，与 Windows AI 网络请求的等待时间一致；仅云候选请求保留 500ms 等待。计时覆盖整行响应，分段发送不会续期，16 KiB 上限继续生效；请求写入也设置 500ms 超时，所有等待仍在后台线程。

## 随包在线候选服务

安装包含 Python 3.9+ 标准库实现的 `msime-client-online-provider`，为 IBus 提供 Google 云候选和 OpenAI 兼容 AI 联想。使用当前用户的私有运行目录启动：

```sh
mkdir -p "$XDG_RUNTIME_DIR/msime-client"
chmod 700 "$XDG_RUNTIME_DIR/msime-client"
msime-client-online-provider "$XDG_RUNTIME_DIR/msime-client/online.sock"
```

将该 socket 的绝对路径填入 runtime-options 的 `online_provider_socket`。仅提供云候选时无需凭据；AI 服务可增加 `--ai-config /absolute/private-ai.json`，文件仅允许所有者读写，包含 `provider`、`endpoint`、`model`、`token` 四个字符串字段。前三项须与共享 AI 设置一致，endpoint 使用 HTTPS，token 只留在服务配置中，不进入 IBus 查询。修改服务凭据后重新启动服务；不会自动启用系统服务或 CI。

服务只接受同一用户连接，同时最多处理四个请求；云候选与 AI 并行请求，AI 失败时仍可返回云候选。HTTP 响应最多 64 KiB，拒绝 HTTP 重定向以保持凭据与端点绑定。AI 沿用 Windows 的 JSON 请求、上下文、candidate_limit 和 DeepSeek thinking 禁用设置，并只取首条模型候选。服务不打印输入或网络错误正文，退出时仅删除自己创建的 socket。该入口同时实现候选翻译；语音由独立的随包 voice provider 提供；账户同步服务仍按各自契约接入。


### 随包候选翻译

同一服务接受 `kind:"translation"`，沿用 Windows 默认腾讯 TMT、自定义 DeepLX 的选择顺序。默认翻译增加 `--tencent-config /absolute/private-tencent.json`，配置文件必须是当前用户所有、其他用户无权限的普通文件，包含 `secret_id`、`secret_key`，以及可选 `region`（默认 `ap-guangzhou`）。凭据只在 provider 中读取，TC3 签名请求固定发送到腾讯 TMT HTTPS 地址，不接受请求覆盖地址。未提供腾讯配置时仍可使用云候选、AI 和自定义翻译。

启用共享设置中的 `custom_translation` 后，服务使用请求中的 endpoint 和可选 API Key 调用 DeepLX 兼容接口，支持本机 HTTP 服务或 HTTPS，禁止重定向。自定义服务失败不会回退到腾讯。英文候选译为中文；中文候选译为所选英语、法语、日语、西班牙语、俄语、德语或韩语。源文本超过 40 个字符或不符合中英文候选规则时跳过。腾讯按翻译方向批量请求，自定义服务逐条请求，每次网络操作超时 2.5 秒，批次在 6 秒预算用尽后停止发起新请求；宿主在后台最多等待 8 秒，过期代次仍由现有 Host API 拒绝。

翻译结果压平换行并过滤控制字符，内存缓存最多 2048 项，成功结果保留 480 秒、失败保留 30 秒。缓存按 provider、凭据摘要和语言方向隔离，不写入磁盘。Linux 原生运行、真实服务联调以及统一测试、格式和构建检查留到迁移验收阶段；本节不代表这些验证已经通过。


## 随包语音服务

`msime-client-voice-provider` 接收现有 `voice`、`voice_stop` 和 `voice_cancel` 请求，实现 OpenAI、Groq、SiliconFlow 批量语音识别及可选润色。需要 Python 3.9+，录音使用 `pulseaudio-utils` 的 `parec`（也适用于 PipeWire 的 PulseAudio 兼容服务），或 `alsa-utils` 的 `arecord`。默认优先使用已安装的 `parec`，可用 `--capture alsa` 显式选择 ALSA；选定后设备打开失败会返回失败，不会偷偷改用另一麦克风。

```sh
msime-client-voice-provider "$XDG_RUNTIME_DIR/msime-client/voice.sock" \
  --config /absolute/private-voice.json --capture pulse
```

先按在线服务章节创建当前用户专用的运行目录，再把 socket 绝对路径填入 `voice_provider_socket`。配置文件必须是当前用户所有、其他用户无权限的普通 JSON 文件，含必需的 `asr` 对象和可选 `polish` 对象；批量识别及润色对象包含 `provider`、`endpoint`、`model`、`token` 四个非空字符串。批量 ASR provider 支持 `openai`、`groq`、`siliconflow`；润色还支持 `deepseek`。这些批量接口须为 HTTPS 且不允许重定向，凭据不通过 socket 查询或命令行参数传递。设置中的 provider/model 须与服务配置一致；更换凭据或端点后重启服务。

服务捕获 16kHz 单声道 PCM，在内存中封装 WAV 并发送到配置的 `/audio/transcriptions` 兼容接口。默认录音上限 300 秒，可用 `--max-recording-seconds` 设置为 1–600 秒；到时自动停止并识别。松开录音快捷键也走同一完成路径，取消则丢弃结果。小于 250ms 的录音不上传，上传音频不超过 20 MiB；SiliconFlow 按 Windows 行为补静音、省略 language 字段，并在网络或服务端错误后最多重试一次。每次 ASR 网络操作超时 60 秒，可选润色超时 3 秒，润色失败保留原转写。正在发送的 HTTP 请求不能撤回，但取消后其结果不会交给输入目标。

润色保留 Windows 的精炼整理、忠实校对、中翻英、口语整理及三个自定义提示词选择，并沿用 `<asr_text>` 包装和 provider thinking 设置。批量识别没有录音中的实时转写；启用润色时可先返回原始转写的 partial，再返回整理后的 final。Doubao 实时识别使用下述 WSS 配置。

提示音尊重 `sound_enabled`、`start_sound`、`end_sound`，通过 `paplay` 或 `aplay` 播放短提示音。`mute_system_audio` 在支持 JSON 输出的 `pactl` 上暂时静音最多 32 个现有播放流，结束或取消后恢复被本服务改变的流；已有静音、已消失或被替换的流不会强制改写。缺少这些可选工具时继续录音。单次仅占用一个麦克风，最多四条语音任务等待网络，控制请求另留容量；会话按连接进程及 generation 区分。客户端断开录音连接或服务收到终止信号时停止采集并恢复播放流。原始音频、转写和凭据均不写入磁盘或日志。

本部分仅完成实现与合并，不代表 Linux 麦克风、PulseAudio/PipeWire/ALSA、真实 ASR/润色或原生宿主已经验收；按用户要求，测试、fmt、clippy、构建和设备联调留到最终统一执行。


### Doubao 实时识别

`asr.provider` 设为 `doubao` 时，语音服务使用相同录音和控制入口流式上传，无需先录完整段音频。运行服务的 Python 环境须安装 `websockets==15.0.1`；依赖清单随包安装至 `share/msime-client/requirements-voice.txt`，缺少依赖时启动返回通用配置错误，不会录音后才失败。批量识别仍只依赖 Python 标准库。同步 WebSocket 客户端参数参考其[官方文档](https://websockets.readthedocs.io/en/15.0.1/reference/sync/client.html)。

Doubao 的 `asr` 配置包含 `provider:"doubao"`、`endpoint`（WSS，如 Windows 使用的 `wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async`）及 `token`；`resource_id` 默认 `volc.seedasr.sauc.duration`。新控制台单 API Key 放入 `token`，旧控制台额外配置 `app_key` 并把 Access Token 放入 `token`。`model` 可省略，协议固定使用 `bigmodel`。凭据仍保存在所有者专用 JSON 文件中；查询只能提供非敏感选项，不能改写已配置端点或凭据，非空 `asr_resource_id` 必须与服务配置一致。

实现沿用 Windows 固定提交 `b21a1671` 的二进制协议：16kHz、16-bit、单声道 PCM，每 200ms 一帧，gzip 压缩，递增序列号，结束帧使用负序列号。`doubao_enable_itn`、`doubao_enable_punc`、`doubao_enable_ddc` 和 `doubao_boosting_table_id` 进入首帧选项。录音中的变更转写以 partial 事件返回；宿主继续根据 `stream_inline_preedit` 决定是否更新预编辑。松开或达到录音上限后发送结束帧，最多等待 30 秒获取最终结果，再进行可选润色。服务错误、超时和取消不会把中间结果冒充最终结果上屏。

音频发送队列最多容纳 10 秒音频，满时终止该请求；单个 WebSocket 响应和解压后的正文分别限制为 1 MiB。识别连接启用 TLS 证书检查、禁用 WebSocket 扩展压缩、拒绝重定向，并关闭该连接日志；Doubao 协议自身仍使用 gzip。取消会停止录音、丢弃结果并中断已建立的连接；建立连接阶段最多等待 10 秒。流式上传在录音时即发送音频，取消不能撤回已经发送的数据，短录音虽不会上屏也可能已有音频发出。

此部分已补实现，未执行录音、真实 Doubao 请求、测试或构建；Linux 原生宿主和真实服务验收仍待最终统一完成。

Linux provider 请求工具可省略 socket 参数，依次使用对应的 `MSIME_*_PROVIDER_SOCKET` 环境变量和 `$XDG_RUNTIME_DIR/msime-client/` 下的默认 socket：`online.sock`、`translation.sock`、`voice.sock`、`cloud-dictionary.sock`、`cloud-clipboard.sock`、`handwriting.sock`、`emoji.sock`。语音的 `--stream` 同样支持省略 socket；手写和 Emoji 的 `--local` 仍使用本地资源发现。IBus 在配置热重载时重新发现在线和语音 socket，候选翻译继续按独立配置、环境变量、在线 socket 的顺序选择服务。

IBus 属性菜单中的“桌面工具”可直接打开手写识别板、屏幕键盘、表情与符号、语音面板、云词典、云剪贴板和设置。该菜单独立于可配置工具栏，通过 `msime-client-settings` 启动已有 Tauri 面板；需要安装桌面二进制，也支持 `MSIME_CLIENT_SETTINGS_COMMAND` 自定义启动器。密码等受限输入上下文禁用这些入口。

安装桌面宿主后，支持 Desktop Actions 的应用菜单或任务栏可直接打开手写、屏幕键盘、表情、语音、云词典与云剪贴板。也可把 `msime-client-settings --panel handwriting` 等命令绑定到桌面环境快捷键；`--panel` 支持 `settings`、`handwriting`、`keyboard`、`emoji`、`voice`、`cloud-dictionary`、`cloud-clipboard`，继续使用同一 runtime-options 配置及桌面面板输入目标捕获流程。

剪贴板工具支持 `add-stdin`，例如 `wl-paste --no-newline | msime-client-clipboard "$XDG_STATE_HOME/msime-client/clipboard.json" add-stdin`（需将 `XDG_STATE_HOME` 设为绝对目录，未设置时使用 `$HOME/.local/state`）。X11 可将管道上游换为 `xclip -selection clipboard -o`。文本通过标准输入传递，首次写入自动创建历史目录；最多读取 1 MiB，保存时保留完整 UTF-8 字符并限制为 4000 字节，继续去重并保留最近 50 项。此命令仅执行一次明确采集，不注册后台剪贴板监听。

剪贴板历史菜单的粘贴操作使用展示时缓存的文本；删除在文件锁内按文本内容匹配，后台新增历史不会导致误删另一行。菜单行绑定加载代次，忽略已过期的行操作；清空也使用同一历史文件锁。条目与删除按钮可见，预览按完整 UTF-8 字符截断。

IBus 剪贴板历史按每组 10 条显示最近 50 条，较早条目也可粘贴和删除。“刷新历史”异步重新加载文件，不必切换输入焦点；刷新会使旧菜单行失效，正在运行的旧加载完成后会重新调度最新加载。

IBus 在可输入的焦点会话中监听历史文件所在目录，外部工具新增、删除或原子替换历史文件后自动异步刷新菜单。失焦或受限上下文停止监听；目录尚不存在时利用既有宿主定时器重试接入。仅监听已配置历史文件，不采集系统剪贴板。

语音 provider 支持 `--capture pipewire`，使用原生 `pw-cat` 录制 16 kHz 单声道 PCM；提示音也可通过 `pw-cat` 播放。`auto` 保持优先 `parec`，其次 `pw-cat`，再尝试 `arecord`。`--capture-device` 可指定 PulseAudio source、PipeWire node name/object.serial 或 ALSA PCM 名称，建议与明确的 `--capture` 后端配合使用。原生 PipeWire 录音无需 PulseAudio 兼容录音工具；系统音频静音优先使用 `pactl`，不可用时回退到 `pw-dump` 与 `wpctl`。参数依据 [PipeWire pw-cat 官方手册](https://docs.pipewire.org/page_man_pw-cat_1.html)。

录音期间静音支持原生 PipeWire/WirePlumber：`pactl` 缺失或无法枚举时，使用 `pw-dump` 查找应用播放流并通过 `wpctl` 静音，录音结束后仅恢复本次静音且节点序列号一致的流。原本已静音、已退出或被新节点复用的流不会被恢复。最多处理 32 个播放流，不更改麦克风静音或默认输出设备音量。参考 [WirePlumber wpctl](https://pipewire.pages.freedesktop.org/wireplumber/man/wpctl.html) 与 [PipeWire pw-dump](https://docs.pipewire.org/page_man_pw-dump_1.html)。

语音服务启动时持有同路径 `.lock` 进程锁。异常终止留下的 socket 在确认属于当前用户、连接被拒绝且 inode 未变化后自动清理，使服务可重新启动；活跃服务、普通文件、符号链接及无法确定状态的端点不会被替换。锁文件保留并由内核在进程退出时释放锁。

在线候选/翻译 provider 与语音 provider 共用 socket 所有权和异常重启恢复逻辑：持有独立 `.lock` 进程锁，清理已确认无监听的残留 socket，并拒绝覆盖活跃服务或其他文件。共用模块 `msime_provider_runtime.py` 随服务一起安装。

### 用户服务启动

安装包提供 `msime-client-online.service` 和 `msime-client-voice.service`，不自动启用。服务通过 `msime-client-provider-session` 使用 `$XDG_RUNTIME_DIR/msime-client/online.sock` 和 `voice.sock`，与 IBus 自动发现路径一致。运行目录首次启动时创建为仅当前用户可访问；已有目录权限不合要求时直接报错。

配置放在 `$XDG_CONFIG_HOME/msime-client/`（默认 `~/.config/msime-client/`）：在线服务可选 `ai-provider.json`、`tencent-provider.json`，语音服务需要 `voice-provider.json`。格式和 owner-only 权限要求与对应 provider 参数一致。仅云候选可不提供私有配置。

按需启动服务：

```sh
systemctl --user daemon-reload
systemctl --user enable --now msime-client-online.service
# 准备语音配置后再启用：
systemctl --user enable --now msime-client-voice.service
```

修改配置后使用 `systemctl --user restart msime-client-voice.service`；停止并取消登录自启使用 `systemctl --user disable --now msime-client-voice.service`。在线服务同理。异常退出会重启，配置错误不会循环重启。语音停止时留出录音退出和恢复静音的时间。

可通过 `systemctl --user edit msime-client-voice.service` 的 `[Service]` 段设置 `Environment=MSIME_VOICE_CAPTURE=pipewire`、`Environment=MSIME_VOICE_CAPTURE_DEVICE=设备名` 和 `Environment=MSIME_VOICE_MAX_RECORDING_SECONDS=300`；凭据仍放在私有 JSON 中。无 systemd 的桌面可直接运行 `msime-client-provider-session online` 或 `voice`。自定义安装前缀可用 CMake 的 `MSIME_SYSTEMD_USER_UNIT_DIR` 指定用户服务搜索目录。

在线和语音默认 socket 的发现由宿主每秒独立刷新，不依赖偏好目录是否配置或偏好文件能否成功读取。服务晚启动后会更新菜单可用状态并重新调度当前在线查询；默认路径仅接受实际 socket，缺失或不可访问的路径不会抛出文件系统异常。活动语音端点切换时先向旧端点取消录音，再保存新端点。

未配置偏好存储目录时，活动 IBus 会话每秒应用 runtime-options 中更新的 preferences，无需切换焦点。配置偏好目录时仍使用持久化快照。两种来源共用会话内递增版本号，菜单覆盖也可形成新版本；相同有效设置不重复提交。runtime-options 更新后忽略此前发出的旧配置读取结果。资源目录等需重建会话的配置仍在下次会话打开时使用。

`clipboard_history_path` 变更会切换当前 IBus 会话的历史来源，并使旧菜单与旧加载任务失效。关闭 `preferences.clipboard_history` 会停止读取和监听、清除会话缓存并禁用菜单操作；重新开启后重新读取配置的历史文件。宿主不会因切换路径或关闭展示而删除历史文件。

候选翻译关闭、目标语言切换或 provider 端点变更会清除当前旧译文；设置热更新后立即调度当前候选翻译。菜单翻译开关和目标语言覆盖也会提交给共享运行时。自定义翻译配置变化时使旧请求失效，避免旧服务结果回填。

云候选菜单开关会传入共享运行时设置，偏好更新后重新调度在线查询。AI 配置变化会使旧请求失效并清除旧上下文；若组合期间 Engine 延后应用新配置，宿主暂不发送旧 AI 配置的请求，仍可按当前开关查询云候选，新配置生效后恢复 AI 请求。

### 独立剪贴板采集

`msime-client-clipboard-monitor /absolute/runtime-options.json` 在没有 Tauri 设置窗口时也可采集文本历史。它读取 runtime-options 的 `preferences_directory`，仅在该目录已保存的 `preferences.json` 中明确开启 `clipboard_history` 时工作；如果指定 `clipboard_history_path`，它必须指向同目录的 `clipboard_history.json`。配置读取失败或关闭开关时停止采集并忘记本轮去重状态。

Wayland 使用 `wl-paste --type text`，X11 使用 `xclip` 或 `xsel`；每次读取限时 1 秒、最多 4096 字节，每轮间隔 750ms。文本经标准输入交给 `msime-client-clipboard-capture`，由 Host API 在偏好锁内重新检查开关并持有历史锁写入，避免关闭设置与写入竞态。监视器不打印剪贴板文本。

可按需执行 `systemctl --user enable --now msime-client-clipboard.service`，使用默认 XDG runtime-options 路径。桌面会话需向用户服务管理器提供 `WAYLAND_DISPLAY` 或 `DISPLAY`；未集成 systemd 图形会话的桌面可从会话自启动运行监视器。安装不会自动启用服务，语音和在线服务不依赖它。

未显式指定 `clipboard_history_path` 时，IBus 使用 `preferences_directory/clipboard_history.json`，与共享设置存储及独立采集服务一致。显式历史路径仍优先；切换偏好目录时默认历史来源随之更新。监视器遇到非对象 JSON 或无效偏好结构时停止本轮采集并等待下次有效配置。

“候选操作”按当前页候选分组，一级菜单显示候选序号与完整 UTF-8 字符预览，子菜单包含固定、删除、固定位置和取消固定。操作仍绑定会话与候选代次。九键拼音分支及外部皮肤选项在原生 IBus 菜单中可见并沿用既有选择回调。

外部皮肤目录只由 Linux 展示层消费，不传给严格校验的 HostOptions。启动、菜单皮肤/主题选择及设置热更新均按最终选择计算外部配色；目录内容变化也会刷新当前展示。自定义候选文字颜色优先于皮肤文字色，外部背景色不写入共享 preferences。

候选主题 `follow` 通过桌面门户的 `org.freedesktop.appearance/color-scheme` 获取系统明暗偏好，并监听后续变化；异步读取不阻塞 IBus，门户重启后重新接入。明确的 `light`/`dark` 设置优先，门户缺失或未表达偏好时使用浅色。内置及外部皮肤共用此解析，切换不会重建输入组合。接口依据 [XDG Desktop Portal Settings](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Settings.html)。

候选配色没有明确文字色时，会根据实际背景的相对亮度选择对比度更高的黑色或白色，避免系统主题与 IBus 面板主题不一致时出现深底深字或浅底浅字。有效的用户文字色和外部皮肤文字色仍优先。

运行配置通过父目录事件监听重载，连续写入合并为 100ms 后的一次读取，并每 5 秒进行低频回退读取，覆盖原子替换、删除重建、父目录替换及目录外符号链接目标更新。每次最多读取 16 KiB；相同内容不重复解析，无效中间内容保留上一次配置，后续有效保存会继续生效。

Linux 桌面未显式设置 `MSIME_CLIENT_STATE_DIR` 时，优先使用 runtime-options 的 `preferences_directory` 作为共享状态目录，保持 IBus、独立采集和桌面历史一致。面板列出历史时重新读取文件；桌面自动采集、手动同步和复制记录均通过共享偏好锁复查开关后写入，避免关闭历史后因旧检查结果继续记录。

### 按次录音选择设备

Linux 设置页的“语音输入 → 录音设备”可选择 PulseAudio、PipeWire、ALSA 或自动选择，并填写对应的设备名称。配置保存为 `preferences.voice_input.capture_backend` 和 `capture_device`；桌面语音面板与 IBus 在下一次请求中传递这两个字段，provider 为每次录音单独构造采集命令，不修改正在录制的会话。

后端和设备都留空时沿用服务 `--capture` / `--capture-device`；明确选择后端而设备留空时使用该后端的系统默认设备。只填写设备则沿用服务后端。选择不存在的后端工具或非法设备会返回失败，不悄悄切换到其他麦克风。设备字段最多 128 个字符、512 UTF-8 字节，禁止控制字符；设备通过独立命令参数传递。无需重启 provider，原始音频及设备配置不会写入日志。

设置页提供“刷新设备”与“可用录音设备”选择器。桌面宿主分别通过 `pactl --format=json list sources`、`pw-dump`、`arecord -L` 读取设备，选中一项时同时填入对应后端和设备名；刷新不会改写当前设置。每个工具最多等待 2 秒、读取 1 MiB，最多返回 256 项，不启动录音，不记录原始工具输出。缺少工具或会话不可访问时仍可手动填写；PulseAudio 的 `.monitor` 播放监视源不列为麦克风。

设备目录依据 [PulseAudio pactl 实现](https://github.com/pulseaudio/pulseaudio/blob/master/src/utils/pactl.c)、[PipeWire pw-dump 文档](https://docs.pipewire.org/page_man_pw-dump_1.html) 和 [ALSA arecord 实现](https://github.com/alsa-project/alsa-utils/blob/master/aplay/aplay.c)。列表反映发现时的设备信息，不保证设备之后仍连接或可用于指定采样格式。

录音采集在连续 5 秒未收到 PCM 字节时终止本次请求并恢复被服务静音的播放流，释放麦克风供下一次重试。正常静音仍有 PCM 数据，不会被当作设备停滞。停止录音后最多收取 1 秒的管道尾部数据，并遵守录音长度及音频字节上限；取消或客户端断开后不再向识别服务补发尾部音频。16-bit PCM 被管道拆开的单字节会与下一块合并，只向流式识别器提交完整采样点。

服务退出时先取消所有会话，并等待各会话完成采集清理与音频恢复，再关闭 socket；不会因为固定 20 秒等待结束就中断仍在恢复的播放流。录音子进程清理失败仍执行音频恢复，识别连接关闭失败仍移除对应会话并释放语音并发槽位。所有工具调用继续使用各自的超时边界，退出等待不包含已经结束采集后的网络识别请求。
