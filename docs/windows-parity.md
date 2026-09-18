# Windows 功能迁移对照

## 范围与固定基线

目标是迁移 MSIME-Windows 的完整功能，而不是只移植语音、设置页或能在当前机器运行的子集。公共业务放共享层、公共管理界面放 Tauri；输入算法与组合状态仍归 C++ Engine；Windows 保留 TSF DLL / Server 进程及协议边界。已合并的其他平台成果不回退。每部分本地验证后提交合并，不要求用户逐项确认，不恢复私有仓库 CI。

2026-09-17 本次对照使用以下不可变对象，未读取相邻仓库未提交内容：

- 来源：`metasequoiaime/MSIME-Windows`，通过 `git ls-remote --symref origin HEAD` 确认默认分支 `develop`，固定提交 `e1d53dd8f01fd351633f08374f189157f5cb47e9`（2026-09-20 审计）。
- 目标：`metasequoiaime/msime` 的 `develop`，固定提交 `71008a3f9c905e7bc880d83f97e4a0d46d623ab5`（2026-09-20 当前远端默认分支；完整对象以远端 `origin/develop` 为准）。
- 来源 Engine 已内嵌为 `engine/`，其 `UPSTREAM.md` 记录导入提交 `c810d201f549b337ae0c4a65a9d694103f1c1754`。目标通过 `engine-lock.json` 和 `scripts/fetch_engine.py` 获取并校验独立的 `vendor/MSIME-Engine` 源码归档，不使用 `.gitmodules`、递归 Git checkout 或 gitlink。两者不能因目录名或协议名相同而视为内容相同，也不能把来源 Server 的新接口记为目标已接入。

来源功能入口以该提交的 `README.md`「功能简介」「核心功能指南」、`ui-html/webview2/settings/ime-settings/src/modules/sidebar.ts`、`server/src/settings/settings_app.cpp` 和 `engine/contracts/webview/messages.json` 交叉核对。README 只是入口索引，后续仍须逐字段、逐动作下钻；本表不是穷尽行为的完成证明。

## 证据等级

- **有调用链**：已找到目的地的真实调用代码；不等于原生系统行为已验证，也不等于和来源完全一致。
- **明确缺口**：可由条件编译、未消费配置或缺失运行时路径直接证明。
- **待逐项对照**：存在代码/测试入口，尚无足够行为等价证据。

测试文件存在只表示可用的验证入口，不表示本次执行通过。没有以窄范围测试、来源 CI 或构建成功代替 Windows 安装后交互验证。此处不计算完成百分比。

## 功能分组与目的地入口

以下路径均相对目标仓库；“来源入口”相对固定的来源提交。

| 功能组 | 来源入口 | 目的地证据 | 当前结论与下一项验证 |
| --- | --- | --- | --- |
| TSF 按键、焦点、edit session、UI-less | `windows/`、`server/src/ipc/` | `platforms/windows/tsf/`、`WindowsServer.cpp`、`SessionController.cpp`、`PipePeer.cpp` | 有调用链；继续验证真实编辑器焦点切换、断线重连、跨位数 DLL/Server、组合提交与撤销。 |
| 全拼、四种双拼、86 五笔、日语、辅助码 | README 对应指南、`engine/`、设置 `input.ts` / `helpcode.ts` | `crates/engine-bridge/`、`crates/input-runtime/`、`platforms/windows/src/ipc/SessionPump.cpp`、共享 `preferences.rs` | Windows 日语模式已将 `-` 交给长音符输入、禁止 `-`/`=` 翻页，并在 TSF/Server 两侧保持一致；候选选择现绑定会话、代次及单调窗口渲染 serial，等待上屏前的绘制回执可避免调频重排错选；macOS 原生候选面板现按共享 `wubi_code_hint` 显示严格前缀的剩余五笔编码，回退/本地模式保持不标注；仍待固定词库逐项核对各输入方案。 |
| 候选分页、高亮、调频、preedit、以词定字 | README 候选调频/preedit/标点指南 | `CandidateWindow.cpp`、`CandidateAction.h`、`SessionController.cpp`、`ReplyCodec.cpp`；Linux `ClientEngine.cpp` | 有调用链；Linux IBus 候选操作菜单现提供上一页/下一页并复用共享分页命令，仍需检查分页键、鼠标与键盘行为、调频持久化和旧候选请求拒绝。 |
| 中英文状态、独立英文候选、全半角、简繁、智能标点 | `server/src/english/`、设置 `input.ts` / `shortcut.ts` | `SharedConfigKeybindings.h`、`PunctuationPolicy.h`、`ReplyCodec.h` 中的 TsfLocalConfig、共享偏好与 Engine 桥接 | 已补齐 TSF client key-router 边界、IPC `Sent` / `DefinitelyNotSent` / `DeliveryAmbiguous` 三态 fallback、标点配置帧及宿主进程策略回归；仍需分别核对按应用/全局状态、CapsLock、标点重复、成对补全与热更新。 |
| K/T/U/E/M/J/Y/R 快捷模式、混输 | README 实用功能快捷模式 | Engine 桥接、共享偏好、`platforms/windows/src/ipc/ServerSession.cpp` 及 `platforms/windows/tests/runtime/session_smoke.cpp` | 已补带锁定词库的 ServerSession 回归：八种快捷模式均验证 Shift 入口、候选生成和选词提交；仍需 Windows 原生 TSF/真实编辑器交互验证。 |
| 谷歌云候选与 AI 联想 | README 云/AI 联想、设置 `ai-settings.ts` | `CloudCandidateWorker.cpp`、`AiCandidateWorker.cpp`，由 `SessionController.cpp` 构造并投递输入队列 | 有调用链；核对每个提供方、超时、取消、失焦后旧结果以及凭据路由，勿只验证 UI 保存。 |
| 候选中英释义、腾讯云翻译、自定义翻译 | README 候选翻译/自定义翻译 | `TranslationWorker.cpp` → `SessionController.cpp` → 候选展示；共享 `translation.rs` / `translation_store.rs` | 有调用链；仍需比较本地优先级、腾讯请求签名、词库编辑与缓存失效。 |
| 设置读取、保存、热更新与窗口行为 | `settings_app.cpp`、`config-sync.ts` | Tauri `load_preferences` / `save_preferences`，`PreferenceMonitor.cpp` 与 `main.cpp` 发布回调；macOS 云端桌面快照覆盖 Apple 20 项基线字段并保留客户端新增双拼预编辑字段 | 有调用链；逐字段核对默认值、冲突/损坏保护、当前组合期间延迟生效。macOS 云端快照现补齐两套辅助码方案、候选学习和本地扩展模式；本地扩展的兼容布尔值应用为八个本地模式的全开/全关。原生备用语音现在读取并回写当前 provider 的 `asr_tokens` / `polish_tokens` 槽位，缺失槽位保留旧扁平字段兼容。不能因配置字段存在就标记功能接通。 |
| API 凭据测试 | `settings_app.cpp::apiCredentialTest` → `ApiCredentialTest::Run` | Tauri `test_api_credential` → `client-core::credential_*`（Windows/macOS） | 有调用链；Windows 已接入聊天、批量 ASR、豆包 WebSocket、腾讯云/NiuTrans/DeepLX 等共享凭据测试。仍需逐项核对来源字段与真实服务行为。 |
| 词库查询、增改删、导入导出、快捷短语 | `dictionary_manager.cpp`、设置 `dict.ts` / `tools-settings.ts` | Tauri `dictionary_request` / `dictionary_maintenance_handshake`，共享 `dictionary_access.rs` / `dictionary_import.rs` | 有调用链；验证 quiesce/resume、失败恢复、五笔/英文/快捷短语/翻译各表的字段和导出编码，保留用户数据。 |
| 语音热键、流式/批量 ASR、润色、声音/静音、上屏方式 | `server/src/voice-input/`、设置 `voice.ts` | `main.cpp` → `VoiceHotkeyController` / `VoiceInputSession` → Engine 语音模块与 TSF；`VoiceSessionEpoch.h` | Windows Tauri 语音面板与 `recognize_voice` 已接入；全提供方、取消及焦点行为仍需 Windows 原生验证。macOS 原生备用窗口已将有效非云快照字段回写共享 `voice_input`，并可编辑 ASR/润色 provider token 槽位，但真实系统链路仍需验证。 |
| 录音设备选择 | 需继续比对来源具体支持范围，不假定来源已支持 | Tauri `list_voice_capture_devices` → `host-macos::voice_capture_devices` → `MSIMEListVoiceCaptureDevices` 与共享 `capture_device/capture_backend`；Windows `VoiceInputConfig` / `VoiceInputSession` | Windows 已按稳定设备 ID 完成枚举、偏好保存和 `AudioCapture::start(..., device_id)` 透传，并有 `voice_capture_selection` 覆盖 backend/device 选择；macOS Tauri 与原生备用设置现在共用 CoreAudio 输入流枚举、默认设备排序和稳定 UID，且只接受空值、`auto`、`macos` 进入 CoreAudio，拒绝把其他平台后端静默重解释为 CoreAudio。真实硬件权限、安装后切换及来源设备标识范围仍待产品级验证。 |
| 手写 | 来源设置 `handwriting-settings.ts` 和模型资源 | `ShellSurfaces.h` / `main.cpp` → Tauri `recognize_handwriting` / `submit_handwriting_candidate`，共享 `panels.tsx` | 有目的地入口；比较模型打包、笔画缩放、撤销/清空、多候选及原编辑器上屏。 |
 | 屏幕键盘 | 来源设置 `screenkb-settings.ts` | `main.cpp` → Tauri keyboard route、`desktop-keyboard.tsx`、Windows `send_key` 分支；macOS Tauri 与原生备用键盘都在每次按键时读取当前前台编辑器，并在实际投递前重新校验身份；无 Accessibility 权限时只拒绝投递、不弹权限请求；Tauri 面板仍捕获 PID+启动时间用于生命周期恢复 | macOS 键盘路径不再把当前设置宿主误当成输入目标，也不会在用户切换编辑器后继续投递到旧窗口；共享 Tauri 面板与原生备用面板的普通键均按 450ms 首次延迟、75ms 间隔自动重复，粘滞修饰键与 Num Lock 保持单次切换且键盘/辅助功能激活仍为单次发送；投递失败、失焦或关闭会停止重复且不自动重放；macOS Tauri 首次显示和隐藏后重开时按当前/主显示器的物理工作区底部居中，兼容负坐标、多显示器和 Retina 缩放。布局、修饰键按下/释放语义及真实焦点恢复仍需逐项核对。 |
| Emoji、颜文字、符号、剪贴板历史 | README 与来源 `clipboard_history.cpp` | `ClipboardMonitor.cpp` / `ClipboardHistory.cpp`、Tauri `load_emoji_catalog` / `paste_clipboard_text`、共享 `panels.tsx` | macOS 常驻输入源与 Tauri 监视器现按 NSPasteboard `changeCount` 读取外部文本变化，共用 4000 UTF-16 单位、12000 UTF-8 字节边界，并复用共享 50 条历史、去重/置顶和开关清理；关闭历史时不读取剪贴板内容。Emoji 面板通过已认证的一次性桌面输入会话把记录定向提交回原应用，普通 Emoji 候选与剪贴板大文本使用独立校验模式。仍需核对安装后真实持续监视与目标窗口行为，不能以普通 SendInput 冒充会话定向提交。 |
| 悬浮工具栏、托盘菜单、入口快捷键 | 来源 `window/*presenter*`、`ui-html/webview2/ftb` / `menu` | `FloatingToolbarWindow.cpp`、`TrayMenuWindow.cpp`、`MaintenanceHotkey.cpp`、`ShellSurfaces.h` / `ShellLauncher.cpp` | 有调用链；设置/手写/键盘/语音/云剪贴板/云词库等启动共享 Tauri，低延迟不抢焦点宿主保留原生。macOS 与 Tauri 预览现消费 `floating_toolbar.english_mode` 及其余组件开关，原生共享偏好合并也保留该字段并按可见组件重算宽度；来源和目标菜单项、禁用条件仍需逐项比对。 |
| 皮肤、主题、字体、外观预览 | 来源 `appearance.ts` / `skin.ts`、`candwnd/skins` | 共享 `packages/ui/src/upstream/`、`skin_catalog.rs`、`CandidateSkin.h`、`CandidateWindow.cpp` | Windows 已消费候选字体/回退字体、主题颜色、横竖排布局和阴影字段；`candidate_font_reload`、`candidate_palette` 与 shadow 回归覆盖非法值回退。仍需逐主题运行时截图、外部资源和字体回退逐项比较。 |
| 更新、关于、帮助、反馈、重启 | 来源 `about-settings.ts` / `feedback-settings.ts` / `update-manifest.ts`，`restartServer` | 共享 `update-manifest.ts` / `index.tsx`，Tauri `open_external_url` / `restart_input_method` | Windows 重启使用固定 UTF-16LE `RestartServer` Aux payload 并有回归覆盖；更新 manifest/release 链接要求干净 HTTPS，外链 opener 拒绝无主机与 shell 字符。安装包信任、来源、失败反馈及原生安装仍待逐项对照。 |
| 服务守护、安装、升级、卸载、资源打包 | 来源 README 服务守护、`installer/`、构建脚本 | `platforms/windows/installer/`、`tests/runner_regression.ps1`、TSF 注册代码 | 安装入口已限制为文件名安全的数字版本并保留现有包清单/用户数据保护回归；仍待 Windows PowerShell、TSF 注册、重启恢复、升级保留数据和卸载清理的产品级验证。 |

共享账号、社区、统计、云词库等已有成果继续保留；不能用它们抵消上表来源功能缺口。是否属于固定 Windows 基线及字段级等价，须另外找来源运行时证据，不能只根据目标页面名称推断。

## 下一批实施顺序

增量记录（2026-09-20）：重新核对来源默认分支 `e1d53dd8f01fd351633f08374f189157f5cb47e9` 与目标 `origin/develop` `71008a3f9c905e7bc880d83f97e4a0d46d623ab5`。来源最新 Windows 切片中的 Ctrl+左右分词移动、`yo` 完整双拼音节、正反双辅助码缓存隔离、候选 Ctrl+Enter 译文提交和自定义数据目录均已在目标找到对应实现；其中 Engine 行为由锁定归档 `0531d4211ab17d3ba43dc8ef86c05ec574b02fa8` 加本地兼容 overlay 重建。重新运行 `python3 scripts/fetch_engine.py` 成功，并确认 overlay 生成 `double_helpcode_cache_key` 与动态候选按当前双辅助码键写入；这只是源码/构建证据，仍不替代 Windows 原生编辑器验证。

增量记录（2026-09-19）：逐键比较来源 `installer/default_config/config.default.toml` 与目标 `platforms/windows/installer/config.default.toml`，来源默认配置键在目标均有对应项；目标新增的 Windows 适配项（候选滚轮、Windows 混输最小前缀、字体回退、智能标点细分、模糊音/自动纠错拆分、提供方鉴权模式）均保留为显式字段，没有通过静默别名丢失。该项只证明配置契约覆盖，不替代运行时热更新和真实设置窗口验证。

增量记录（2026-09-20）：对照来源 `a898c3b1` / `e6419573` / `25769868` 与目标 `d50c30ad`，Windows Ctrl+Enter 译文提交已覆盖单条和多条释义；多条释义进入独立副候选页，候选导航键保持该页，空格/数字键精确上屏。已选分词后的 Ctrl+Backspace 现在保存宿主前缀与被消费的原始拼音；剩余拼音删空后再次按键会通过受限 ServerSession 字符重放恢复原始分词。原生 TSF 仍保留自身 CompositionRestore / creating-word history 边界，公共层没有接管 TSF 状态。该切片通过 x86/x64 MinGW 语法交叉编译、Rust workspace 检查、差异检查和本地 push hook；未执行 Windows 原生安装、TSF 注册或真实编辑器交互。

增量记录（2026-09-18）：Windows 屏幕键盘及其他非激活面板现在按前台编辑器所在显示器的物理工作区定位；`MonitorFromWindow`/`GetMonitorInfoW` 处理多显示器、任务栏避让和负坐标，查询失败时回退系统工作区。该切片已通过 x86_64 与 i686 MinGW 交叉检查、Rust 格式检查和差异空白检查；未执行 Windows 原生安装及真实编辑器交互验证。

增量记录（2026-09-19）：Linux IBus 候选操作菜单新增上一页/下一页动作；动作复用 `MSIME_PREVIOUS_PAGE` / `MSIME_NEXT_PAGE`，并沿用已渲染候选页的会话、代次栅栏，避免面板滞后时翻动更新后的 Engine 视图。新增 IBus smoke 覆盖翻页与回退；当前 macOS 环境缺少 IBus 开发包，未执行原生 Linux 面板构建或真实桌面交互验证。

增量记录（2026-09-19）：Linux 新增 IBus/Fcitx5 共用的候选译义拆分策略，兼容 Windows 词典使用的 ASCII 与全角分号，并过滤空译义、修剪外围空白；IBus 与 Fcitx5 的 Ctrl+Enter 现在对多译义显示各自平台的临时副候选页，选择后直接上屏并恢复 Engine 组合，单译义仍直接提交。纯策略和 IBus 合成 smoke 已覆盖；Fcitx5 原生构建仍需 Linux 开发环境验证。

增量记录（2026-09-19）：Fcitx5 临时译义页的分页回调现在同时校验候选页创建时的 session/generation；面板重绘后迟到的上一页/下一页事件会被丢弃，不会翻动新的 Engine 视图或新的译义 overlay。该切片通过 Rust 格式、差异空白和 `scripts/verify-local.sh --quick`；当前 macOS 环境仍未执行 Fcitx5 原生构建与桌面交互验证。

增量记录（2026-09-19）：Fcitx5 临时译义页的键盘导航补齐小键盘上下键与 PageUp/PageDown，和普通候选页及 IBus 的导航语义保持一致；翻页仍由本地译义分页状态处理，不把事件交给 Engine。

增量记录（2026-09-19）：Fcitx5 现消费共享 `tsf_preedit_style` 与 `candidate_preedit_style`：支持 raw/pinyin/empty 预编辑显示，并在候选辅助文本中按配置附加当前拼音预编辑；行为与 IBus 的共享配置语义一致。验证通过 Rust 格式、差异空白和 quick 本地检查；Fcitx5 原生 Linux 构建仍待相应开发环境。

增量记录（2026-09-19）：Fcitx5 状态菜单新增“双拼原始预编辑”和“五笔剩余编码”开关，仅在对应输入方案下启用，并通过共享偏好更新路径持久化；这补齐了 IBus 已有的方案特定展示设置。原生 Fcitx5 构建与真实菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 addon contract smoke 现在检查预编辑样式和方案特定显示动作的源码契约，并修正测试根目录解析，确保该检查可从仓库任意工作目录执行；这仍是静态契约验证，不替代原生 Fcitx5 构建或桌面交互。

增量记录（2026-09-19）：Fcitx5 状态栏新增按输入上下文循环切换全拼、双拼、五笔和日文方案的入口。切换前结束当前组合，保存共享 `scheme` 偏好，并用上下文级 override 重建 Host API session；方案 override 不写入其他输入上下文。已通过契约 smoke、Rust 格式、差异空白和 quick 检查；原生 Fcitx5 菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 双拼状态栏入口现在按 `xiaohe`、`ziranma`、`shoudao`、`microsoft` 循环切换 profile；仅在双拼方案下生效，结束组合后用上下文级 profile override 重建 session，并保存共享 `shuangpin_profile` 偏好。原生 Fcitx5 菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 状态栏新增词频模式循环入口，按禁用、固定、减半、线性、提升顺序切换；通过共享偏好快照即时更新当前 Engine，并异步持久化 `frequency.mode`。触发次数和线性步长仍沿用 Tauri/IBus 设置路径，原生 Fcitx5 菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 进一步新增词频触发次数和线性调整步长入口，各自在 1–10 范围循环，使用共享偏好快照更新当前 Engine，并持久化 `frequency.trigger_count` / `frequency.linear_step`。原生 Fcitx5 菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 状态栏新增候选主题循环入口，按跟随系统、浅色、深色切换并即时更新共享 `candidate_theme` 偏好。主题边框、圆角和面板配色仍由 Fcitx5/桌面 panel 决定，不伪造 IBus 或 Windows 原生窗口的不可表达装饰；原生菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 辅助码状态栏入口现在按蓝天、自然码、搜狗 2.0、搜狗 Plus、小鹤循环选择，分别作用于全拼/双拼对应的 helpcode 配置；切换前结束组合并用上下文级 override 重建 session，同时持久化共享 schema。原生菜单交互仍待 Linux 环境验证。

增量记录（2026-09-18）：Windows Tauri 语音取消命令现在按 `request_id` 从共享会话表退休对应会话；重复或未知请求保持幂等，不再让已取消的会话继续占用后续录音/识别生命周期。该修复已合入 `develop`（`e61f67bc`）；仍需 Windows 原生麦克风、取消竞态和真实编辑器上屏验证。

增量记录（2026-09-18）：Windows Tauri Emoji/剪贴板提交在真正写入前重新捕获当前外部前台窗口；识别或面板停留期间切换编辑器时，不再把文本粘贴到打开面板时的旧目标。面板自身仍在前台时保留原目标；仍需 Windows 原生剪贴板、Emoji 面板和真实编辑器验证。

增量记录（2026-09-18）：Windows 候选翻译 worker 现在在偏好热更新后没有可用翻译请求时，异步清空正/负缓存并推进请求序列；进行中的结果会被视为过期，重新启用翻译或切换提供方不会被旧的负缓存阻塞。目标 C++ 代码已通过格式与差异检查；完整 Windows 原生 provider/编辑器交互仍待验证。

增量记录（2026-09-19）：Linux IBus 与 Fcitx5 现接入 Windows 候选翻译快捷语义。候选页存在有效高亮译文时，Ctrl+Enter 提交当前已渲染译文并结束 Engine 组合；没有译文时仍将组合交给应用。IBus 通过 session/generation 与最近渲染候选身份校验，Fcitx5 使用其原生候选页的同一份共享 View；两者不伪造 Windows 的多译义副候选窗口。Linux 两个宿主同时接入 Ctrl+Backspace、Ctrl+Left、Ctrl+Right 的共享分段编辑命令。合成 provider/Engine bridge 回归已通过，原生 IBus/Fcitx5 桌面验证仍需 Linux 环境执行。

增量记录（目标基线之后）：Windows `ai.assistant` / `voice.polish` 已从共享设置按钮接到 Tauri `test_api_credential` 的 Windows 分支及 `client-core::credential_test`。共享实现注入传输，生产 HTTPS 请求禁用重定向，5 秒连接/15 秒总时限、256 KiB 响应上限，公开错误不携带响应原文。Linux provider 路径保持不变。ASR（OpenAI、SiliconFlow、Groq、Doubao、system）与三类翻译凭据测试现均经过 Tauri 命令路由，桌面命令回归覆盖无凭据分类；合成请求测试和共享模块 Windows 交叉检查不能替代 Windows 原生设置窗口或真实服务验证。上表的明确缺口描述保留为固定目标提交时的状态。

Linux 在线 provider 的 AI 凭据测试与 Windows 终态契约对齐：只有响应中的 `choices` 为非空数组才报告连接成功；空数组、错误对象或无模型回答的 JSON 会判定失败。回归使用合成响应，不记录真实 token、提示词或服务端正文；该增量只收紧 Linux 凭据探测，不改变在线候选解析路径。

本次 macOS 增量：原生输入控制器现在按与 Tauri/Unix 宿主相同的优先级读取 `MSIME_CLIENT_HOST_OPTIONS` 指向的运行时配置（无该变量时读取 bundle/AppSupport 的 `runtime-options.json`）中的绝对 `voice_provider_socket`，再回退到 `MSIME_VOICE_PROVIDER_SOCKET`；只有路径存在时才把语音交给共享 Tauri provider，避免配置字段已保存但 macOS 错误回退到本地 Speech/Doubao。新增纯合成路径回归覆盖配置优先级、环境回退、相对路径和不存在路径拒绝；没有改变原生 Speech/HTTP/Doubao 的提交所有权。

1. **API 凭据测试真实接入**：来源已有独立设置任务队列；目标先复核可共享的提供方测试实现，补 Windows 路径和失败分类。测试只用合成凭据与本地模拟传输，不把真实凭据写入日志。
2. **Tauri 语音运行链**：明确控制器与输入目标是两个身份。OS 对端认证、有限消息/队列/关闭时限、request ID 与代际、事件与最终结果都必须连起来。Tauri 面板收结果后提交和原生直接提交只能有一个最终提交所有者，防止双重上屏。
3. **字段级配置与设备选择**：从来源 `ime_config.h` / `ime_config.cpp`、设置模块逐字段映射到共享偏好，再确认每个字段的原生消费者；设备选择单独验证稳定 ID 和实际采集。
4. **输入与面板产品行为**：按上表方案、在线候选、翻译、词库、面板、外观、服务/安装分组补差异与本地回归，每组及时合并。不因缺少一种验证环境而停止可执行的实现工作，也不声称未执行的原生验证通过。

## 语音传输必须保留的边界

剪贴板长度增量（2026-09-18）：固定来源 `MSIME-Windows` 远端默认分支 `develop` 的 `734b11e3b20c3ce44e5e96b877b37d6ed878c0a4`，`ClipboardHistory::kMaxChars` 为 4000 UTF-16 单位。Windows Tauri 粘贴宿主现使用共享历史的 12000 UTF-8 字节上限，不再误用普通输入的 4096 字节上限，避免完整中文历史记录可保存却无法粘贴。语音包装函数仍保留 4096 字节限制；空串、NUL 和超限均在系统操作前拒绝。跨宿主纯策略测试覆盖 4000 个合成汉字、补充平面字符与边界，Windows 条件编译交叉检查覆盖真实调用；未据此宣称完成 Windows 实机剪贴板验证。

翻译凭据测试增量：Windows 腾讯云、NiuTrans、自定义 DeepLX 测试现由 Tauri 调用 `client-core::credential_translation`，复用共享签名及解析。腾讯设置按钮传递当前编辑的 SecretId/SecretKey/地域；Linux 的 provider 请求保持原样。测试要求真实译文字段，不把任意 HTTP 2xx 当作成功；返回结果不包含服务端原文。自定义服务保留 HTTP/HTTPS 支持，禁止重定向。此项不改变固定基线记录，也不代表真实服务或 Windows 原生窗口验证完成。

- hello 中的 `client_id` 不是认证；控制器进程不能复用 TSF 目标进程 ID。必须由 OS 对端信息验证控制器，再单独绑定目标焦点租约。
- `PipeRegistry` 注册代际不等于激活 epoch。排队前检查还不够，执行时仍需检查焦点、会话及代际。
- 不能把未握手的 Aux 通道当成可接收凭据、识别文本的认证语音通道。
- `VoiceControlMessage` codec、来源仓库的派发包装、端点常量或 Engine 锁定归档更新都不是目标监听器、Tauri 客户端与流式结果已经接通的证据。
- #2228 / #2230 修复的是已有原生语音失败提示与旧完成回调隔离，不证明 Tauri 语音功能完成，也不证明 SendInput 回退焦点安全。

## 验证入口与本次限制

豆包凭据测试增量（来源仍为 `30a22e6f3d47adf783e8f038b1dafbd71edbb4f1`，本次目标起点 `91c5dc8b`）：Windows 设置已通过 Tauri 接到共享 `credential_doubao`，提供新版 API Key 与旧版 App ID/Access Token 的互斥认证头；新版忽略残留 App ID。传输接口可注入，生产 WSS 不跟随重定向，连接阶段 5 秒、总时限 15 秒，消息/累计响应 1 MiB、最多 64 条消息，解压复用有界共享解码器。只发送一秒合成 PCM 静音，要求有效终态 JSON，不返回服务端诊断或识别文本。内存 WebSocket、本地 TCP 重定向/超时和 UI 编辑值回归均使用合成数据；没有真实豆包凭据或原生 Windows 窗口验证。下段保留先前批量 ASR 增量时点记录；本项不补齐 Tauri 录音控制与最终上屏链。

批量 ASR 凭据测试增量：OpenAI、SiliconFlow、Groq 的 Windows 设置按钮现连接到 Tauri 和共享 `credential_asr`。请求使用内存生成的一秒 16 kHz 单声道 PCM16 静音 WAV，以 multipart 上传，不访问麦克风；界面提示可能计入服务用量。生产传输使用 HTTPS、禁止重定向、5 秒连接/15 秒请求时限及 256 KiB 响应上限。豆包需要独立 WebSocket 握手与最终协议响应，目前未借用批量入口，也未宣称豆包凭据测试或完整语音运行链已完成。

- 原生协议/会话：`platforms/windows/tests/runtime/pipe_io.cpp`、`platforms/windows/tests/runtime/server_smoke.cpp`、`platforms/windows/tests/runtime/session_pump.cpp`、`platforms/windows/tests/input/tsf_key_dispatch.cpp`。
- 配置/外观/启动：`preference_monitor.cpp`、`shared_config_keybindings.cpp`、`candidate_skin.cpp`、`shell_surfaces.cpp`。
- 语音：`voice_control_message.cpp`、`voice_providers.cpp`、`voice_session_epoch.cpp`；这些不覆盖 Tauri→Server→麦克风→ASR→编辑器全链。
- UI：`apps/desktop/src/credential-test.test.tsx`、`voice-recognition-client.test.ts`、`dictionary-safety.test.tsx`、`handwriting-pointer.test.tsx`。组件模拟测试不能证明 Windows 条件编译分支可用。
- 本次是源码对照与文档更新，不新增原生运行通过声明。GitNexus 索引已重建；概念查询遇到只读 FTS 错误，改为按固定提交文件与调用点核对。提交前仍运行 staged detect-changes。

后续修改本表时同时记录所用来源和目标提交。若来源默认分支变化，重新核对实际默认分支并固定对象；不静默把浮动 HEAD 的新功能算入旧基线已完成项。
