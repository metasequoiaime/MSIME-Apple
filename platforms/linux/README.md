# Linux IBus 预览宿主

本目录只处理 IBus 系统入口，使用同一个 `msime-host-api` 动态库；不直接创建 C++ Engine、不复制候选分页、数字选词或配置持久化逻辑，不依赖 Tauri 常驻。按键与焦点在 GLib 主线程调用线程绑定会话，系统候选点击取当前共享视图中的代次和全局索引。预编辑采用 Engine 的 ASCII editing_text，避免把字节光标用于中文显示串。失焦、禁用和 reset 清除组合；修饰键与 key-up 透传，快捷键取消组合后透传。密码、PIN、数字与电话字段不处理输入，private/no-spellcheck 文本会话关闭学习。

共享运行时只返回当前候选页；IBus lookup table 显示该页，auxiliary text 标示共享页码。宿主读取共享 navigation 六组设置，支持减号/等号、逗号/句号、方括号、Tab/Shift+Tab、PageUp/Down 翻页及上下候选移动，也支持小键盘导航键。设置通过验证后立即更新按键分派，不等待 Engine 组合结束；按键路径不读文件。按当前键盘布局的字符映射，Shift 符号不当作未按 Shift 的物理键，保留 Unicode `U+`。关闭的标点绑定交回 Engine，关闭的 Tab/Page/上下键先完成组合再交还编辑器；空闲时透传。Panel 翻页按钮独立于键盘绑定。尚未验证各桌面 panel 对原生翻页按钮的呈现；不把当前页伪装成完整候选集自行分页。

## 构建与运行

候选辅助文本在页码后展示 Engine 快照提供的本地模式标签（U+、日期时间、短语、Emoji、颜文字、简拼、EN、日文）。普通或未知模式不附加标签，取消组合或没有候选时隐藏辅助文本；不从预编辑前缀推断模式。

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

准备配置必须在没有会话使用该状态目录时执行。`cmake --install` 会安装宿主、词典入口和标准 IBus component XML；发行版或前端仍需生成 `/etc/msime-client/runtime-options.json`，其中资源和用户数据路径由安装器按系统策略填充。安装组件不自动切换用户输入法；关闭进程即结束本次注册。

## 隔离验证

`bash platforms/linux/tests/check-container.sh /absolute/verified-resources` 创建专用 Linux 容器，源码与词库只读挂载，构建缓存仅写入本仓 target/linux。基础 Rust 镜像固定摘要，apt 开发依赖来自 Debian bookworm 仓库；不声称所有系统包字节级可复现。容器内创建独立 D-Bus 和 IBus daemon，不连接宿主桌面，不修改现有输入源，结束后移除容器并保留构建缓存。

`engine_smoke` 使用真实共享库与固定 Release 词库，通过 D-Bus 调用实际 IBusEngine：验证预编辑与候选信号、上屏、第二页全局索引点击、标点、修饰键/key-up、快捷键取消、失焦、密码隔离与私密文本恢复。另启动实际宿主可执行文件，由独立 Python IBus 输入上下文通过 daemon/factory 输入合成拼音并接收提交。共享核心/运行时/宿主 25 项 Rust 测试纳入本地脚本。

配置包含绝对路径 `preferences_directory` 时，活动会话每秒在后台通过共享 PreferencesStore 尝试读取设置，写锁占用、损坏文件及旧版本保留当前状态并重试。GLib 主线程复核会话后发布设置，Engine 相关更改由共享运行时延迟到组合结束；私密会话始终覆盖 learning=false。失焦时不发布，关闭或重建会话后丢弃旧读取结果；无此配置字段时保留启动快照行为。后台任务不调用线程绑定的输入会话接口。

已验证的基础环境为 Debian bookworm arm64、IBus 1.5.27。仍需真实 GTK/Qt 编辑器、X11/Wayland 焦点与选区、panel 位置、其他架构与发行版、安装打包及完整 Windows 功能对照；不是完整 Linux 产品迁移完成。CI 保持禁用。

系统行为依据 [IBus Engine API](https://ibus.github.io/docs/ibus-1.5/IBusEngine.html) 和 [IBus InputContext API](https://ibus.github.io/docs/ibus-1.5/IBusInputContext.html)。

`candidate_follow_cursor` 是 Windows 候选窗口的定位选项。IBus Engine API 只提供候选表和输入上下文光标位置的通知，不提供由输入法宿主固定 panel 锚点的接口；候选 panel 的定位由桌面 panel 自己决定。因此 Linux 会读取并透传该共享配置，但不伪造 Windows 的固定候选窗口行为：在 Linux 上候选表始终交给 IBus panel 按当前输入上下文位置呈现。该限制属于 IBus/桌面环境边界，不影响候选内容、分页或选词。
