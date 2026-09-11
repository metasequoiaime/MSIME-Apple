# Linux IBus 预览宿主

本目录只处理 IBus 系统入口，使用同一个 `msime-host-api` 动态库；不直接创建 C++ Engine、不复制候选分页、数字选词或配置持久化逻辑，不依赖 Tauri 常驻。按键与焦点在 GLib 主线程调用线程绑定会话，系统候选点击取当前共享视图中的代次和全局索引。预编辑采用 Engine 的 ASCII editing_text，避免把字节光标用于中文显示串。失焦、禁用和 reset 清除组合；修饰键与 key-up 透传，快捷键取消组合后透传。密码、PIN、数字与电话字段不处理输入，private/no-spellcheck 文本会话关闭学习。

共享运行时只返回当前候选页；IBus lookup table 显示该页，auxiliary text 标示共享页码。宿主读取共享 navigation 六组设置，支持减号/等号、逗号/句号、方括号、Tab/Shift+Tab、PageUp/Down 翻页及上下候选移动，也支持小键盘导航键。设置通过验证后立即更新按键分派，不等待 Engine 组合结束；按键路径不读文件。按当前键盘布局的字符映射，Shift 符号不当作未按 Shift 的物理键，保留 Unicode `U+`。关闭的标点绑定交回 Engine，关闭的 Tab/Page/上下键先完成组合再交还编辑器；空闲时透传。Panel 翻页按钮独立于键盘绑定。尚未验证各桌面 panel 对原生翻页按钮的呈现；不把当前页伪装成完整候选集自行分页。

可选的 `online_provider_socket` 顶层启动配置指定用户管理的绝对 Unix socket。宿主复制在线查询后在 GLib worker 中请求该服务，再通过 Host API 的代次校验回填候选；未配置时不发起在线请求。socket 服务负责凭据、网络和 provider 策略。

同一个 socket 也承载候选翻译请求。候选视图更新后，宿主发送一行 JSON：

```json
{"version":1,"kind":"translation","query":{"generation":9,"target_language":"en","candidates":["你好","世界"]}}
```

服务应在一行内返回 `{"translations":[{"text":"你好","translation":"hello"}]}`；未知候选可以省略。宿主只接受最多 9 个候选、每项最多 4096 字节、每次响应最多 500ms，并把返回的 generation 原样交给 Host API 校验；过期视图不会被更新。服务必须由用户管理绝对 Unix socket，负责所有凭据、网络访问和日志策略，输入法不会记录原始输入或 API Key。关闭 `preferences.candidate_translations` 后不会发起该请求。

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

发行安装可在 CMake 配置时传入已由 `prepare_host` 生成的配置：
`-DMSIME_RUNTIME_OPTIONS_FILE=/absolute/runtime-options.json`。该文件会安装到
`/usr/local/etc/msime-client/runtime-options.json`，并与 component XML 的启动路径一致；
未传入时不会伪造运行配置，适合开发预览流程。

准备配置必须在没有会话使用该状态目录时执行。`cmake --install` 会安装宿主、词典入口和标准 IBus component XML；发行版或前端仍需生成 `/etc/msime-client/runtime-options.json`，其中资源和用户数据路径由安装器按系统策略填充。安装组件不自动切换用户输入法；关闭进程即结束本次注册。

## 隔离验证

`bash platforms/linux/tests/check-container.sh /absolute/verified-resources` 创建专用 Linux 容器，源码与词库只读挂载，构建缓存仅写入本仓 target/linux。基础 Rust 镜像固定摘要，apt 开发依赖来自 Debian bookworm 仓库；不声称所有系统包字节级可复现。容器内创建独立 D-Bus 和 IBus daemon，不连接宿主桌面，不修改现有输入源，结束后移除容器并保留构建缓存。

`engine_smoke` 使用真实共享库与固定 Release 词库，通过 D-Bus 调用实际 IBusEngine：验证预编辑与候选信号、上屏、第二页全局索引点击、标点、修饰键/key-up、快捷键取消、失焦、密码隔离与私密文本恢复。另启动实际宿主可执行文件，由独立 Python IBus 输入上下文通过 daemon/factory 输入合成拼音并接收提交。共享核心/运行时/宿主 25 项 Rust 测试纳入本地脚本。

配置包含绝对路径 `preferences_directory` 时，活动会话每秒在后台通过共享 PreferencesStore 尝试读取设置，写锁占用、损坏文件及旧版本保留当前状态并重试。GLib 主线程复核会话后发布设置，Engine 相关更改由共享运行时延迟到组合结束；私密会话始终覆盖 learning=false。失焦时不发布，关闭或重建会话后丢弃旧读取结果；无此配置字段时保留启动快照行为。后台任务不调用线程绑定的输入会话接口。

已验证的基础环境为 Debian bookworm arm64、IBus 1.5.27。仍需真实 GTK/Qt 编辑器、X11/Wayland 焦点与选区、panel 位置、其他架构与发行版、安装打包及完整 Windows 功能对照；不是完整 Linux 产品迁移完成。CI 保持禁用。

系统行为依据 [IBus Engine API](https://ibus.github.io/docs/ibus-1.5/IBusEngine.html) 和 [IBus InputContext API](https://ibus.github.io/docs/ibus-1.5/IBusInputContext.html)。

`candidate_follow_cursor` 是 Windows 候选窗口的定位选项。IBus Engine API 只提供候选表和输入上下文光标位置的通知，不提供由输入法宿主固定 panel 锚点的接口；候选 panel 的定位由桌面 panel 自己决定。因此 Linux 会读取并透传该共享配置，但不伪造 Windows 的固定候选窗口行为：在 Linux 上候选表始终交给 IBus panel 按当前输入上下文位置呈现。该限制属于 IBus/桌面环境边界，不影响候选内容、分页或选词。

`candidate_font_size` 同样属于宿主渲染设置。Linux IBus Engine 只能提交候选文本和标签，不能为单个 lookup table 指定字体大小；实际字号由桌面 panel 和用户主题控制。共享设置仍由核心校验并保存，Linux 不会把字号误写成候选文本或辅助信息，也不声称覆盖 panel 的主题配置。

`candidate_preedit_font_size` 遵循同一平台边界。IBus 的 `UpdatePreeditText` 只携带文本、光标和可见性，不携带字体或字号；预编辑显示由应用程序和桌面输入上下文主题绘制。Linux 会保留共享设置的校验与持久化，但不会把字号编码进预编辑字符串，也不声称可以覆盖 GTK/Qt 应用的字体设置。

`candidate_font_family` 是 Windows 候选窗口的字体族设置。IBus lookup table 没有输入法侧字体族属性；Linux 保留共享设置的校验与持久化，但候选字体由桌面 panel 主题决定，不把字体名写入候选文本或辅助文本。

`candidate_fallback_fonts` 同样不能由 IBus Engine 指定。lookup table 不携带字体族或字体回退链；Linux 保留最多八项回退字体的共享配置校验与持久化，但实际字形回退由桌面 panel、字体栈和系统语言环境决定。
