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
| 全拼、四种双拼、86 五笔、日语、辅助码 | README 对应指南、`engine/`、设置 `input.ts` / `helpcode.ts` | `crates/engine-bridge/`、`crates/input-runtime/`、`platforms/windows/src/ipc/SessionPump.cpp`、共享 `preferences.rs` | Windows 日语模式已将 `-` 交给长音符输入、禁止 `-`/`=` 翻页，并在 TSF/Server 两侧保持一致；候选选择现绑定会话、代次及单调窗口渲染 serial，等待上屏前的绘制回执可避免调频重排错选；macOS 原生候选面板现按共享 `wubi_code_hint` 显示严格前缀的剩余五笔编码，回退/本地模式保持不标注；各输入方案已用锁定词库逐项核对（`crates/engine-bridge/examples/schemes_dictionary.rs`，见第七批）；辅助码的单码调序与双码筛选已按来源规格逐条核对（第十五批）；日文与中文方案的往返保留由 `apps/desktop/tests/settings/settings.test.tsx` 跨三种中文方案覆盖；仍待真实编辑器交互验证。 |
| 候选分页、高亮、调频、preedit、以词定字 | README 候选调频/preedit/标点指南 | `CandidateWindow.cpp`、`CandidateAction.h`、`SessionController.cpp`、`ReplyCodec.cpp`；Linux `ClientEngine.cpp` | 有调用链；Linux IBus 候选操作菜单现提供上一页/下一页并复用共享分页命令，调频持久化已用锁定词库覆盖三个半边——跨会话记住、关掉就不写、重置回出厂顺序（`crates/engine-bridge/examples/learning_dictionary.rs`，见第八批）；翻页现在能越过 Engine 对单字母查询的初始上限（第九批）；以词定字已按两端取字、三字候选、组合被消耗、无汉字候选与越界索引覆盖（第十四批）；调频五种模式各走各的规则已逐条核对（第十三批）；仍需检查分页键与鼠标行为和旧候选请求拒绝。 |
| 中英文状态、独立英文候选、全半角、简繁、智能标点 | `server/src/english/`、设置 `input.ts` / `shortcut.ts` | `SharedConfigKeybindings.h`、`PunctuationPolicy.h`、`ReplyCodec.h` 中的 TsfLocalConfig、共享偏好与 Engine 桥接 | 已补齐 TSF client key-router 边界、IPC `Sent` / `DefinitelyNotSent` / `DeliveryAmbiguous` 三态 fallback、标点配置帧及宿主进程策略回归；仍需分别核对按应用/全局状态、CapsLock、标点重复、成对补全与热更新。 |
| K/T/U/E/M/J/Y/R 快捷模式、混输 | README 实用功能快捷模式 | Engine 桥接、共享偏好、`platforms/windows/src/ipc/ServerSession.cpp` 及 `platforms/windows/tests/runtime/session_smoke.cpp` | 已补带锁定词库的 ServerSession 回归：八种快捷模式均验证 Shift 入口、候选生成和选词提交；仍需 Windows 原生 TSF/真实编辑器交互验证。 |
| 谷歌云候选与 AI 联想 | README 云/AI 联想、设置 `ai-settings.ts` | `CloudCandidateWorker.cpp`、`AiCandidateWorker.cpp`，由 `SessionController.cpp` 构造并投递输入队列 | 有调用链；核对每个提供方、超时、取消、失焦后旧结果以及凭据路由，勿只验证 UI 保存。 |
| 候选中英释义、腾讯云翻译、自定义翻译 | README 候选翻译/自定义翻译 | `TranslationWorker.cpp` → `SessionController.cpp` → 候选展示；共享 `translation.rs` / `translation_store.rs` | 有调用链；仍需比较本地优先级、腾讯请求签名、词库编辑与缓存失效。 |
| 设置读取、保存、热更新与窗口行为 | `settings_app.cpp`、`config-sync.ts` | Tauri `load_preferences` / `save_preferences`，`PreferenceMonitor.cpp` 与 `main.cpp` 发布回调；macOS 云端桌面快照覆盖 Apple 20 项基线字段并保留客户端新增双拼预编辑字段 | 有调用链；逐字段核对默认值、冲突/损坏保护、当前组合期间延迟生效。macOS 云端快照现补齐两套辅助码方案、候选学习和本地扩展模式；本地扩展的兼容布尔值应用为八个本地模式的全开/全关。原生备用语音现在读取并回写当前 provider 的 `asr_tokens` / `polish_tokens` 槽位，缺失槽位保留旧扁平字段兼容。不能因配置字段存在就标记功能接通。 |
| API 凭据测试 | `settings_app.cpp::apiCredentialTest` → `ApiCredentialTest::Run` | Tauri `test_api_credential` → `client-core::credential_*`（Windows/macOS） | 有调用链；Windows 已接入聊天、批量 ASR、豆包 WebSocket、腾讯云/NiuTrans/DeepLX 等共享凭据测试。仍需逐项核对来源字段与真实服务行为。 |
| 词库查询、增改删、导入导出、快捷短语 | `dictionary_manager.cpp`、设置 `dict.ts` / `tools-settings.ts` | Tauri `dictionary_request` / `dictionary_maintenance_handshake`，共享 `dictionary/access.rs` / `dictionary/import.rs` | 有调用链；验证 quiesce/resume、失败恢复、五笔/英文/快捷短语/翻译各表的字段和导出编码，保留用户数据。 |
| 语音热键、流式/批量 ASR、润色、声音/静音、上屏方式 | `server/src/voice-input/`、设置 `voice.ts` | `main.cpp` → `VoiceHotkeyController` / `VoiceInputSession` → Engine 语音模块与 TSF；`VoiceSessionEpoch.h` | Windows Tauri 语音面板与 `recognize_voice` 已接入；全提供方、取消及焦点行为仍需 Windows 原生验证。macOS 原生备用窗口已将有效非云快照字段回写共享 `voice_input`，并可编辑 ASR/润色 provider token 槽位，但真实系统链路仍需验证。 |
| 录音设备选择 | 需继续比对来源具体支持范围，不假定来源已支持 | Tauri `list_voice_capture_devices` → `host-macos::voice_capture_devices` → `MSIMEListVoiceCaptureDevices` 与共享 `capture_device/capture_backend`；Windows `VoiceInputConfig` / `VoiceInputSession` | Windows 已按稳定设备 ID 完成枚举、偏好保存和 `AudioCapture::start(..., device_id)` 透传，并有 `voice_capture_selection` 覆盖 backend/device 选择；macOS Tauri 与原生备用设置现在共用 CoreAudio 输入流枚举、默认设备排序和稳定 UID，且只接受空值、`auto`、`macos` 进入 CoreAudio，拒绝把其他平台后端静默重解释为 CoreAudio。真实硬件权限、安装后切换及来源设备标识范围仍待产品级验证。 |
| 手写 | 来源设置 `handwriting-settings.ts` 和模型资源 | `ShellSurfaces.h` / `main.cpp` → Tauri `recognize_handwriting` / `submit_handwriting_candidate`，共享 `panels.tsx` | 有目的地入口；比较模型打包、笔画缩放、撤销/清空、多候选及原编辑器上屏。 |
 | 屏幕键盘 | 来源设置 `screenkb-settings.ts` | `main.cpp` → Tauri keyboard route、`desktop-keyboard.tsx`、Windows `send_key` 分支；macOS Tauri 与原生备用键盘都在每次按键时读取当前前台编辑器，并在实际投递前重新校验身份；无 Accessibility 权限时只拒绝投递、不弹权限请求；Tauri 面板仍捕获 PID+启动时间用于生命周期恢复 | macOS 键盘路径不再把当前设置宿主误当成输入目标，也不会在用户切换编辑器后继续投递到旧窗口；共享 Tauri 面板与原生备用面板的普通键均按 450ms 首次延迟、75ms 间隔自动重复，粘滞修饰键与 Num Lock 保持单次切换且键盘/辅助功能激活仍为单次发送；投递失败、失焦或关闭会停止重复且不自动重放；macOS Tauri 首次显示和隐藏后重开时按当前/主显示器的物理工作区底部居中，兼容负坐标、多显示器和 Retina 缩放。布局、修饰键按下/释放语义及真实焦点恢复仍需逐项核对。 |
| Emoji、颜文字、符号、剪贴板历史 | README 与来源 `clipboard_history.cpp` | `ClipboardMonitor.cpp` / `ClipboardHistory.cpp`、Tauri `load_emoji_catalog` / `paste_clipboard_text`、共享 `panels.tsx` | macOS 常驻输入源与 Tauri 监视器现按 NSPasteboard `changeCount` 读取外部文本变化，共用 4000 UTF-16 单位、12000 UTF-8 字节边界，并复用共享 50 条历史、去重/置顶和开关清理；关闭历史时不读取剪贴板内容。Emoji 面板通过已认证的一次性桌面输入会话把记录定向提交回原应用，普通 Emoji 候选与剪贴板大文本使用独立校验模式。仍需核对安装后真实持续监视与目标窗口行为，不能以普通 SendInput 冒充会话定向提交。 |
| 悬浮工具栏、托盘菜单、入口快捷键 | 来源 `window/*presenter*`、`ui-html/webview2/ftb` / `menu` | `FloatingToolbarWindow.cpp`、`TrayMenuWindow.cpp`、`MaintenanceHotkey.cpp`、`ShellSurfaces.h` / `ShellLauncher.cpp` | 有调用链；设置/手写/键盘/语音/云剪贴板/云词库等启动共享 Tauri，低延迟不抢焦点宿主保留原生。macOS 与 Tauri 预览现消费 `floating_toolbar.english_mode` 及其余组件开关，原生共享偏好合并也保留该字段并按可见组件重算宽度；来源和目标菜单项、禁用条件仍需逐项比对。 |
| 皮肤、主题、字体、外观预览 | 来源 `appearance.ts` / `skin.ts`、`candwnd/skins` | 共享 `packages/ui/src/upstream/`、`skin/catalog.rs`、`CandidateSkin.h`、`CandidateWindow.cpp` | Windows 已消费候选字体/回退字体、主题颜色、横竖排布局和阴影字段；`candidate_font_reload`、`candidate_palette` 与 shadow 回归覆盖非法值回退。仍需逐主题运行时截图、外部资源和字体回退逐项比较。 |
| 更新、关于、帮助、反馈、重启 | 来源 `about-settings.ts` / `feedback-settings.ts` / `update-manifest.ts`，`restartServer` | 共享 `update-manifest.ts` / `index.tsx`，Tauri `open_external_url` / `restart_input_method` | Windows 重启使用固定 UTF-16LE `RestartServer` Aux payload 并有回归覆盖；更新 manifest/release 链接要求干净 HTTPS，外链 opener 拒绝无主机与 shell 字符。安装包信任、来源、失败反馈及原生安装仍待逐项对照。 |
| 服务守护、安装、升级、卸载、资源打包 | 来源 README 服务守护、`installer/`、构建脚本 | `platforms/windows/installer/`、`tests/runner_regression.ps1`、TSF 注册代码 | 安装入口已限制为文件名安全的数字版本并保留现有包清单/用户数据保护回归；仍待 Windows PowerShell、TSF 注册、重启恢复、升级保留数据和卸载清理的产品级验证。 |

共享账号、社区、统计、云词库等已有成果继续保留；不能用它们抵消上表来源功能缺口。是否属于固定 Windows 基线及字段级等价，须另外找来源运行时证据，不能只根据目标页面名称推断。

增量记录（2026-09-20，Windows 本批六项）：来源固定为 `MSIME-Windows` 的 `e1d53dd8f01fd351633f08374f189157f5cb47e9`，目标起点 `origin/develop` `5097a1558f3fd9cdbf4345ffcb01b8318749edb7`。本批全部以 x86_64/i686 MinGW 交叉语法检查加 `scripts/verify-local.sh --quick` 验证，没有 Windows 主机，因此没有任何一项声称完成原生安装、TSF 注册或真实编辑器交互。

1. 语音条按它出现的那块显示器取 DPI（#3036）。`WaveOverlay` 按前台窗口所在显示器定位，却用自身窗口的 `GetDpiForWindow` 取缩放，而该窗口创建时没有 per-monitor 上下文——于是 DPI 恒为 96、收不到 `WM_DPICHANGED`，在缩放或副显示器上由合成器拉伸而非按真实尺寸绘制。现在 `wave_overlay_monitor_metrics` 在 per-monitor 线程上下文里一并返回该显示器的有效 DPI（`GetDpiForMonitor`，回退系统 DPI 再回退 96，不让 0 参与尺寸运算），定位与缩放取自同一份快照，并把新 DPI 推进渲染目标；覆盖 `WaveOverlayScale.h` 的纯回退测试。
2. msimeui 复用渲染目标时刷新 DPI（#3038）。`EnsureForWindow` / `EnsureForComposition` 的早退路径都不设 DPI，合成路径只要交换链够大就一直复用，旧缩放可以无限存活。同时补上上游的 `SetDpiOverride`（RDP 客户端缩放同步）。另修复 msimeui 测试套件：两次重命名把它的 runner 写成了服务端的 `main.cpp`，留下仓库之外的路径，CMake 无法解析，整套测试自 `046e0ead8` 起没有生成过目标、也就没有报告过。
3. 候选行改为逐项测量（#3039）。迁移来的 `CandidateList` 是定高行模型：超宽候选被裁剪而非换行，其后候选拿到被裁剪的矩形因而点击落点错误，长辅助码与译文无处安放，横排在 `Arrange` 收窄时无法回流，竖排在被最小宽度撑大的卡片里保持自然宽度，于是选中高亮与命中区域够不到行右缘。换成上游的测量几何，并带入其依赖的按外观字体与回退字体（`ApplyFontFallback`）以及 `Card` 的显式阴影 pass。补齐上游 7 个候选布局用例与 `test_font_fallback.cpp`。
4. 方向键折叠选区而不是跨过它（#3040）。msimeui 的 TSF 文本编辑器无条件推进光标，`ABCDE` 中选中 `BCD` 按右方向键落到 `E` 之后，比 Windows 其他文本框多走一个字符。补 `test_text_selection.cpp`。
5. 裸 Shift 中英切换在吞掉释放的宿主里恢复（#3045，来源 `08386814`）。裸 Shift 键盘钩子只在 `mintty.exe` 安装，而 Word 既不给 `OnTestKeyUp` 也不给 `OnKeyUp`，两条能排队切换的回调都不走，Shift 在 Word 里不切换中英文。改为对所有宿主安装：会送达释放的宿主不受影响，`_MarkBareShiftHandled()` 会闩住 key-event sink 已经切过的序号。成员随之改掉 mintty 专名，三条释放路径补 `[issue47]` 日志。
6. 重写标点前先核对它跟在什么后面（#3048）。空格转换与两秒内的撤回都只校验焦点会话、前台窗口和「光标前就是那个标点」，而同一个标点在文档里通常不止一处，窗口内移动光标又不是焦点变化：输入 `你好，世界，` 后点回前一个 `，` 再按空格，改的是错的那个。arm 时记下标点前面的字符，重写前回读两个字符核对指纹；文本存储读不出内容（终端与代理存储）和 arm 时没有记录（标点开在文档首）都判为匹配，否则会在这些宿主里直接废掉该功能。指纹判定是纯函数并带单测。

另核对两项不需要移植：来源 `f05507ad`（升级时配置解析失败被出厂模板覆盖、凭证清零）的根因在目标不存在——共享偏好用原子写入，解析失败返回错误而不是回落默认值后再写回；来源 `windows_ipc.h` 的 22/24/25 智能标点子开关 opcode 在目标由一帧打包的标点配置携带，是已记录的适配而非缺口。

增量记录（2026-09-20，Windows 第二批）：来源仍固定为 `e1d53dd8f01fd351633f08374f189157f5cb47e9`，目标起点 `414cdfbaf24bf3be8f22c581ca56c565a655e28f`。本批四项同样只有交叉编译与本地 quick 验证，没有 Windows 主机。

1. 候选皮肤预览阴影与原生候选窗对齐（#3051）。四套内置皮肤的 16 份候选窗 CSS 停在单层阴影，来源早已换成环境层加接触层两层，而目标原生 D2D 的透明留白（`CandidateShadow.h` 的 32/20/32/40）本来就是按两层算的——设置页预览里的阴影和用户真正看到的候选窗不是一个东西。按来源同步这 16 份 CSS；差异只有 box-shadow 与末行换行，候选窗 HTML 模板不动，目标在其中的脚本位置调整保留。
2. Unicode 模式数字键的真引擎回归（#3053）。打码位是数字键唯一「是输入而不是选词序号」的场合，判断分在两层：引擎报 handled，运行时只对引擎拒绝的数字才落到选词。input-runtime 的既有用例全用 fixture 引擎（对数字答 not handled），这个组合从来没被覆盖过，而会发现它的 windows-session 与 macOS local-mode-preferences 各自需要自己的主机。新用例用真引擎跑通 shift+U 再 4e2d，在锁定的 Engine 上通过——这与 `known-failures.txt` 里把两套失败都归因于该行为的记录相矛盾。两行都没有删：本机跑不了这两套，凭推断删基线会让基线失去意义；改为在两条记录上注明该引擎行为已不存在，下次在 Windows 或已配置的 macOS 上跑的人该去确认能不能删，而不是照抄重录。
3. 智能标点三个子开关补进共享偏好（#3054）。设置页有五个智能标点开关，Windows Server 也读全部五个，但 `Preferences` 只有前两个字段。结构体带 `deny_unknown_fields`，Tauri 的 `save_preferences` 又把前端对象直接反序列化成它，所以未知键不是被丢掉而是让整次保存失败——用户打开「中文标点后按空格转换」「数字后直出」「字母后直出」任一个，设置窗口就再也存不下任何东西。补齐三个字段，缺省为关（与 Windows 基线 `config.default.toml` 和来源把整族默认关掉一致）。顺带加 `scripts/test-preferences-field-parity.py` 并挂进 `--quick`（#3056），按名字配对 TS 类型与 Rust 结构体逐个比字段集，两个方向都查，Rust 独有的需在 `RUST_ONLY` 写明理由（当前只有 `ui_backend`）。另记一处本批未动的分歧：`smart_punctuation` 与 `smart_punctuation_repeat` 共享默认为开，而 Windows 基线两个都是关，来源也已改成整族默认关；Windows 运行时读的是共享偏好而非那份 TOML，所以实际默认与记录在案的基线相反。改这两个会同时影响 macOS、Linux 和移动端首次运行，留待单独决定。
4. 用户名带中文时清除学习数据不再走 ANSI 路径转换（#3059）。仓库窄字符串都是 UTF-8，`path::string()` 却按系统窄编码转换——Windows 上就是 ANSI 代码页，`C:\Users\陆傲天` 这类 profile 要么转错要么直接抛。`reset_learned_data` 有三处这样用，其中拼 SQLite `-wal` / `-shm` / `-journal` 那处在 try 块里且发生在新文件已就位之后：抛出会触发回滚并把已经成功的清除报成失败，转错则把 `-wal` 留在原地，用户刚清掉的学习数据下次打开又回来。改为在 path 自身 native 字符串上拼接，完全不过窄转换。既有用例现在在 ASCII 与 `陆傲天` 两种根目录下各跑一遍；另加 `scripts/test-windows-path-encoding.py` 挂进 `--quick`，禁止 Windows 会编译到的 C++ 出现 `path::string()`——这类问题在系统编码为 UTF-8 的机器上一点痕迹都没有，而跑该脚本的机器全都是，只能静态拦。

另核对确认无缺口：候选右键菜单（置顶 / 固定排位 1–5 / 取消固定 / 删除）与来源逐项一致；托盘菜单目标为超集（多手写识别板）；悬浮工具栏与菜单模板除目标特意调整的脚本位置外与来源一致；Windows Server 从共享偏好读取的 23 个键在 Rust 结构体中全部存在；Windows 侧 C++ 的宽窄转换全部走 `CP_UTF8`，文件打开一律传 `std::filesystem::path`。

增量记录（2026-09-20，Windows 第三批：把 Windows 编译门禁真正跑起来）：目标起点 `6caddd999e38b8fb973009f0b972f7f273bac454`。本批的起因是一个方法问题——此前每一批的验证都写着「按文件交叉语法检查加 quick」，而 `verify-local.sh` 的 native host 阶段只认 Windows 主机上的 `target/win-full`，于是它在每一台真正跑过本地验证的机器上都只打印 skipped。把 `platforms/windows/build-cross.sh x64` 跑起来之后，发现原生构建同时坏了六处：

- `tests/runtime/tsf_config_frames.cpp` 引 `windows_ipc.h` 的相对路径解析不到（它链接的 `msime-windows-replies` 本就把契约目录作为 PUBLIC include 暴露）；
- `ee02012d4` 把测试按职责分到子目录时，12 个 TSF 测试的相对 include 少了一级，这些目标全都配置不出来；
- `Watchdog.cpp` 在匿名命名空间里用未限定的 `watchdog_protocol::managed_argument`；
- `tests/ui/candidate_initialization.cpp` 的四层嵌套初始化器少两个右括号；
- 四个测试把 `tests/core/TestHostOptions.h` 当同目录头文件引；
- `server_smoke.cpp` 还在按三参数调用早已加了 `actions_available` / `fixed_position` 的 `CandidateFlyoutWindow::open`，`ServerResources.rc` 与 CMake `OBJECT_DEPENDS` 各指着一个不存在的 `ServerResources.h`（真头文件在 `src/ipc/`），后者直接让 make 报 "No rule to make target"。

修完之后（#3072）整套构建通过：host DLL、TSF DLL、Server、msimeui 与全部原生测试可执行文件都链接成功。

随后把这条路径接进门禁，免得再烂一次：宿主不是 Windows、但 MinGW 与已引导到清单基线的 vcpkg 都在时，native host 阶段走交叉构建（#3074）；vcpkg 的查找顺序补上主工作区，这样在本仓库惯用的短生命周期 worktree 里也能生效，引导一次整台机器就位（#3079）；pipe-only 配置同样改为交叉构建——它的注释写着「一个没人跑的配置就是会烂掉的配置」，而它自己也在每台非 Windows 机器上跳过，其实它连 vcpkg 都不需要（#3082）。三处都做了反向验证：故意插入失败的 `static_assert` 后阶段确实报错并失败。

顺带修掉一处候选窗绘制缺陷（#3076）：候选卡片宽度被工作区上限夹住，行文字用 `NO_WRAP` 且 `DrawText` 没传 `CLIP`，于是超过上限的候选（AI 联想、云候选，或候选后面再接 `"  · " + 译文`）会画过卡片右边缘、落在为阴影留的透明边距上，看起来像浮在窗口旁边的一段文字，而且点不到——命中测试用的正是同一个行矩形。传上 CLIP 让它截在行矩形处。上游对应路径是换行，但那要求行高可变，而这个渲染器的行高来自固定的 `candidate_row` 度量，属于另一回事。

本批限制：x86 在本机构建不了——这台的 MinGW 用 SJLJ 展开而 x86 Rust GNU 需要 DWARF，`build-cross.sh` 自己就会拒绝；32 位宿主进程要加载的 TSF DLL 因此仍未被任何门禁覆盖。测试是链接了但没有执行，本机没有 Windows，也没有装 Wine（那是对用户机器的系统级改动，且这些测试要建窗口、用 TSF COM 与 D2D，在 Wine 下本就不可信）。#3076 的实际绘制结果同样没有看到。

增量记录（2026-09-20，Windows 第四批：设置页逐项对照）：把来源十四个设置 partial 里的可见文案逐条与共享 Tauri 设置页比对，按「文案不同」与「功能缺失」分开判读。绝大多数是措辞差异（「乱序纠错」对「字母顺序错位」、「始终使用英文标点」对「标点锁定」、「按应用记忆/全局统一」对「中英文状态范围」等），逐项确认对应控件都在。

只查出一处真缺口并已补上（#3094）：豆包的整句流式与双向流式是同一模型的两个识别接口，差别只体现在 `asr_endpoint` 这串 URL 上。来源给的是带名字的下拉并写明取舍——整句流式边录边传、说完返回整句，服务方称准确率更高且推荐用于输入法；双向流式返回增量结果，流式预编辑刷新更频繁——而目标只有一个 url 输入框，等于要求用户背两串看不出区别的地址。在豆包 provider 下补同样的下拉，选中即写入下方地址；不新增偏好字段，这个选择本来就只是 `asr_endpoint` 的值。地址不属于两个预设时显示「自定义地址」，选它不做任何事。

同批核对确认无缺口的还有：五个语音快捷键开关、录音提示音与静音其他声音、豆包新旧鉴权与四个识别选项、候选翻译的三家 provider 凭据、辅助码双拼/全拼两套方案与候选窗显示、皮肤目录的打开与重新扫描、重启输入法入口、词库按类型导出、候选调频五种模式与 1~10 的触发次数与线性步长（来源 README 写的「1～6」与它自己的默认配置不一致，以配置为准）。另外「界面渲染」这一项来源有而目标没有，是已记录的有意取舍：目标只有 Direct2D 候选窗，没有可选项，`ui_backend` 作为配置契约保留并登记在字段漂移门禁的 `RUST_ONLY` 里。

增量记录（2026-09-20，Windows 第五批：跟进来源基线之后的新提交）：来源远端默认分支已推进到 `1e4c331d5a7d62b1f219fcc0979a89dd5ead7309`，比本表此前固定的 `e1d53dd8` 多出 18 个提交。逐个分类后，Windows 侧可移植的三项全部完成，其余为 Engine 与其打包，理由见末段。

1. 菜单项回调不再读已释放的闭包（#3097，来源 `3135af32`）。`MenuFlyoutItem::OnMouseUp` 直接调 `onClick_()`，而候选右键菜单每个动作都是「先关菜单再投递消息」：关菜单同步放掉该菜单项的最后一个引用，正在执行的 `std::function` 于是在自己的 `operator()` 还在栈上时被销毁——小闭包按 small-object optimization 就住在那个堆块里，随后的窗口重排同步派发 WM_SIZE/WM_PAINT 触发重新分配把它回收。来源在自己的 D2D 候选框上复现为右键删除候选必定 0xC0000005。改法是调用前把 handler 拷到栈上；`Button::OnClick` 同形状一并改。回归不去捕捉内存破坏（能否复现取决于分配器与编译器是否重新加载捕获，读已释放内存本身也是未定义行为），改为断言 handler 在自己 `operator()` 期间始终存活。同类扫描到本仓库的 `CandidateFlyoutWindow::choose` 也是「hide() 后调 chosen_()」，但那里 `chosen_` 是 flyout 自己的成员、`hide()` 不销毁 flyout，所有权不同，未改。
2. 终端里改写不了的标点改走输入队列（#3099，来源 `1640cb35`）。「中文标点后按空格转英文」与两秒内同键撤回都是编辑会话里的 `ITfRange::SetText` 就地改写，而终端类宿主的 TSF 上下文只是代理、不保存已上屏文字，会照单全收 ShiftStart 与 SetText 并报告成功，屏幕上什么都没变。判据不看进程名，看改写前能不能把待改写字符读回来；读不回就改走本仓库早已有的 SendInput 改写队列（执行前校验焦点 token、前台窗口与期限，合成事件带自生成标记）。期限单列常量 500ms，因为它约束的是消息投递而非用户按键窗口。注意来源那次回归本仓库没有：来源在 #413 里把 SendInput 整个换掉了，而这边「数字/字母后直出再按同键」一直走 SendInput，缺的只是按空格转换与其撤回在终端下的兜底。
3. 安装前检查 WebView2 与 VC 运行库（#3100，来源 `1ac904da`）。两者都不随包分发，缺任一装完即坏且故障现场在安装结束之后。`InitializeSetup` 在第一屏之前查注册表（不做文件探测：Setup.exe 是 32 位进程，`FileExists` 会被 WOW64 重定向，只装 x64 redist 的机器会被误判），VC 要求 14.20 以上而非只看 `Installed=1`，静默安装默认继续并把缺失写进日志。文案按本产品改过：这边候选窗是 Direct2D 绘制、不受 WebView2 影响，受影响的是设置窗口与表情 / 手写 / 屏幕键盘 / 语音面板——照抄来源的「候选窗口打不开」会是错的。新增 `scripts/test-installer-prerequisites.py` 挂进 `--quick` 钉住上述判据；Inno 的 Pascal Script 在非 Windows 机器上无从编译，该脚本不替代 Windows 上的编译与交互验证。

其余 15 个提交不移植，理由记下以免下次重新判断：`ccbaa3a6`（Google 解码器前把 ü 换成 nue/lue/ju 写法）、`80b1fc42` / `03a5b4fe` / `e2a5f5f9`（词格整句改用 kenlm 三元模型并重排优先级）、`01c5bca3` / `663f7230`（选中的整句候选落成用户词组）、`b4728fdb` 都在 Engine 及其 Server 消费侧。来源把 Engine 以 `engine/` 在树内维护，本仓库由 `engine-lock.json` 固定独立 `MSIME-Engine` 归档加本地 overlay 获取，两条路径不同：这些行为要进来只能是提 Engine 锁，而不是照抄 C++。本批没有提锁——提锁的影响面覆盖全部平台，且整句重排在本仓库正由 Rust 侧的 `chinese-ime-lm` 另行推进（见 #3088），两边同时动同一块行为会互相盖掉。`d30d2946` / `bc1a1c7a` 是给上述 Engine 产物打包（sc.lm、Google 解码器系统词典），随锁一起考虑。另外尝试用 engine-bridge 的真引擎直接判定 ü 拼写在本仓库是否同样出错，未能得出结论：该测试装置用的是空词库临时目录，`qu`、`xu` 这类无 ü 的音节同样出不了候选，要判定必须带真实系统词典，属于提锁时一并验证的范围。

## HarmonyOS 逐条对照（2026-09-20）

来源为本地 `MSIME-Windows` 检出 `997fdfd9` 的 `README.md`「功能简介」与「核心功能指南」，逐条列出目的地实现位置与验证方式。列这张表是为了让"覆盖完整"成为可核对的断言而不是结论：任何一行填不出目的地，就是一个缺口。

| 来源功能 | Harmony 实现位置 | 验证 |
| --- | --- | --- |
| 全拼、四种双拼、86 五笔 | `keyboard/KeyboardScheme.ts`；Engine 经共享 `prepare_host_configuration` | 逻辑回归；设备上 Engine 会话建立 |
| 日文罗马字、平假名/片假名、日语词库 | `input/JapaneseNineKeyLayout.ts`、`input/JapaneseVariantPolicy.ts` | 逻辑回归 |
| 切日文保留中文方案 | `KeyboardScheme.mapping` + `KeyboardSession.schemeChanges` | 逻辑回归 |
| 五种辅助码方案、单码/双码 | `input/ChineseHelpcodePolicy.ts`；Engine 侧 `quanpin_helpcode`/`shuangpin_helpcode`；设置页辅助码分页 | 逻辑回归 + UI 回归 |
| 谷歌云候选、AI 联想（四提供方） | `candidate/OnlineCandidatePolicy.ts`；NAPI `onlineQuery`/`applyOnlineCandidates` | 逻辑回归 |
| 候选中英互译、腾讯 TMT / NiuTrans / DeepLX | `candidate/TranslationPolicy.ts`、`CredentialCrypto.ets` | 逻辑回归 |
| 自定义候选窗翻译（覆盖层） | 设置页写 `<state>/user/custom_translations.txt`；Engine `prepare_translation_sidecar` 读取 | 解析规则逐条对齐 C++ 并有测试 |
| 候选调频（五种算法、触发次数、步长） | Engine 侧 `frequency`，设置页无平台门 | 共享偏好契约 |
| 候选窗右键菜单（删除候选等） | `input/CandidateContextMenuPolicy.ts` + `KeyboardView.onMouse`；触屏长按保持不变 | 逻辑回归；2in1 鼠标未在设备上点 |
| 候选序号字号 | `candidate/CandidateNumberFontPolicy.ts`（上游 `.num { font-size: 0.8em }`） | 逻辑回归 |
| preedit 光标（分词编辑可见） | `candidate/PreeditCaretPolicy.ts`（上游 `.cursor`）；共享视图 `caret_position` | 逻辑回归；2in1 分词键未在设备上按 |
| 候选释义外观 | `candidate/CandidateTranslationStyle.ts`（上游竖排 `.cand-translation`） | 逻辑回归 |
| preedit 显示、双拼原始预编辑 | `candidate_preedit_style`；`shuangpin_preedit` 能力位 | 逻辑回归 + 能力位测试 |
| 中英混输、emoji/颜文字混输、独立英文候选 | Engine 侧 `mixed_input`；`dedicated_english` | 共享偏好契约 |
| 直接英文补全 | `input/EnglishSuggestionPolicy.ts`；NAPI `englishCompletions` | 逻辑回归 |
| 智能标点、重复转中文、空格转 ASCII、成对补全、以词定字 | `input/SmartPunctuation*.ts`、`PairedPunctuationPolicy.ts`、`CandidateTextPolicy.ts` | 逻辑回归 |
| 中文标点直输（`\`→、 `` ` ``→· `$`→￥ `^`→…… `_`→——） | Engine 侧 `input_session.cpp`；硬件键经 `isAsciiPunctuation` 全部送达 | 硬件键全覆盖；触摸键盘见下 |
| 中英文状态按应用/全局记忆 | `input/ImeModeScopePolicy.ts` | 逻辑回归 |
| 全半角、简繁 | `input/FullWidthInputPolicy.ts`、`input/ChineseOutputPolicy.ts` | 逻辑回归 |
| 八个快捷模式 K/T/U/E/M/J/Y/R | Engine 侧 `local_modes`；`input/LocalInputMode.ts` | 共享偏好契约 |
| 词库查询/增改删/导入导出、快捷短语 | `DictionaryMaintenancePolicy.ts`；共享 `dictionary_request` | 逻辑回归 |
| 语音：豆包流式、三家批量、润色 | `input/Harmony*Recognizer.ets`、`HarmonyVoicePolisher.ets` | 构建；provider 未在设备上跑 |
| 语音五个快捷键、空格锁定 | `input/VoiceHotkeyPolicy.ts` | 逻辑回归 |
| 录音提示音、录音时静音其他音频 | `input/HarmonyVoiceRecordingBehaviour.ets` + `VoiceRecordingBehaviourPolicy.ts` | 逻辑回归；音频未在设备上听 |
| 录音设备选择 | `input/VoiceCaptureDevicePolicy.ts`、`HarmonyVoiceCaptureDevices.ets` | 逻辑回归 |
| 手写识别 | `input/HandwritingStrokePolicy.ts` + Core Vision Kit；设置页手写分页有本宿主专属说明 | 逻辑回归 + UI 回归；识别本身未在设备上跑 |
| 软键盘组字（手机） | `KeyboardView` 触摸路径 → `KeyboardSession.press` → Engine | **设备上验证**：点 `N` 得到预编辑 `n` 与候选 `1 那` |
| 设置页在设备上渲染 | `pages/Settings.ets` WebView 加载共享 `SettingsPage` | **设备上验证**：2in1 上完整侧栏（含 #3165 解封的辅助码页）与候选窗预览 |
| 屏幕键盘 | 本宿主自身即键盘；2in1 另有 `DesktopSurface.SCREEN_KEYBOARD` | 设备上面板创建成功 |
| 悬浮工具栏、组件开关、缩放 | `FloatingToolbar.ets`、`FloatingToolbarLayout.ts` | 逻辑回归 |
| 悬浮工具栏缩放档位与图标字号 | `FloatingToolbarLayout.scale` / `.fontSize` | 与来源逐项一致，见下 |
| Emoji、颜文字、符号、剪贴板历史 | `emoji/EmojiCatalogModel.ts`、`clipboard/*` | 逻辑回归 |
| 四种皮肤、深浅色、字体 | `candidate/CandidateSkinPolicy.ts`、`skin/KeyboardSkin.ts` 的四套候选配色、`candidate/CandidateFontFamilyPolicy.ts` | 逻辑回归；配色取自上游 `packages/ui/src/upstream/candidate-themes/skins` |
| `Ctrl+Shift+E`、`Ctrl+Shift+Space`、`Ctrl+.` | `InputModeRouting.ts` | 逻辑回归；硬件键未在设备上按 |
| `Ctrl+Shift+Alt+1–8`、`+C`（数字键行与小键盘均可） | `HardwareKeyRouter.ts`、`KeyboardSession.resetCache` | 逻辑回归；同上 |
| `Ctrl+Shift+Super+K`（打开屏幕键盘） | `input/PanelShortcutPolicy.ts` → `DesktopSurface.SCREEN_KEYBOARD` | 逻辑回归；硬件键未在设备上按 |
| 外接键盘（手机/平板接蓝牙或 USB 键盘） | `input/HardwareKeyboardPolicy.ts`、`input/HarmonyHardwareKeyboards.ets` | 逻辑回归；热插拔未在设备上插拔 |
| 更新、关于、帮助、反馈 | 共享设置页 | 共享 UI |
| 设置页感知外部偏好变更 | `entryability` 的 `windowStageEvent` + `input/PreferenceRevisionPolicy.ts` | 逻辑回归；窗口切换未在设备上走 |
| 外部皮肤目录入口 | `pages/Settings.ets` 的 `importSkinFolder` + `skin/SkinImportPolicy.ts`；能力位 `skin_directory_import` 决定按钮文案 | 逻辑回归 + UI 回归；选择器未在设备上走 |
| 设置窗口本体 | `pages/Settings.ets` 的 WebView 加载 `apps/harmony` 构建的共享 `SettingsPage` | 构建产物防漂移校验（`scripts/test-harmony-settings-bundle.py`） |
| 设置窗口冷启动 | 共享 `SettingsStartupPage` | 逻辑回归；此前为纯白窗口最多 5 秒 |
| 开机引导（启用输入法、选为当前） | 共享 `WelcomeFlowPage` + `input/OnboardingStatePolicy.ts` | **设备上验证**：全新安装未启用时渲染「1/4 欢迎使用水杉」 |
| 服务守护、安装、卸载 | 不适用：扩展生命周期由系统管理 | — |
| `Ctrl+Shift+Alt+R`/`+T`（重启/退出服务） | 不适用：本宿主没有独立服务进程 | — |
| 用户词库日志回放（`MetasequoiaImeDictionaryReplay`） | 不适用：来源随安装包分发该 CLI 但设置界面不暴露它；HarmonyOS 应用无用户可调用的命令行，而在设置页加入口等于给本宿主一个来源没有的功能 | — |

三类条目没有目的地实现，都是平台差异而非缺口：Windows 的服务守护与服务重启/退出快捷键针对独立 Server 进程，HarmonyOS 的输入法扩展由系统拉起与回收；用户词库日志回放在来源也只是随包分发的命令行工具，设置界面并不暴露它。

按来源 `server/src/` 的 25 个实现目录逐个对照，只有上述三项没有目的地实现，其余全部映射到本宿主的具体文件。这是本仓库做过的最细一层功能清点——比 README 条目、能力位、偏好字段都更贴近实现。

2026-09-20 在 2in1 模拟器实例（`const.product.devicetype` = `2in1`、API 23、aarch64）上取得了硬件按键这一栏的设备证据，该栏此前长期记为"未验证"。逐项结果：

| 项目 | 设备证据 |
| --- | --- |
| 安装、启用、切为当前输入法 | `ime -e -f` 返回 `FULL_EXPERIENCE_MODE`，`ime -g` 返回本宿主 |
| 扩展启动链 | `module loaded` → `session 1 created` → `routing hardware keys: 0 device(s)` → `panel ready: 2in1, candidate window, with toolbar` |
| 接管真实编辑器 | 浏览器页内搜索框：`attached to editor: pattern=0 enter=3` |
| 硬件和弦 `Ctrl+Shift+E` | 工具栏在 `中` 与 `英` 之间往返切换，两个方向均生效 |
| 按键领取契约 | 中文模式下字母键被领取、不进编辑器；英文模式下同一键穿透到编辑器；退格两种模式下均放行 |
| `Ctrl+Shift+Super+K` 打开屏幕键盘 | 和弦按下后面板出现在窗口底部 |
| 悬浮工具栏渲染 | 屏幕右下角显示 `中 。 半 简 😊 ⚙` 并随模式更新 |

其中按键领取契约是关键判据：**同一个字母键在两种模式下行为相反**，这只有键真正进入本宿主的路由才可能发生。

同次运行暴露一个设备上才能观察到的缺陷，**尚未修复**：2in1 上字母被领进组合串后，预编辑与候选窗都不出现。已排除的原因有两项——`panel.show()` 本身可用（`Ctrl+Shift+Super+K` 能把面板显示出来），`onComposition` 回调确实在 `if (desktop)` 分支内被赋值。资源暂存也成立（`StagedResources.stage` 返回假时 `onCreate` 会提前返回，而日志显示 `session 1 created` 与 `panel ready` 都发生了）。症状收敛为：Engine 接受按键但不返回 editing text，因此 `composing()` 始终为假、`onComposition(true)` 从不触发。再往下定位需要带诊断日志的构建。

复现步骤：2in1 实例上安装并切为当前输入法 → 打开浏览器并点中页内搜索框（确认日志出现 `attached to editor`）→ 确认工具栏显示 `中` → `hdc shell uinput -K -d 2030 -i 50 -u 2030`。预期出现候选窗，实际字段与面板都无变化。

同一个 HAP 在 phone 实例上做对照，结论把范围切干净了：**Engine、词库与组字链路全部正常，坏的只是 2in1 的硬件键路径**。手机上点软键盘的 `N` 键，预编辑立刻显示 `n`、候选栏出现 `1 那`、回车键由"搜索"变为"选定"。两条路径最终调用的是同一个 `KeyboardSession.press()`，触摸路径能组字，硬件键路径不能。

同次还确认了资源与数据侧没有问题：`files/engine` 暂存 292 MB，`msime.db` 107 MB、`dict_japanese.dat` 66 MB、`english.db` 8.4 MB、`dict_pinyin.dat`、`others.db`、`sentence-model.safetensors` 均在位，`engine.ready` 标记按代次写入；设置页的词库查询在设备上执行成功（全新安装的用户词库为空属正常）。

带诊断日志的构建已在 2in1 上跑过，输出是：

```
composing key produced no composition: scheme=quanpin local=none english=false candidates=0
```

即宿主侧四项输入全部正确——方案是全拼、无本地模式、非英文、候选为零——`client.character` 确实被调用，Engine 收到合法字母后返回了空视图。排查因此越过了宿主侧：`press()` 的参数、方案、模式都不是原因。

余下的怀疑集中在 Engine 在该设备上打开词库的时机与结果：`prepare_host` 只校验文件存在与清单一致，真正打开 SQLite 是另一回事，而一次静默的打开失败会让此后每次查询都返回空，且不影响 `session created`。验证这一点需要 Engine 侧的日志，不是宿主侧能看到的。

那条诊断日志已经留在代码里（不记录按键字符，只记录宿主状态），因此这个失败此后不会再是静默的。

进一步的设备排查把范围又收窄了一大截。先前这里写作「硬件字母只在屏幕键盘界面打开时才能起一个新的组合串」，那句话把顺序读错了：那次实验里组合串是**触摸**起的，硬件键只是接着延长了它，界面开着是巧合而非条件。准确的表述是：**硬件字母能延长已有的组合串，但起不了新的组合串。** 三项互相印证的观察：

1. 同一台 2in1 上点屏幕键盘的 `N` 键，预编辑 `n` 与候选 `1 那 / 2 年 / 3 女 / 4 难 / 5 内 / 6 你` 正常出现——Engine 在该设备上没有问题，此前"手机能、2in1 不能"的说法同时换了设备与路径两个变量，不成立，已由这次同机对照取代。
2. 组合串建立后注入硬件字母 `I`，组合串延长为 `ni`、候选变为 `1 你 / 2 ni / 3 尼 / 4 妮 / 5 泥 / 6 逆`——硬件键路径本身是通的。
3. 组合串被取消、界面关闭后再注入同一个字母，诊断日志立即触发，组合串仍为空。

因此缺陷不在按键投递、不在 Engine（同一台设备上触摸能起组合串）、也不在宿主侧的方案与模式判断，而在"硬件键作为**首个**字母时未能让 Engine 起一个组合串"这一处。触摸与硬件两条路径调用的是同一个 `press()`、传入同样的参数，所以差别不在参数，而在两次调用时宿主自身的状态——那正是下一步要查的。

仍未取得设备证据的是：语音 provider 实际识别、手写实际识别。两者需要真实凭据与真实音频/笔迹。其余条目均有不依赖设备的回归覆盖。

候选皮肤一项此前只写「逻辑回归」，掩盖了一个外观缺陷：四个来源皮肤被近似映射到触摸键盘的调色板上，而 `wechat` 与 `willow_green` 都落在 `forest`，于是微信绿与杨柳青在 2in1 上完全同色——`#07c160` 和 `#58b980` 并不接近，四个皮肤实际只剩三个。不渲染上游 CSS 并不需要另造一套颜色：上游样式表就在本仓库 `packages/ui/src/upstream/candidate-themes/skins` 下，四套配色（明暗各一）现直接取自各自的样式表，由 ArkUI 原生绘制。触摸键盘的八个皮肤是另一项偏好，未改动，这四个也不进触摸皮肤选择器。

来源指南列出的五个中文标点直输映射（`\`→、、`` ` ``→·、`$`→￥、`^`→……、`_`→——）都在 Engine 侧的 `input_session.cpp` 里，本宿主调的是同一个 Engine，因此**硬件键路径全部具备**——`HardwareKeyRouter` 的 `isAsciiPunctuation` 覆盖 0x5b–0x60，这五个字符都落在其中。

触摸键盘则只覆盖其中三个。符号行是 `1234567890` / `,.?!;:'"@/` / `()[]<>\-_=`，所以 `\`（、）、`_`（——）、`<` `>`（《》）能点出来，而 **`^`（……）与 `$`（￥）不在行内**；符号面板是数据驱动的 `symbol_catalog`，其中有单个的 `·` `—` `…`，没有中文排版用的双字形 `……` `——`，也没有 `、￥《》`。因此在手机形态下，省略号与人民币号无法通过点按输入，间隔号则可经符号面板取得。

这不是本宿主特有：`platforms/android/java/.../KeyboardLayout.java` 的三行符号与这里**逐字相同**，限制是随移植一起来的。需要说清的是两者是各自独立的文件而非共用代码——改本宿主这一份不会影响 Android，先前记作「共用」是不准确的。不在此改动的理由是另一条：来源没有触摸键盘，因此这三行符号**没有可对照的来源行为**，在十键一行的布局里挤进 `^` 与 `$` 要么让行数不齐、要么挤掉 `@` 或 `=`，那是触摸布局的设计取舍而不是对照缺口。

悬浮工具栏核对过两项声称，均成立。`FloatingToolbarLayout.scale` 的注释写着"匹配 Windows 工具栏的四档缩放"，核对来源 `floating-toolbar.ts` 的 `normalizeScaleKey`：确实只有 0.75 / 1 / 1.25 / 1.5 四档且其余一律归为 1，本宿主的实现与之逐项相同。图标字号方面，共享设置页给出的选项正是 16、18、20、22、24、26、28，与本宿主的 16..28 与默认 24 完全吻合——共享文档把 `scale_percent` 校验到 50..200、`font_size` 校验到 12..48，那是文档容许范围，不是界面给得出的值。

工具栏的**度量**则与来源不同，这是有意的而非缺陷，记在这里以便后面真要做设计决定时有个出处：来源的 `ui-html/webview2/ftb` 用 `--ftb-bar-height: 35px`、`--ftb-icon-size: 24px`、`--ftb-gap: 6px`、左右内边距 8/4（左侧留给拖动手柄）；本宿主用 44 / 42 / 10.5 与对称的 10，且文件头写明"Ported from platforms/macos/src/FloatingToolbarPanel.mm, including the arithmetic"。也就是说它跟的是 macOS 而不是 Windows。在一台既有触摸又有鼠标的 2in1 上把图标压到 24px 是否合适，是产品判断，不在此单方面改动。

设备上跑本次新增的三项功能时，暴露出一个此前无人发现的桥接缺陷，影响面远大于这三项：`javaScriptProxy` 分 `methodList`（同步）与 `asyncMethodList`（异步）两张表，而本仓库把**全部方法都注册进了同步表**，其中六个是早就存在的异步方法——`account`、`cloudDictionary`、`cloudDictionarySnapshot`、`aiModels`、`aiTest`、`testApiCredential`。异步方法注册在同步表里，页面拿到的不是它的返回值。开机引导正是这样失效的：宿主日志打印「opening welcome flow」，页面却画出设置页，因为那次查询的回复页面读不到，被 `catch` 兜成了「不需要引导」。

两条官方异步注册路径在本机的 API 23 模拟器上都不可用：属性形式的 `asyncMethodList` 与 `registerJavaScriptProxy` 的第四参数都让 Promise 永不兑现，页面停在启动页。两者都在设备上试过。因此本宿主自己的三个方法改为不走异步桥接——引导状态由宿主在窗口创建时算好、页面同步读取且回复带 `ready` 标志以免竞态，选择器与皮肤导入改为同步发起、结果不经返回值传递。

那六个早就存在的异步方法仍未修复：它们带参数且要做网络往返，无法照搬这个办法，需要另一套机制（例如宿主用 `runJavaScript` 回推结果，就像偏好变更通知那样）。这一条记在这里，因为它意味着账号、云词库与 AI 相关的设置项在本宿主上很可能一直没有真正工作过。

外部皮肤目录此前是一处缺口，现已按平台自己的方式补上。来源的 `skin_directory::open` 有 `#[cfg(target_os = "windows")]` 分支，所以"打开皮肤目录"是来源实实在在有的功能；共享皮肤页把它渲染成一个按钮，并按 `disabled={!openDirectory}` 决定可用性。本宿主不提供该成员，于是那个按钮**渲染出来但永远点不动**。

本宿主的皮肤目录在应用沙箱内（`${filesDir}/state/skins`），系统文件管理器浏览不到，所以"打开目录"在这个平台上没有对应物。用户的目标是把皮肤包放进去，因此方向反过来：用户用文档选择器指向皮肤所在的文件夹，由本宿主拷进去。选的是文件夹而不是文件，因为一个皮肤就是一个目录——`skin/catalog.rs` 判 `is_dir` 并在其中找样式表，导入单个文件会导入一个随后被目录扫描拒绝列出的东西。

按钮文案由新增的能力位 `skin_directory_import` 决定，在本宿主上显示「导入皮肤」：一个说「打开目录」却永远打不开目录的按钮，比没有按钮更误导。

顺带记下形状：这是本轮第三个"控件渲染出来但恒久不可用"的地方，三个都已处理：手写页的打开按钮、辅助码分页、以及这里的皮肤目录。它们的共同点是宿主缺一个 client 成员，而共享页选择了禁用而非隐藏——按平台名门控的那一类缺陷之外，这是另一类需要逐项核对 client 成员与渲染结果才能发现的缺陷。

设置界面一项此前记作「共享 UI」，这句话在源码层面成立、在运行时不成立：HarmonyOS 的设置窗口是 WebView 加载一个提交进仓库的构建产物，而它自 #2863 起没有被重建过，其间 52 个提交改动了 `packages/ui/src`。也就是说本仓库在长达数十个提交的时间里，HarmonyOS 上渲染的是一个别处已不存在的界面，此后新增的每一个能力位控件在这里都不可见。陈旧的包不报错——窗口照常打开，只是少掉一批控件，看上去像是这个平台本来就没有这些设置。已重建，并把「改完共享 UI 要重新生成」从一句文档变成 `verify-local.sh` 里的一道逐字节校验。共享 UI 的结论今后按该校验成立，而不是按源码引用关系成立。

硬件按键一项此前被记为「2in1 形态限制」，该结论是错的，已随本批纠正。`KeyboardExtensionAbility` 只在 `KeyboardFormFactor.isDesktop()` 时订阅 `keyEvent`，而那段注释论证的是「2in1 上这是唯一通路」——它说明桌面需要订阅，不说明手机不能订阅。真实后果不止于验证不到：手机或平板接上蓝牙/USB 键盘时扩展根本不订阅，框架把按键直接交给编辑器，物理键打出原文字母而完全不组字，这是功能缺口而非形态差异。现已按「形态决定画不画键、枚举决定路不路由键」拆开，判据是 `ALPHABETIC_KEYBOARD` 而非 `sources` 含 `keyboard`（后者在每台手机上都为音量与电源键成立）。因此该项的设备证据不再依赖一台能启动的 2in1，任何接得上键盘的 HarmonyOS 设备都能验证。

增量记录（2026-09-20，Windows 第六批：把三项「留待决定」逐个落定）：上一批把三件事记为需要用户决定，这一批逐个查清并处理，不再挂着。

1. 智能标点在 Windows 上的首次默认（#3105）。Windows 安装包发的 `config.default.toml` 五个开关全为关，来源也已把整族改成默认关；但那只是安装模板，运行中的 Server 读的是共享偏好文档，而共享默认里主开关与同键转回都是开——Windows 上的实际首次默认与它自己随包发出去的基线正好相反。默认函数改为 `!cfg!(windows)`：只动 Windows，其余宿主一直是开着发的，让偏好在老用户脚下变掉比按平台不同更糟；两边都不影响已存下来的值。判据放进 `test-default-config-parity.py`，它比对安装模板 TOML 与 Rust 源码两份互相独立的来源，把默认函数改回 `true` 会指名报错——不像单测断言实现等于实现那样自证。
2. x86（#3108）。32 位 TSF DLL 会被加载进每个 32 位宿主，但这个架构从来没被构建过：`build-cross.sh x86` 的 Rust 侧要 DWARF 展开，而 macOS 上常见的 i686 MinGW 是 SJLJ。查下去发现一处只在 x86_64 成立的代码：`CandidateWindow.cpp` 把无捕获 lambda 直接传给 `EnumFontFamiliesExW`，而 `FONTENUMPROCW` 是 `__stdcall`、lambda 转出来的是 `__cdecl`——x86_64 上只有一种调用约定所以同型，x86 上是不同类型，直接编译错误。改成具名 `CALLBACK` 函数（`ShellLauncher` 的 `EnumWindows` 回调本来就是这个写法）。新增 `scripts/test-windows-32bit-compile.py` 挂进 `--quick`：编译参数取自 x64 构建产出的 `compile_commands.json` 而不是另一份手工清单，往 CMake 加源文件或 include 自动被覆盖；只换编译器且 `-fsyntax-only`，不链接因此不需要 32 位库。当前 247 个源文件全部通过。x86 的**链接**仍未覆盖，那要等一套 DWARF 展开的 i686 工具链。
3. Engine 锁（结论：现在提锁拿不到那些行为，不是暂缓）。来源基线之后的 Engine 侧提交（ü 换 nue/lue/ju 写法再送进 Google 解码器、词格整句改 kenlm 三元模型、整句候选落用户词组）只存在于来源自己树内的 `engine/`。本仓库跟踪的是独立仓库 `metasequoiaime/MSIME-Engine`，克隆后核对：它比本仓库锁定的 `0531d421` 只多 5 个提交（`e25f2b8`、`5eab393`、`d45268d` 及两个 release chore），全部是词格 ngram 表的构建与落盘；全仓搜不到 kenlm / `sc.lm`，也搜不到把 ü 改写成 nue/lue/ju 再交给 Google 解码器的那段。也就是说提锁既拿不到上述任何一项 Windows 对照项，又会把词格 ngram 表的改动带进来，而整句重排在本仓库正由 Rust 侧的 `chinese-ime-lm` 另行推进（#3088）——两边同时动同一块行为会互相盖掉。因此本批不提锁，且这次是有依据的结论：等那些改动发布到独立 Engine 仓库之后再议。附带一提，本仓库的 Engine 是否同样存在 ü 拼写问题，仍未判定：engine-bridge 的测试装置用空词库临时目录，`qu`、`xu` 这类无 ü 的音节同样出不了候选，要判定必须带真实系统词典。（第七批已用锁定词库判定：不存在该问题，两种写法都通。）

增量记录（2026-09-20，Windows 第七批：用锁定词库逐项核对输入方案，并结掉 ü 那条「未判定」）：本批不改产品代码，新增 `crates/engine-bridge/examples/schemes_dictionary.rs`，按本仓库既有的真词库探针约定（同 `local_modes_dictionary`）接收一个按 `resources/desktop-dictionary.lock.json` 备齐的资源目录。起因是方案类的单测全部建在合成 sqlite 词库上：那能证明拼写解析器切对了音节，却证明不了这个方案够得着真实词条——空表对正确和错误的拼写一律回答「没有候选」。

覆盖到的：全拼 `nihao` 首选 `你好`；四套双拼 profile 各自用 `ni` 走通到 `你`（`ni` 在四套里都是 n+i，一个输入就覆盖四条路径，不必硬编四张韵母表）；微软双拼另加 `nihk`，preedit 必须切成 `ni'hao` 且首选 `你好`；五笔按键名汉字 `gggg`/`hhhh`/`aaaa` 得到 `王`/`目`/`工`；日语罗马字 `nihon`/`sakura` 的假名读音为 `にほん`/`さくら` 且候选含 `日本`/`さくら`，同时反查全拼不带假名读音。每次探测各用独立的 user 与 cache 目录，免得前一次的学习影响后一次的候选顺序。

同时把第六批第 3 条里记为「仍未判定」的 ü 拼写结掉，结论是本仓库**不存在**该问题：`nve` 与 `nue` 首选同为 `虐`，`lve` 与 `lue` 同为 `略`，j/q/x 后那个其实是 ü 的 `u`（`ju`/`qu`/`xu`/`jue`/`quan`）也全部出候选。来源 `ccbaa3a6` 需要在交给 Google 解码器之前把 ü 改写成 nue/lue/ju 写法，这边两种写法本来就都通，因此不是缺口，也不构成提 Engine 锁的理由。之所以拖到现在才判定，正是因为空词库分辨不出这件事——判据必须带真实词典。

该探针与其余真词库探针一样不挂进 `verify-local.sh`：锁定词库不在仓库里。本批没有 Windows 主机，不声称任何原生安装、TSF 注册或真实编辑器交互。

增量记录（2026-09-20，Windows 第八批：候选调频的持久化）：同样不改产品代码，新增 `crates/engine-bridge/examples/learning_dictionary.rs`。调频是排序变化，只有在存在排序的地方才看得见——单测那套合成词库对一个查询返回的条目太少，「往前挪了」不成立，所以这项此前没有任何覆盖，`learning: true` 在整个仓库里没被任何用例走过。

探针覆盖这个设置的三个半边：选过的候选在**新开的**会话里排到原位之前（只在同一个会话内有效就不叫学习）；`reset_learned_data` 之后回到出厂顺序，且这一步跑在确实写入过的那个 store 上，所以一个什么都没做的重置会在这里失败而不是悄悄通过；`learning: false` 时同样的选择在干净 store 上不改变任何顺序，用的是另一个 store——要证的是有没有写进去，而前一个已经被写过了。

与第七批同理，不挂进 `verify-local.sh`：锁定词库不在仓库里。没有 Windows 主机，不声称原生交互验证。

增量记录（2026-09-20，Windows 第九批：翻页停在 Engine 的初始上限）：来源在 `move_page` 里对末页做展开，本仓库没有对应物——查下去不是漏写一段调用，而是这条能力在本仓库根本够不着。

Engine 对**单字母**查询（`j`、`n` 这类只按声母的查询）只给 24 个候选，把其余的留到有人来要为止，`InputSession::expand_initial_candidates` 就是来要的入口。来源直接用内部的 `ImeSession`；本仓库只链 `metasequoia::Session` 这个公开门面，而门面从不转发它。实测：打一个 `j`，候选恒为 24 个、翻到第 5 页就是尽头，词库里其余 1431 个再也翻不到。

处理分三层，都沿用仓库既有机制：

1. Engine 侧走 overlay（`scripts/apply_engine_expand_initial_candidates.py`，登记进 `engine-lock.json` 的 `overlay_scripts`，与既有的 `apply_engine_double_helpcode_cache.py` 同一条路子）。只做两件事：把已有能力转发到公开门面；以及在 `InputSession::expand_initial_candidates` 成功后调用 `update_mixed_candidates()`。后者是必需的——`candidates()` 服务的是由引擎列表重建的 mixed 列表，不刷新的话这个方法会报成功而自己的访问器仍然返回那份短列表，等于谁调都看不见刚解除的上限。不改算法、不改排序。
2. 桥接暴露 `Session::expand_initial_candidates`。
3. `InputEngine` 加同名默认方法（默认答「没有更多」，因此 fixture 引擎与既有用例行为不变），运行时在 NextPage 走到末页时调用。移植来源的两条边界语义：下一页正好是那个不满的末页时先展开再进去，使它第一次显示就是满的；已经在末页且当前页不满时，新到的候选填进当前页而**不翻页**——翻过去会正好跨过刚到的那些。

实测：`j` 从 5 页变为 291 页，第四页起是此前够不到的候选。`crates/input-runtime/src/tests.rs` 新增三个 fixture 用例（能翻到被扣下的候选、填满当前页时不前进、不扣候选的引擎翻页行为逐页不变），`schemes_dictionary` 补一段真词库断言。

一处自己踩的坑记下来：overlay 的 `replace_once` 是从既有脚本抄的，而既有脚本的每个 hunk 都会消耗掉自己的锚点，我这三个 hunk 都是在锚点后面追加、锚点仍在，于是「锚点还在吗」回答不了「是否已经应用过」——跑第二遍就又插了一份，Engine 直接编译失败于重定义。改为每个 hunk 另给一个只有改写后文件才有的标记来判定，并实际连跑两次验证幂等。

增量记录（2026-09-20，Windows 第十批：自动造词）：来源在 Server 里手工串这件事——候选只消耗了部分输入就把 `creating_word` 打开，用 `update_creating_word_progress` 累积各段，完成时落进用户词库。本仓库没有对应代码，一度看起来是缺口；查下去不是：锁定 Engine 的 `InputSession::commit` 内部已经自带整条链（`advance_composition_after_selection` + `update_creating_word_progress` + `store_user_phrase_from_canonical_pinyin`），而门面的 `select` 正是走它。来源要手工串，是因为它那版 Engine 把这几步摊在外面。

新增 `crates/engine-bridge/examples/phrase_creation_dictionary.rs` 验证。这件事两头都看不见：空词库给不出「只消耗一部分」的候选，组合根本不会发生；而只看完整输入也看不见，因为词格对任何输入都能给出整句候选，`海滩跑步` 无论存没存过都排第一。区分两者的是**简拼**——存过的短语答 `htpb`，重新生成的整句不答。探针即以此为判据，并覆盖关掉学习时同样的组合不写入。

过程中先得出过一个错误结论，记下来免得下次重犯：第一版探针判定「组合出的短语没有落盘」，证据是简拼召不回、候选来源恒为整句生成、工作词库全表扫不到。三条证据都是真的，结论却是错的——桥接的 `prepare_options` 把 `learning` 显式设为 `false`（与 Engine 自身默认的 `true` 相反），而探针没设，于是不落盘正是正确行为。开启后简拼立刻召回，来源从整句生成变为词库条目。教训是判定「功能缺失」之前先核对自己有没有把它打开，而不是先去读 Engine 内部。

增量记录（2026-09-20，Windows 第十一批：把一条记在基线上的「环境所限」变回真的跑）：Wine runner 的四条失败里，`windows-installer-launch` 的原因写着「它按仓库相对路径找安装脚本，而容器没挂仓库」。那不是环境限制，是 runner 自己少挂了一个目录——那个目录就在手边。

按 `MSIME_WINE_RESOURCES` 同样的方式把 `platforms/windows/installer` 只读挂进容器，并在跑到该套件时把 `msime_setup.iss` 的路径传进去。该测试读的是真实的安装脚本而不是参数的副本，所以这是它本来就要的输入。

结果从 73 通过 / 4 失败变为 74 通过 / 3 失败，基线里那一条随之删掉。剩下三条的原因仍是测量出来的：`windows-server-smoke` 无合成器、`windows-fullscreen-foreground` 无真实显示器、`windows-session-smoke` 的词库准备在 Wine 下失败（同一调用在本机返回 ok）。

这一轮顺带暴露了我自己的一个方法错误，记下来：主工作区落后 develop 44 个提交，而我在它上面 grep 判定过若干「本仓库没有 X」。落后正好会伪造缺失——`run-tests-wine.sh` 就是这样被我判成不存在的，它其实早在 develop 上。凡是结论为「不存在」的检查，必须在最新代码上复核；结论为「存在」的不受影响。第一遍用旧产物跑出的 `windows-dedicated-english` 失败同理，是旧二进制而非回归，重新交叉构建后即通过。

增量记录（2026-09-20，Windows 第十二批：给 Wine 容器一块虚拟显示）：上一批之后 Wine 还剩三条失败，其中两条记的理由是「要合成器」和「要真实显示器」。前者读错了——`XDG_RUNTIME_DIR is invalid or not set` 说的是没有 X 服务器，而不是没有合成器，X 服务器这个容器供得起。镜像装上 `xvfb`，跑测试时走 `xvfb-run -a`。

`windows-fullscreen-foreground` 随之通过，基线那条删掉。`windows-server-smoke` 也走过了窗口创建，但停在新的地方：断言候选窗报告 `DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2`，而 Wine 建得出窗口却不把这个感知上下文从 `GetWindowDpiAwarenessContext` 带回来。仍是 Wine 的限制，但比它替换掉的那条窄得多，也是读出来的而不是推的。

合起来，Wine 下从最初的 72 通过 / 5 失败到现在 75 通过 / 2 失败。

一个坑：`xvfb` 包本身不含 `xauth`，缺了它 `xvfb-run` 直接报 `xauth command not found`，于是整轮 77 个套件全部 FAIL——看起来像改动把一切弄坏了，实际是 runner 自己起不来。加装 `xauth` 即可。这类「全红」要先怀疑 runner，不要先怀疑被测对象。

增量记录（2026-09-20，Windows 第十四批：以词定字）：沿来源 README 的功能清单继续。`[` 上屏高亮候选的首个汉字、`]` 上屏末字，这条规则只有在存在多字候选时才有意义，空词库根本走不到。新增 `crates/engine-bridge/examples/word_to_character_dictionary.rs`。

覆盖两端取字、三字候选（末字不能靠取第二个字蒙混过去）、组合被消耗、不含汉字的候选、越界索引。

「组合被消耗」这一条专门去来源核对过，不是想当然：来源在发出 `Normal` 或 `CommitExactText` 之后调用 `ClearState()`，所以把剩余输入留着继续组合的宿主会与它不一致。本仓库经 Engine 的 `select_edge` 达到同样结果。

不含汉字的候选（该输入的英文候选）也两边一致：Engine 拒绝处理且不动组合，宿主随后回退到从候选文本里抽字；抽不到就整条上屏——来源的 `ExtractHanCharacter` 返回空时同样保留完整候选文本走 `Normal`。

增量记录（2026-09-20，Windows 第十五批：辅助码）：来源 README 给辅助码的篇幅最长，规格也最细，且自带可验证的例子——「阿」的自然码辅助码是 `ek`。新增 `crates/engine-bridge/examples/helpcode_dictionary.rs`：单码只调整顺序（匹配的排前，其余保留），双码严格筛选（只留匹配的），词组第一码取首字首码、第二码取末字首码。四条全部符合来源描述，包括 `ayiEN` 同时留下「阿姨」和「阿姨好」——末字「好」是 `nz`，规则读的是末字的**首**码，所以它该留下。

这一批差点报出一个不存在的缺陷，记下来：第一次探测时 `aEK` 返回**空候选列表**、`aE` 也不把「阿」提前，看起来像双码辅助整个坏掉。实际是辅助码表（`helpcodes/*.txt`）是与词库分开的 Engine 资源，而我的资源目录只按 `resources/desktop-dictionary.lock.json` 备了 8 个词典产物，根本没有那些表。表一旦缺失，没有任何候选能匹配任何辅助码，于是单码不再调序、双码把一切筛光——读起来正是「功能坏了」的样子。补上表之后四条立刻全对。

顺着这条又核了一遍打包：设置页提供五种方案，而安装测试只断言打包了 `helpcode.txt` 一个文件，一度怀疑只发了蓝天小雨点一种。查 `Prepare-PackageFiles.ps1` 是 `Copy-DirectoryContents` 整个 helpcodes 目录，五种都发，安装测试那行只是抽查。不是缺口。

探针自己把表补进资源视图，因此不需要使用者额外准备；大词库用符号链接、辅助码表实拷贝——Engine 把资源暂存进用户目录那一步不跟随链接目录，链过去等于没有表。

增量记录（2026-09-20，Windows 第十六批：简繁转换的实现差异，以及它此前零覆盖）：沿来源 README 清单查到简繁，发现两件事。

**一、实现方式不同，且此前从未记录。** 来源用 OpenCC：`server/src/conversion/chinese_converter.cpp` 加载 `assets/opencc` 下的 `s2t.json`，是词级转换。本仓库用 `platforms/windows/src/input/ChineseTextConversion.cpp` 的 `LCMapStringEx(LCMAP_TRADITIONAL_CHINESE)`，映射表属于操作系统，是逐字的。全仓搜不到 opencc 的任何痕迹。

这会在一对多的字上产生不同输出（「发」既可作「發」也可作「髮」，「里」「干」同理），而词级转换正是用来消解这种歧义的。**具体差多少没有测量**：`LCMapStringEx` 只在 Windows 上有行为，本机没有 Windows 主机；拿 Wine 的映射表冒充 Windows 的映射表没有意义。

引入 OpenCC 是加依赖（库加数据资产，另有许可问题），按仓库规矩不擅自做，记在此处待定。

**二、这个函数此前没有任何测试。** 新增 `platforms/windows/tests/input/chinese_conversion.cpp`，并且刻意不去钉映射表——钉具体的繁体字等于钉一个 Windows 版本，在 Wine 下则是钉 Wine 的表。测的是这段代码自己的契约：开关关闭时原样返回、空输入、ASCII 原样、非法 UTF-8 走回退而不抛也不丢字、转换不会把非空文本变空、结果仍是同样字数的合法 UTF-8。Wine 下通过，套件计数 75/77 变为 76/78。

增量记录（2026-09-20，Windows 第十七批：中英混输的触发字符数）：来源写明英文候选在字母串达到设定长度（1～8）后才出现。新增 `crates/engine-bridge/examples/mixed_input_dictionary.rs`，用真实英文词库验证阈值 2 与 3 各自的边界、把阈值抬到超过已输入长度会把候选收回、以及关掉混输后任何长度都不出英文候选。

这项的陷阱在于「没有英文候选」有两个原因：阈值没到，和词库里根本没有以这串字母开头的词。分不清这两者的测试，在功能被整个关掉时也会通过。所以每个否定用例都与同一串字母上的肯定用例成对出现，关掉开关那一组用的正是上面刚刚出过候选的字母串。

（探测过程中 `shij` 在任何阈值下都不出英文候选，正是后一种原因——英文词库没有该前缀，不是阈值失效。这也是不把它写进断言的理由。）

增量记录（2026-09-20，Windows 第十八批：emoji 与颜文字在候选里的位置）：来源把规则写成「emoji 在英文候选之后插入，颜文字排在 emoji 之后」。其实现更具体——`server/src/ipc/candidate_selection_policy.h` 的 `NormalizeMixedCandidateOrder`：头部按 本地、[云]、[AI]、英文₁、emoji₁、颜文字₁ 依次插入，其余按 英文→emoji→颜文字 的组序追加到尾部。本仓库实测输出与这条规则逐项吻合（`ku` 的尾部正是「剩余英文→剩余 emoji」）。

新增 `crates/engine-bridge/examples/mixed_ordering_dictionary.rs`，钉住用户看得见的那部分：三类各自第一个的相对次序，以及两个开关各自只移除自己那一类。后半条是必需的——只断言「存在时的次序」，对一个完全忽略开关的实现同样成立。

顺带更正本表此前一处标签错误：候选来源的数值按 `core/word_item.h` 的枚举序号，9 是 **Fallback** 不是 Generated（Generated 是 8）。第十批记录里把整句候选的来源 9 写成「整句生成」，措辞不准；该批的结论（那条候选不是词库条目、学习后变为词库条目）不受影响。

增量记录（2026-09-20，Windows 第十九批：快捷模式的文档化边界）：`local_modes_dictionary` 此前只验证八种模式各自能进入、能出候选、能上屏，没有核对**内容**。按来源表格补两处。

日期时间模式的三个答案各有三种拼法（`rq`/`riqi`/`date`、`sj`/`shijian`/`time`、`xq`/`xingqi`/`week`），此前只测过 `rq`，九个入口里八个从未走过。判据是同一答案的三种拼法**结果必须一致**——这才证明它们是别名，而不是三个恰好都非空的东西。时间那组只比形状：它的答案在探针运行期间会变，要求三者相等会在跨秒时失败。另加一条日期与星期的结果必须不同，否则三组全返回同一个字符串也能通过。

超级简拼按首字母检索，`nh` 能检索到「你好」。**这里我先写错了断言**：按来源表格里「全拼如 `nh` → 你好」写成了断言首选等于「你好」，实测首选是「女孩」。来源那句是举例说明简拼检索得到它，不是承诺排第一；排第几取决于词频，钉首选是过度规定。改为断言「你好」在候选之中，并附一条前八个候选都不是单字——单字会说明它退化成了普通拼音检索而非简拼检索。

增量记录（2026-09-20，Windows 第二十批：来源 README 的功能清单走完）：第十三到十九批沿来源 README 逐项验证，本批把结论收口并更新上表中已被覆盖、却仍写着「仍需核对」的行。

这条轴上查到的**唯一真差异**是简繁转换的实现方式（第十六批，结论已在第二十七批更正为跨平台策略而非 Windows 单点缺口）。

其余逐项都与来源一致：输入方案与辅助码、候选调频五种模式、以词定字、中英混输触发长度、emoji 与颜文字的插入位置、快捷模式的文档化拼法、日文与中文方案的往返保留（后者已由 `apps/desktop/tests/settings/settings.test.tsx` 覆盖，不需另加探针）。

这七批里我自己犯过三类错，一并记下，因为它们各自代表一种失效模式：**前提没核对**（`learning` 默认关、辅助码表没备、主工作区落后 44 个提交，三次都差点把「我没打开它」报成「功能坏了」）；**把举例当契约**（来源写「如 `nh` → 你好」是说简拼检索得到它，我写成了断言首选等于它）；**否定断言不设防**（只断言「有候选时的次序」或「没有英文候选」，对一个把功能整个关掉的实现同样成立，因此每条否定都要与同一输入上的肯定成对）。

增量记录（2026-09-20，Windows 第二十一批：x86 终于被构建出来）：第六批把 x86 记为受阻，理由是「`build-cross.sh x86` 的 Rust 侧要 DWARF 展开，而 macOS 上常见的 i686 MinGW 是 SJLJ」。那条守卫自己就写着「换一套兼容的工具链」——那是**这台机器**的限制，不是这个架构的。Debian 的 i686 MinGW 配置为 `--disable-sjlj-exceptions --with-dwarf2`，容器里现成。

新增 `platforms/windows/cross/Dockerfile` 与 `platforms/windows/build-cross-container.sh`：把仓库挂进容器跑既有的 `build-cross.sh`，不改构建流程本身。vcpkg 与依赖树用容器专属目录，因为 macOS 上引导出的 vcpkg 里是 macOS 二进制。结果：**x86 的 host DLL、TSF DLL、Server 与全部原生测试首次全部链接成功**，32 位宿主进程要加载的那个 TSF DLL 至此不再是从未构建过的目标。

路上暴露出四处只有在这条路径上才会现形的问题，逐条修掉，四处都是各平台都更正确的写法而非容器补丁：

1. **CMake 的 C 编译器落到宿主**。`build-cross.sh` 只设了 `CMAKE_CXX_COMPILER`，C 编译器取默认；在 Linux 容器里那就是 `/usr/bin/cc`，链接时报 `unrecognized option '--major-image-version'`。显式设 `CMAKE_C_COMPILER`。
2. **没有声明目标 Windows 版本**。`ID2D1DeviceContext5` 在 Direct2D 头文件里被 `NTDDI_VERSION >= NTDDI_WIN10_RS2` 挡着，而构建从未声明过版本、取的是工具链默认值——Homebrew 的够高，Debian 的不够。代码本来就要求 1703（per-monitor v2 DPI 与该接口都起自那一版），现在在 CMakeLists 里写明。（改这处时我顺手把 `project()` 的语言加成了 `C CXX`，那是多余的：容器里触发 C 编译器检测的是 Engine 的 voice 子项目，而加上之后 pipe-only 那条不含该子项目的配置反倒开始要求 C 编译器。已撤回，只保留 `CMAKE_C_COMPILER`。）
3. **`#include "InputScope.h"`**。那是平台头不是自有头，MinGW 提供的是 `inputscope.h`，大小写敏感的文件系统找不到。改为 `#include <inputscope.h>`。
4. **`hr == D2DERR_RECREATE_TARGET` 的符号比较**。`HRESULT` 有符号而该宏在部分 SDK/MinGW 版本里是无符号，于是在一套工具链上是警告、另一套上静默。按规矩做了广度扫描：同样写法共 **7 处**，全部改为显式转 `HRESULT`。

本机 x64 构建与 Wine 套件（76 通过 / 2 失败）均无回归。x86 的**执行**仍未覆盖：Wine runner 目前只搬 x86_64 的 MinGW 运行库。

增量记录（2026-09-20，Windows 第二十二批：x86 不只构建，也真的跑起来了）：上一批让 x86 首次链接成功，但执行仍未覆盖，理由是 Wine runner 只搬 x86_64 的运行库。这一批把两处补齐。

**运行库要跟着产物走。** x64 由本机工具链构建，x86 由容器构建——把本机的 i686 运行库拿给 x86 用是错的，本机那套是 SJLJ，而产物是 DWARF，差别正好就在展开器上。runner 现在按架构取：x64 仍问本机编译器，x86 从 cross 镜像里取（`-print-file-name`，不去猜发行版这个月用的是哪个版本化 gcc 目录），取的是 `libgcc_s_dw2-1.dll` 而不是 `libgcc_s_seh-1.dll`。

**Wine 镜像原本跑不了 32 位。** 补上运行库之后 78 个套件仍然全红。按上一批记下的规矩先查 runner，单独跑一个可执行文件得到 `failed to load syswow64\ntdll.dll` —— Debian 的 wine 在 amd64 上要 `dpkg --add-architecture i386` 加 `wine32` 才有 WoW64，缺了它每个 32 位程序都起不来。加上之后：**x86 76 通过 / 2 失败**，与 x64 完全相同的两条、同样的原因（Wine 不回传 PER_MONITOR_AWARE_V2；词库准备在 Wine 下失败而本机 ok）。

至此那个要被加载进每个 32 位宿主进程的 TSF DLL，既构建得出也跑得起来。x64 在同一镜像上无回归。

增量记录（2026-09-20，Windows 第二十三批：托盘到 Tauri 壳之间的路由契约加门禁）：托盘菜单与悬浮工具栏交给共享 Tauri 壳的是一个路由字符串，C++ 侧 `ShellSurfaces.h` 产出、Rust 侧 `host_surface.rs` 解析。两边各有自己的测试，各自按自己的词汇表通过，所以**只改一边的名字不会有任何可见故障**——解析不了的路由不是错误，它打开普通设置窗口，于是那行菜单照样能点，只是打开了错的东西。

新增 `scripts/test-shell-route-parity.py` 并挂进 `--quick`：从两个文件各自抽出面板路由与设置分区的名字集合，逐个核对 C++ 能产出的每一个都在 Rust 接受的范围内。当前 4 个面板路由与 1 个设置分区全部对得上。

做了反向验证，因为只会通过的门禁没有价值：把 Rust 侧的 `"handwriting"` 改成 `"handwriting-x"`，门禁指名报出「Windows Server 产出的面板路由 handwriting，SurfaceRoute::parse 不接受，那行会打开设置窗口」；把 `"about"` 同样改掉也会各报各的。恢复后通过。

（Linux 的启动器发同一份契约，因此这道门禁同时覆盖它。）

增量记录（2026-09-20，Windows 第二十四批：一条我自己归错因的失败，其实是真缺陷）：`windows-session-smoke` 在 Wine 下的词库准备失败，我此前把它记成「Wine 的限制，不是产品的」，依据是同一个 `msime_client_prepare_host` 在本机返回 `ok:true`。那个依据本身没错，结论错了。

这次先让测试把拒绝原因打出来（它原本只断言 `ok`，把回复里的 `error` 丢掉了，一条消息代表所有失败方式——和第十一批那次「队列任务失败」同样的毛病）。真正的原因是 **`Runtime directories must be absolute`**。

顺着查：`prepare_host_configuration` 用 `std::fs::canonicalize`，Windows 上它返回 `\\?\` 扩展长度形式；Engine 用 `std::filesystem::path::is_absolute` 校验，而 **libstdc++ 认为 `\\?\Z:\res` 的 root name 为空、因而不是绝对路径**。用一个最小 MinGW 程序在 Wine 下直接验证了这一点。这不是 Wine 的行为，是 libstdc++ 的行为——MSVC 的标准库能解析该前缀，所以用它构建的发布版从不暴露；GNU 交叉构建以及跑这些二进制的每一个测试都会撞上。

修法是交给 Engine 之前去掉该前缀，且只解开驱动器形式：`\\?\UNC\server\share` 对文件系统的含义与 `\\server\share` 不同，不能改写成一个「恰好能解析」的路径。

修完之后准备成功，套件推进到「Layout-produced punctuation replaced digit selection」——那条断言此前从未被执行过，因为每一次运行都停在它前面。它是下一个要查的东西，不是已知的环境限制，基线按此改写。

教训与第十五批的辅助码那次相反：那次是「我没打开它」被误当成功能坏了；这次是真缺陷被我误当成环境限制。两者的共同点是**把观察到的现象直接当成结论，而没有把失败原因取出来看**。

增量记录（2026-09-20，Windows 第二十五批：新推进到的那条断言写错了）：上一批修好路径前缀之后，`windows-session-smoke` 推进到「Layout-produced punctuation replaced digit selection」——一条此前从未被执行过的断言。它测的是非美式布局下未加 Shift 的数字键产生标点时仍应按数字选词。

先确认不是第一批那次改动（选词分支只认数字键）引入的：那里取的是 `normalize_digit_key(packet.keycode)`，用的是 keycode 不是 `wch`，VK '1' 带 `&` 仍得 '1'。不是它。

取实情：回复是 `NavigationIgnored`、commit 为空；再打印按键前的会话，`candidates` 为空、`editing_text` 为空。原因清楚了——这段上文用 Ctrl+Enter 提交了候选翻译，**组合已经结束**，此时按 '1' 无可选，返回 Ignored 正是对的。**是断言写错了**，它要一个活着的组合却没有建立。

修法是在两条「不该被消耗」的检查之后重新键入一段输入，并先断言确有候选可选。那两条检查本身仍然有效，只是它们真正断言的是「视图没有变化」，在空组合上同样成立。

结果：带资源目录时 `windows-session-smoke` **整体通过**，套件从 76/78 变为 **77/78**，只剩 `windows-server-smoke`（Wine 不把 PER_MONITOR_AWARE_V2 从 `GetWindowDpiAwarenessContext` 带回来）。

这是第二次遇到「从未被执行过的断言本身是错的」（前一次是模式通知那条）。共同点是：一条断言只要没被执行过，它就只是一段**意图**，不是事实。

增量记录（2026-09-20，Windows 第二十六批：让 77/78 成为默认而不是靠手工准备）：上一批把 Wine 套件推到 77/78，但那只在有人先把约 185 MB 词库备到某个目录、再设 `MSIME_WINE_RESOURCES` 时成立——也就是说完整覆盖依赖一次没有记录在案的人工操作。

runner 现在自己去找仓库既有的约定缓存 `target/desktop-resources`（`platforms/windows/installer/DesktopResources.md` 就是这么写的，打包脚本也默认它），并解析其中按代次哈希命名的子目录——`install_resources` 把产物装在那一层，直接挂父目录是挂不到文件的。每次运行都打印用的是哪一份，免得计数含义不明。

写进注释的那条准备命令是**实跑验证过的，而且第一版是错的**：只跑 `install_resources` 会失败，因为锁里有一个产物来自 Engine 检出而不是词库发布，必须先跑 `scripts/fetch_engine.py`。这正是不该照抄自己记忆里的命令的理由。

结果：有缓存的检出直接得到 77/78 且无需知道任何环境变量；没有的仍是 76/78，基线按此改写，两条路径都实测过。

增量记录（2026-09-20，Windows 第二十七批：更正第十六批对简繁转换的定性）：第十六批把简繁记成「Windows 用 `LCMapStringEx` 而来源用 OpenCC，引不引 OpenCC 属于待定的依赖决定」。那段描述没错，但**定性错了**——我只看了 Windows 一个平台就把它当成 Windows 的单点选择。

把三个桌面宿主都查一遍：Windows 用 `LCMapStringEx(LCMAP_TRADITIONAL_CHINESE)`，macOS 用 `CFStringTransform(Simplified-Traditional)`，Linux 用 ICU 的 `Simplified-Traditional` transliterator。**三家用的都是各自平台自带的转换设施**，而来源在包里带一份 OpenCC 数据。也就是说这不是 Windows 漏掉了什么，而是本仓库一条一致的跨平台策略；换成 OpenCC 意味着三个平台一起换，或者让 Windows 与另外两个不一致。

取舍仍然真实存在：逐字映射在一对多的字上不如词级转换（「发」既可作「發」也可作「髮」），而消解这种歧义正是词级转换存在的理由。变化的是这件事该怎么提出来——不是「Windows 要不要加个依赖」，而是「三个桌面宿主要不要一起从平台设施换成随包分发的词级表」。仍然待定，但现在问题问对了。

附带一处不对称，查清后认为合理：Linux 那边有 `汉语 → 漢語` 的具体断言，Windows 那边（第十六批新增的测试）刻意不钉映射表。理由是 ICU 是随包的库、行为稳定，而 `LCMapStringEx` 的表归操作系统、随 Windows 版本变动——在后者上钉具体繁体字等于钉一个 Windows 版本。

增量记录（2026-09-20，Windows 第二十八批：把最后一条失败查到底，并否掉一个我自己做过的改动）：`windows-server-smoke` 是 Wine 下唯一还失败的套件，此前记的理由是「Wine 不把 `PER_MONITOR_AWARE_V2` 从 `GetWindowDpiAwarenessContext` 带回来」。写一个最小程序实测：Wine **接受** `SetThreadDpiAwarenessContext(PMv2)`，线程确实是 PMv2，但在该线程上创建的窗口报回 per-monitor **v1**（awareness=2）。所以那句话是对的，只是不完整。

据此我先做了一处改动：按 ntdll 的 `wine_get_version` 精确识别 Wine，在其下接受 v1（Windows 上仍严格要求 v2）。它确实让断言通过了——**然后套件在更深处继续失败**，`window.failed()` 为真、窗口不可见。也就是说放松那条断言**换不来任何通过**，只给测试代码增加了 Wine 感知的复杂度。**改动已撤回。**

真正的拦路者查清了：`DeviceResources::EnsureForComposition` 走 `DCompositionCreateDevice` 与 `CreateSwapChainForComposition`，而 Wine 的 DirectComposition 基本是桩。往镜像里加 Mesa 软件光栅器也无济于事，设备照样建不出来。

这是唯一一条真正需要 Windows（或一个实现了 DirectComposition 的 Wine）的套件，基线按上述顺序逐条记下，免得下一个人重走这三步。

顺带说明这轮的取舍：能让计数好看的改动（放松断言）被否掉了，因为它并不能让套件通过；留下的是一条把原因查准的记录。计数不是目的。

增量记录（2026-09-20，Windows 第二十九批：那条「需要 Windows」其实源于一处有意的设计分歧）：上一批把 `windows-server-smoke` 的拦路者定位到 Wine 的 DirectComposition 是桩。这一批问下一个问题——**来源是怎么做的**，因为如果来源也走 DirectComposition，那它就是纯环境限制；如果不是，那这条失败是本仓库自己的选择带来的。

来源的输入法窗口用 **`WS_EX_LAYERED` 分层窗口**（`server/src/window/ime_windows.cpp`），DirectComposition 只出现在它的 WebView2 与设置路径里。本仓库的原生候选窗、候选浮出、悬浮工具栏、托盘菜单四个表面统一走 `DeviceResources::EnsureForComposition`，即 `DCompositionCreateDevice` 加 `CreateSwapChainForComposition`。

所以这条失败的性质要改写：**不是「这个功能只能在 Windows 上验证」，而是「本仓库为这四个表面选了一条来源没走的合成路径，而 Wine 尚未实现它」**。来源那条路在 Wine 下本来是跑得起来的。

这不构成要求改回分层窗口的理由——合成交换链避开了 `UpdateLayeredWindow` 每帧的 CPU 拷贝，四个表面都是低延迟且不能抢焦点的，选它有实在的道理，属于表里一贯记的「适配平台特性」。而且 `EnsureForComposition` 失败时回退到 `EnsureForWindow` 也不是好主意：普通 HWND 交换链拿不到逐像素透明，候选卡片的阴影会退化成不透明矩形，静默变丑比明确失败更糟。

记下来是因为这两种读法对后续决策不同：若哪天要让这套在无 DirectComposition 的环境（Wine、或某些远程会话）下也能画，那是一次明确的渲染路径工作，而不是「等一台 Windows 机器」。

增量记录（2026-09-20，Windows 第三十批：更正第二十八批的拦路者，并记下一次做了又撤回的实现）：第二十八批说 `windows-server-smoke` 卡在 Wine 的 DirectComposition 是桩。**那个结论是读代码路径推出来的，不是测出来的，而且是错的。**

按第二十九批的判断（来源用分层窗口，所以这条路可以不依赖合成器），我实现了一条分层回退：`EnsureForComposition` 失败时改走 `CreateDCRenderTarget` + 预乘 alpha DIB + `UpdateLayeredWindow`。先用一个独立最小程序在 Wine 下验证过这整条链可用（D2D 工厂、`CreateDCRenderTarget`、`BindDC`、绘制、`UpdateLayeredWindow` 全部成功，窗口可见）。接缝也是干净的：没有任何调用方用 `GetDeviceContext()`，全部走已是基接口类型的 `GetRenderTarget()`。

**但回退在套件里根本没被走到。** 逐步加诊断才看清：`DeviceResources::EnsureFactories()` 需要 Direct2D、DirectWrite 与 WIC 三样，Wine 下前两样成功，`CoCreateInstance(CLSID_WICImagingFactory)` 返回 `REGDB_E_CLASSNOTREG`。`windowscodecs.dll` 在 prefix 里存在，但类没注册；`wine regsvr32 windowscodecs.dll` 不是修好它而是挂住。

也就是说 `EnsureFactories` 在 `EnsureForComposition` 走到 `DCompositionCreateDevice` 之前就返回了假——**Wine 的 DirectComposition 到底行不行，至今仍然未知**。

因此那条分层回退**已撤回**，没有合入：它编译得过、原理验证过，但在这里一次都没被执行到，合进去等于把一段无法演示其作用的渲染代码放进产品。等 WIC 可用之后再说。

第二十八批那条「否掉一个能让计数变好看的改动」的判断依然成立，但**理由变了**：当时我以为渲染永远不通，所以放松 DPI 断言没意义；实际是连工厂都建不起来。结论对，推理错。这两者的区别值得记下——对的结论配错的推理，下一次就会错。

增量记录（2026-09-20，Windows 第三十一批：三道坎逐个查清并移走，候选窗在 Wine 下真的画出来了）：上一批测出 `EnsureFactories` 的 WIC 失败于 `REGDB_E_CLASSNOTREG`。这一批找到原因并接着往下走。

**一、prefix 是在没有显示器的情况下烘进镜像的。** Dockerfile 里那句 `wineboot --init 2>/dev/null; true` 看起来成功了，实际留下一个 WIC 未注册的 prefix。对照实验很直接：同一镜像里用烘好的 prefix 取 WIC 得 `0x80040154`，而在显示器下新建一个 prefix 再取就是 `S_OK`。改成在 `xvfb-run` 下创建并等 `wineserver -w`（注册表在 `wineboot` 返回时仍在写）。

**二、DPI 断言。** Wine 接受 `SetThreadDpiAwarenessContext(PMv2)`，但该线程创建的窗口报回 v1。测试改为按 ntdll 是否导出 `wine_get_version` 精确识别 Wine，仅在其下接受 v1，Windows 上仍要求 v2，线程自身的上下文照旧严格断言。

**三、DirectComposition 确实是桩**（这次是测出来的：WIC 修好、窗口能建之后，合成路径仍然失败）。`DeviceResources` 现在在 `EnsureForComposition` 失败时回退到分层窗口——`CreateDCRenderTarget` 加预乘 alpha DIB 加 `UpdateLayeredWindow`，正是来源画这些表面的方式。**回退只在原先直接失败的地方生效**，有合成器的宿主永远走不到它。

结果：候选窗在 Wine 下画出来并可见（`failed()` 为假），套件从第 115 行推进到第 185 行——**中间约七十行断言此前从未被执行过，现在全部通过**。现在停在点击命中测试：卡片画出来了、窗口可见，但合成的 `WM_LBUTTONDOWN`/`UP` 没有被记为一次点击。那是新的前沿。

两点自我更正：第三十批我说这段回退「无法演示其作用，因此撤回」——那个判断在当时是对的（它确实一次都没被走到），**移走 WIC 这道坎之后就不对了**，所以这次它带着证据回来了。另外，一次运行里 `windows-voice-controller-connection` 失败过一次、随后两次都通过，是负载相关的不稳定而非本批引入的回归；我重跑了才这么说。

增量记录（2026-09-20，Windows 第三十二批：候选点击在任何同步派发 WM_CAPTURECHANGED 的系统上都不会生效）：上一批让候选窗在 Wine 下画了出来，套件随即停在点击测试。一路查下去发现两处，一处在测试、一处在产品。

**测试侧**：`first_candidate_point` 按**窗口**宽度算行布局，并把算出的**卡片坐标**直接当客户区坐标发出去。而窗口的 `hit()` 明确只在卡片内命中——透明阴影留白不可交互——它会先减去 32/20 的左上留白，并按卡片宽度（窗口宽减去左右留白）排布行。于是这个辅助函数产生的点永远落在行的左上方之外。它从未被执行过，所以一直没人发现。

**产品侧，这条是真缺陷**：`WM_LBUTTONUP` 先 `ReleaseCapture()` 再读 `pressed_`。`ReleaseCapture` 会把 `WM_CAPTURECHANGED` 派发给这个窗口，而那正是取消路径——它清空 `pressed_`。也就是说释放动作销毁了紧接着要读的那次按下，点击到不了回调。顺序调换即可：先取走按下、清空，再释放捕获。**这不是 Wine 特有的**，任何同步派发该消息的系统上都一样。

两处修完，套件从第 192 行推进到第 305 行，中间包括点击计数与三种取消语义（`WM_MOUSELEAVE`、`WM_CANCELMODE`、`WM_CAPTURECHANGED`）全部通过。现在停在候选浮出窗那一段，是另一个表面，属于下一个前沿。

过程中还有一次自己造成的弯路值得记：有一轮我把构建输出重定向到 `/dev/null`，构建其实因为 `%f` 对上整型而失败，于是我拿旧的可执行文件跑了一整轮并得出「诊断没有输出」的困惑结论。**关键命令不要丢掉输出**——仓库规矩里本来就写着不要把需要看 exit code 的命令接管道，这次是同一类错误的另一种形态。

增量记录（2026-09-20，Windows 第三十三批：x64 套件在 Wine 下首次 78/78 全通过）：最后一条 `windows-server-smoke` 拿下了，原因是第五处——**只画文字的表面不该依赖 COM**。

浮出窗 `open()` 返回可见，`UpdateWindow()` 触发重绘后变为不可见。把被吞掉的异常打出来是「Candidate menu device unavailable」，再往里是 `EnsureFactories()` 为假，最后定位到 `CoCreateInstance(CLSID_WICImagingFactory)` 返回 `0x800401F0`（`CO_E_NOTINITIALIZED`）——运行该窗口的线程没有初始化 COM。

`EnsureFactories` 把 WIC 当硬性前提，而 WIC 在这里只用于两个位图函数，且那两个函数**本来就检查空工厂并提前返回**。所以改为按需创建：`EnsureFactories` 不再因它失败，两个位图函数在真正需要时自己尝试。**只影响当前会整体失败的路径**，COM 已初始化的宿主行为不变。

至此 x64 在 Wine 下 **78 通过 / 0 失败**，是本仓库第一次整套通过。三轮连跑为 78/0、78/0、77/1，那一次失败是 `windows-voice-controller-listener`；加上更早一轮的 `windows-voice-controller-connection`，这一族在模拟环境下是负载相关而非固定失败，已按仓库既有写法记进基线，免得单轮飘红被当成回归。

**x86 仍是 76/2**（`windows-server-smoke` 与 `windows-session-smoke`），卡在与 x64 同一条渲染断言上。已排除 WIC：32 位探针在同一镜像里取 WIC 成功。原因未定，留作下一轮，不猜。

回顾这条线的全部五道坎，四道是测出来的、一道是我先推错又测正的：prefix 无显示器创建导致 WIC 未注册 → DPI v2 不回传 → DirectComposition 是桩（回退到分层窗口）→ 点击点算在卡片坐标系却当客户区坐标发 → `ReleaseCapture` 先于读取按下 → WIC 被当成硬性前提。其中**后两条是产品缺陷，会影响真实 Windows 用户**，其余是环境或测试自身的问题。

增量记录（2026-09-20，Windows 第三十四批：x86 那两条的原因查定）：上一批留下「x86 仍是 76/2，原因未定」。查定了，是 Wine 32 位与 64 位之间的不对称。

分层回退在 x86 上建不起来：Wine 的 32 位 Direct2D 对 `CreateDCRenderTarget` 返回 `DXGI_ERROR_UNSUPPORTED`（`0x887A0004`），用 `D2D1_RENDER_TARGET_TYPE_DEFAULT` 与 `_SOFTWARE` 都一样；同一镜像里编成 64 位的同一段代码则成功。于是需要真正绘制的那两个套件在 x86 上失败、在 x64 上通过。

**不是 WIC**：32 位探针在同一镜像里取 WIC 成功，这一条先排除了。

有一条可能的出路是改用 WIC 位图渲染目标再拷进 DIB——但那会把刚刚从这条路径上摘掉的 COM 依赖又装回去，而收益只在 Wine。因此记录而不做：这是明确的取舍，不是没想到。

至此两个架构的状态是 x64 78/78、x86 76/78，两边剩余项的原因都精确到具体 API 与错误码，没有一条写着「环境所限」四个字了事。

## 来源模块的落点

逐模块记下来源的每个目录在本仓库落在哪里，以及为什么。上面那张功能表按「功能组」组织，回答的是某个功能有没有；这张按**来源的源码目录**组织，回答的是来源的每一块代码去了哪儿——两者互相校验，一块代码找不到落点就是缺口，哪怕对应功能在表里被标成有。

### TSF DLL：逐文件对应

来源 `windows/src/` 下 38 个 `.cpp`，本仓库 `platforms/windows/tsf/` 全部都有，同名同目录结构。另有 6 个来源没有的：`EngineResponse.cpp`、`EngineSessionAdapter.cpp`、`HostOptionsPaths.cpp`、`PreparedHostOptions.cpp`、`Global/TsfPropertyGuids.cpp`、`Thread/ThreadState.cpp`——它们是进程边界带来的，来源把 Engine 放在同进程，这边 TIP 要通过契约与 Server 对话。再加一套来源没有的 TSF 测试（`tsf/tests/`，19 个）。

### Server：按目的地分三类

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
| `user-dictionary-replay/` | `crates/engine-bridge`（`replay_user_dictionary`） | 词库维护跨平台共享 |
| `settings/`、`webview2/`、`emoji-panel/`、`keyboard-panel/`、`handwriting-panel/` | Tauri 壳（`apps/desktop/`、`packages/ui/`） | 「公共功能+UI 放 tauri」；来源用 WebView2 自绘，这边两个桌面宿主共用同一个 Tauri 应用，入口契约见 `ShellSurfaces.h` |
| `utils/` | 分散在对应模块 | 工具函数不单独成目录 |

来源有而本仓库有意不做的只有一项：`webview2/` 作为**候选窗**的可选渲染后端。这边候选窗只有 Direct2D 一种实现，`ui_backend` 作为配置契约保留（已登记在字段漂移门禁的 `RUST_ONLY`）。

## 下一批实施顺序

增量记录（2026-09-20，HarmonyOS 异步桥回推通道）：`#3236` 只恢复了无参数的同步方法，六个带参数、要做网络往返的方法仍然是坏的：`asyncMethodList` 与另一条官方异步注册路径在本 API 等级上都会挂住，页面等不到任何 settle。本片改为页面**同步**发起 `startRequest(kind, id, payload)`，宿主做完异步工作后用 `runJavaScript` 按请求号把结果回推，页面侧以请求号匹配 pending promise，30 秒超时。恢复的六条：`account`、`cloud_dictionary`、`cloud_dictionary_snapshot`、`ai_models`、`ai_test`、`api_credential`。

设备证据（MateBook Pro 2in1 模拟器，HarmonyOS 6.0.1(21)）：设置页加载正常；「我的」页点「刷新登录方式」后 NETSTACK 记录到一次真实 HTTPS 往返（`RespCode:200`，45 ms），即请求腿把异步工作真的发了出去。回包腿的直接观测在 AI 辅助页取得：把接口地址填成不可达的 `https://127.0.0.1:1/v1` 并填入 token 后点「获取模型列表」，宿主 `aiModels()` 捕获连接失败（`os_errno 111`，`curl_code 7`）并返回 `{ok:false,error:'ai_models_unavailable'}`，该字符串经 `runJavaScript` 回推后由页面渲染在「服务模型」区。请求与回包两腿都有设备证据。

该次测试中窗口一度整片变黑。这不是页面或进程故障：两个 `app.msime.client:render` 进程始终存活，faultlog 无新条目，宿主磁盘处于 98% 且模拟器 GL 交换管道掉到 3 KB/s（`DGLES d_eglSwapBuffers_special`），移动窗口即完整重绘、之前注入的点击也都已生效。记为模拟器合成卡顿，与本片改动无关；与本会话早先那次被误判为「显示层故障」的是同一个宿主磁盘条件。

本片发现但未修的一类缺陷：`apps/harmony/src/main.tsx` 的 `unwrap` 以 `new Error(reply.error)` 抛出，而共享 UI 解码错误的主契约是普通对象上的 `error.code`（桌面端 Tauri 的 `CommandError { code }`）。后果有三处已确认：`packages/ui/src/index.tsx` 的 `message()` 先判 `instanceof Error` 再查 code 表，所以偏好保存冲突在本宿主显示宿主返回的原文而不是「设置已在其他窗口修改。请重新读取后再保存。」；`packages/ui/src/account/account-page.tsx` 的 `accountMessage()` 要求 `"code" in error`，而 `Error` 实例没有该属性，于是全部账号失败一律落到泛化的「账号服务暂不可用，请稍后再试。」；AI 取模型失败在本宿主显示机器码 `ai_models_unavailable`，桌面显示中文兜底。影响面是 `main.tsx` 里全部 25 处 `unwrap` 调用点，不限于本片恢复的路径。下一片按桌面契约把 reject 形状改为 `{ code }`。

增量记录（2026-09-20，HarmonyOS 首次设备运行）：目标 `21da4a315`。此前 HarmonyOS 一栏的全部结论都只有源码与构建证据，本次首次在模拟器上实际运行，证据等级随之改变。

环境为 DevEco 自带的 HarmonyOS 6.0.1(21) phone 镜像，与项目 `compileSdkVersion` 一致；`bm install` 接受未签名 HAP。干净安装后启用输入法，本宿主日志域输出为：`module loaded` → `staged .../files/engine` → `session 1 created` → `panel ready: phone, soft keyboard`，系统侧返回 `Succeeded in enabling IME. status:FULL_EXPERIENCE_MODE`。即 ArkTS → NAPI → Rust → C++ Engine 整条链在设备上可用，Engine 会话与软键盘面板均真实创建。三个 ABI 的原生库均已构建，HAP 含全部 `libs/<abi>/`。

该次运行同时暴露并修复了一个只有在设备上才会出现的缺陷：暂存标记只记录"已暂存"而不记录暂存的是哪一代资源，因此包内资源更新后永不重新拷出，而共享校验对暂存目录做逐项精确比对，陈旧副本不是"旧"而是被直接拒绝（`existing resource generation has unexpected files`），键盘因此拒绝启动。设置页与键盘扩展此前各有一套规则写同一目录，也会留下已从资源集中移除的文件。现统一为一份按包内清单计算代次的实现。

补充（同日稍后）：磁盘恢复后重启模拟器，解锁屏幕并成功切换，`ime -g` 返回 `The current input method is: app.msime.client, status: FULL_EXPERIENCE_MODE`，即系统已把本输入法设为当前输入法。修复后的按代次暂存逻辑在设备上也已生效（日志出现 `staged .../files/engine`）。

仍未取得证据：把焦点交给真实编辑器后输入并上屏。该模拟器实例的 sceneboard 反复卡死（faultlog 中有多条 `sysfreeze-com.ohos.sceneboard`），`aa start` 报成功但画面不刷新，注入的触摸事件也不落到图标上，因此无法让任一编辑器取得焦点；输入法扩展在没有编辑器请求前不会被系统拉起。另仍未取得证据、焦点与选区、生命周期、真机签名与安装、麦克风授权流程。被系统启用并绘出面板不等于输入验收，这一栏不据此宣称平台接入完成。

增量记录（2026-09-20，HarmonyOS 第二批）：目标 `a09527a29`。来源对象为本地 `MSIME-Windows` 检出 `997fdfd9cb27ebbf3a8f998cdefae3274eb5deb9` 的 `README.md`「功能简介」「核心功能指南」，以及目标仓库内 `platforms/linux/src/core/ClientEngine.cpp` 与 `platforms/android/java/` 中已实现的同源行为；来源远端默认分支当前为 `1e4c331d5a7d62b1f219fcc0979a89dd5ead7309`，本批未读取该提交的新增内容，因此不把其后的任何变化计入。

本批补齐的来源功能：(1) 2in1 硬件键盘的五个语音快捷键（右 Alt 长按、Ctrl+Win、Ctrl+右 Alt、空格锁定、Ctrl+F9 开停、Esc 取消），共享设置页一直显示这五个 `voice_input.hotkey_*` 开关而本宿主一个都不消费；空格与 Esc 只在录音期间占用。(2) `Ctrl+Shift+E`、`Ctrl+Shift+Space`、`Ctrl+.` 三个模式快捷键，与 Linux 宿主同源，且和来源一样不受设置页那四项可关闭绑定的影响。(3) 直接英文输入的只读英文补全，走共享 `msime_client_english_completions_request`（此前 NAPI 未导出），全角字母归一为 ASCII，少于两字母不查询。(4) 录音设备选择：HTTP ASR 与豆包各自建流，故可用 `AudioSessionManager.selectMediaInputDevice` 路由；标识为设备类型加地址，缺失时回落系统默认，不把别的平台 backend 重解释为本平台设备。(5) 按应用记忆中英文状态（编辑器属性自 API 14 带 `bundleName`），映射不落盘、上限 64 个应用。(6) 切换到日语时写入 `last_chinese_scheme`。(7) 工具栏设置按钮可关闭；`Ctrl+Shift+Alt+1–8` 删除候选，来源不允许删除的候选来源仍拒绝执行但按键保持被占用。

本批修正的一类缺陷：共享设置页多处控件按平台名而非能力位判断，导致本宿主已经消费的偏好用户无法修改——候选英文字体、英文补全开关、双拼预编辑、模糊音/触摸方案列表/自定义皮肤/离线释义四个板块，均改为 `HostCapabilities` 能力位；同类问题在五笔剩余编码提示与离线释义上表现为宿主侧写死 `true`，离线释义的共享默认为关闭，等于未经询问即显示。

验证边界：全部切片通过 `hvigorw assembleHap`、`platforms/harmony/tests/run.sh` 与 `scripts/verify-local.sh --quick`；`msime-client-core` 对 `aarch64-unknown-linux-ohos` 的 `cargo check` 通过。`msime-engine-bridge` 要求 `MSIME_OHOS_DEPS` 指向为设备编译的 sqlite3 前缀，仓库不携带 amalgamation 也无固定来源，故 NAPI 动态库未构建，当前 HAP 不含 `entry/libs/<abi>/`。无 HarmonyOS 真机或模拟器运行，平台接入未完成。

增量记录（2026-09-19，HarmonyOS 批次）：目标起点 `55d3e531d`，逐项结果如下。(1) `hvigorw assembleHap` 在 develop 上以 33 个 ArkTS 编译错误失败，即 HarmonyOS 宿主有一段时间根本打不出包；本地没有任何检查会发现，因为 `platforms/harmony/tests/run.sh` 和所有 TypeScript 检查只编译 `.ts`，承载全部 ArkUI 代码的 `.ets` 只有打包这一步会编译。已修复并在 README 记为必跑门。其中两个错误是被漏掉的构建掩盖的真实缺陷：默认 `KeyboardPreferences` 记录缺 `voiceTheme` 与 `enabledSchemes`；`CandidateManagementAction.candidateActionsAvailable` 收的是方案名而视图持有的是 Engine 数字 id，于是 `scheme === 'japanese'` 这条守卫从未生效，日语候选会显示 Host API 必然拒绝的词库管理项。(2) `wubi_code_hint` 与 `candidate_english_gloss` 此前写死为 `true`；离线释义的共享默认是关闭，因此每台设备都在没被询问的情况下显示。(3) `input_mode_hud` 完全未消费，共享设置页又把该开关按平台名写死只给 macOS；现改为 `HostCapabilities::input_mode_hud` 能力驱动，macOS 与 Harmony 声明，2in1 徽标只在开启时创建。(4) 键盘选择器从不写 `last_chinese_scheme`，`KeyboardScheme.mapping` 写好却无人调用；从键盘切到日语后设置页的「中文」只能退回 quanpin。(5) 录音设备选择补齐：HTTP ASR 与豆包两条路径各自创建 `AudioCapturer`，因此可通过 `AudioSessionManager.selectMediaInputDevice` 路由；标识用设备类型加地址而非每会话重分配的 `id`，设备缺失或 backend 属于别的平台时回落系统默认，不把 Windows 端点标识重解释为 Harmony 设备。(6) `candidate_english_font` 可保存却不被候选面板读取；现按共享 `resolved-candidate-fonts.ts` 的顺序把英文字体排在中文字体之前，由 ArkUI 逐字形回退。以上均通过 `hvigorw assembleHap`、`platforms/harmony/tests/run.sh` 与 `scripts/verify-local.sh --quick`；没有 HarmonyOS 真机或模拟器运行，平台接入仍未完成。

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

增量记录（2026-09-19）：Fcitx5 状态栏新增候选皮肤循环入口，按 `fluent`、`wechat`、`graphite`、`willow_green` 切换并持久化共享 `candidate_skin` 偏好；切换前结束当前组合，再重建当前输入上下文的 Host API session。Fcitx5/桌面 panel 不一定能表达 Windows 原生候选窗口的全部边框、圆角、alpha、间距等装饰，本切片只同步共享 skin preference，平台 panel 保留不可表达装饰的控制权；原生菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 候选皮肤入口现消费共享 `candidate_skin_catalog` 中经过主机校验的外部皮肤 ID/标题，和 IBus 一样可从内置皮肤循环到外部皮肤；Fcitx5 仅将受限字符集的 ID 与长度受控标题交给 panel，不把外部路径或 CSS 直接注入平台菜单。原生 catalog 读取与桌面交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 运行时 options 刷新现在同步更新候选皮肤 catalog 标题与可循环项；设置页重新扫描外部皮肤后，当前输入上下文的状态入口不会继续显示旧 catalog。该同步仍只更新平台菜单元数据，不把外部 CSS 或路径交给 Fcitx panel。

增量记录（2026-09-19）：Fcitx5 会话创建时现在加载共享 PreferencesStore 的 revision 快照，状态栏中需要原子偏好更新的动作（如候选主题）不再因缺少 revision 而静默失败；快照读取失败时仍保留已准备的输入会话，动作会等待后续偏好存储恢复。

增量记录（2026-09-19）：Fcitx5 偏好热重载现在将全局 revision 快照与当前输入上下文 override 分开处理；全局设置刷新不会覆盖当前上下文的输入方案、双拼 profile、辅助码 schema 或候选皮肤，且更新 Engine 时仍使用带 override 的有效快照。

增量记录（2026-09-19）：Fcitx5 状态动作在成功更新共享偏好后也会重新套用当前上下文 override，避免切换候选主题、标点、混输或其他设置时把该上下文的方案/皮肤状态意外恢复为全局值。

增量记录（2026-09-19）：Fcitx5 状态动作发送给 Host API 的偏好快照现在也包含当前上下文 override；持久化仍只写全局 PreferencesStore 字段，因此 Engine 有效配置与跨上下文共享配置保持分离。

增量记录（2026-09-19）：Fcitx5 候选布局与模式范围动作现在通过 Host API 即时更新当前会话并重绘候选面板，不再只写偏好文件后等待下一次会话创建；上下文 override 与全局持久化边界保持不变。

增量记录（2026-09-19）：Fcitx5 云候选、AI 联想、候选翻译开关和翻译目标语言动作现在通过统一有效偏好快照即时更新当前 Engine，再清理对应旧结果并重绘；持久化仍只修改共享偏好字段。

增量记录（2026-09-19）：Fcitx5“学习用户词频”动作现在通过有效偏好快照即时更新 Engine，不再只修改本地状态与偏好文件；切换后当前会话立即采用新的学习策略。

增量记录（2026-09-19）：Fcitx5 通过专用 Host API 更新九键布局、候选页大小、中文/成对标点和标点锁定后，会同步更新内存偏好快照，避免后续其他动作使用旧快照覆盖刚生效的值。

增量记录（2026-09-19）：Fcitx5 辅助码状态栏入口现在按蓝天、自然码、搜狗 2.0、搜狗 Plus、小鹤循环选择，分别作用于全拼/双拼对应的 helpcode 配置；切换前结束组合并用上下文级 override 重建 session，同时持久化共享 schema。原生菜单交互仍待 Linux 环境验证。

增量记录（2026-09-19）：Fcitx5 状态栏现提供 Unicode、日期时间、快捷短语、Emoji、颜文字、超级简拼、临时英文、临时日文八个本地输入模式开关；开关通过共享 `local_modes` 偏好快照即时更新 Engine，并持久化对应字段。原生 Fcitx5 菜单交互仍待 Linux 环境验证。

增量记录（2026-09-18）：Windows Tauri 语音取消命令现在按 `request_id` 从共享会话表退休对应会话；重复或未知请求保持幂等，不再让已取消的会话继续占用后续录音/识别生命周期。该修复已合入 `develop`（`e61f67bc`）；仍需 Windows 原生麦克风、取消竞态和真实编辑器上屏验证。

增量记录（2026-09-18）：Windows Tauri Emoji/剪贴板提交在真正写入前重新捕获当前外部前台窗口；识别或面板停留期间切换编辑器时，不再把文本粘贴到打开面板时的旧目标。面板自身仍在前台时保留原目标；仍需 Windows 原生剪贴板、Emoji 面板和真实编辑器验证。

增量记录（2026-09-18）：Windows 候选翻译 worker 现在在偏好热更新后没有可用翻译请求时，异步清空正/负缓存并推进请求序列；进行中的结果会被视为过期，重新启用翻译或切换提供方不会被旧的负缓存阻塞。目标 C++ 代码已通过格式与差异检查；完整 Windows 原生 provider/编辑器交互仍待验证。

增量记录（2026-09-19）：Linux IBus 与 Fcitx5 现接入 Windows 候选翻译快捷语义。候选页存在有效高亮译文时，Ctrl+Enter 提交当前已渲染译文并结束 Engine 组合；没有译文时仍将组合交给应用。IBus 通过 session/generation 与最近渲染候选身份校验，Fcitx5 使用其原生候选页的同一份共享 View；两者不伪造 Windows 的多译义副候选窗口。Linux 两个宿主同时接入 Ctrl+Backspace、Ctrl+Left、Ctrl+Right 的共享分段编辑命令。合成 provider/Engine bridge 回归已通过，原生 IBus/Fcitx5 桌面验证仍需 Linux 环境执行。

增量记录（目标基线之后）：Windows `ai.assistant` / `voice.polish` 已从共享设置按钮接到 Tauri `test_api_credential` 的 Windows 分支及 `client-core::credential::probe`。共享实现注入传输，生产 HTTPS 请求禁用重定向，5 秒连接/15 秒总时限、256 KiB 响应上限，公开错误不携带响应原文。Linux provider 路径保持不变。ASR（OpenAI、SiliconFlow、Groq、Doubao、system）与三类翻译凭据测试现均经过 Tauri 命令路由，桌面命令回归覆盖无凭据分类；合成请求测试和共享模块 Windows 交叉检查不能替代 Windows 原生设置窗口或真实服务验证。上表的明确缺口描述保留为固定目标提交时的状态。

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

Fcitx5 全角/半角动作增量（2026-09-19）：状态动作现在同时更新 Engine 运行时、有效偏好快照和持久化的 `character_width`（`fullwidth` / `halfwidth`），并覆盖原生 fixture 的即时生效与保存回读。此项不代表 Linux 原生桌面构建或交互验证已完成。

Fcitx5 繁体输出动作增量（2026-09-19）：状态动作现在同步 `traditional_chinese_output` 的当前上下文内存快照、revision 快照和持久化字段，避免后续偏好动作用旧快照覆盖当前繁体状态；原生 Linux 桌面构建与交互验证仍待相应环境。

Fcitx5 英文模式标签增量（2026-09-19）：状态栏中切换 Engine dedicated-English 模式的动作改为显示“英文输入模式”，与 IBus/Windows 语义区分于“英文候选”混输开关；动作 ID 与现有键绑定保持兼容。

Fcitx5 偏好保存串行化增量（2026-09-19）：多个状态动作连续修改共享 PreferencesStore 时，现在等待前一个异步 revision 保存完成再启动下一个，避免并发读取同一 revision 导致后一次字段更新丢失；原生 fixture 覆盖连续全角/半角切换的最终值。

Fcitx5 会话重建动作增量（2026-09-19）：方案、双拼 profile、辅助码 schema 和候选皮肤切换现在在重建当前输入上下文前等待对应偏好保存完成，避免新会话从尚未落盘的旧配置读取并短暂恢复旧状态。

Fcitx5 候选操作增量（2026-09-19）：未固定候选不再发布可执行的“取消固定” CandidateAction；只有候选已有固定位置时才提供该动作，匹配 IBus 菜单的禁用语义并避免面板误导用户。

Fcitx5 语音取消增量（2026-09-19）：取消或失焦关闭语音时不再直接销毁仍在运行的异步 provider future；先发送取消请求并标记结果丢弃，future 完成后由事件循环回收，避免 `std::future` 析构在输入线程同步等待网络任务。新的语音请求会等待旧任务完成并丢弃其结果，防止重叠会话。

Fcitx5 语音取消 fixture 增量（2026-09-19）：native fixture 新增合成延迟 provider future，验证取消入口在 100ms 内返回、延迟结果异步回收且不会提交文本；不使用真实音频、凭据或网络。

Fcitx5 候选管理边界增量（2026-09-19）：原生 CandidateAction 现在只对全拼/双拼/英文词典中可写入的候选发布固定、删除和位置操作；云候选、AI、Emoji、日文及其他只读来源不再显示会被 Host API 拒绝的管理入口，与 IBus 菜单和共享词典策略一致。

Fcitx5 候选 stale 栅栏增量（2026-09-19）：CandidateAction 的可见性现在同时校验当前焦点、输入启用状态、受限/私密上下文、session 和 generation；失焦或面板滞后的旧候选不会继续显示管理入口。

Fcitx5 剪贴板历史读取 stale 栅栏增量（2026-09-19）：异步本地剪贴板历史读取现在绑定请求路径与 clipboard generation；会话关闭、路径切换或禁用历史时会使旧结果失效，避免旧配置的条目污染新输入上下文。原生 Linux 桌面构建与交互验证仍待相应环境。

Fcitx5 云剪贴板读取 stale 栅栏增量（2026-09-19）：异步云剪贴板 provider 读取现在绑定 provider socket 与 generation；会话关闭或 provider 配置切换时，旧 provider 响应不会写入当前输入上下文。原生 Linux 桌面构建与云 provider 交互验证仍待相应环境。

Fcitx5 Emoji 目录读取 stale 栅栏增量（2026-09-19）：Emoji 条目与分组异步查询现在绑定当前会话 generation；会话关闭后，即使旧搜索词相同，旧目录结果也不会重新填充当前缓存。原生 Linux 桌面构建与 Emoji 交互验证仍待相应环境。

Fcitx5 剪贴板菜单预览增量（2026-09-19）：剪贴板与云剪贴板菜单标签现在按 UTF-8 字符边界截断，不再用字节截断导致中文或 Emoji 标签损坏；非法 UTF-8 输入只显示安全省略号。原生 Linux 桌面菜单交互仍待相应环境。

Fcitx5 在线候选来源隔离增量（2026-09-19）：云候选与 AI provider 请求现在只接受匹配当前请求槽位的 `source`，不再把一次 provider 响应中的另一来源候选跨槽位注入；与 IBus 的来源过滤一致。原生 Linux provider 交互仍待相应环境。

Fcitx5 候选动作执行 stale 栅栏增量（2026-09-19）：CandidateAction 触发时重新枚举动作现在也校验当前焦点、输入启用状态、受限/私密上下文，避免菜单创建后状态变化仍执行旧候选管理操作；原生 Linux 桌面构建与交互验证仍待相应环境。
