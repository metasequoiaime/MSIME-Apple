# Windows 功能迁移对照

这份文档记录 Windows 宿主对来源产品 MSIME-Windows 的迁移结果：迁移的范围与基线、一直盯着这件事的几道门禁、每个功能组落在本仓库哪里、哪些地方刻意与来源不同及其理由，以及本仓库特有的 Windows 进程与协议边界。

迁移已完成。功能对照不是一次读完 README 得出的结论，而是由五道检查持续地问同样几个问题：来源能被设定的每一项、来源界面能发起的每个动作、来源发布日志里的每一条、来源源码树里的每个文件，在这边分别由什么答复。下面「持续门禁」一节给出这几个问题今天的答案。

## 迁移范围与固定基线

目标是迁移 MSIME-Windows 的完整功能，而不是语音、设置页或某台机器上跑得起来的子集。分工固定为：公共业务逻辑放共享 Rust 层（`crates/client-core`、`crates/input-runtime`、`crates/host-api`），公共管理界面放 Tauri 壳与共享 React 设置页（`apps/desktop/`、`packages/ui/`），输入算法与组合状态仍归 C++ Engine，Windows 侧保留 TSF DLL 与 Server 两个进程及其协议边界。

对照使用的是固定对象，不是某个仓库当天的 HEAD：

- 来源：`metasequoiaime/MSIME-Windows` 的提交 `345cb87a3822f6ad7013bb29506fe3d856c1931a`。所有 reference 门禁统一经 `scripts/reference_source.py` 读取这个对象（`PINNED_SHA`），不跟随相邻检出的当前分支或可变远端 tip；环境变量 `MSIME_REFERENCE_DIR` 只覆盖检出位置，不能覆盖版本。检出存在但缺这个对象时，脚本判定为无效的验证环境并指出恢复命令，而不是回落到一个可变分支。
- 目标：`metasequoiaime/msime` 的 `develop`。
- Engine：来源把 Engine 以 `engine/` 在自己树内维护；本仓库由 `engine-lock.json` 固定一份独立的 `msime-engine` 源码归档（带 sha256），经 `scripts/fetch_engine.py` 取回并校验成 `vendor/MSIME-Engine`，不使用 submodule 或 gitlink。来源树内做过、而独立 Engine 不再单独发布的改动，由登记在 `engine-lock.json` `overlay_scripts` 里的 `scripts/apply_engine_*.py` 承接——这条路径已用于加加辅助码、双码辅助码缓存、初始候选上限展开、独立整句学习、全拼纠错等多项。两个 Engine 不因目录名或协议名相同而视为内容相同。

来源的功能入口以该提交的 `README.md`「功能简介」「核心功能指南」、`ui-html/webview2/settings/ime-settings/src/modules/sidebar.ts`、`server/src/settings/settings_app.cpp`、`installer/default_config/config.default.toml` 和 `engine/contracts/webview/messages.json` 交叉核对。README 只是入口索引，真正的判据是后面几道逐字段、逐动作、逐文件的检查。

## 持续门禁

按名字对界面、按记忆对功能，这两种做法在这次迁移里反复产生同样两类假结果：看着缺的其实是有意改名（`y_mode` 就是 `local_modes.temporary_english`，`cn_en_mixed_input_min_chars` 就是 `mixed_input.minimum_prefix`），看着有的其实只是某个无关标识符里恰好含同一个词。所以对照的结论写成可执行的脚本，由 `scripts/verify-local.sh` 每次运行。

| 问的是什么 | 谁在问 | 答案 |
| --- | --- | --- |
| 来源能被设定的每一项，本仓有没有 | `scripts/test-windows-config-keys.py` | 来源出厂配置的 180 个键（18 个段）全部有对应物 |
| 每一项设定对应共享层的哪个字段，那个字段今天还在不在 | `scripts/test-reference-config-coverage.py` | 178 项全部有着落，其中 6 项以 `!kind: why` 写明为什么没有字段 |
| 来源界面能对宿主发起的每个动作 | `scripts/test-reference-ui-actions.py` | 46 个动作全部有人答 |
| 来源发布日志里的每一条 `feat:` | `scripts/test-reference-feature-log.py` | 19 条全部过过一遍 |
| 来源源码树里的每个文件 | `scripts/test-reference-source-inventory.py` | 274 个 `.cpp`/`.h`：161 个同名、101 个改名并指向存在的路径、12 个写明不需要 |

这几道检查各自的判据：

- 配置键那道检查比的是**键名**而不是值。两边刻意不同的默认值由 `scripts/test-default-config-parity.py` 单独比对——它读安装模板 TOML 与 Rust 源码两份互相独立的材料，改错一边会指名报错，而不像单测那样用实现断言实现。本仓多出来的键不报告：适配可以提供更多，不能更少。
- 覆盖率那道检查除了要求字段存在，还要求它**在共享设置页上被提到**。只在 preferences crate 里存在算「纸面支持」：字段在、能往返、没有用户改得动它。主体不存在于本平台的条目记在 `PLATFORM_LOCAL` 里。
- 界面动作那道检查不能按名字比：来源的四个界面（设置、悬浮工具栏、候选窗、托盘菜单）是 WebView2 文档，向宿主 post message，而这边其中三个是原生代码、根本没有消息。所以每个动作映射到一个在本仓库仍可检索到的 token，或记为有理由的缺席。
- 源码清单那道检查的第二种形式指向一个必须存在的路径而不是一句话；第三种形式（`DELIBERATELY_ABSENT`）是要带着怀疑读的部分——迁移正是在这里藏它没做的事——所以每条都写明用户得到的是什么替代物。
- 来源检出是可选的。没有检出时这五道检查各自报告它需要什么然后通过，与其他依赖外部材料的阶段一致。

### Windows 侧的编译与运行门禁

除上面五道对照检查外，与 Windows 直接相关的还有：

- `scripts/test-windows-32bit-compile.py`：32 位 TSF DLL 会被加载进每个 32 位宿主，所以同一份 C++ 必须两个架构都编得过。编译参数取自 x64 构建产出的 `compile_commands.json` 而非另一份手工清单，往 CMake 加源文件或 include 自动被覆盖；只换编译器并 `-fsyntax-only`，因此不需要 32 位库。
- `scripts/test-windows-path-encoding.py`：禁止 Windows 会编译到的 C++ 出现 `path::string()`。这个转换在 Windows 上按 ANSI 代码页走，`C:\Users\陆傲天` 这类 profile 要么转错要么抛；而在系统编码为 UTF-8 的机器上一点痕迹都没有，只能静态拦。
- `scripts/test-windows-native-run.py`：`platforms/windows/tests/` 里大部分是纯策略——对契约结构体的纯函数，整个翻译单元没有 Win32 调用。哪些属于这一类是发现出来的而非列出来的（能用宿主编译器独立编译链接的就是），这些源文件因此在任何机器上都真的被执行，而不只是链接通过。
- `scripts/test-installer-prerequisites.py`：钉住安装器对 WebView2 与 VC 运行库的注册表判据（不做文件探测：Setup.exe 是 32 位进程，`FileExists` 会被 WOW64 重定向）。
- `scripts/test-preferences-field-parity.py`：按名字配对 TS 类型与 Rust 结构体，两个方向都查字段集；Rust 独有的须在 `RUST_ONLY` 写明理由。
- 交叉构建：`platforms/windows/build-cross.sh x64`（MinGW + vcpkg，校验 vcpkg HEAD 与清单基线一致后装 `<arch>-mingw-static` 依赖，再依次构建 `msime-host-api`、`MetasequoiaImeDictionaryReplay` 与整个 CMake 工程），本机工具链不满足 DWARF 展开时走 `build-cross-container.sh`。`verify-local.sh` 在非 Windows 宿主上自动接这条路径，并用目录锁让多个 worktree 串行。
- pipe-only 配置（`-DMSIME_WINDOWS_PIPE_ONLY=ON`）在 x86_64 与 i686 两个架构上各配置构建一次：`windows_ipc.h` 的 `static_assert` 钉的是帧大小与字段偏移，两个位数都要成立。
- 运行：`platforms/windows/run-tests-wine.sh x64` 在 `xvfb-run -a wine` 下运行交叉产物（C++ 套件与 `cargo test --no-run` 产出的 Rust 套件），每个套件 120 秒超时，失败集合与 `scripts/known-failures.txt` 比对，只对不在清单里的名字失败。
- MSVC 全量构建与打包：`platforms/windows/Build-Client.ps1`（x64 出 Server/Watchdog/prepare/TSF，x86 出 TSF 与 Host DLL；完成前读五个 x64 EXE 与两对 TSF/Host DLL 的 PE 头做架构与类型门禁），安装包走 `platforms/windows/installer/Package-SimplySign.ps1`。
- CI：`.github/workflows/ci-platforms.yml` 的 Windows 作业跑在 `debian:trixie-slim` 容器里（环境与 `platforms/windows/cross/Dockerfile` 一致；Ubuntu 24.04 的 MinGW 头文件没有 `msimeui` SVG 渲染要用的 `d2d1_3.h`），执行 `build-cross.sh x64`。`.github/workflows/release-windows.yml` 手动触发，同样走交叉构建并把 `target/windows-full/x64/` 打成压缩包发布。

### 原生测试套件

`platforms/windows/CMakeLists.txt` 注册 96 个 ctest，`platforms/windows/tsf/CMakeLists.txt` 注册 19 个，`platforms/windows/msimeui/tests/` 是一个聚合套件，`platforms/windows/tests/native-pipe/` 另有两个 Windows-only 管道用例（`windows-pipe-io`、`windows-aux-listener`）。源文件按职责分在 `tests/{candidate,clipboard,core,input,runtime,ui,voice}` 下。按领域看：

- 协议与会话：`windows-server`、`windows-session`、`windows-reply-codec`、`windows-reply-composer`、`windows-input-queue`、`windows-registration-inbox`、`windows-aux-message`、`windows-runner-control`。
- 焦点与按键：`windows-focus-gate`、`windows-focus-router`、`windows-main-frame`、`windows-tsf-focus-lease-protocol`、`windows-tsf-key-dispatch`、`windows-input-key-policy`、`windows-key-event-send-result`、`windows-terminal-deactivation-policy`、`windows-mode-authority`、`windows-dedicated-english` 与 `-controller`。
- 候选与外观：`windows-candidate-card-size`、`-shadow`、`-wheel`、`-menu`、`-menu-layout`、`-initialization`、`-palette`、`-skin`、`-appearance`、`-render-sync`、`-font-format`、`-completion-policy`、`-text-policy`、`-ui-action-policy`、`-action-availability`、`-translation-merge`，以及五个热重载用例（`windows-candidate-skin-reload`、`-theme-reload`、`-layout-reload`、`-font-reload`、`windows-floating-toolbar-reload`）。
- 工具栏与托盘：`windows-toolbar-layout`、`-icons`、`-click`、`-coordinates`、`-mode-command`、`windows-floating-toolbar-placement`、`-visibility`、`windows-tray-menu-layout`、`-dispatch`。
- 联网候选与翻译：`windows-cloud-candidate-worker`、`windows-ai-candidate-worker`、`windows-translation-worker`、`windows-online-request-guard`、`windows-translation-display`、`windows-provider-token`。
- 语音：`windows-voice-controller-protocol`、`-connection`、`-listener`、`-dispatch`、`windows-voice-control-message`、`windows-voice-session-epoch`、`windows-voice-hotkey-policy`、`windows-voice-capture-selection`、`windows-voice-providers`、`windows-voice-theme`、`windows-voice-review-result`、`windows-wave-overlay-scale`、`windows-polish-prompt`。
- 剪贴板：`windows-clipboard-text`、`windows-clipboard-monitor`（后者实际注册 `AddClipboardFormatListener`、验证重复 `start` 幂等与重复 `stop` 不崩溃，不改写系统剪贴板、不记录用户内容）。
- 配置、启动与守护：`windows-shared-config-keybindings`、`windows-tsf-config-frames`、`windows-preview-config`、`windows-shell-surfaces`、`windows-server-launch`、`windows-installer-launch`、`windows-first-run`、`windows-prepare-host`、`windows-watchdog-policy`、`windows-maintenance-hotkeys`、`windows-diagnostic-log`、`windows-diagnostic-batch`、`windows-typing-statistics`。
- 输入策略：`windows-punctuation-policy`、`windows-paired-punctuation-host-policy`、`windows-edit-policy`、`windows-navigation-policy`、`windows-word-character-policy`、`windows-chinese-conversion`、`windows-preedit-caret`、`windows-fullscreen-foreground`。
- TSF 侧：`msime-tsf-client-key-router` 与 `-authenticated-client-key-router`、`msime-tsf-key-repeat-guard`、`msime-tsf-keyboard-cancellation`、`msime-tsf-smart-punctuation-fingerprint`、`msime-tsf-paired-punctuation-policy`、`msime-tsf-character-result`、`msime-tsf-raw-commit`、`msime-tsf-commit-and-continue-payload`、`msime-tsf-engine-response`、`msime-tsf-candidate-ownership`、`msime-tsf-preedit-caret`、`msime-tsf-host-focus`、`msime-tsf-prepared-options`、`msime-tsf-host-library-config`、`msime-tsf-module-path`、`msime-tsf-version-resource`、`msime-tsf-class-factory`。

`tsf/tests/exports/`、`tsf/tests/registration_profiles/`、`tsf/tests/registration_categories/` 是各自 configure 的独立子工程，做 PE 导出与注册契约检查而不加载 DLL。`platforms/windows/tests/tools/` 与 `installer/tests/` 下另有 PowerShell 套件（构建产物、通知收集、可移植可执行文件、运行时依赖、安装器入口与包内文件、TSF 注册、Watchdog 任务、仓库根布局），它们需要 Windows 主机，随 MSVC 构建与打包流程运行。

真词库行为另有一组探针，放在 `crates/engine-bridge/examples/` 与 `crates/input-runtime/examples/`，接收一个按 `resources/desktop-dictionary.lock.json` 备齐的资源目录。它们不挂进 `verify-local.sh`，因为锁定词库不在仓库里；但判据必须带真实词典的那几件事只有它们答得了——空词库对正确和错误的拼写一律回答「没有候选」。

## 功能分组与实现落点

路径相对本仓库；「来源入口」相对固定的来源提交。

| 功能组 | 来源入口 | 本仓落点 |
| --- | --- | --- |
| TSF 按键、焦点、edit session、UI-less | `windows/`、`server/src/ipc/` | `platforms/windows/tsf/`、`src/system/WindowsServer.cpp`、`src/ipc/SessionController.cpp`、`src/ipc/PipePeer.cpp` |
| 全拼、四种双拼、86 五笔、日语、辅助码 | README 对应指南、`engine/`、设置 `input.ts` / `helpcode.ts` | `crates/engine-bridge/`、`crates/input-runtime/`、`platforms/windows/src/ipc/SessionPump.cpp`、共享 `preferences.rs` |
| 候选分页、高亮、调频、preedit、以词定字 | README 候选调频 / preedit / 标点指南 | `src/candidate/CandidateWindow.cpp`、`src/candidate/CandidateAction.h`、`src/ipc/SessionController.cpp`、`src/ipc/ReplyCodec.cpp` |
| 中英文状态、独立英文候选、全半角、简繁、智能标点 | `server/src/english/`、设置 `input.ts` / `shortcut.ts` | `src/system/SharedConfigKeybindings.h`、`src/input/PunctuationPolicy.h`、`src/ipc/ReplyCodec.h` 的 TsfLocalConfig、`crates/client-core/src/chinese_conversion.rs` |
| K/T/U/E/M/J/Y/R 快捷模式、混输 | README 实用功能快捷模式 | Engine 桥接与共享偏好、`src/ipc/ServerSession.cpp`，混输排序在 `crates/input-runtime` |
| 谷歌云候选与 AI 联想 | README 云 / AI 联想、设置 `ai-settings.ts` | `src/candidate/CloudCandidateWorker.cpp`、`src/candidate/AiCandidateWorker.cpp`，由 `SessionController.cpp` 构造并投递输入队列 |
| 候选中英释义、腾讯云翻译、自定义翻译 | README 候选翻译 / 自定义翻译 | `src/candidate/TranslationWorker.cpp`、`src/candidate/CandidateTranslationPolicy.h`，共享 `crates/client-core/src/translation.rs` 与 `translation/store.rs` |
| 设置读取、保存、热更新与窗口行为 | `settings_app.cpp`、`config-sync.ts` | Tauri `load_preferences` / `save_preferences`、`src/system/PreferenceMonitor.cpp` 与 Server 的发布回调 |
| API 凭据测试（本仓库新增，来源没有此功能） | 来源无对应物 | Tauri `test_api_credential` → `crates/client-core/src/credential/`（豆包、批量 ASR、腾讯 / NiuTrans / DeepLX） |
| 词库查询、增改删、导入导出、快捷短语 | `dictionary_manager.cpp`、设置 `dict.ts` / `tools-settings.ts` | Tauri `dictionary_request`、共享 `dictionary/access.rs` 与 `dictionary/import.rs`，回放 CLI 为 `crates/engine-bridge` 的 `MetasequoiaImeDictionaryReplay` |
| 语音热键、流式 / 批量 ASR、润色、声音 / 静音、上屏方式 | `server/src/voice-input/`、设置 `voice.ts` | `src/voice/`（`VoiceHotkey.cpp`、`VoiceInputSession.cpp`、`DoubaoAsrClient.cpp`、`CuePlayer.cpp`、`SystemAudioMuter.cpp`、`WaveOverlay.cpp`、`VoiceSessionEpoch.h`）+ Tauri 语音面板 |
| 录音设备选择 | 来源语音设置 | `src/voice/VoiceCaptureSelection.h` 与 `VoiceInputSession`，按稳定设备 ID 枚举、保存并透传给 `AudioCapture::start` |
| 手写 | 设置 `handwriting-settings.ts` 与模型资源 | `src/system/ShellSurfaces.h` → Tauri `recognize_handwriting` / `submit_handwriting_candidate`，界面在共享 `panels.tsx` |
| 屏幕键盘 | 来源面板 `server/src/keyboard-panel/KeyboardPanel.cpp` | Tauri keyboard route 与共享 `packages/ui/src/keyboard/`，投递走 Windows host 的 `send_key` |
| Emoji、颜文字、符号、剪贴板历史 | README 与来源 `clipboard_history.cpp` | `src/clipboard/ClipboardMonitor.cpp`、`ClipboardHistory.cpp`、`ClipboardPaste.cpp`、`ClipboardPresentation.cpp`，面板与目录走 Tauri `load_emoji_catalog` / `paste_clipboard_text` |
| 悬浮工具栏、托盘菜单、入口快捷键 | 来源 `window/*presenter*`、`ui-html/webview2/ftb` 与 `menu` | `src/candidate/FloatingToolbarWindow.cpp`、`src/candidate/TrayMenuWindow.cpp`、`src/input/MaintenanceHotkey.cpp`、`src/system/ShellSurfaces.h` 与 `ShellLauncher.cpp` |
| 皮肤、主题、字体、外观预览 | 来源 `appearance.ts` / `skin.ts`、`candwnd/skins` | `src/candidate/CandidateSkin.h`、`CandidatePalette.h`、`CandidateShadow.h`、`CandidateWindow.cpp`，共享 `packages/ui/src/upstream/` 与 `crates/client-core/src/skin/catalog.rs` |
| 打字统计 | 来源 Server 私有统计表与统计页 | 采集在 Server，存储与展示在共享 `crates/client-core/src/typing_statistics.rs` 与共享设置页 |
| 更新、关于、帮助、反馈、重启 | 来源 `about-settings.ts` / `feedback-settings.ts` / `update-manifest.ts`、`restartServer` | 共享 `update-manifest.ts` 与设置页，Tauri `open_external_url` / `restart_input_method`，重启走固定 UTF-16LE `RestartServer` Aux payload |
| 服务守护、安装、升级、卸载、资源打包 | 来源 README 服务守护、`installer/`、构建脚本 | `platforms/windows/src/system/Watchdog.cpp` 与 `WatchdogPolicy.h`、`src/entrypoints/prepare_host_main.cpp`、`platforms/windows/installer/` |

### 逐项核对过的几处行为

这些是对照过程中判据比较细、结论值得单独记住的地方，都有对应用例：

- **输入方案**：全拼 `nihao` 首选 `你好`；四套双拼 profile 各自走通；微软双拼 `nihk` 的 preedit 切成 `ni'hao`；五笔 `gggg`/`hhhh`/`aaaa` 得到 `王`/`目`/`工`；日语罗马字 `nihon`/`sakura` 的假名读音与候选都正确，且反查全拼不带假名读音。ü 的两种写法（`nve`/`nue`、`lve`/`lue`，以及 j/q/x 后的 `u`）在本仓库都通，来源为 Google 解码器做的拼写改写在这边不需要。
- **调频持久化**：选过的候选在新开的会话里排到原位之前；`reset_learned_data` 之后回到出厂顺序，且这一步跑在确实写入过的 store 上；`learning: false` 时同样的选择在干净 store 上不改变任何顺序。五种调频模式各走各的规则。
- **翻页**：Engine 对单字母查询只给 24 个初始候选，`InputSession::expand_initial_candidates` 经 overlay 转发到公开门面后，运行时在末页触发展开——`j` 从 5 页变为 291 页。两条边界语义与来源一致：下一页正好是不满的末页时先展开再进去；已经在末页且当前页不满时，新到的候选填进当前页而不翻页。
- **自动造词**：锁定 Engine 的 `InputSession::commit` 内部已自带整条链，门面的 `select` 走的就是它，所以本仓库不需要来源在 Server 里手工串的那几步。判据是**简拼**——组合出来的短语答 `htpb`，重新生成的整句不答。
- **混输候选的座位表**：来源 `candidate_selection_policy.h` 的四种排布已实现进运行时的 `normalize_online_slots`，只在快照里确实存在云 / AI 候选时生效。插入是压缩的而非固定编号：没有英文候选时 AI 落第二。多于一个的云 / AI 候选按本地候选处理而不是丢弃。
- **以词定字**：`[` 上屏高亮候选的首个汉字、`]` 上屏末字，覆盖三字候选、组合被消耗、无汉字候选与越界索引。
- **辅助码**：单码调序与双码筛选按来源规格逐条核对，全拼与双拼两套方案及候选窗显示都在；五笔的逐键提示按共享 `wubi_code_hint` 显示严格前缀的剩余编码，回退与本地模式不标注。
- **八个快捷模式**（K/T/U/E/M/J/Y/R）：带锁定词库的 `ServerSession` 回归逐个验证 Shift 入口、候选生成与选词提交。Unicode 模式的数字键是「打码位」而不是选词序号，判断分在两层——引擎报 handled，运行时只把引擎拒绝的数字落到选词；这个组合有真引擎回归覆盖。
- **中英文状态**：按应用 / 全局的作用域是纯决策函数并有 `windows-mode-authority` 覆盖；标点重复与成对补全随配置帧下发并由 `windows-tsf-config-frames` 钉住；CapsLock 由 Server 持有并经 `CapsLockChanged` 帧下发；热更新有 `preference_monitor` 用例。
- **日语**：`-` 交给长音符输入而不是翻页，`-`/`=` 不再用作翻页键，TSF 与 Server 两侧保持一致，且这条走的是物理按键到真实 Engine 的完整路径。
- **凭据测试**（本仓库新增的功能）：豆包走独立 WebSocket 握手，传输可注入，生产 WSS 不跟随重定向，连接阶段 5 秒、总时限 15 秒，消息与累计响应上限 1 MiB、最多 64 条消息，只发送一秒合成 PCM 静音并要求有效终态 JSON，不回传服务端诊断或识别文本；批量 ASR（OpenAI、SiliconFlow、Groq）用内存生成的一秒 16 kHz 单声道 PCM16 静音 WAV 以 multipart 上传，不访问麦克风，HTTPS、禁止重定向、5 秒连接 / 15 秒请求、256 KiB 响应上限；翻译侧要求真实译文字段而不是把任意 HTTP 2xx 当成功，自定义服务保留 HTTP/HTTPS 但禁止重定向。新版豆包 API Key 与旧版 App ID/Access Token 互斥，新版忽略残留 App ID。
- **语音**：五个语音快捷键开关、录音提示音与静音其他声音、豆包的整句流式与双向流式两个识别接口（设置页给带名字的下拉，选中即写入 `asr_endpoint`，地址不属于两个预设时显示「自定义地址」）都在。录音设备按稳定设备 ID 枚举、保存并透传给 `AudioCapture::start`。语音会话的代际由 `VoiceSessionEpoch.h` 持有，取消与失焦的旧结果不交付。
- **词库**：查询、增改删、按类型导出、快捷短语都走 Tauri `dictionary_request` 与共享 `dictionary/access.rs`；维护前后的 quiesce / resume 由 `dictionary_maintenance_handshake` 协调。
- **皮肤与外观**：Windows 消费候选字体与回退字体、主题颜色、横竖排布局与阴影字段；`windows-candidate-font-reload`、`windows-candidate-palette` 与阴影回归覆盖非法值的回退路径。四套内置皮肤的候选窗 CSS 预览与原生候选窗用同一套两层阴影（环境层加接触层），与 `CandidateShadow.h` 的透明留白一致。
- **重启**：使用固定 UTF-16LE `RestartServer` Aux payload，有回归覆盖。
- **两个位数都编得过**：`CandidateWindow.cpp` 曾把无捕获 lambda 直接传给 `EnumFontFamiliesExW`，而 `FONTENUMPROCW` 是 `__stdcall`——在 x86_64 上是同一种调用约定，在 x86 上是不同类型。改成具名 `CALLBACK` 函数后，当前全部 Windows 源文件在 x86 语法检查下通过。
- **非 ASCII 用户目录**：`reset_learned_data` 拼 SQLite 的 `-wal` / `-shm` / `-journal` 路径时直接在 `path` 的 native 字符串上拼接，不过窄字符转换，因此 `C:\Users\陆傲天` 这类 profile 不会转错也不会抛；既有用例在 ASCII 与中文两种根目录下各跑一遍。
- **翻译**：缓存键按服务商与账号分域，凭据、端点、目标语言与启用开关任一变化都丢弃正负两种结果；腾讯请求签名按官方 TC3-HMAC-SHA256 独立算出已知答案钉住；本地自定义释义每次请求现算，编辑立即生效且恒胜过缓存的云端结果。
- **云与 AI worker**：结果绑定 lease / query / 候选；去抖窗口内只付新的那次；同一前缀第二次吃缓存；空结果不入缓存；在途被取代时结果不交付；提供方抛异常只被记录而不带走 worker 线程；非法信封到不了提供方。
- **智能标点**：重写标点前回读两个字符核对指纹（arm 时记下标点前面的字符），避免用户把光标移到文档里另一处同样的标点上时改错位置；文本存储读不出内容（终端与代理存储）判为匹配，以免在这些宿主里直接废掉该功能。读不回待改写字符时改走 SendInput 改写队列，执行前校验焦点 token、前台窗口与 500ms 期限。
- **成对补全关闭时的引号与书名号**：来源 `GetPunctuation` 的引号轮换（“ 之后是 ”）与 `<` `>` 嵌套计数（《〈〉》）不看成对开关，被排除的宿主（Excel）因此回落到左右轮换。锁定引擎在成对关闭时只给左半边，由 overlay `scripts/apply_engine_punctuation_alternation.py` 去掉 `PunctuationPolicy::translate` 里的两处开关判断；状态随会话存活、切换开关不重置，与来源一致。各宿主都只在成对开启且未排除时自己改写 ” → “，不会重复轮换；HarmonyOS 成对开启时由 `PairedPunctuationPolicy.reopenQuote` 做同样的改写。`crates/host-api/src/tests.rs` 经 FFI 驱动真实引擎钉住“”“”、‘’、《〈〉》与不重置。
- **候选窗绘制**：行按逐项测量而非定高，带按外观字体的回退（`ApplyFontFallback`）与卡片的显式阴影 pass。每个候选按来源 `CandidateList::MeasureItem` 分成三段：候选文字（含角标）、辅助码、译文。辅助码与候选同字号同颜色，接在文字后 4 DIP；译文字号为候选的 0.78，间隔为候选字号的 0.65，颜色是辅助码颜色的 alpha 乘 0.62，选中行两者都跟随选中文字色。竖排时放得下就同一行，放不下就移到文字下方并按列宽换行，辅助码一旦下移译文也跟着下移；横排时译文总在文字下方。几何在 `CandidateCardSize.h` 的 `candidate_item_layout` / `candidate_page_layout`：竖排各行按自身高度堆叠，横排各列取最高一行的高度，卡片高度按夹紧后的宽度计算；换行高度由 DirectWrite 以绘制同款 NEAR + WRAP 格式实测。`paint` 以实际绘制宽度排版并缓存行矩形，`hit` 用这份缓存，点击与绘制不会错位；`windows-candidate-card-size` 覆盖这些规则。合成路径复用渲染目标时刷新 DPI，语音波形浮层的定位与缩放取自同一份 per-monitor 快照。
- **屏幕键盘**：普通键 450ms 首次延迟、75ms 间隔自动重复，粘滞修饰键与 Num Lock 单次切换；投递失败、失焦或关闭会停止重复且不自动重放。修饰键按下 / 释放的扩展键集合与来源逐键相同，布局为来源的超集（多出 F10–F12、PrtSc/Scroll/Pause、导航簇与 Menu 键）。
- **剪贴板**：历史上限 50 条，文本边界为 4000 UTF-16 单位与 12000 UTF-8 字节；`normalize_clipboard_text` 只去掉 CF_UNICODETEXT 带来的东西（首个 NUL 起截断、剥掉尾部 `\r`），换行与空白是用户内容、原样往返。
- **简繁转换**：共享层 `crates/client-core/src/chinese_conversion.rs` 按 OpenCC `data/config/s2t.json` 实现词级转换（兼容表归一化，再以 STPhrases ∪ 地区词派生表 → STCharacters 做最大正向匹配，完整 IDS 序列整体透传），数据取自来源钉的同一个 OpenCC 提交并登记在 `docs/third-party.md`。边界导出 `msime_client_simplified_to_traditional` 返回裸文本而非 JSON——它在每个候选上都要调用；首次调用解析词典，之后单次约 1 µs。与该提交构建出的 OpenCC CLI 做对照，4 万行随机文本逐字节一致。
- **安装器**：完整安装器提供数据目录选择页，拒绝系统 / 用户关键目录的父级、受保护目录内部、路径穿越与未标记的非空目录，并在就绪页展示迁移源与目标；`config.toml` 只 `onlyifdoesntexist`，升级不覆盖用户数据；light 包固定原目录。安装前在第一屏之前查注册表确认 WebView2 与 VC 运行库（要求 14.20 以上而非只看 `Installed=1`），静默安装默认继续并把缺失写进日志。
- **安装后的首次准备**：完整安装器在提升权限下写入词库、出厂配置和所有权标记，但不以安装器身份替用户执行 Host API 准备。Server 的生产首次启动因此除全新目录外，也接受已有且带 `.metasequoiaime-data` 所有权标记、尚无 `runtime-options.json` 的目录，在用户上下文中完成准备；普通已有目录、已有运行时配置、文件和符号链接不会被接管或重建，准备失败保留现有数据。独立的 `msime-client-prepare` 仍只接受全新目录。
- **检查更新**：各平台由 `.github/workflows/release-*.yml` 独立发布到同一个仓库、标签带平台前缀，所以读的是发行版列表而不是 `releases/latest`——后者返回的通常是别的平台那一个。只取本平台前缀、非草稿、非预发布的发行版，按版本号而不是列表顺序取最新，没有则显示「暂无可用发行版」。Server 遥测上报的版本号由 CMake 从 `platforms/windows/version.txt` 读入，`Build-Client.ps1` 的 `-TargetVersion` 把同一个版本号同时传给 Tauri 和 Server。
- **外部链接**：走 `msime_host_windows::open_url`，用 `ShellExecuteW` 把 https URL 直接交给默认浏览器，非 https 一律拒绝，与已有的 `open_directory` 共用同一段调用；不经 `cmd /C start`，不闪控制台窗口，URL 也不过 cmd 解析。

### 来源源码树的落点

上面那张表按功能组织，回答某个功能有没有；这一节按**来源的源码目录**组织，回答来源的每一块代码去了哪儿。两者互相校验：一块代码找不到落点就是缺口，哪怕对应功能在表里被标成有。`scripts/test-reference-source-inventory.py` 把这一节变成每次都会跑的断言。

**TSF DLL：逐文件对应。** 来源 `windows/src/` 下的 38 个 `.cpp` 在 `platforms/windows/tsf/` 全部都有，同名同目录结构。另有 6 个来源没有的：`EngineResponse.cpp`、`EngineSessionAdapter.cpp`、`HostOptionsPaths.cpp`、`PreparedHostOptions.cpp`、`Global/TsfPropertyGuids.cpp`、`Thread/ThreadState.cpp`——它们是进程边界带来的，来源把 Engine 放在同进程，这边 TIP 要通过契约与 Server 对话。再加一套来源没有的 TSF 测试（`platforms/windows/tsf/tests/`）。

**Server：按目的地分三类。**

| 来源目录 | 落点 | 归类理由 |
| --- | --- | --- |
| `ipc/`、`session/`、`watchdog/`、`log/` | `platforms/windows/src/ipc/`、`src/system/` | 进程边界与 TSF 协议，只能是原生 |
| `window/`（候选窗、悬浮工具栏、托盘） | `platforms/windows/src/candidate/` | 低延迟、不抢焦点，保留原生 Direct2D |
| `voice-input/` | `platforms/windows/src/voice/` + Tauri 语音面板 | 热键与上屏原生，界面在 Tauri |
| `cloud/cloud_ime.cpp` | `platforms/windows/src/candidate/CloudCandidateWorker.cpp` | 在输入队列上跑，跟着会话生命周期 |
| `cloud/tencent_tmt.cpp`、`cloud_translation.cpp` | `crates/client-core/src/credential/translation.rs` | 凭据与请求逻辑跨平台共享 |
| `cloud/custom_translation.cpp`、`translation_gloss.cpp` | `crates/client-core/src/translation.rs` | 同上 |
| `skin/candidate_skin_catalog.cpp` | `crates/client-core/src/skin/catalog.rs` | 皮肤目录跨平台共享 |
| `english/`、`emoji/`、`kaomoji/`、`conversion/` | Engine 与共享偏好 | 这些是输入算法的一部分，Engine 拥有 |
| `user-dictionary-replay/` | `crates/engine-bridge`（`MetasequoiaImeDictionaryReplay`） | 词库维护跨平台共享 |
| `settings/`、`webview2/`、`emoji-panel/`、`keyboard-panel/`、`handwriting-panel/` | Tauri 壳（`apps/desktop/`、`packages/ui/`） | 公共功能与界面放 Tauri；来源用 WebView2 自绘，这边两个桌面宿主共用同一个 Tauri 应用，入口契约见 `src/system/ShellSurfaces.h` |
| `utils/` | 分散在对应模块 | 工具函数不单独成目录 |

来源另有 `experiments/tsf-edit-control`，已迁入 `platforms/windows/experiments/tsf-edit-control` 并接成 Windows-only CMake 目标：Direct2D/DirectWrite 绘制的原生 Win32 编辑宿主与最小 demo，用来重复检查 TSF 文档上下文、preedit 与 display attribute、候选位置、软换行、选区、插入点和鼠标命中这些边界。它是验证工具而非产品组件，不注册 TSF、不启动生产 Server。来源工程特有而这边不存在的 `common.ver`、`InputScope.h`、`tsattrs.h` 依赖已去除，宿主仍用系统 TSF 头文件。

## 与来源刻意不同的取舍

这些差异都是适配本产品的进程结构与多平台共享层所做的取舍，每条都记着理由与替代物，不是欠账。

**候选相关的四个表面由原生 Direct2D 绘制。** 候选窗、候选浮出、悬浮工具栏、托盘菜单在来源是 WebView2 文档，在这边是原生窗口。来源把 WebView2 同时当作候选窗的可选渲染后端，这边候选窗只有 Direct2D 一种实现；配置键 `ui_backend` 作为契约保留并登记在字段漂移门禁的 `RUST_ONLY` 里。

**这四个表面走合成交换链，而不是来源的分层窗口。** 来源的输入法窗口用 `WS_EX_LAYERED`（`server/src/window/ime_windows.cpp`），DirectComposition 只出现在它的 WebView2 与设置路径里；这边统一走 `DeviceResources::EnsureForComposition`（`DCompositionCreateDevice` 加 `CreateSwapChainForComposition`）。理由是合成交换链避开 `UpdateLayeredWindow` 每帧的 CPU 拷贝，而这四个表面都是低延迟且不能抢焦点的。失败时也不回退到普通 HWND 交换链：那拿不到逐像素透明，候选卡片的阴影会退化成不透明矩形，静默变丑比明确失败更糟。代价记在这里：无 DirectComposition 的环境（如 Wine）要画出这套，是一次明确的渲染路径工作。

**设置页与各类面板走 Tauri 与共享 React。** 设置、表情、手写、屏幕键盘、语音面板都在独立的 Tauri 进程里，两个桌面宿主共用同一个应用，入口契约是 `src/system/ShellSurfaces.h`。

**菜单的禁用语义因此与来源不同。** 来源的菜单 HTML 里 `disabled` 出现零次——它的面板全在同进程内，永远可用。这边的面板在独立的壳里，壳可能不在，所以能力缺失的行**保持可见但置灰**，而不是点了没反应或干脆隐藏（`src/candidate/TrayMenuLayout.h` 的注释写明依据：保住来源「菜单从不隐藏条目」的可见性语义，同时诚实反映进程边界）。托盘菜单的动作与来源一一对应，且这边多出手写识别板。

**偏好文件每次整份写出，不做三方合并。** 来源的升级路径是模板三方合并——用户改过的键保留、仍停在旧默认值的键跟随新默认值、模板里没有的键与段落丢弃。这边的 `preferences.json` 每次把全部字段写出来，没有「旧默认值」这个概念，所以改默认值到不了已有用户；`deny_unknown_fields` 又让退役字段不能删（`ui_backend` 的注释已写明）。这是存储模型层面的取舍。附带的好处是来源那次「升级时配置解析失败被出厂模板覆盖、凭证清零」的缺陷在这边不存在：共享偏好用原子写入，解析失败返回错误而不是回落默认值后再写回。

**智能标点在 Windows 上默认关闭。** Windows 随包的 `config.default.toml` 五个开关全为关，来源也已把整族改成默认关；但那只是安装模板，运行中的 Server 读的是共享偏好文档。默认函数写成 `!cfg!(windows)`：只动 Windows，其余宿主一直是开着发的，让偏好在老用户脚下变掉比按平台不同更糟；两边都不影响已存下来的值。判据在 `scripts/test-default-config-parity.py`。

**三个语音开关在 Windows 与 macOS 上默认打开，其余宿主默认关闭。** 来源的 `config.default.toml` 出厂就打开 `mute_system_audio`、`doubao_enable_ddc` 与 `polish_text`，Windows 随包模板也一样，但运行中的宿主读的是共享偏好文档，而它原来三个全关，于是 Windows 的全新 profile 拿到的恰好与自己随包的模板相反——和智能标点是同一个坑。默认函数 `source_voice_default()` 写成 `cfg!(any(windows, target_os = "macos"))`，同时用作缺键时的 serde 默认；Linux、Android、iOS、HarmonyOS 保持原样，理由同上一条；已存下来的值不受影响。macOS 原生侧在共享快照写进 NSUserDefaults 之前使用的回退值（`VoiceProviderOptions.h` 的润色与 DDC、`MSIMEVoiceMuteSystemAudioEnabled`、原生语音设置窗口的勾选框）与之一致。`default_ime_mode` 在 macOS 仍是中文：用户是从输入法菜单里主动选中本输入法之后才开始打字的。判据在 `scripts/test-default-config-parity.py`，模板与共享默认任一边改回去都会报出来。

**智能标点的三个子开关不走独立 opcode。** 来源 `windows_ipc.h` 的 22/24/25 三个 opcode 在这边由一帧打包的标点配置携带。

**打字统计的落点与存储都与来源不同。** 采集放在 Server 而不是 TSF DLL：来源的 Engine 与 DLL 同进程，而这边 Server 是唯一看得到每一条上屏字符串的地方，共享 Host API 也链在这一侧，文本本来就要作为上屏载荷从 Server 走到 DLL，采集不让它多跨任何一道边界。唯一的例外是 TIP 不吃掉的按键：它们由应用自己插入，永远到不了 Server 的上屏出口，于是英文模式的字母、中文模式下的半角数字与标点表之外的符号由 DLL 在 `OnTestKeyDown` 的三个放行出口采集，按批经已有的 Aux 管道（`TypingStatistics` 动词）交给 Server 落盘，和上屏出口共用同一段代码——即便如此，来源为此另开的那条统计命名管道（`FANY_IME_STATS_*` 契约）这边仍然不需要。统计默认关闭，关闭时 Server 不回 OK，DLL 据此退避，不在关闭期间持续把按键字符送过管道。存储则做在共享 `crates/client-core/src/typing_statistics.rs` 与共享设置页，而不是来源的 Windows 私有 SQLite 表：这些维度和「每天多少字」是同一件事，后者早就在共享层、六个宿主写同一份文档，单开一套 Windows 私有存储会让同一个用户的统计分裂成两份。速度指标另有一处有意不同：来源只数 `cjk + latin`，而它的 `latin` 是纯 ASCII 字母、假名落在 `other`，于是纯日文输入的速度恒为零；这边有完整日文模式，所以假名与谚文等也算进可读字符，数字与标点仍然不算。

**半截词的 preedit 不在 Windows 打开。** 其余五个宿主（macOS、Linux、HarmonyOS、Android、iOS）把「已选的那一段 + 读音」画在组字里，Windows 的 TSF 侧自己累积前缀，打开会重复；桌面外壳没有候选窗，不适用。

**候选文字本身超宽时截断而不是换行。** 辅助码与译文已按来源在行内放不下时换到文字下方、行高随之可变（见上文「候选窗绘制」），但候选文字自身仍是单行，超出的部分截在行矩形处，与命中测试用的是同一个矩形。横排仍把卡片等分成等宽列，比列宽还宽的候选照旧被截断；来源按每项自然宽度分列，这一处尚未迁移。

**诊断日志固定写数据目录。** 来源先写桌面、失败再退回数据目录；这边固定写数据目录下的 `logs\server.log`，因为输入法在桌面上凭空出现文件不是用户预期的副作用。设置页的「Server 端日志」「TSF 端日志」两个开关（`diagnostic_log.server` / `diagnostic_log.tsf`）分别控制写入，内容只有 Server 启停原因、各组件是否就绪、退出码与 TIP 上报的诊断批次，不记按键、输入内容或候选文本；4 MiB 轮转为 `server.log.1`，最多保留两份；UTF-8 BOM 与 CRLF 行尾与来源一致；偏好发布时立即生效，无需重启 Server。

**macOS 语音有三处刻意与来源不同。** 静音其他声音是整台默认输出设备而不是按进程，因为 macOS 13 没有公开接口，时序上改为开始提示音播完再静音、先恢复再播结束提示音，以保证提示音听得见；录音录满上传上限时自动结束并提交已录部分，而不是像来源那样提交时报超限并丢掉整段；提示音文件缺失时回落到系统声音而不是不出声。细节见 `platforms/macos/README.md` 的「语音输入」。

**简繁转换由 Windows、Linux 与共享层走 OpenCC 词级，macOS 仍是逐字。** Linux 的 `platforms/linux/src/system/ChineseTextConversion.cpp` 调同一个 `msime_client_simplified_to_traditional` 导出，两个宿主因此都不再依赖 `libicu`；macOS 的 `CFStringTransform` 是系统提供的逐字转换，要改成同一条路径只需把调用换成共享层那个导出。逐字转换解决不了一对多的字，「头发」会成「頭發」。

**设置页有几处措辞与控件刻意与来源不同**：「始终使用英文标点」与这边的「中文标点」绑同一个 `chinese_punctuation` 但极性相反，只改名不反转控件即是错标；剪贴板管理来源写「关闭后立即清空」，这边写「保存关闭设置后清空」，因为这边的清空发生在偏好保存时；候选窗字体一项 Windows 显示的是「候选窗英文字体 + 补充字体」而非来源的「主字体 + 中文补充字体」，是 Windows 字体路径上的既有取舍。

## Windows 进程与协议边界

**两个目标，边界写死在构建里。** TSF tip 是进程内 DLL（`platforms/windows/tsf/`，`OUTPUT_NAME MetasequoiaImeTsf`，经 `IME/MetasequoiaIME.def` 导出四个未修饰 COM 入口，链 Rust `msime-host-api` 的导入库）；Server 是独立的窗口子系统可执行文件（`src/entrypoints/server_main.cpp`，`OUTPUT_NAME MetasequoiaImeServer`）。另有 `MetasequoiaImeWatchdog`（对应安装器的登录任务）与 `msime-client-prepare`（准备 `runtime-options.json`）。

**Server 是窗口程序而不是控制台程序。** 控制台子系统会让 Watchdog 与 TSF DLL 每次拉起 Server 都带出一个黑色控制台窗口。现在链接为 Windows 子系统（MinGW `-mwindows`；MSVC `WIN32_EXECUTABLE` 加 `/ENTRY:wmainCRTStartup`，入口仍是 `wmain`）。`--config` 预览与 `--help` 从终端启动时挂到父控制台（`AttachConsole(ATTACH_PARENT_PROCESS)`），状态行与 Ctrl+C 照旧；受管启动（`--watchdog-managed` / `--production`）从不挂接，因为 TSF DLL 是在当前焦点程序里拉起 Server 的，那个程序本身可能是控制台程序。

**退出码是 Watchdog 契约的一部分。** 维护快捷键的「停止」（Ctrl+Shift+Alt+T）返回 `watchdog::stop_exit_code` 而不是 0——返回 0 会被 Watchdog 判为非正常退出并在两秒后重新拉起，等于停不下来。已打开的设置等 Tauri 窗口是独立进程，不随 Server 关闭，与「重启」时的行为相同。

**命名管道分三个角色**：Main、Aux、Diagnostic（`src/ipc/` 下的 `PipeListener`、`PipeService`、`PipeMainTransport`、`AuxListener`、`DiagnosticListener` 等）。协议侧的几条规则是这条边界的要害，都由用例钉住：

- hello 帧里的 `client_id` 不是认证。控制器进程不能复用 TSF 目标进程的 ID；对端由 OS 提供的信息验证（`PipePeer::bind` 校验客户端 PID、登录会话与 TokenUser SID），焦点租约另外单独绑定。
- `PipeRegistry` 的注册代际不等于激活 epoch。排队前检查不够，执行时仍要检查焦点、会话与代际。
- 未握手的 Aux 通道不是可接收凭据与识别文本的认证语音通道。
- 投递结果分 `Sent` / `DefinitelyNotSent` / `DeliveryAmbiguous` 三态，fallback 按三态分别处理，而不是把「不确定」当成「失败」重放。

**面板文本投递先校验再恢复焦点。** Windows host 导出与 Tauri 面板入口共用的 `valid_text` 判据，在恢复目标编辑器焦点**之前**拒绝空串、超过 4096 字节的文本和控制字符（`send_text` 复用同一判据，避免两个入口漂移），因此无效请求不会改变用户当前焦点。恢复焦点本身在 `SetForegroundWindow` 成功后立即读 `GetForegroundWindow` 确认目标确实是前台窗口，才继续全局 `SendInput`；语音路径与面板路径共享这道边界。

**偏好热更新的时序。** 监视器先在输入队列应用 `PreferenceSnapshot`，再从监视线程通知 `SessionController` 的发布回调；回调清理并按新配置重新发起当前候选页的翻译查询。应用延迟到未确认的回复完成之后，且回调提交的观察任务必须看到新的导航绑定与以词定字状态——「发布任务已入队」不等于「偏好已生效」。

**TSF DLL 的 COM 边界。** 类工厂契约由 `msime-tsf-class-factory` 钉住：从同目录加载出货 DLL，解析 `DllGetClassObject`，用固定 CLSID 取得 `IClassFactory`，实例化的对象实现 `ITfTextInputProcessor`；未知 CLSID 返回 `CLASS_E_CLASSNOTAVAILABLE`，已知 CLSID 但请求不支持的类工厂接口返回 `E_NOINTERFACE`，空输出指针在 `QueryInterface` 返回 `E_POINTER`、在 `CreateInstance` 返回 `E_INVALIDARG`；类工厂拒绝聚合；`DllCanUnloadNow` 钉住「类工厂或 TIP 仍被引用时不可卸载、全部释放后可卸载」，并覆盖 `LockServer(TRUE/FALSE)`。生产的 `DllGetClassObject` 先清空输出，再按 CLSID、然后按接口判定，不把这两类错误混为一谈。

**安装布局与注册。** 32 位与 64 位 TSF DLL 分别装到 `{commonpf32|64}\metasequoiaime\msime_v<ver>\` 并带 `regserver` 标志注册 TIP，PDB 同目录；Server 装在 `{commonpf64}\metasequoiaime\server`；应用数据装到用户选定的 `DataDir`；HKLM `Software\Metasequoia\MetasequoiaIME` 写 `VersionDir` / `ServerPath` / `DataDir`；`THIRD_PARTY_NOTICES.txt` 与 `LICENSE.txt` 随包分发（GPLv3 第 4、6 条）。`ISCC /DLightPackage=1` 出不含词库的轻量包。

### Windows 发布流水线产出真实安装包（2026-09-23）

- 流水线：`.github/workflows/release-windows.yml` 在 windows-2025（MSVC，Visual Studio 18 2026）上按 `installer/Package-SimplySign.ps1` 的顺序走完 `Build-Client.ps1` → `Collect-Notices.ps1` → `Prepare-PackageFiles.ps1` → `Compile-Installer.ps1`，只是跳过签名。原生依赖按 `platforms/windows/vcpkg.json` 的 baseline 装进 x64/x86 两个前缀并缓存；Inno Setup 固定 6.7.1，`ChineseSimplified.isl` 取自同版本标签并校验 SHA-256。
- 产物：`MetasequoiaIME_Setup_v<版本>.exe` 与 `.sha256` 作为 workflow artifact 上传；`publish` 输入默认关闭，打开时才创建 `windows-v<版本>` Release。安装包未签名，因为代码签名证书是只在发布机上的 Certum SimplySign 卡，签名仍是本地步骤。
- 第一次在 MSVC 上完整构建暴露并修掉的问题：Engine overlay 脚本按 ANSI 代码页读写 UTF-8 源；engine-bridge 的 MSVC 编译拿不到 vcpkg 头文件；strict 目标的 `/W4 /WX` 窄化、遮蔽与 `getenv` 弃用告警；TSF 引入 Engine 管道契约时被 SDK 的 `max` 宏改写；PowerShell 调 pnpm（`.cmd`）时 Tauri `--config` 的内联 JSON 丢了引号；`Collect-Notices.ps1` 按整个文件比较 Engine 标记；安装脚本 `[Code]` 里有先用后声明的 `UserConfigPath` 和保留字 `Protected`。
- 证据：https://github.com/metasequoiaime/msime/actions/runs/35815935438 成功，artifact `msime-windows-0.1.0` 内含 201 MB 的 `MetasequoiaIME_Setup_v0.1.0.exe`，下载后 `.sha256` 校验通过。安装包尚未在真实 Windows 上安装验收。
- Rust 与前端依赖的通知：发布工作流在 Windows runner 上用 `platforms/linux/collect-notices.py`（与 Linux 发布同一个收集器）从 Cargo 解析出的 Windows 依赖图收集 `msime-host-api`、`msime-engine-bridge`（词库回放工具）和 `msime-desktop` 静态链接的 crate 许可证文件，再从 `apps/desktop` 的 `node_modules` 收集前端打包进去的 npm 包，两份文件作为 `-SupplementalNotices` 交给 `Collect-Notices.ps1`，随 `THIRD_PARTY_NOTICES.txt` 进安装包。
