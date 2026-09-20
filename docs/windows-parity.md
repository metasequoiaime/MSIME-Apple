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
| 候选分页、高亮、调频、preedit、以词定字 | README 候选调频/preedit/标点指南 | `CandidateWindow.cpp`、`CandidateAction.h`、`SessionController.cpp`、`ReplyCodec.cpp`；Linux `ClientEngine.cpp` | 有调用链；Linux IBus 候选操作菜单现提供上一页/下一页并复用共享分页命令，调频持久化已用锁定词库覆盖三个半边——跨会话记住、关掉就不写、重置回出厂顺序（`crates/engine-bridge/examples/learning_dictionary.rs`，见第八批）；翻页现在能越过 Engine 对单字母查询的初始上限（第九批）；以词定字已按两端取字、三字候选、组合被消耗、无汉字候选与越界索引覆盖（第十四批）；调频五种模式各走各的规则已逐条核对（第十三批）；分页键、鼠标滚轮与旧候选请求拒绝三项已核对（第四十一批），均有用例；本行到此走完。 |
| 中英文状态、独立英文候选、全半角、简繁、智能标点 | `server/src/english/`、设置 `input.ts` / `shortcut.ts` | `SharedConfigKeybindings.h`、`PunctuationPolicy.h`、`ReplyCodec.h` 中的 TsfLocalConfig、共享偏好与 Engine 桥接 | 已补齐 TSF client key-router 边界、IPC `Sent` / `DefinitelyNotSent` / `DeliveryAmbiguous` 三态 fallback、标点配置帧及宿主进程策略回归；五项已逐个核对（第四十批）：按应用/全局状态有纯决策函数与 `mode_authority` 用例；标点重复与成对补全随配置帧下发并由 `tsf_config_frames` 钉住；热更新有 `preference_monitor` 用例；CapsLock 由 Server 持有并经 `CapsLockChanged` 帧下发，帧本身已在第四十二批补上用例。 |
| K/T/U/E/M/J/Y/R 快捷模式、混输 | README 实用功能快捷模式 | Engine 桥接、共享偏好、`platforms/windows/src/ipc/ServerSession.cpp` 及 `platforms/windows/tests/runtime/session_smoke.cpp` | 已补带锁定词库的 ServerSession 回归：八种快捷模式均验证 Shift 入口、候选生成和选词提交；仍需 Windows 原生 TSF/真实编辑器交互验证。 |
| 谷歌云候选与 AI 联想 | README 云/AI 联想、设置 `ai-settings.ts` | `CloudCandidateWorker.cpp`、`AiCandidateWorker.cpp`，由 `SessionController.cpp` 构造并投递输入队列 | 有调用链；核对每个提供方、超时、取消、失焦后旧结果以及凭据路由，勿只验证 UI 保存。 |
| 候选中英释义、腾讯云翻译、自定义翻译 | README 候选翻译/自定义翻译 | `TranslationWorker.cpp` → `SessionController.cpp` → 候选展示；共享 `translation.rs` / `translation_store.rs` | 有调用链；缓存失效已核对并确认做到（第三十六批）：缓存键按服务商与账号分域，凭据、端点、目标语言与启用开关任一变化都丢弃正负两种结果；腾讯请求签名已按官方 TC3-HMAC-SHA256 构造独立算出已知答案并钉住（第三十七批）；本地优先级已按源码核对为正确实现但**零测试覆盖**（第三十八批）；词库编辑已核对（第三十九批）：设置侧有五个按 Engine 实际读取语义写的用例，消费侧每次请求现算本地释义，编辑立即生效且恒胜过缓存的云端结果。本行四项到此走完。 |
| 设置读取、保存、热更新与窗口行为 | `settings_app.cpp`、`config-sync.ts` | Tauri `load_preferences` / `save_preferences`，`PreferenceMonitor.cpp` 与 `main.cpp` 发布回调；macOS 云端桌面快照覆盖 Apple 20 项基线字段并保留客户端新增双拼预编辑字段 | 有调用链；逐字段核对默认值、冲突/损坏保护、当前组合期间延迟生效。macOS 云端快照现补齐两套辅助码方案、候选学习和本地扩展模式；本地扩展的兼容布尔值应用为八个本地模式的全开/全关。原生备用语音现在读取并回写当前 provider 的 `asr_tokens` / `polish_tokens` 槽位，缺失槽位保留旧扁平字段兼容。不能因配置字段存在就标记功能接通。 |
| API 凭据测试（**本仓库新增，来源没有此功能**） | 来源无对应物；`settings/settings_app.cpp` 存在但不含凭据测试 | Tauri `test_api_credential` → `client-core::credential_*`（Windows/macOS） | 有调用链；Windows 已接入聊天、批量 ASR、豆包 WebSocket、腾讯云/NiuTrans/DeepLX 等共享凭据测试。**「逐项核对来源字段」一项已撤销（第五十二批）——来源没有可比的字段**；仅「真实服务行为」仍需真实账号验证。 |
| 词库查询、增改删、导入导出、快捷短语 | `dictionary_manager.cpp`、设置 `dict.ts` / `tools-settings.ts` | Tauri `dictionary_request` / `dictionary_maintenance_handshake`，共享 `dictionary/access.rs` / `dictionary/import.rs` | 有调用链；验证 quiesce/resume、失败恢复、五笔/英文/快捷短语/翻译各表的字段和导出编码，保留用户数据。 |
| 语音热键、流式/批量 ASR、润色、声音/静音、上屏方式 | `server/src/voice-input/`、设置 `voice.ts` | `main.cpp` → `VoiceHotkeyController` / `VoiceInputSession` → Engine 语音模块与 TSF；`VoiceSessionEpoch.h` | Windows Tauri 语音面板与 `recognize_voice` 已接入；全提供方、取消及焦点行为仍需 Windows 原生验证。macOS 原生备用窗口已将有效非云快照字段回写共享 `voice_input`，并可编辑 ASR/润色 provider token 槽位，但真实系统链路仍需验证。 |
| 录音设备选择 | 需继续比对来源具体支持范围，不假定来源已支持 | Tauri `list_voice_capture_devices` → `host-macos::voice_capture_devices` → `MSIMEListVoiceCaptureDevices` 与共享 `capture_device/capture_backend`；Windows `VoiceInputConfig` / `VoiceInputSession` | Windows 已按稳定设备 ID 完成枚举、偏好保存和 `AudioCapture::start(..., device_id)` 透传，并有 `voice_capture_selection` 覆盖 backend/device 选择；macOS Tauri 与原生备用设置现在共用 CoreAudio 输入流枚举、默认设备排序和稳定 UID，且只接受空值、`auto`、`macos` 进入 CoreAudio，拒绝把其他平台后端静默重解释为 CoreAudio。真实硬件权限、安装后切换及来源设备标识范围仍待产品级验证。 |
| 手写 | 来源设置 `handwriting-settings.ts` 和模型资源 | `ShellSurfaces.h` / `main.cpp` → Tauri `recognize_handwriting` / `submit_handwriting_candidate`，共享 `panels.tsx` | 有目的地入口；比较模型打包、笔画缩放、撤销/清空、多候选及原编辑器上屏。 |
 | 屏幕键盘 | 来源面板 `server/src/keyboard-panel/KeyboardPanel.cpp`（设置页 `screenkb-settings.ts` 只是入口按钮） | `main.cpp` → Tauri keyboard route、`desktop-keyboard.tsx`、Windows `send_key` 分支；macOS Tauri 与原生备用键盘都在每次按键时读取当前前台编辑器，并在实际投递前重新校验身份；无 Accessibility 权限时只拒绝投递、不弹权限请求；Tauri 面板仍捕获 PID+启动时间用于生命周期恢复 | macOS 键盘路径不再把当前设置宿主误当成输入目标，也不会在用户切换编辑器后继续投递到旧窗口；共享 Tauri 面板与原生备用面板的普通键均按 450ms 首次延迟、75ms 间隔自动重复，粘滞修饰键与 Num Lock 保持单次切换且键盘/辅助功能激活仍为单次发送；投递失败、失焦或关闭会停止重复且不自动重放；macOS Tauri 首次显示和隐藏后重开时按当前/主显示器的物理工作区底部居中，兼容负坐标、多显示器和 Retina 缩放。修饰键按下/释放语义已逐项核对并确认一致（第五十批）：扩展键集合与来源逐键相同，按下/抬起标志有正反两面的用例；布局已逐键比对（第五十一批）：修饰键排完全一致，目标为超集（多出 F10–F12、PrtSc/Scroll/Pause、导航簇与 Menu 键）；仅真实焦点恢复仍需原生验证。 |
| Emoji、颜文字、符号、剪贴板历史 | README 与来源 `clipboard_history.cpp` | `ClipboardMonitor.cpp` / `ClipboardHistory.cpp`、Tauri `load_emoji_catalog` / `paste_clipboard_text`、共享 `panels.tsx` | macOS 常驻输入源与 Tauri 监视器现按 NSPasteboard `changeCount` 读取外部文本变化，共用 4000 UTF-16 单位、12000 UTF-8 字节边界，并复用共享 50 条历史、去重/置顶和开关清理；关闭历史时不读取剪贴板内容。Emoji 面板通过已认证的一次性桌面输入会话把记录定向提交回原应用，普通 Emoji 候选与剪贴板大文本使用独立校验模式。仍需核对安装后真实持续监视与目标窗口行为，不能以普通 SendInput 冒充会话定向提交。 |
| 悬浮工具栏、托盘菜单、入口快捷键 | 来源 `window/*presenter*`、`ui-html/webview2/ftb` / `menu` | `FloatingToolbarWindow.cpp`、`TrayMenuWindow.cpp`、`MaintenanceHotkey.cpp`、`ShellSurfaces.h` / `ShellLauncher.cpp` | 有调用链；设置/手写/键盘/语音/云剪贴板/云词库等启动共享 Tauri，低延迟不抢焦点宿主保留原生。macOS 与 Tauri 预览现消费 `floating_toolbar.english_mode` 及其余组件开关，原生共享偏好合并也保留该字段并按可见组件重算宽度；菜单项与禁用条件已逐项比对（第四十三批）：动作一一对应且目标多出手写识别板；工具栏组件与来源 README 所列六项一一对应；禁用语义是进程边界带来的有意差异，已记录。 |
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

增量记录（2026-09-20，Windows 第三十五批：更正一个我自己报出去的数字）：上一批我说 x64 在 Wine 下 78/78 全部通过。**那个数字是对的，但它的含义比我说的窄**——`msimeui-tests` 根本没被跑到。

CMake 把它产出到 `bin/` 子目录，而 runner 的通配符找的是与其余可执行文件同级的位置，于是**那个模式什么都没匹配上，整套测试在每一次计数里都不存在**。我在给自己加的分层回退补测试时，去确认「既有的合成用例是否已覆盖它」，才发现这个套件压根没跑。

补上之后它**失败**：35 个用例里跑过 18 个，然后进程死于 `rosetta error: invalid gdt selector index 5`。通过的那些是布局类用例，停下的位置是需要真实 DirectWrite 与 Direct2D 设备的那组——**是 arm64 主机模拟 x86_64 的问题，不是 Wine，也不是产品**。x86_64 主机上很可能走得更远，基线只记这台机器的实际情况。

所以正确的说法是：**x64 在 Wine 下 78 通过 / 1 失败**，那一条是此前静默缺席的 `msimeui-tests`。它不是新坏的，只是终于可见了。

这条教训和之前几次同形，但方向相反：前几次是「断言从未被执行过所以是错的」，这次是「**整套测试从未被执行过，而计数看起来完全正常**」。一个通配符匹配不到东西时不会报错，只会安静地少跑一批——比断言写错更难发现。

增量记录（2026-09-20，Windows 第三十六批：核清一条过时的「仍需核对」）：表里翻译那行写着「仍需比较本地优先级、腾讯请求签名、词库编辑与缓存失效」。其中**缓存失效已经做到了**，描述过时。

`TranslationWorker` 给缓存键加了服务商域：小牛按 `niutrans:<app_id>`（源码注释写明「切换账号不能复用别人的译文，而密钥本身绝不进入缓存键」），自定义按 `custom:<endpoint>`，腾讯为 `tencent`。`SessionController` 在凭据、端点、目标语言或启用开关变化时调用 `clear_cache()`，并且注释写明要连负缓存一起丢——「即使候选页仍然合格」。

本批只改这一行描述，不动代码。另外两项（本地优先级、腾讯请求签名）仍未核对，保留在表里。

增量记录（2026-09-20，Windows 第三十七批：腾讯签名从「自证」改成「已知答案」）：表里剩下的两项之一是腾讯请求签名。现有测试只验三件事——同输入同输出、不同输入不同输出、长度 64。**一个算错但稳定的实现能全部通过**，因为它拿这段代码跟它自己比。

按腾讯公开的 TC3-HMAC-SHA256 构造（`HMAC(HMAC(HMAC("TC3"+key, date), service), "tc3_request")`）在这段代码之外独立算出期望值，钉住三样：派生签名、载荷摘要、以及**整个 Authorization 头**——后者把凭据作用域与签名头列表一并钉住，因为请求被拒可能源于这三者中的任何一个。

做了反向验证：把实现里的 `"tc3_request"` 改成 `"tc3_reques"`，**只有新测试失败**（7 通过 / 1 失败），原有的确定性测试在错误实现上照常通过。恢复后 8 个全过。这正是自证型测试抓不住的那类改动。

表里那行剩下本地优先级与词库编辑两项，仍未核对。

增量记录（2026-09-20，Windows 第三十八批：本地优先级是对的，但一行测试都没有）：表里剩下的「本地优先级」按源码核对结果是**实现正确**。`TranslationWorker` 先把已有译文的候选收进 `translated_texts`，再遍历 `custom_translation_plan` 的结果，对已在集合中的条目 `continue`——本地命中既不会被重复拿去问云端，也不会被云端结果覆盖。源码注释写明这是「保留本地词典命中、只对未命中的去问云端」，并点出错误做法是「把一条离线命中当成整页」。

但它**没有任何测试**：`platforms/windows/tests/` 下没有一个文件引用 `TranslationWorker`。共享侧的 `custom_translation_plan` 有测试，覆盖的是去重、来源筛选、语向与长度限制——请求里根本不带已有译文，所以那条合并规则不在它的覆盖范围内。

正确的做法是把这段合并判据抽成纯函数（`CandidateTranslationPolicy.h` 就是现成的去处）再钉住。**本批没有做**：那是对线上 worker 的行为性改动，而本机的 Docker 守护进程已停（见下一段），Windows 套件跑不起来。不做无法验证的改动，这一条按未覆盖记录，等能跑套件时再补。

顺带记下本机状态：本轮密集的容器构建与多份词库下载把磁盘撑满（一度只剩 119 MB），OrbStack 因此停止，不是它自身故障。已清理自己产生的临时文件与主工作区的 `target/windows-full`；未触碰其他任务的 worktree 与正在被使用的共享 vcpkg 依赖树。跨检出共享依赖的机制仓库本来就有，本轮在主机侧没有充分利用，是这次资源耗尽的直接原因。

增量记录（2026-09-20，Windows 第三十九批：翻译那一行的四项全部走完）：表里这行原写着「仍需比较本地优先级、腾讯请求签名、词库编辑与缓存失效」。四项逐个核完：

- **缓存失效**（第三十六批）：已做到，且比那句话要求的细——缓存键按服务商与账号分域，凭据、端点、目标语言、启用开关任一变化丢弃正负两种结果。
- **腾讯请求签名**（第三十七批）：原测试只验确定性与敏感性，算错但稳定的实现照样通过；改为按官方构造独立算出的已知答案，并做了反向验证。
- **本地优先级**（第三十八批）：实现正确，但零测试覆盖，按未覆盖记录，没有做无法验证的改动。
- **词库编辑**（本批）：设置侧有五个用例，且是按 Engine 实际的读取与覆盖语义写的——被 Engine 丢弃的行要计数而不是静默保留、同源多次拼写以最后一次为准。消费侧 `msime_client_candidate_gloss_request` 每次请求现算，带 `user_data` 与 `resources`，所以编辑立即生效；本地结果在 plan 与缓存循环之前填入，因此恒胜过缓存的云端结果。

四项里三项确认做到、一项确认缺测试。这一行不再留「仍需」。

增量记录（2026-09-20，Windows 第四十批：中英文状态那一行的五项逐个核对）：这行原写着「仍需分别核对按应用/全局状态、CapsLock、标点重复、成对补全与热更新」。

**有测试的四项**：按应用/全局状态在 `ModeAuthority.h` 里是一个纯决策函数（失焦不推送、未播种时先由首次观察播种、换客户端时权威胜出且只推不一致者、同客户端改模式则成为新权威），`tests/input/mode_authority.cpp` 覆盖；标点重复（`SmartPunctuationRepeatToChineseChanged`）与成对补全（`PairedPunctuationChanged`）随配置帧下发，`tests/runtime/tsf_config_frames.cpp` 钉住帧序并另外覆盖按进程排除成对补全的策略；热更新由 `PreferenceMonitor` 负责，有 `tests/core/preference_monitor.cpp`。

**只有源码核对、没有专门用例的一项**：CapsLock。Server 以 `GetKeyState(VK_CAPITAL)` 播种、由维护钩子回调更新，再经 `CapsLockChanged` 帧下发；源码注释写明钩子回调只发布状态、绝不碰传输，由主循环投递。这一项按「已实现但缺专门覆盖」记录，与第三十八批的本地优先级同等对待——**不把读过代码算成测过**。

增量记录（2026-09-20，Windows 第四十一批：候选分页那一行的最后三项）：原写着「仍需检查分页键与鼠标行为和旧候选请求拒绝」。三项都有实际覆盖。

**分页键**：`NavigationPolicy.h` 的键映射此前已与来源 `event_listener.cpp` 逐键对照过——减号/等号、逗号/句点、方括号、Tab（Shift 为上一页）、PageUp/PageDown、上下方向键移动选择，语义与来源一致；`tests/input/navigation_policy.cpp` 覆盖。来源侧的五个开关（`paging_minus_equal` 等）在本仓库以 `navigation` 结构体承载，字段一一对应。

**鼠标滚轮**：`consume_candidate_wheel_delta` 是纯函数，`tests/ui/candidate_wheel.cpp` 钉住四条——不足一格的位移要保留、满一格才发出翻页、方向正确映射、反向滚动时清掉残留行程。窗口侧另有一条契约：滚轮翻页未开启时把消息交还默认过程，而不是在这个 NOACTIVATE 窗口上吞掉它。

**旧候选请求拒绝**：`tests/runtime/session_smoke.cpp` 在记下一个代次、让它过期之后，断言用旧代次选词被拒绝。

三项均有用例，本行不再留「仍需」。

增量记录（2026-09-20，Windows 第四十二批：把上一批记为缺覆盖的 CapsLock 补上）：第四十批把 CapsLock 记成「已实现但只有源码核对」。Docker 恢复、Windows 套件能跑之后，按当时说的把它补上。

`caps_lock_frame` 现在有三条断言：帧长与协议结构一致、类型是 `CapsLockChanged`、载荷是 TIP 解析的 `"0"`/`"1"`（不是裸字节，也不是配置帧那种 key=value 形状）。另加一条反向约束——配置帧集合里不得出现 `CapsLockChanged`，免得它哪天被顺手并进那一批。

做了反向验证：把 `caps_lock_frame` 的类型换成 `InputModeChanged`，测试在帧类型那一行失败；恢复后套件回到 78 通过 / 1 失败（唯一那条是基线里已记的 `msimeui-tests`，Rosetta 在 arm64 主机上模拟 x86_64 的崩溃）。

**本地优先级那条没有跟着补，是重新权衡后的决定**：真正值得测的是整个合并过程，而它嵌在 `TranslationWorker` 的循环里，抽出来要重构；只抽一个「集合里有没有」的谓词则证明不了什么。行为今天是正确的，为一条已正确的规则重构只能端到端验证的 worker，风险大于收益。维持记录为未覆盖，不因为「能跑了」就顺手改。

增量记录（2026-09-20，Windows 第四十三批：托盘菜单与工具栏逐项比对）：这行原写着「来源和目标菜单项、禁用条件仍需逐项比对」。

**菜单项**：来源 `ui-html/webview2/menu/default.html` 里的动作共六个——`floatingToggle`、`emojiSymbols`、`keyboardPanel`、`voiceInput`、`settings`、`about`。本仓库 `TrayMenuCommand` 七个，前六个一一对应，多出的是手写识别板（与第二批记的「目标为超集」一致）。

**工具栏组件**：来源 README 写「中英文切换始终显示，其余组件（全角、标点、简繁、表情、屏幕键盘、设置）可按需勾选」，另可调整缩放与图标尺寸。`FloatingToolbarPreferences` 逐项对应：`english_mode`、`fullwidth`、`punctuation`、`character_set`、`emoji`、`screen_keyboard`、`settings`，加上 `scale_percent` 与 `font_size`。

**禁用条件是有意差异，不是缺口**：来源的菜单 HTML 里 `disabled` 出现零次——它的面板全在同进程内，永远可用，所以从不禁用。本仓库的面板在独立的 Tauri 壳里，壳可能不在，于是能力缺失的行**保持可见但置灰**，而不是点了没反应或干脆隐藏。`TrayMenuLayout.h` 的注释写明这个选择的依据正是「与发行版菜单从不隐藏条目一致」——保住来源的可见性语义，同时诚实反映进程边界。

这一行不再留「仍需」。

增量记录（2026-09-20，Windows 第四十四批：核查这张表自己是否完整）：前面四十三批都在核表里的条目，这批核的是**表本身有没有漏掉来源的模块**。

来源 `server/src/` 下 25 个模块，24 个在本表有落点。唯一没有的是 `defines`，里面只有 `base_structures.h`、`defines.h`、`globals.h` 三个头文件，是类型与常量定义而非功能模块，不构成缺口。

顶层目录里 `docs`、`server`、`windows`、`ui`、`ui-html`、`installer`、`scripts`、`tests`、`vendor` 都有落点，**唯独 `experiments` 没有**。它下面是 `tsf-edit-control`：一个基于 Win32 TSF 的编辑控件实验工程，用 Direct2D / DirectWrite 绘制，自带最小宿主 demo，功能包括 preedit 与 display attribute 绘制、候选框位置上报、软换行、选区与鼠标命中。

**这个缺口值得单独记一笔**，因为它不是功能缺口而是**验证工具缺口**：本表里「原生 TSF / 真实编辑器交互验证」这一项之所以一直推迟，缺的正是一个可控的编辑宿主，而来源自带了一个。本仓库 `platforms/windows/msimeui/demos/` 下只有 `msimeui-demo`（绘制 demo），没有对应的 TSF 编辑控件宿主。

本批没有移植它，按「已识别、未移植」记录。**当时给的理由（「Wine 的 TSF 支持不足」）随即被下一批的实测推翻**，见第四十五批：核心链路在 Wine 下完全可用。不移植的理由因此要重述为——该工程用 Direct2D 绘制并依赖真实 TIP 激活，而 TIP 激活这一步尚未用真实 COM 服务器验证过。等那一步过了，它就是现成的起点。


增量记录（2026-09-20，Windows 第四十五批：实测 Wine 的 TSF，推翻一个继承来的假设）：上一批把「原生 TSF / 真实编辑器交互验证」推迟的理由写成「Wine 的 TSF 支持不足」。那是从表里继承的说法，**本轮此前没有人实测过**。这批测了。

容器里的 Wine 带 `msctf.dll`、`msctfmonitor.dll`、`msctfp.dll`、`msimtf.dll`，注册表里有 `HKLM\SOFTWARE\Microsoft\CTF` 及其 `TIP` 子键。用最小探针逐个调用，结果是：

- `CoCreateInstance(CLSID_TF_ThreadMgr)` → S_OK
- `ITfThreadMgr::Activate` → S_OK，拿到 client id
- `CreateDocumentMgr` → S_OK
- `ITfDocumentMgr::CreateContext` → S_OK，拿到编辑 cookie
- `Push` + `SetFocus` + `GetFocus` 往返 → S_OK，取回的正是同一个文档
- `CoCreateInstance(CLSID_TF_InputProcessorProfiles)` → S_OK
- `ITfInputProcessorProfiles::Register` → S_OK
- `AddLanguageProfile` → S_OK
- `ActivateLanguageProfile` → **E_INVALIDARG**

**结论要分两半说，不能含糊。** 文档管理器、编辑上下文、编辑 cookie、焦点往返这条核心链路在 Wine 下完全可用，所以「Wine 的 TSF 不足以承载一个编辑宿主」这个说法，就核心路径而言**不成立**。

唯一失败的 `ActivateLanguageProfile` **不能归咎于 Wine**：探针注册的是一个临时 CLSID，背后没有任何 COM 服务器，E_INVALIDARG 完全可能是这个测试设置本身造成的。要分辨，得拿本仓库真实的 TIP 去试——而 `msime-tsf` 当前不在交叉构建的产物里（它要求 `WIN32` 并依赖 `MSIME_HOST_LIBRARY`），本批没有走到那一步。

所以下一步是明确的：让 `msime-tsf` 在 mingw 交叉构建里产出，再用真实 COM 服务器重试激活。在那之前，表里那几行的推迟理由应当写成「TIP 激活未经真实服务器验证」，而不是笼统的「Wine 的 TSF 支持不足」——后者已被实测推翻。

增量记录（2026-09-20，Windows 第四十六批：Wine 的 TSF 边界测到底，并更正两处自己的错话）：第四十五批测出核心链路可用、`ActivateLanguageProfile` 失败，但当时用的是没有 COM 服务器的临时 CLSID，无法归因。这批拿**真实 TIP** 测完了。

先更正两处：其一，第四十五批说「`msime-tsf` 当前不在交叉构建产物里」——**错的**，它一直在产出，是 `target/windows-full/<arch>/tsf/libMetasequoiaImeTsf.dll`（21 MB），当时只看了顶层目录。其二，中途一度判断「`DllRegisterServer` 在 Wine 下挂死」——**也是错的**，见下。

用真实 CLSID `{E3062E9A-D834-4637-8958-ED8CFA427D01}` 与 profile GUID `{4D59B1B4-D503-44AE-9259-BAD9BB2778AB}` 逐层测下来：

**Wine 实现了的（全部 S_OK）**：`ITfThreadMgr` 创建与 `Activate`、`CreateDocumentMgr`、`CreateContext`（拿到编辑 cookie）、`Push` + `SetFocus` + `GetFocus` 往返、`ITfInputProcessorProfiles`、`ITfInputProcessorProfileMgr`、`ITfCategoryMgr`。TIP 的 DLL 本身 `LoadLibrary` 正常，`DllRegisterServer` 符号也在。

**Wine 没有实现的**：`ITfInputProcessorProfileMgr::RegisterProfile` → **E_NOTIMPL (0x80004001)**；`ITfCategoryMgr::RegisterCategory` → **E_FAIL (0x80004005)**。

**因此**：本仓库 TIP 的 `DllRegisterServer` 必然失败——它三步里前两步就过不去。直接调用它，**3 毫秒返回 E_FAIL，并不挂死**。此前观察到的 `regsvr32` 卡满 120 秒超时，是 **regsvr32 自己的失败对话框在 xvfb 下无人关闭**，与这个 DLL 无关。

**这条边界取代原先那句笼统的「Wine 的 TSF 支持不足」**：Wine 能跑的是 TSF 的**运行时**，不能跑的是 TIP 的**注册**。凡是直接驱动 `ITfContext` 的行为，Wine 下都可验证；凡是需要「已注册并激活的输入法」才成立的行为，Wine 下不可能验证，且原因不是实现不全，而是那两个注册接口根本没实现——不是本仓库能绕过的。

对来源 `experiments/tsf-edit-control` 的移植，这给出了明确前提：它作为编辑宿主的部分（绘制、候选框位置上报、选区命中）在 Wine 下可跑；但要让本仓库的 TIP 真正挂进去，仍需真实 Windows。

增量记录（2026-09-20，Windows 第四十七批：TIP 能在 Wine 下创建出来，但激活失败的那一步没隔离出来）：第四十六批测出 Wine 不实现 TIP 注册。这批追问一步——**注册不了，能不能绕过注册直接驱动 TIP**。

**能创建。** `DllGetClassObject` 是导出符号，绕开注册表拿到类工厂 S_OK，`CreateInstance(IID_ITfTextInputProcessor)` S_OK——本仓库真实的 TIP 对象在 Wine 下被实例化出来了。这一点此前没有人试过，它说明「Wine 下碰不到 TIP」的印象是错的。

**但激活失败**：`ITfTextInputProcessor::Activate(threadMgr, clientId)` 在 219 毫秒后返回 E_FAIL。

**失败的具体步骤没有隔离出来，本批不假装知道。** 追查过程中一度得出一条看着很顺的因果链——Wine 的 `RegisterProfile` 是 E_NOTIMPL，所以没有默认语言配置，所以 `GetDefaultLanguageProfile` 失败，所以 `_AddTextProcessorEngine` 返回 FALSE。**实测把这条链打断了两处**：`GetDefaultLanguageProfile` 返回的是 S_FALSE，而 `S_FALSE` 不算 `FAILED`，那道检查会放行；继续往下的 `SetupLanguageProfile` 读过源码，它只在 `tfClientId == 0 且 pThreadMgr == nullptr` 时失败，并不拒绝空的 profile GUID。所以这条链是错的，没有写进结论。

**顺带确认的**：`ITfCategoryMgr::RegisterGUID` 在 Wine 下 S_OK（atom 正常，`GetGUID` 往返一致），失败的只有 `RegisterCategory`。也就是说显示属性的 atom 注册这一步不是障碍，障碍只在类别注册，而类别注册属于 `DllRegisterServer` 而非激活路径。

**下一步的线索**：`CCompositionProcessorEngine::SetupLanguageProfile` 带一个 `isComLessMode` 参数——TIP 自身就有一条绕开 COM 注册的模式。要隔离 `Activate` 的失败点，需要构建一个带日志的 TIP；而 com-less 模式很可能正是 Wine 这种无法注册的环境下该走的路。这两件都留给下一轮，本批只报实测到的事实。

增量记录（2026-09-20，Windows 第四十八批：com-less 那条线索实测不成立，附 Wine 下 TSF 的完整测绘）：上一批把 `isComLessMode` 点名为「像样的线索」。**这批试了，不成立**——记下来，省得下一个人再花一遍力气。

`ITfTextInputProcessorEx` 取到 S_OK 之后，`ActivateEx` 用三种标志各试一次：`TF_TMAE_COMLESS`、`TF_TMAE_COMLESS | TF_TMAE_SECUREMODE`、以及 flags 为 0 —— **三者一律 E_FAIL**（151ms / 122ms / 118ms）。com-less 模式救不了它，失败点在别处。

顺带把激活序列最前面两步的原语也测了，全部可用：`ITfSource` 的 QI、`AdviseSink(ITfThreadMgrEventSink)`（拿到 cookie）、`UnadviseSink`、`ITfKeystrokeMgr` 的 QI 均为 S_OK。所以失败发生在这两步之后。

**Wine 下 TSF 的完整测绘（全部实测，非推断）：**

| 能力 | 结果 |
|---|---|
| `ITfThreadMgr` 创建 / `Activate` | S_OK |
| `CreateDocumentMgr` / `CreateContext` | S_OK，拿到编辑 cookie |
| `Push` / `SetFocus` / `GetFocus` 往返 | S_OK，取回同一文档 |
| `ITfSource` QI / `AdviseSink` / `UnadviseSink` | S_OK |
| `ITfKeystrokeMgr` QI | S_OK |
| `ITfCategoryMgr` 创建 / `RegisterGUID` / `GetGUID` | S_OK，atom 往返一致 |
| `ITfInputProcessorProfiles` / `ProfileMgr` 创建 | S_OK |
| `GetCurrentLanguage` | S_OK |
| TIP 经 `DllGetClassObject` 实例化（绕过注册表） | S_OK，`ITfTextInputProcessor` 与 `Ex` 都拿得到 |
| `GetDefaultLanguageProfile` | S_FALSE（无已注册配置） |
| `ITfCategoryMgr::RegisterCategory` | **E_FAIL** |
| `ITfInputProcessorProfileMgr::RegisterProfile` | **E_NOTIMPL** |
| TIP `ActivateEx`（三种标志） | **E_FAIL** |

**结论**：Wine 能提供 TSF 的运行时与全部前置原语，也能让本仓库的 TIP 被实例化；不能提供的是 TIP 注册，而激活失败的具体步骤**仍未隔离**。要往下走只有一条路——构建一个带日志的 TIP，逐个 `goto ExitError` 打点。本轮不做，因为那要改线上 TIP 的构建配置，且改完仍无法在 Wine 下产生可用的输入法，收益只在诊断本身。

增量记录（2026-09-20，Windows 第四十九批：屏幕键盘那行的来源指错了文件）：这行原把「布局、修饰键按下/释放语义」的比对来源写成设置模块 `screenkb-settings.ts`。**那个文件里两样都没有**——它总共 19 行，只做两件事：按主题切换预览图 `softkbd_light.png` / `softkbd.png`，以及给一个按钮挂上 `postMessage({type:'openKeyboardPanel'})`。它是设置页里的入口，不是键盘本身。

真正的来源是 `server/src/keyboard-panel/KeyboardPanel.cpp`，其中引用了 37 个不同的虚拟键：左右 Win（`VK_LWIN` / `VK_RWIN`）、左右 Ctrl 与 Alt（`VK_CONTROL` / `VK_RCONTROL`、`VK_MENU` / `VK_RMENU`）、应用键 `VK_APPS`、导航簇（`VK_HOME` / `VK_END` / `VK_PRIOR` / `VK_NEXT` / 四向方向键）、`VK_INSERT` / `VK_DELETE`、`VK_NUMLOCK` / `VK_CAPITAL`、以及整套 OEM 标点（`VK_OEM_1` 到 `VK_OEM_7` 加 `VK_OEM_COMMA` / `MINUS` / `PERIOD` / `PLUS`）。

**本批只更正比对对象，没有做逐键比对。** 这个更正本身有价值：原先那条待办指着一个不含目标内容的文件，任何人照着它去核都会扑空；现在它指向真正需要 diff 的那份源码。左右修饰键是否都区分、`VK_APPS` 与两个 Win 键是否都有对应，是逐键比对时要回答的第一批问题。

增量记录（2026-09-20，Windows 第五十批：屏幕键盘的修饰键语义逐项核对，结论是一致）：上一批把比对对象更正为 `server/src/keyboard-panel/KeyboardPanel.cpp` 之后，这批做了其中「修饰键按下/释放语义」那一项。

来源用 `IsExtendedVirtualKey` 决定合成按键时是否附带 `KEYEVENTF_EXTENDEDKEY`。这不是装饰：不带这个标志，右 Alt 会被当成左 Alt，方向簇会被当成小键盘数字。本仓库对应的是 `crates/host-windows/src/lib.rs` 的 `extended_key`。

**两边的集合逐键相同**，共 17 个：`VK_DELETE`、`VK_LWIN`、`VK_RWIN`、`VK_RMENU`、`VK_RCONTROL`、`VK_INSERT`、`VK_HOME`、`VK_END`、`VK_PRIOR`、`VK_NEXT`、四个方向键、`VK_NUMLOCK`、`VK_DIVIDE`、`VK_APPS`。左右修饰键的区分、Apps 键、导航簇全部对上。

本仓库的注释比来源写得更清楚，点明了后果——「不带这个标志，方向簇会变成 2/4/6/8，Home/End/PgUp/PgDn/Ins/Del 会变成 7/1/9/3/0/.」——并说明「移植后的 React 布局把它们全部暴露出来，所以这里比来源更要紧」。

覆盖是正反两面的：`extended_keys_cover_the_cluster_the_panel_exposes` 断言整簇键都带上标志；另一条用 `VK_SPACE` 断言普通键**不带**该标志、扫描码非零、按下时无 `KEYEVENTF_KEYUP` 而抬起时有。按下/释放语义因此也一并钉住。

这一项到此走完。同一行里剩下的两项——布局逐键比对、真实焦点恢复——本批没有做；前者需要拿来源的按键表与宿主下发的布局逐个对，后者需要真实 Windows。

增量记录（2026-09-20，Windows 第五十一批：屏幕键盘布局逐键比对，含一个查出来不成立的怀疑）：接上一批，这批做了「布局逐键比对」。

**先说一个差点报错的发现。** 比对底排时注意到本仓库左右两侧的 Ctrl 都发 `0x11`、左右 Alt 都发 `0x12`、左右 Win 都发 `0x5b`，即右侧修饰键发的是左键虚拟码。这看着像缺陷——右 Alt 在许多布局上是 AltGr，有应用会区分左右 Ctrl。而且它会让上一批刚核对过的 `extended_key()` 里 `VK_RMENU` / `VK_RCONTROL` / `VK_RWIN` 三个分支在面板路径上永远走不到。

**但查了来源之后不成立**：`KeyboardPanel.cpp` 第 194–201 行做的是同一件事——`Ctrl → VK_CONTROL`、`Win → VK_LWIN`、`Alt → VK_MENU`，右侧三个键同样用左键码。`IsExtendedVirtualKey` 里那三个右键分支在来源自己的面板上同样走不到，它是个通用助手而非面板专用。**本仓库忠实复刻了来源的行为，不是缺口。**

**逐键比对结果**：来源布局是标准 QWERTY 块——数字排、三排字母、底排修饰键收尾于 Del 与 Ctrl，共 17 个具名虚拟键。**没有** F 键、导航簇、PrtSc/Scroll/Pause，也没有 Menu（Apps）键。

本仓库布局是**超集**：在同样的 QWERTY 块之上，另有 F10–F12、PrtSc、Scroll、Pause、Ins、Home、End、PgUp、PgDn、Menu（`VK_APPS`）与四向方向键。这正好印证了 `extended_key` 那段注释里的说法——「移植后的 React 布局把它们全部暴露出来，所以这里比来源更要紧」。换句话说，上一批核对的扩展键处理在来源那边多半是备而不用，在本仓库却是实打实要紧的。

这一项到此走完。同一行只剩真实焦点恢复，需要原生环境。

增量记录（2026-09-20，Windows 第五十二批：一条永远核不完的待办，因为它要比的东西不存在）：「API 凭据测试」那行把来源写成 `settings_app.cpp::apiCredentialTest` → `ApiCredentialTest::Run`，并留了「仍需逐项核对来源字段与真实服务行为」。

**那两个函数在来源全树都不存在。** `server/src/settings/settings_app.cpp` 这个文件确实在（1522 行），但里面没有 `apiCredentialTest`；整棵树（排除 vendor）搜 `apiCredentialTest`、`ApiCredentialTest`、`testCredential`、`testConnection`、`verifyToken` 全部无果。

再往外找也没有：来源 `server/src/ai/ai_assistant.cpp` 里唯一匹配 `test` 的四处全是 `g_latest` 这个变量名的子串；没有 `/v1/models` 之类的模型列举；设置页 `ai-settings.ts` 的标识符里只有 `aiToken`、`aiEndpoint`、`aiModel` 等输入控件，没有测试按钮；设置页 HTML 里两处「测试」都是正文用语（「测试反馈」「仅供测试使用」）。

**结论：API 凭据测试是本仓库新增的功能，不是从来源迁移过来的。** 因此「逐项核对来源字段」这条待办无法执行，也不该执行——没有可比对的来源字段。本批把它撤销，并在表里标明该功能为新增。

这条待办的形状与第四十九批那条一样：**看起来是个有效待办，实际指向不存在的东西**。区别是上一条指错了文件（真来源在别处），这一条指向的功能压根不存在。两者都比「没做」更坏，因为它们会让人以为还有已知的工作量。

行内保留的只有「真实服务行为」——那是任何依赖外部服务的功能都需要真实账号才能验的，与来源无关。

增量记录（2026-09-20，Windows 第五十三批：想给剪贴板补一条真调 Win32 的测试，结果发现测错了对象）：`tests/clipboard/` 下三个用例都是纯逻辑（历史、链接识别、呈现），`clipboard_text.cpp` 测的也只是 `normalize_clipboard_text` 这个纯字符串函数。真正调 `OpenClipboard` / `EmptyClipboard` / `SetClipboardData` 的地方一行没测，而 Wine 实现了这套 API——看上去是个能当场关掉的缺口。

写完测试却链接失败：`msime::windows::paste_clipboard_text` 未定义。追下去发现 **`platforms/windows/src/clipboard/ClipboardPaste.cpp` 没有出现在任何 CMakeLists 里，不被编译进任何目标；`paste_clipboard_text` 在全仓库也没有任何调用者。**

在用的是另一条路径：`apps/desktop/src-tauri/src/clipboard_history.rs` 调 `msime_host_windows::write_clipboard_text`，即共享 Rust 宿主里的实现，由 Tauri 壳消费。换句话说剪贴板写入早已随「公共功能进 Tauri」这条主线搬到 Rust 侧，C++ 那份是被留下的平行实现。

**本批没有删它**（可能是预留或其他分支在用），也没有把它接起来（那会无缘无故改动生产路径）。按「存在但未接入」记录。

**同时记下一个覆盖事实**：在用的 Rust 路径在 Wine 套件里也没有覆盖——`run-tests-wine.sh` 只 glob `windows-*.exe`、`msime-tsf-*.exe` 与 `msimeui-tests.exe`，即只跑 C++ 测试可执行文件，不跑 cargo 为 Windows 目标产出的测试二进制。要覆盖 `write_clipboard_text` / `read_clipboard_text`，得先扩展这个运行器——**第五十四批做了这件事**，那两个函数所在的 crate 现在随套件一起在 Wine 下执行。

这一条的教训与本轮多次遇到的同形：**先确认要测的东西是活的**。三个纯逻辑用例的存在，让剪贴板看起来「有覆盖」；而真正会在用户机器上跑的那两条路径，一条根本没编译，另一条套件够不着。


增量记录（2026-09-20，Windows 第五十四批：让 Wine 套件也跑 Rust 宿主的 Windows 测试）：上一批记下一个事实——`run-tests-wine.sh` 只 glob `windows-*.exe`、`msime-tsf-*.exe` 与 `msimeui-tests.exe`，即只跑 C++ 测试可执行文件。于是 `crates/host-windows` 里那套 Windows 专有代码在容器里零覆盖：剪贴板读写、合成按键、扩展键集合，全都只在真实 Windows 上才可能被执行到。

本批把它接上了。`cargo test -p msime-host-windows --target x86_64-pc-windows-gnu --no-run` 能为同一目标产出测试二进制，它们在同一个 Wine 下跑得起来——先实测确认，再改脚本：把产物收进 `target/wine-rust-tests/<arch>`，作为只读卷挂进容器，让原有循环一并跑。x86 用 `i686-pc-windows-gnu`；目标未安装或 cargo 不可用时优雅跳过，不影响 C++ 套件。

结果：套件从 78 通过 / 1 失败变成 **80 通过 / 1 失败**，新增的 `rust-msime_host_windows`（11 个单元测试）与 `rust-paste_policy`（2 个）全部通过。其中就包括第五十批只靠读源码核对过的扩展键与扫描码那几条——它们现在是真的被执行了，不再只是被读过。

**另记一个偶发**：第一次运行时 `windows-voice-controller-listener` 失败，第二次通过，其余一致。它不是本批引入的（本批只增加挂载与二进制），但它是一个此前没有记录在案的不稳定用例，写在这里以免下次有人把它当成新回归。

增量记录（2026-09-20，Windows 第五十五批：把 host-api 也纳入 Wine，当场抓到一个「在 Windows 上断言了反面」的测试）：第五十四批让 Wine 跑起 `msime-host-windows` 的测试。这批把 `msime-host-api` 也纳入——那是 Server 链接的 `msime_host_api.dll` 所在的 crate，FFI 边界就在这里，值得在它实际发布的目标上执行。

它需要与交叉构建同一棵原生依赖树（`MSIME_WINDOWS_DEPS`），所以运行器现在按 `MSIME_WINDOWS_DEPS_ROOT` 推出前缀；前缀不存在时只跑 host-windows 并打印一行说明，不让整轮失败。

**首次为 Windows 目标执行 host-api 的 99 个测试，2 个失败，其中一个是真问题。**

`contextual_punctuation_respects_editor_context_preferences_and_composition` 显式设了 `smart_punctuation_direct_digit` 与 `_direct_letter`，却让 `smart_punctuation` 走默认值——而那个默认是 `!cfg!(windows)`（Windows 上由 TIP 自己处理智能标点，所以共享默认关闭）。于是这个用例在 Windows 目标下**断言了与它本意相反的事**，并且一直「通过」，因为套件从来只为宿主目标跑过。本批把前提写进测试本身。产品代码没有改动：Windows 上默认关闭是有意的。

另一个失败 `the_c_header_and_the_rust_exports_agree` 不是缺陷——它在运行时遍历自己 crate 的 `src/` 比对 C 头文件与 Rust 导出，而容器里只有可执行文件。这是一项没有平台维度的源码一致性检查，宿主那轮已经覆盖，故在 Wine 下按名跳过并写明理由。

**还修正了一处自己的疏漏**：`cargo test --no-run --message-format=json` 报出的 `executable` 不只有测试，还包括 examples——`prepare_host`、`preferences_latency`、`dictionary_requests` 都是需要命令行参数的普通程序，被当成测试跑就成了三个假失败。现在按 `profile.test` 过滤。

结果：套件从 78 通过 / 1 失败增至 **83 通过 / 1 失败**，唯一失败仍是基线里那条 `msimeui-tests`（Rosetta 在 arm64 主机上模拟 x86_64）。

增量记录（2026-09-20，Windows 第五十六批：`client-core` 也在 Windows 目标下执行，一段从未被跑过的 Windows 专有代码终于被覆盖）：第五十五批抓到的那个 bug 有个类特征——**平台相关的默认值，配上一个假定非 Windows 取值的测试**。顺着这个特征在 `client-core` 里扫了一遍 `cfg(windows)`：

- `preferences.rs` 的 `smart_punctuation_default`，已在上一批处理。
- `preferences/tests.rs` 里有一处 `let expected = !cfg!(windows);`——**这是正确的写法**，它显式承认了平台差异，留作对照。
- `translation/store.rs` 有两段 `#[cfg(windows)]`：`persist_replacing` 在替换文件遇到 `PermissionDenied` 时做有限重试，注释写明是为了避开 Windows 上另一进程短暂持有文件的窗口。

**最后这段在宿主目标下永远编译不到**，因此从来没有被任何测试执行过。本批把 `msime-client-core` 也纳入 Wine 运行器，它的 247 个单元测试因此在 Windows 目标上执行，其中 `concurrent_replacement_never_exposes_partial_records` 正是覆盖这条重试路径的那个——全部通过。

结果：套件从 83 通过 / 1 失败增至 **86 通过 / 1 失败**。至此在 Wine 下执行的 Rust 测试二进制共八个，合计约 350 个用例，覆盖 `client-core`（共享逻辑与 Windows 专有文件替换）、`host-api`（发布 DLL 的 FFI 边界）与 `host-windows`（剪贴板、合成按键、扩展键）。唯一失败仍是基线里的 `msimeui-tests`。

三批连起来的意义：本轮此前多次只能写「已实现但缺覆盖」或「靠读源码核对」，原因不是没人想测，而是**套件够不着那些代码**。运行器扩展之后，那些条目里有相当一部分不再需要真实 Windows 才能验证。

增量记录（2026-09-20，Windows 第五十七批：Wine 容器没有 locale，中文路径一律失败——对一个中文输入法而言是严重盲区）：把 `msime-engine-bridge` 也纳入 Wine 运行器时，`reset_learned_data_restores_packaged_dictionaries_and_clears_journal` 失败，`create_dir_all` 在创建名为 `陆傲天` 的目录时返回 `NotFound`，而同一循环里的 `ascii` 那轮正常。

**没有直接当成缺陷。** 写了一个只调 `std::fs::create_dir_all` 的最小 Rust 程序去分辨：ASCII 目录成功、CJK 目录 `NotFound`，写文件则是 `Path not found`。这说明问题在环境而非本仓库代码。

根因是容器**根本没有设 locale**：`LANG` 为空、`LC_CTYPE="POSIX"`。Wine 依据 locale 决定文件名的编码映射，POSIX 下非 ASCII 路径直接失败。镜像里其实有 `C.utf8`。加上 `-e LANG=C.utf8 -e LC_ALL=C.utf8` 之后，同一个探针两轮全部成功，`engine-bridge` 那条测试也随之通过。

**这一条值得单独强调**：本仓库是中文输入法，而它的 Windows 测试环境此前无法处理中文路径。任何涉及 CJK 文件名的行为在这里都测不了，且失败形式是 `NotFound` 这种容易被误判成代码缺陷的错误。

同批另外三处改动：`--tests` 只构建测试目标（`engine-bridge` 有个用 `std::os::unix` 的 example，为该目标根本编不过）；运行器不再静默吞掉 cargo 的错误——没有产出任何 Rust 二进制时会打印提示并附上日志路径（`msimeui-tests` 长期没被执行而计数看起来正常，正是这种静默造成的）；`engine-bridge` 纳入后新增 28 个用例。

结果：套件 **88 通过 / 1 失败**，十个 Rust 测试二进制全部通过，唯一失败仍是基线里的 `msimeui-tests`。会话开始时这个数字是 78 通过 / 1 失败。

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

增量记录（2026-09-21，混输候选的座位表：来源 Server 里的那一步没迁过来）：来源 `server/src/ipc/candidate_selection_policy.h` 把四种排布写死：

```text
无云：    中文, 英文, AI, emoji, 颜文字
有云：    中文, 云, AI, 英文, emoji, 颜文字
只有云：  中文, 云, 英文, emoji, 颜文字
基础：    中文, 英文, emoji, 颜文字
```

它跑在来源的 **Server** 里，对引擎返回的候选再排一次。本仓把 Server 换成共享运行时时，这一步没跟过来——用户看到的就是引擎自己的摆放。两者在没有联网候选时一致（实测 `ni` 的基础排布正是第四行），一旦注入 AI 就分叉：本仓给出 `你, 尼, AI, ni, 😀, 颜文字`，英文候选从第二位被挤到第四位，第二位换成了另一个中文候选。

把那张表实现进运行时（`normalize_online_slots`），只在快照里确实存在云/AI 候选时生效——其余情况引擎的顺序已经等于表，不动也就没有风险。多于一个的云/AI 候选按本地候选处理而不是丢弃（来源那边是被 move 走后丢掉）。

**顺带更正我自己两条记录之前的一个判断。** #3383 里我按 README 那句「插入首页第三项」写下「来源是给座位编号，不是压缩排列」，并据此钉住「AI 单独到达时仍落第三」。来源的实现不是这样：`candidate_selection_policy.h` 的插入是压缩的，没有英文候选时 AI 就落第二。代码优先于散文，探针的断言与注释都已按实现改正。

用例：新增 `crates/input-runtime/examples/mixed_slots.rs` 用 `ni` 这个输入（同时产出中文、英文 `ni`、emoji、颜文字，且两种联网源都可用）逐个验四种排布。

增量记录（2026-09-21，维护快捷键已齐，另修关于页日志开关的名字）：来源《服务守护》一节的四组维护快捷键在 macOS 上都在，也都有宿主用例：`Control+Shift+Option` 加 1–8 删除候选（八个槽位逐个验过，含重复按键抑制）、加 C 清缓存、加 R 重新注册并退出、加 T 退出进程。来源写的是 `Ctrl+Shift+Alt`，macOS 换成 Option 是平台适配，共享设置页里那句说明也按平台改过。

顺带修掉关于页的一处：诊断日志开关在 macOS 上显示为「Server 端日志」，描述写着「排查 Server 通信……记录慢请求阶段、候选窗、悬浮工具栏、菜单、焦点会话和通信状态」。macOS 没有 Server 进程，输入法就是一个进程；它实际记的是焦点进出与偏好加载/应用/保存的结果（`msime_macos_diagnostic_write` 的六个调用点），落在应用支持目录的 `diagnostic.log`。Linux 早就各自命名为「IBus 宿主日志」并写了自己的说明，macOS 一直沿用 Windows 的那份。现改名为「输入法日志」，描述按它真正记录的内容与文件位置重写——来源那句「复现后可直接发送该文件」保留，因为这才是这个开关存在的理由。

增量记录（2026-09-21，云候选与 AI 联想的插入位置：不用联网也能验）：来源把位置写死了——云联想「返回了当前本地不存在的结果，会插入在首页的第二项」，AI 联想「不与本地以及云联想重复，会插入首页第三项」。位置是引擎定的，没有真实候选列表就看不出来，而联网这一块此前只有契约测试（请求怎么发、凭据怎么路由），没有「插进来之后长什么样」。

新增 `crates/input-runtime/examples/online_slots.rs`：不联网，直接把结果交给运行时的 `apply_online_candidate`——真实 provider 的回调走的就是这个入口。实测 `nihao` 的本地候选是 `你好 / 你好吗 / 你好啊 / 拟好`，注入之后变成 `你好 / 合成云候选 / 合成 AI 候选 / 你好吗`：云在第二、AI 在第三、本地首选不动。另两条：AI 单独到达时仍落第三而不是往上挤（来源是给座位编号，不是压缩排列）；云端返回的结果与本地已有的重复时不会插成两条。

增量记录（2026-09-21，标点表与「切换提示」：两条都不是缺口）：

**标点表。** 来源《标点与以词定字》最后一条列了六个不是「ASCII 键的中文孪生」的映射：`\` → 、、反引号 → ·、`Shift+6` → ……、`Shift+-` → ——、`Shift+,` / `Shift+.` → 《 》。它们来自引擎的表而不是任何宿主，所以此前两侧都没人验：共享用例用合成引擎，宿主用例不出宿主。新增 `crates/input-runtime/examples/punctuation_table.rs`，拿真实词库逐个打，六条全中；关掉中文标点后没有一个再产出中文标点（引擎此时不接管这个键，交给宿主原样输入，所以断言的是「不产出中文标点」而不是「产出 ASCII」——这是层次问题，第一版写错过一次）。

**切换中英文时显示提示。** 这一项来源没有（`ui-html` 里搜不到对应控件），是本仓在 macOS 上的增项（输入模式 HUD，能力位 `input_mode_hud` 只给 macOS 与 HarmonyOS）。属超集，不需要迁移。

至此来源《核心功能指南》各节都有对应的可重跑验证：输入方案/辅助码/日语（`schemes_dictionary`、`helpcode_dictionary`）、调频（`frequency_modes_dictionary`）、以词定字（`word_to_character_dictionary`）、混输与 emoji/颜文字顺序（`mixed_*_dictionary`）、八种快捷模式（`local_modes`）、标点表（本条）、智能标点（共享用例 + 默认值修复）、成对补全（#3380）、语音快捷键（`voice-hold-shortcut`）、词库导入导出与自定义释义（#3350）。剩下的是网络类（云候选、AI 联想、在线翻译）与真实编辑器里的手感。

增量记录（2026-09-21，成对标点自动补全：按第一条路实现，#3380）：上一条记的三条路里选了第一条，并把 Apple 来源缺的那段簿记补上了。落地形态与来源不同，因为平台不同：

- 左符号照常作为**提交文本**落进文档（引擎给的就是它），所以它任何时候都不会丢。
- 右符号作为**标记文本**跟在光标后面：`（|）`。组合开始后它继续留在标记文本的尾部——`（ni|）`、`（你好|）`——所以整段组合是在这对符号里面进行的。
- 上屏时右符号跟着提交文本一起落下（`你好）`），光标落到右符号之后，并把它记进 `PairedPunctuationTracker`，于是紧接着再打一次右符号会被跳过而不是打出两个。
- 组合被拆掉的每一处（失焦、`commitComposition:`、Esc、宿主重置）都先把欠的右符号补上，所以「打开了一对但没打完」不会把右符号吞掉；切到另一个客户端时则是丢弃而不是写进新文档。
- Excel 仍按来源的排除名单跳过。

与 Apple 来源的区别写在这里：它把整对符号一起作为标记文本送出（`setMarkedText:` 配 `(1, 0)` 的选择区），而标记文本会被下一次 `setMarkedText:` 替换——用户接着打字时那对括号会被顶掉。本仓把左符号先提交掉，只让右符号留在标记区，因此最坏情况是多一个或少一个右符号，不会丢掉用户已经落下的字。

用例：共享层 `MSIMEApplyTransitionWithPendingClosing` 四条（组合期尾随、上屏时带走、无待补时行为不变、行内预编辑为空时仍显示右符号），宿主级一条走完整条链（开对→组合→上屏→再开一对→拆掉时补上→关掉开关后恢复原样）。全量 `ctest` 126/126。

仍未验证的：真实编辑器里的观感。标记文本在不同应用里的呈现（下划线、选区）不完全一致，这一条要在编辑器里看。

增量记录（2026-09-21，成对标点自动补全：macOS 上整个没有发生，待定实现形态）：接着验标点那几条，这一条比前面几处都大。

**事实。** 引擎不做自动补全：用真实词库实测，`paired_punctuation` 打开、中文标点打开，输入 `(` 提交的只有 `（`（`[` → `【`、`"` → `“`、`<` → `《` 同样），随后按 `)` 才提交 `）`。补右符号是宿主的活：Windows 的 TSF 宿主自己做（`KeyHandler.cpp` 的 `punctuationStr.push_back(pairedClosing)` 之后整串插入），Linux 宿主也自己做（`ClientEngine.cpp` 的 `normalize_punctuation_pair` 把右符号接在提交文本后）。**macOS 两件事都没做**：`InputController.mm` 里唯一与配对相关的写入路径，要求提交文本长度 ≥2 且首尾成对才把右符号记进 `PairedPunctuationTracker`，而引擎永远只提交一个字符，所以那段永远不执行，跟踪器里也永远是空的——它的另一半（再按一次右符号时跳过而不是打出两个）因此也是死的。

于是 macOS 上：开关默认开、设置页写着「输入左侧符号时自动补全右侧符号，并将光标置于中间」、连 Excel 的排除名单（与来源同一个）都在，唯独功能不存在。

**为什么不能照抄 Windows。** Windows 插入两个字符后把光标左移一格（`moveCursorSync(CURSOR_LEFT)`）。IMK 没有对应的 API：输入法不能移动宿主应用的插入点。Apple 来源（MSIME-Apple）给出的是这个平台自己的答案，注释写得很清楚——把整对字符作为 **marked text** 送出，选择区落在中间（`setMarkedText:@"（）" selectionRange:NSMakeRange(1, 0)`），因为「IMK 没有 setSelectedRange，带插入点的标记文本是受支持且不抢焦点的表达方式」。

**没有定下来的地方。** 标记文本会被下一次 `setMarkedText:`/`insertText:` 替换。也就是说照抄这套之后，用户打完 `（` 再打 `nihao` 时，宿主为新组合送出的标记文本会不会把那对括号一起顶掉——取决于宿主接到下一个键时先提交还是先改写标记区，而这一点只能在真实编辑器里看。没有在真实编辑器里验证之前，不往这条会改写用户文档的路径上落代码。

**三条路，待定夺：**

1. 照搬 Apple 来源的标记文本方案，并把「下一个键先提交已标记的那一对、再开始新组合」这段补齐（本仓宿主需要新增这段簿记，Apple 那份没有）。功能与来源等价，需要真实编辑器验收。
2. 只插入两个字符（提交而非标记），光标落在右符号之后。功能上补齐了「自动补全」，但「光标置于中间」这半条不成立，描述要跟着改。
3. 保持现状，把 macOS 上这个开关的描述改成实话，或在这个平台隐藏它。

一并记下：`PairedPunctuationTracker` 与它的 `paired-punctuation` CTest 是为「再按一次右符号时跳过」写的，形态没问题，只是在补全落地之前没有输入。

增量记录（2026-09-21，智能标点：开关默认开、描述照抄来源、行为却不发生）：接着按指南往下验标点那几条时，发现的是一处默认值造成的「开关说了不算」。

来源的设置页在智能标点这一族上只有**两个**开关（智能标点、重复标点转中文），且出厂都是开；单独一个「智能标点」就意味着它自己的描述——「中文标点模式下，字母或数字后的 , . : 自动使用英文标点」。本仓把它拆成了三个：父开关之外另有「数字后直出」「字母后直出」两个细分项（还有一个来源没有的「中文标点后按空格转换」）。父开关在除 Windows 外的所有宿主上默认开，两个细分项默认关，而 `punctuation::route` 要求 `direct_digit || direct_letter` 才走 ASCII。

于是出厂状态下：智能标点是开的，它下面那句照抄来源的描述是**假的**，打 `v1,` 得到的是 `v1，`。用户得再找到另外两个开关才能得到描述里写的行为。

改法是让两个细分项跟随父开关的默认（`smart_punctuation_default()`），Windows 一侧完全不变（父开关本来就默认关，细分项跟着关），已存下的文档也不受影响（serde 默认只对缺键生效）。「按空格转换」不跟随：它重写的是用户已经看见落下的字符，来源也没有对应物，保持默认关。

`scripts/test-default-config-parity.py` 里那条「三个细分项必须在所有宿主上默认关」的断言按同一理由改写：它真正要守的是「Windows 新用户拿到整族关闭」，跟随父开关同样满足，而且现在守的是跟随关系本身。原有两条偏好用例与一条 host-api 用例一并更新——其中 host-api 那条此前是用出厂默认去断言「不转换」，现在改成显式关掉两个细分项再断言，意思更清楚。

增量记录（2026-09-21，八种快捷模式：拿真实词库把指南里的例子逐条打一遍）：到这一层为止，比对的都是「页面上写了什么」。八种快捷模式各自有偏好、有菜单项、有宿主用例，但没有一处检查「按下 Shift+T 再打 rq，屏幕上到底出什么」——宿主用例用的是空的资源文件（它要验的那道门只问文件在不在），共享用例用的是合成引擎。指南里最具体的那部分，恰恰是没人验的那部分。

新增 `crates/input-runtime/examples/local_modes.rs`，按来源《实用功能快捷模式》表里的例子逐条打，读回候选。它要已验证的词库发布，所以与旁边的 `runtime_dictionary` 一样是 example 而不是 CTest：

```sh
cargo run -p msime-input-runtime --example local_modes -- <verified-dictionary-directory>
```

本机实测（词库缓存在 `~/msime-shared/resources/<hash>/`）全部通过，抽样为证：`T` + `rq` → `2026年9月21日`；`U` + `4e00` → `一`，`+1f600` → `😀`；`E` + `xiaolian` → `😀`；`M` + `haixiu` → `(*/ω＼*)`；`J` + `nh` 的候选里有 `你好`（排在 女孩、你会 之后，与第八批记录的引擎排序一致）；`R` + `nihon` → `日本 / にほん`；`Y` + `hello` 空格上屏 `hello` 且模式自动退回中文，`R` 同理。`T` 的三种拼法（rq/riqi/date、sj/shijian/time、xq/xingqi/week）各自都验了，指南列三种就是说它们等价。

`K` 只验了「进入模式并吃掉编码字母」这一半——另一半要用户词库里先有短语，属于有状态的验收。

增量记录（2026-09-21，页内顺序与描述文案这两层）：顺序的两条断言（输入页、外观页）此前也只渲染 Windows 宿主，现按同一张宿主表对两个宿主各跑一遍。结果是齐的——macOS 的两页顺序与来源一致，没有缺口。

描述文案（每个控件下面那句 `<small>`）逐条比过来源的 51 条。本仓写的是忠实的节略版，规则都在：`U 模式` 那句「空格上屏；Shift+数字选词」、`J 模式` 的「双拼按当前方案转换声母」、`Y 模式` 的「上屏后回到中文」等都与来源一致。一处措辞差异是刻意的且更准：剪贴板管理，来源写「关闭后立即清空」，本仓写「保存关闭设置后清空」——本仓清空发生在偏好保存时，照抄会写出一句不成立的话。

顺带记一件事：`U 模式` 那句描述里的「Shift+数字选词」在 #3348 之前 macOS 其实做不到——页面写着、宿主没有。这类「描述先行、实现落后」的情况，比对文案本身是抓不出来的，得从描述反推去验实现。

增量记录（2026-09-21，再往下一层：控件里的选项，对 macOS 也钉一遍）：小节钉住不等于选项一致——上一条「每页候选项数量」就是在选项这一层出的问题。`referenceOptions` 原来只有六个控件、也只渲染 Windows 宿主，现在扩到二十一个控件并对两个宿主各跑一遍（42 条）。

查到两处真差异，都是标签，都已改：

- **润色方案的四个预设名**。本仓写的是 清理口语 / 忠实原文 / 中译英 / 自然口语，来源是 精炼整理 / 忠实校对 / 中翻英 / 口语整理。提示词本身当初是逐字从 `voice_providers.cpp` 抄过来的，名字就在同一张表里（`PolishPromptPreset`），却没跟着抄。
- **候选窗口主题的「跟随」**。同一页另外七个主题选择器和来源都写「跟随全局」，只有这一个写「跟随」。

顺带修掉 macOS 原生语音设置窗的一处：提示词方案那个下拉把**原始 id**（`cleanup`、`zh2en`…）直接当菜单项显示，而且保存的就是这个标题字符串。现在 id 与显示名分开，显示的是来源那四个名字，存的仍是 id。

这两处能漂掉是因为原本没有任何用例钉住它们——改完之后 837 条用例照样全绿，正说明这一点。新增的那 42 条现在钉住了。

增量记录（2026-09-21，设置页小节的那张表，补上 macOS 与来源剩下六页）：`referenceSections` 这张表把来源设置窗每一页的小节钉在渲染结果上，但它只渲染 **Windows** 宿主，而且只覆盖八页。对本次迁移来说这两点都不够：一个藏在 macOS 未声明的能力位后面、或藏在平台名分支后面的小节，在这张表下照样通过。

两件事一起做：

1. **同一张表再对 macOS 宿主跑一遍**，宿主能力按 `host_surface.rs::for_platform(Macos)` 逐字段给全（此前 Windows 那一份只给了六个，快捷键页的两节其实藏在 `mode_switch_shortcuts` / `panel_shortcuts` 后面——补上之后 Windows 这侧也多钉住了两节）。macOS 少掉的小节必须在 `macosAbsentSections` 里写明理由，而且条目失效也会失败。跑出来只有三条，都是平台适配而不是缺口：Windows 字体行上的「保存后自动应用」（macOS 换字体不需要重启）、「打开手写识别板」（手写面板要输入法进程的 IMK 会话，设置窗是另一个进程，macOS 改为提示从工具栏或输入法菜单打开）、以及帮助页的「快速上手 / 基本功能」（macOS 用 `macosHelpCards` 的术语—说明行回答同样三个问题）。
2. **把来源剩下的六页补进表**：语音输入、皮肤、词库、AI 辅助、快捷键、关于。补的过程中确认了几处形态差异都不是缺口——来源四套内置皮肤各自成节，这里是一个卡片选择器（四套皮肤本身都在）；来源「批量导入纯汉字词组」与「导出词库」两节，这里合成带类别选择的「本地词库管理」，导入说明里写明支持纯汉字自动注音；来源「TSF 端日志」是 Windows TIP 进程的，按平台门控。

顺带放弃了一版做法：先写了一个把来源 `section-title` 抽成清单、再在 `index.tsx` 文本里查找的脚本。它对这个页面不成立——大量标题是 `{label}辅助码方案` 这类表达式渲染的，纯文本查找必然误报。改用已有的渲染断言是对的，这一版没有提交。

增量记录（2026-09-21，出厂默认值逐项比对：四处首次启动就不一样的，待定夺）：把来源的出厂配置 `installer/default_config/config.default.toml`（150 个键）与共享 `Preferences::default()` 逐键比了一遍。除去该文件里的占位值（`FAKESECRET_…` 的三个 token、腾讯的 `<YOUR_…>`、示例提示词、以及作者自己的 `settings_page.theme = "dark"`）之外，剩下**四处是真的默认行为差异**，且本仓 Windows 模板与来源一致、其余宿主（含 macOS）走共享默认：

| 键 | 来源 / 本仓 Windows | 共享默认（macOS 等） |
| --- | --- | --- |
| `input.default_ime_mode` | `english` | `chinese` |
| `voice_input.mute_system_audio` | `true` | `false` |
| `voice_input.doubao_enable_ddc` | `true` | `false` |
| `voice_input.polish_text` | `true` | `false` |

第一条是用户装完立刻能感觉到的：来源那边装好后输入法起手是英文态，macOS 起手是中文态（`AppearancePreferences.defaultImeMode` 在没有存储值时回落到 `chinese`）。

**本轮不动它们**，理由是这不是「macOS 漏实现了什么」，四个字段每一个 macOS 都在消费；改的是默认值，而共享默认同时被 Linux、Android、iOS、HarmonyOS 使用，翻一处就翻五个宿主的首次启动行为。另外起手是中文还是英文，在 macOS 上与 Windows 的处境并不同——macOS 上用户是明确从输入菜单选中「水杉输入法」才开始打字的，选了中文输入法却起手英文，未必是这个平台想要的。这属于产品取舍，留给所有者定。

比对方法可重跑：`Preferences::default()` 用一个临时 example 序列化成 JSON，再按叶子名与来源 TOML 逐键对；不匹配的叶子名（来源有而共享没有同名字段的 80 个）多是命名差异，已在上一条记录里核过。

增量记录（2026-09-21，几条查过、判为「不是缺口」的，连同判据）：这一轮把来源设置窗写配置的 73 个键、宿主能力矩阵、以及 macOS 侧所有收窄共享取值的归一化函数逐个过了一遍，结果除了上面那条每页候选项数量之外没有别的缺口。判据记在这里，免得下一轮重查：

- **设置键映射**：来源 `settings_app.cpp` 里 `path == "…"` 的 73 个键逐个在共享偏好或共享设置页里找到对应物，差异全是命名（`paging_brackets` → `navigation.brackets`、`cn_en_mixed_input` → `mixed_input.english`、`utility.*_mode` → `local_modes.*`、`word_to_character` → `word_character`、`*_helpcode_schema` → `quanpin_helpcode.schema` 等）。`input.wubi_schema` 与 `input.japanese_schema` 在来源那边各自只有一个选项（86 五笔、罗马字），不需要共享字段。
- **宿主能力矩阵**：`HostCapabilities::for_platform` 里没有任何一项是「Windows 有、macOS 没有」。
- **悬浮工具栏缩放**：macOS 的白名单 75/100/125/150 与来源下拉逐项相同。
- **翻页键的缺省**：原生窗口那个三选一的「候选翻页快捷键」只在共享 `navigation` 没有显式布尔值时充当缺省，一旦设置页写过就以共享值为准；它推出的缺省（minus_equal 开、brackets 关、其余开、mouse_wheel 关）与共享 `NavigationPreferences::default()` 逐项相同。
- **候选字号**：`metasequoia::mac` 下那两个只认 16/18/20 的 `NormalizeCandidateFontSize` 属保留的 Apple 适配层（`MetasequoiaInputController.mm`，不编进产物）；发出去的宿主走的是 12–32。

另有两条是**刻意保留的差异**，都不属于 macOS 侧的缺口，一并记下来源：

- **混输最小前缀的默认值**（本条已订正并修掉）：先前这里按守卫的注释写成「来源安装模板是 5」。实测不是——来源 `installer/default_config/config.default.toml` 自加入该文件起就是 2，历史上从未出现过 5（`git log -S` 无命中），而 2 也正是共享默认。macOS 这侧本来就是 2，与来源一致；差的是本仓 Windows 模板的 5，出厂状态下英文候选要敲五个字母才出来，而来源是两个，`scripts/test-default-config-parity.py` 的断言还挡着不让改。模板改回 2，守卫改为「与共享默认一致」。
- **快捷短语编码允许数字**：来源文档写「编码只能是英文字母」，本仓的 `validate_entry` 显式放行数字。共享运行时对数字键是「引擎先拒绝再说」（`result.handled` 优先于候选选择），所以带数字的编码在 K 模式下仍然打得出来，属超集而非缺口。

增量记录（2026-09-21，每页候选项数量：macOS 把共享默认值改写掉了）：来源外观页的「每页候选项数量」提供 3–9，默认 6；共享偏好 `candidate_page_size` 接受 1–9，默认也是 6。macOS 这一侧是 `NormalizeCandidatePageSize`：只认 5、7、9，**其余一律改写成 9**。于是一个谁都没动过的设置，在这个平台上显示并保存为 9，而别的平台是 6；从别处写下的配置（另一个宿主、手改、云端同步回来的外观快照）带着 4 或 6 进来也会被静默改掉。云外观校验器 `MSIMECloudAppearanceCandidatePageSize` 同样只接受这三个值，一份别的宿主写的快照会被整条拒绝。

这三个值来自 Apple 来源那个窗口，是本仓早先对齐它时引入的（#ecaf6a069「align macos candidate page sizes」），不是 macOS 的平台约束——面板画几行就是几行。按当前目标（复刻 MSIME-Windows）改回来：宿主接受共享偏好的整个 1–9 并把越界值拉到最近一端而不是顶到 9，未设置读作共享默认的 6，原生窗口与共享设置页都列出来源的 3–9，云快照按同一范围校验。

顺带发现 `CandidatePageSizeTest.cpp` 根本没注册进 CMake——有文件、没目标，从来没跑过，这正是那条改写规则一直没被重新审视的原因。已接进 CTest（126 项），并把它从「5/7/9 的三值表」改成覆盖整个范围、越界拉到最近一端、以及窗口列出的那七项。

增量记录（2026-09-21，README 其余各节：自定义候选窗翻译在桌面端没有入口）：来源《自定义候选窗翻译》一节的做法是「在 `%LOCALAPPDATA%\metasequoiaime\` 下新建 `custom_translations.txt`」。这条指令迁到 macOS 就不成立了——同一个目录在 `~/Library/Application Support/` 下，Finder 默认不显示它，用户按文档照做会找不到地方。

共享设置页本来就有这一节（输入页的「自定义候选释义」，连 Tab 分隔、`#` 注释、同源词以最后一次为准这些说明都在），但它由 `client.customTranslations` 门控，而这个能力只有 HarmonyOS 提供。于是桌面三个宿主上整节不渲染：既没有来源那条文件路径的等价物，也没有界面。

按「公共功能+UI 放 Tauri」补上宿主这一端：两个命令读写 `<state>/user/custom_translations.txt`（引擎读的就是这个路径），语义与 HarmonyOS 那份一致——上限 1 MiB、清空即删除文件（留一个空文件会让引擎每次会话都读出一个空集合）、文件不存在时读作空文档。另加两条 macOS 上必要的细节：读取时剥掉 UTF-8 BOM（来源明确接受带 BOM 的文件，留着会在页面上显示出来又原样存回去），以及写入先落到同目录的临时文件再改名，让一次失败的保存留下上一份覆盖层而不是半份。

用例：Rust 侧两条（往返 + BOM + 清空删除 + 超限/NUL 拒绝且拒绝后旧覆盖层还在），UI 侧一条钉住桌面宿主也能拿到这一节。

增量记录（2026-09-21，快捷模式指南逐条核对，第一条差异：Unicode 模式的候选选择）：测试清单走完之后换入口——来源 README 的《实用功能快捷模式》八行，每行都是可核对的具体约定。Unicode（U）那行写的是「空格上屏首选；`Shift + 数字` 选其他候选」，理由就在同一行里：不加 Shift 的数字是正在输入的码位。来源实现为 `event_listener.cpp` 的 `is_unicode_shift_digit_selection`，与空格走同一条选择路径。

macOS 缺后半条。`ShouldRoutePhysicalCandidateDigit` 明确把 Unicode 模式和任何带修饰键的数字都排除在候选选择之外，而没有第二条规则把 Shift+数字 接回来——于是这个模式下键盘只能上屏第一个候选，面板里其余候选看得见、够不着（方向键还能挪高亮，但文档写的那条交互不存在）。

按来源补上，写成与既有那条并列的纯函数：候选面板可见、处于 Unicode 组合、且修饰键恰好只有 Shift。键位映射沿用既有的 1–9（不含 0），与来源的 `'1'..'9'` 相同。四条纯函数用例加一条宿主级用例（真的发一个 Shift+2 事件，断言选中第二个候选，同时不加 Shift 的 `2` 仍作为十六进制输入到达引擎）。反向验证过：去掉新分支，宿主那条在第 4496 行失败。

增量记录（2026-09-21，来源测试清单这一轮走完）：43 个文件按落点分完，macOS 侧这一轮到此为止。三处真实差异已各自修掉（方向键末尾不扩充、字体 face 名不解析、空槽位提示词），其余的判断依据记在这里，免得下一轮重查。

**对 macOS 不成立的（Windows 进程边界或 WebView2 自绘）**：`test_inline_protocol`（设置壳的资源内联）、`test_candidate_window_template`（WebView2 候选模板的锚点替换，macOS 是原生面板）、`test_candidate_size_estimator`（Direct2D 度量，对应物是 `CandidateRowFit.h`）、`test_ipc_protocol_constants`、`test_pipe_write_policy`、`test_terminal_deactivation_policy`、`test_active_client_state`、`test_outbound_session_state`、`test_async_request_origin`。

**归 Engine 或共享层、两边跑的是同一份的**：`test_quanpin_scheme`、`test_shuangpin_query`、`test_shuangpin_scheme`、`test_engine_shuangpin_session`、`test_wubi`、`test_japanese_romaji`、`test_jianpin_query`、`test_emoji_query`、`test_kaomoji_query`、`test_kaomoji_sql`、`test_date_time_query`、`test_english_dictionary`、`test_user_dictionary_journal`、`test_translation_gloss`、`test_custom_translation`。

**查过、无缺口的**：候选固定位置的独立配色、悬浮工具栏可见性三条件、翻页键六组开关、混输英文的最小前缀（两边都是 2，且都由偏好校验钉在 1–8）、剪贴板历史的 50 条上限与去重后置顶、词库分页的有界扫描与 `has_more`。

**一处实现不同、结果等价，实测过**：简繁输出。来源用 OpenCC 的 `s2t.json`（随包带 `assets/opencc`），macOS 用 ICU 的 `CFStringTransform(Simplified-Traditional)`，不带数据文件。ICU 这条一向被认为弱在词组上下文，所以按公认的难例实测了一遍：皇后→皇后、头发→頭髮、干面→乾麵、里面→裡面、面条→麵條、后天→後天、发展→發展、周杰伦→周傑倫，八条全对。结论是平台适配而不是缺口，不引入 OpenCC 与它的数据文件。

**记一处刻意保留的差异**：偏好文件的升级路径。来源 `test_config_template_merge` 钉的是三方合并——用户改过的键保留、仍停在旧默认值的键跟随新默认值、模板里没有的键和段落丢弃。本仓的 `preferences.json` 每次都把全部字段写出来，没有「旧默认值」这个概念，所以改默认值永远到不了已有用户；`deny_unknown_fields` 又让退役字段不能删（`ui_backend` 的注释已经写明这一点）。这是存储模型层面的取舍，不是某个功能的缺口，改动面也远超一次功能迁移，单独提出来由所有者决定，本轮不动。

增量记录（2026-09-21，来源测试清单第三批：语音润色的提示词槽位）：来源 `test_voice_providers.cpp` 的三条里，`voice_providers_empty_custom_falls_back_to_cleanup` 钉的是「自定义槽位留空时用精炼整理那份内置提示词」——它断言留空的自定义二拿到的文本含「整理助手」。本仓 `shared/voice/PolishPrompt.h` 在这一条上漂了：自定义一和自定义三留空回落到 `kCleanupPrompt`，自定义二留空回落到 `kFaithfulPrompt`。于是一个用户从没填过内容的槽位，模型收到的是「校对」而不是「精炼整理」，与另外两个空槽位的行为也不一致。

这个头文件是共享的：Windows 宿主 `platforms/windows/src/system/PolishPrompt.h` 只是把它 include 进来，macOS 经 `HTTPVoiceRequest.mm` 用的也是它，所以这一处同时影响两个桌面宿主。

漂移能发生是因为原有用例只断言了「不是 legacy 那份」和「非空」，没说是哪一份内置。现按来源改为 `kCleanupPrompt`，并把三个空槽位都钉到「与完全未配置时拿到的那份相同」。反向验证过：改回去，用例在第 56 行失败。

顺带把这个测试挪到它测的代码旁边（`shared/voice/tests/polish_prompt.cpp`），并在 macOS 的 CTest 里注册。它此前只在 Windows 构建里跑，而两个桌面宿主都发这份提示词——这正是漂移没人发现的原因。

增量记录（2026-09-21，来源测试清单第二批：字体族解析）：来源 `test_system_font_family.cpp` 钉住两条——下拉里列的是 DirectWrite 的族名且有序，以及**旧配置里存的 face 名要解析成 CSS 能匹配的族名**（`仓耳今楷05 W03` → `仓耳今楷05`）。第一条 macOS 已满足：`system_fonts::list` 走 `CTFontManagerCopyAvailableFontFamilyNames`，装进 `BTreeSet` 天然有序。第二条此前是空的：`resolve_css_families` 只在 Windows 上查别名，其余平台原样返回，注释写的是「其他宿主本来就只有族名」。

对 macOS 这条不成立，理由和 Windows 完全一样：偏好里的字体名不只来自下拉——旧版本写下的文件、迁移过来的配置、手改的 JSON 都算数，而 CoreText 认 PostScript 名（`PingFangSC-Semibold`）、CSS 不认。于是候选窗（走 `NSFont`）显示的是用户选的那个字体，紧挨着的设置页预览（走 CSS）悄悄回退成别的——只有预览是错的，两边还对不上。

按 CoreText 补上，形态与 Windows 那份对应但不照搬：CoreText 查不到名字时不报错，而是返回一个替代字体，所以只有「拿回来的就是问的那一个」时才采用答案——PostScript 名、全名、或者问的本来就是族名，三者之一匹配才算数，否则保留原值不动。实测：`Helvetica-Bold` → `Helvetica`，`PingFangSC-Semibold` → `PingFang SC`，`HiraginoSans-W3` 与 `Hiragino Sans W3` 都 → `Hiragino Sans`，`Synthetic W03` 原样返回。用例另钉住顺序与条数——调用方是按位置把答案配回候选字体/英文字体/回落字体三个字段的，少一条或换个顺序就会把一个字体的族名安到另一个设置上。

增量记录（2026-09-21，来源测试清单这条轴转向 macOS，第一批：候选导航）：前几批按来源的设置页、文案、配色比，这一批换一个入口——来源 `server/tests/src/` 的 43 个测试。它们是来源自己用断言钉住的行为，而「两边都有、行为不同」这一类恰恰只有它们抓得住。这一批走候选窗那一组（`test_candidate_ui_state`、`test_candidate_ui_owner`、`test_candidate_size_estimator`、`test_candidate_view_model`、`test_floating_toolbar_visibility_policy`）。

查到一处真实差异并修掉：**用方向键走到已加载候选的末尾时，引擎扣住的那批候选放不出来。**

来源 `server/src/ipc/event_listener.cpp` 的 `move_selection` 在两种情况下先调 `expand_initial_candidates()` 再移动——选中项已在最后一个候选上，或选中项在当前页尾且下一页是短尾页。本仓的共享运行时只在 `Action::NextPage` 上扩充（`expand_for_next_page`），`Action::NextCandidate` 直接把高亮夹在 `cached.candidates.len() - 1`。引擎对单字母查询有二十四条的初始上限，于是同一个查询下按 Page Down 能走到词库深处，按方向键（以及任何一次一条地走的宿主路径）走到第二十四条就停住，再按没有反应。macOS 的方向键走的正是这条路（`InputController.mm` 把 ↑/↓ 发成 `MSIME_PREVIOUS_CANDIDATE`/`MSIME_NEXT_CANDIDATE`，即 host-api 的 102/103），Linux 与 HarmonyOS 同理。

改在共享层（`crates/input-runtime`），两个触发条件按来源逐条对应，扩充后的重排复用原有路径（`rerank` + `demote_runner_up_readings`），四条用例钉住：走到末尾能取到扣住的候选、踏进短尾页前先填满（与翻页一侧同形，页面不会先短一下再长出来）、引擎没有存货时高亮停在最后一条不回绕、向上走永远不请求扩充（否则会在用户往回读的时候重排列表）。

同组其余四项没有缺口，一并记下判据：候选窗的固定位置项本仓已按来源的 `#379AD3` 单独着色（`InputController.mm` 的 `candidateFixed`，与来源 `candidate_view_model.h` 同值），不与高亮合并；悬浮工具栏可见性 `configured_enabled && !fullscreen && ime_active` 与来源 `floating_toolbar_visibility_policy.h` 逐项相同（`MetasequoiaFloatingToolbarShouldShow`）；`candidate_size_estimator` 是 Direct2D 的度量工具，macOS 侧由 `CandidateRowFit.h` 和原生面板用例覆盖，属实现形态差异；翻页键的六组开关（minus/equal、逗号句号、方括号、Tab、PageUp/Down、方向键）macOS 全部消费，另有 Home/End 落在当前页首尾。（**这句在 2026-09-21 的第二十五批被推翻**：来源不是没有 Home/End，而是在客户端一侧把它们分类成 `FUNCTION_MOVE_PAGE_TOP/BOTTOM`，选的是整份列表的首末项。见该批。）

方向键的朝向是刻意的平台适配：来源只认 ↑/↓，macOS 按候选窗朝向决定（竖排认 ↑/↓，横排认 ←/→），这是既有决定，不动。

增量记录（2026-09-20，视觉层）：文字各层比完，转到最影响「看起来一不一样」的东西——配色与度量。结论是这一层**本来就是精确移植**：

- 配色。来源 `styles/variables.css` 的深色 64 个、浅色 63 个变量，与本仓 `styles.css` 里两个主题块逐值相同，唯一差异是一条长阴影在本仓换了行、渲染值一致。
- 侧边栏。来源 `sidebar.css` 的 26 处像素度量逐条对过：宽 200px、纵向内边距 12px、item 的 6px/12px 内边距与 2px/8px 外边距、gap 15px、圆角 5px、指示条 4×22px 且 999px 胶囊圆角、图标 24px 容器配 22px 图、头部 25px 图标与 19px 标题、`contain: layout style paint`、`scrollbar-gutter: stable`，全部一致（本仓写作 Tailwind：`w-50`、`py-3`、`gap-[15px]`、`rounded-[5px]`、`before:rounded-full`、`translate-y-px` 等）。
- 卡片与分节。`.section` 的 18px 下边距、20px 24px 内边距、1px 边框、8px 圆角、卡片背景与阴影，`.section-title` 的 15px/550，`.section-header` 的两端对齐 gap 10px，`.divider` 的 0.5px，全部一致；本仓另加了来源不需要的窄屏适配。

也就是说用户最初说的「UI 完全不一样」，不在配色和度量，而在本轮前十三片修掉的那些：占位应用图标、侧边栏顺序与两对重复图标、各页 section 的顺序与叫法、选项与描述文案。

这一层此前同样没有任何检查。现把来源的 `variables.css` 按 `packages/ui/src/upstream/` 既有做法引入为 `settings-variables.css`，并加 `scripts/test-settings-palette-parity.py` 逐值比对、接入 `verify-local.sh`。本仓用 Tailwind 重新声明同一批名字而不是引用那张表，所以两份副本会一个色号一个色号地漂移而无人察觉——正是该有检查的形状。

写守卫时先做错一版：用 accent 的值本身当区分两个主题块的锚点，于是改 accent（最可能被改的那一个）会让锚点消失、抛异常栈而不是报出差异。已改用 `color-scheme` 作锚点，并在找不到锚点时给出说明。改一位十六进制验证：现在报「dark: --accent-color is #8e8cd9 here and #8e8cd8 in the source palette」。

增量记录（2026-09-20，按钮与操作项）：标题、选项、描述之后比最后一类可见元素——可点的操作。来源各 partial 的按钮逐个在本仓查过，只有两个没有同名对应物，且都不是缺口：`批量导入` 与 `新增短语`。来源把它们分在两处（dict 页的纯汉字批量导入、tools 页的快捷短语编辑器），本仓合成一个「本地词库管理」，以全拼/五笔/英文/快捷短语为类别，查询、新增、编辑、导入、导出、删除俱全，描述里写明导入支持「标准、Windows TSV、Rime 和纯汉字自动注音」——正是来源那个批量导入做的事。不把本仓的「导入」改名成「批量导入」：它同时兼管另外三种格式，改名反而说窄了。

顺带扫了反方向的问题——本仓有没有在某个宿主上显示却点不动的按钮。共享设置页一份、六个宿主，宿主能做什么以可选回调的形式到达；一个按钮若不检查回调是否存在，就会在做不到该功能的宿主上照常渲染、按下去什么也不发生。死按钮比没有按钮更糟，它宣称功能存在。扫下来全部已门控（`disabled={!client.x}`、可选链，或外层渲染条件），包括处理得很细的一处：外部皮肤的「打开目录」在沙箱宿主上由 `importsSkin` 改写成它实际做的事，而不是许诺一个打不开的文件夹。

这条不变量此前只靠逐个按钮写得仔细来维持，没有任何检查。现加 `scripts/test-settings-action-guard.py` 静态守卫并接入 `verify-local.sh`。

写这个守卫时自己先写错一版：正则只匹配 `client.X(` 这种调用形式，而面板那几个按钮写的是 `onClick={() => void openPanel(client.openScreenKeyboard)}`——把回调传进辅助函数而不是调用。我删掉一个 `disabled` 去验证，守卫却仍然通过，才发现这一版是摆设。已放宽为匹配 `client.X` 的出现（调用与传参都算），重新验证：删掉门控会报 `index.tsx:7541`，还原后通过。

增量记录（2026-09-20，开关描述文案）：标题和选项都钉住之后，比最后一层可见文字——每个开关下面那句 `<small>` 描述。逐条比对前先在代码里核实来源的说法对本仓是否成立，成立的才采用。

采用三条，每条的断言都验过：

- 智能标点。来源写「中文标点模式下，字母或数字后的 , . : 自动使用英文标点」，本仓原文是「根据输入上下文选择中文或英文标点形式」——说了等于没说。`SmartPunctuationRepeatPolicy.chineseMark` 处理的正是 `, . :`，`isAsciiAlphanumeric` 对应「字母或数字后」，来源的说法准确，采用。
- 重复标点转中文。来源写「智能标点输出英文标点后，2 秒内再次输入同一标点时替换为中文标点」，本仓原文是「短时间重复输入 ASCII 标点时转换为中文标点」，既没说 2 秒也没说前提。`SmartPunctuationRepeatPolicy.WINDOW_MS` 就是 2000，`KeyboardSession` 里那串前置条件也正是「智能标点已输出英文标点」的情形，采用。
- 成对标点自动补全。来源写「输入左侧符号时自动补全右侧符号，并将光标置于中间」，本仓原文是「自动补全成对引号和括号」，漏了光标行为。补全路径里确有 `moveCursorSync(CURSOR_LEFT)`，采用。

**不采用**一条：候选词翻译。来源写「仅在竖排候选窗口中显示中文与所选语种的互译，每项最多两个简短释义」，这两个限制对本仓都不成立——本仓支持同时显示两种语言（另有「候选词翻译第二种语言」一项），且 HarmonyOS 触屏的候选行是横排、翻译就渲染在那里。照抄会把不成立的限制写进界面。

改完撞到一个和先前「云候选」同类的问题：新描述里含「智能标点」四字，于是 `getByRole("checkbox", { name: /智能标点/ })` 同时命中「智能标点」和「重复标点转中文」两个开关，已改为锚定的 `/^智能标点/`。这类正则在描述文案变化时会失效，值得注意。

未验证：这三行没有在设备上目视确认——模拟器滚动粒度较粗，几次都跨过了标点那几节。改动由 343 条测试与 bundle 漂移门覆盖，HAP 安装后页面渲染正常。

增量记录（2026-09-20，下拉选项的文案）：section 标题已由 `referenceSections` 钉住，这一轮下沉一层比选项本身。来源三处与本仓不同（取值一致、只是标签）：「候选项排列方式」来源是 横向/纵向 且横向在前，本仓是 竖排/横排；「候选窗预编辑」来源是 拼音分词/不显示，本仓是 显示拼音/隐藏；「中英文状态」来源是 按应用记忆/全局统一，本仓是 按应用/全局。第二处同时是仓内不一致——紧挨着的「行内预编辑」对同一组 `pinyin`/`empty` 用的就是「拼音分词/不显示」。三处均已改用来源的说法，并新增 `referenceOptions` 表把这五个控件的选项逐项钉住。设备确认：外观页尾部现在显示 纵向 与 拼音分词。

同一轮把来源另外两个集中策略头文件核完，均无可修项：

`server/src/window/floating_toolbar_visibility_policy.h` 两条。`ShouldShowFloatingToolbar(configured_enabled, fullscreen, ime_active)` 本仓的 Windows 宿主已经实现（`platforms/windows/src/system/server_main.cpp`），连来源自己的用例也已移植（`platforms/windows/tests/core/fullscreen_foreground.cpp`）。HarmonyOS 覆盖了其中两项——工具栏只在 `desktop && toolbarEnabled()` 时创建，且活在键盘扩展里，我们不是当前输入法时它根本不存在。缺的 `fullscreen` 一项**没有可用信号**：输入法扩展只能拿到 `display.getDefaultDisplaySync()` 的尺寸与密度，前台窗口是否全屏属于窗管的特权查询，STATUS_BAR 面板在全屏下的去留由系统决定。这是平台能力差异，不是实现缺口。另一条 `ShouldDeferFloatingToolbarHide` 是 WebView2 首帧宽限期，无对应物。

`server/src/window/ui_backend_policy.h` 是在 Direct2D 原生渲染与 WebView2 之间按 surface 选择后端，即来源外观页那一项「界面渲染」。HarmonyOS 用 ArkTS 原生渲染，没有第二套后端，无对应物——与第二片记录的「界面渲染不引入」一致。

增量记录（2026-09-20，`input_key_policy.h` 逐条走完）：不再抽查点位，把来源 `server/src/ipc/input_key_policy.h` 里那八条 `constexpr` 当作契约整体核对。结果：

- `IsEnglishModeToggleKey`（Ctrl+Shift+E）、`WordToCharacterDirection`（无修饰键的 `-`/`=` 或 `[`/`]`）—— 上一片已确认相符。
- `NormalizeNumpadDigitKey` —— Harmony 的 `HardwareKeyRouter.normalizeNumpad` 同样把小键盘 0–9 归一成主键盘数字，并在 `route` 入口只做一次（来源在 Server 边界做一次），且多填了缺失的字符。
- `ShouldLearnEnteredEnglishWord` —— `engine-bridge` 的 `commit_raw_with_policy` 里是 `before.dedicated_english || local_special_mode || (chinese_scheme && !complete_pure_pinyin)`，与来源逐项相同。
- `IsBackendIndependentCompositionResetKey`（Shift/Esc）与 `ShouldResetCompositionForImeMode` —— 这两条是 Windows 分体架构下 Server 与 TSF 的**同步**约定（TSF 已在本地取消组字，Server 必须跟着重置后端），HarmonyOS 的键盘扩展自己拥有组字，没有对应物。其用户可见效果「离开中文模式会清掉正在拼的字」在本仓由引擎的 `set_dedicated_english_mode` → `reset_composition()` 覆盖，已在上一片钉住。来源的 Shift 切换同样受 `ReadConfiguredSwitchLanguageHotkeys().shift` 门控，与本仓一致。
- `ShouldSendCompositionReply`、`InputSessionMatchesConfig` —— 都是 Windows IPC 回包协议的内部规则，非分体架构没有对应物。

来源自己有一份该策略的测试 `server/tests/src/test_input_key_policy.cpp`。把其中以词定字那组用例移植到本仓的路由测试上，补齐了此前没覆盖的三类：偏好错配（设为 minus_equal 时按方括号必须无效，反之亦然）、功能关闭、以及任一修饰键按下时都不生效（来源写作 `(modifiers & kKeyModifierMask) != 0`，本仓等价于 Ctrl/Alt/Meta 在更上面被 RELEASE、Shift 在分支内排除）。已把错配那一条的守卫放松验证过测试确实会红。

移植时自己先错了一次：夹具把 minus/equals 的 keycode 写成 2041/2042，实际是 2057/2058，于是「minus/equal 在其为配置项时生效」那条失败——是夹具写错不是代码问题。

增量记录（2026-09-20，硬件键盘的按键归属）：沿上一片往下核了四处，**全部相符**，结论记在此处以免再查：

- 以词定字的修饰键。来源 `WordToCharacterDirection`（`server/src/ipc/input_key_policy.h`）要求不带任何修饰键，`(modifiers & kKeyModifierMask) != 0` 直接返回 0。Harmony 的对应分支只显式写了 `!key.shiftKey`，看着像漏了 Ctrl/Alt，实际 `HardwareKeyRouter` 在更上面就有 `if (key.ctrlKey || key.altKey || key.logoKey) return RELEASE`，带修饰键的组合根本到不了那里，等价。
- 模式切换快捷键。Harmony 的 `mode_switch_shortcuts` 为真，实现不在 `HardwareKeyRouter` 而在 `InputModeRouting`，由 `KeyboardExtensionAbility` 在按键进引擎之前先行消费。
- `Ctrl+Shift+E`。来源 `IsEnglishModeToggleKey` 绑的英文模式切换，`InputModeRouting` 已实现，套件里也有「Ctrl+Shift+E switches the composing language」。该模块头注释写明 `Ctrl+Shift+E`、`Ctrl+Shift+Space`（全半角）、`Ctrl+.`（标点集）三条都按 Windows 基线固定实现。
- 切换语言是否清空组字。来源是 `SetEnglishInputMode` 紧跟 `ClearState`；本仓经 `msime_client_set_english_mode` → `runtime.set_dedicated_english` → 引擎 `InputSession::set_dedicated_english_mode`，后者在标志真正翻转时调 `reset_composition()`，行为一致。

最后这条此前没有任何测试钉着：`input-runtime` 测试桩的 `set_dedicated_english` 用的是 trait 的空默认实现，所以该行为成立仅仅因为真实引擎恰好会重置。考虑到本仓引擎比来源新 467 个提交，这正是该钉住的一类风险。现让测试桩如实建模（模式真正改变时清空组字，重复设置同一模式不动），并加测试断言切换语言后组字消失、重复设置不误清。已把重置去掉验证过它确实会红（`left: "a"`, `right: ""`）。

增量记录（2026-09-20，组字期标点的上屏时机）：来源在组字进行中遇到标点时，先用高亮候选结束组字、再输出该标点——`IsCommitWithHighlightedCandidatePunctuationInCandidateMode`（`server/src/ipc/event_listener.cpp`）列出的是 `` ` ! @ # $ % ^ & * ( ) [ ] ; : \ " , < . > ? ' ``，并排除三类：`-`/`=`/Tab 永不触发，`,`/`.` 与 `[`/`]` 在被配成翻页键时也不触发。共享运行时的 `punctuation()` 行为与之一致（先 `engine.finish(self.highlighted)` 再翻译标点），注释里也写明了原因。

差的是 HarmonyOS 的硬件键盘路由。`HardwareKeyRouter` 的标点分支写的是 `!composing && chinese && !japanese && isAsciiPunctuation(...)`，只在**没有组字**时把标点交给引擎；组字进行中则落到 `return RELEASE`，把键还给应用。于是在 2in1 上敲 `nihao` 再按 `!`，组字仍开着而 `!` 被插进编辑器里、排在还没上屏的拼音前面；触屏路径不受影响，它直接调 `KeyboardSession.punctuation()` 走运行时。现去掉 `!composing` 这一条：标点无论是否在组字中都归键盘所有，组字中的那次由运行时按来源的规则结束组字。翻页键不受影响——它们在更上面的 `composing` 分支里就被消费掉了，且按 keyCode 匹配（逗号是 2043），日语标点仍归应用。

写这条测试时自己先踩了一次：夹具用 `keyCode: 0` 配 `unicodeChar: ','` 去验「逗号仍然翻页」，而导航是按 keyCode 匹配的，于是逗号没被认成翻页键、落到了标点分支——是夹具写错，不是代码问题，已改为用真实 keyCode 并断言 `PREVIOUS_PAGE`。

增量记录（2026-09-20，把逐页核对固化成可执行的检查）：前四片的页面对照都是靠读两边的源码得出的，而两边的朴素搜索都会失真——来源用 `class="section-title ai-heading"` 这类组合类名，本仓大量标题由 `{label}` 表达式渲染，于是同一批结论被反复重新推导，我自己在本轮里就误判过「实用功能少了八种模式」「皮肤页没有外部皮肤」。现把已核实的对应关系写成 `referenceSections` 表并配一个 `test.each`，覆盖外观、输入、辅助码、实用功能、悬浮工具栏、屏幕键盘、手写识别板、帮助八页：任何一节被删掉或改名，这里直接失败。已用「把候选项排列方式改名」验证过它确实会红。

写这个表时发现两类先前没注意的门控，都不是缺失：其一，好几节挂在宿主能力后面（`candidate_font_controls`、`candidate_follow_cursor`、`ime_mode_scope`、`floating_toolbar_appearance`），用裸 fixture 断言会把「宿主没声明」误读成「界面没有」，故 fixture 按 `host_surface.rs` 给 Windows 的那组能力来写；其二，`候选窗主字体` 在本仓的 Windows 宿主上是被 `{!windows && …}` 有意隐藏的——Windows 显示的是「候选窗英文字体 + 补充字体」，那行还带 Windows 专属的「保存后自动应用」说明，而来源显示的是「主字体 + 中文补充字体」。这是 Windows 字体路径上的既有取舍，不属于 HarmonyOS 的迁移范围，表里以注释记录而不断言。

同一轮还核过几处怀疑、结论都是已实现或有意适配，一并记下以免再查：HarmonyOS 的 `InputCommand` 枚举值与 C ABI 的命令码逐一对应（分段命令是显式的 12/13/14，不是顺延的 9/10/11）；翻页键集合覆盖来源的 `IsPagingKey` 全部并多出鼠标滚轮；日语浊音/半浊音/小假名在触屏上以 `SURFACE_VARIANTS` 面板实现（点假名直接按下对应罗马字笔画），而不是来源的 `CycleKanaVariant` 循环命令。

增量记录（2026-09-20，输入行为层第一片）：先确认了一件决定工作量的事——两个仓库用的是同一个引擎 `github.com/metasequoiaime/MSIME-Engine`，来源以 submodule 锁在 `6bd22549`，本仓以 `engine-lock.json` 锁在 `0531d421`，而后者比前者**新 467 个提交**（来源那个 commit 是本仓的祖先）。所以候选生成、分词、词库这些引擎行为不存在「缺失」，本仓跑的是同一引擎的更新版本；行为差异只可能出在宿主怎么驱动它。本仓的候选快照字段（candidates / candidate_codes / candidate_annotations / candidate_sources / candidate_positions / candidate_corrected）也与来源 `CandidateViewItem` 的 text/annotation/badge/translation/fixed_position 一一对应，并多一个纠错标记。

据此查到一处真实差异并修掉：引擎会把一部分候选扣在初始结果之后，要调 `expand_initial_candidates` 才放出来，而运行时里这个调用只有一处——`expand_for_next_page`，只在 `Action::NextPage` 时触发。翻页的宿主能拿到，改为「一次列出全部」的触屏宿主则永远拿不到。`all_candidates()` 是 `&self`，只读 `self.cached`。实测（`withholding_runtime(12, 8, 5)`）：翻页前 `all_candidates()` 返回 12 条，翻页到底后返回 20 条——号称「全部」的面板少了 8 条，正好是引擎扣住的那批。HarmonyOS 的触屏路径用的就是 `allCandidates`（`KeyboardSession.ets`，注释写明沿用 iOS 的做法放弃翻页），所以这 8 条在触屏上无法通过任何操作到达。现让 `all_candidates()` 先扩充再返回：这个调用本身就是「把全部给我」。扩充失败不致命，调用方仍拿到已有的那一代。

未验证：设备上的候选条数没有亲眼确认。改动在 Rust 侧，已用 `MSIME_OHOS_DEPS` 复用既有前缀重新编出 `libmsimeclient.so` 并打包安装成功，但要看到展开列表需要先在系统设置里把输入法设为当前输入法，这条 GUI 路径本次没有走通。证据是运行时里实测的 12→20。

增量记录（2026-09-20，候选窗与悬浮工具栏面板对照）：设置窗逐页走完后，转到打字时出现的两个面板本身。

候选窗。来源的呈现规则在 `server/src/window/candidate_view_model.h`：一项由 text + annotation + badge 串接，翻译另起 `cand-translation`，而固定位置的项会被单独套上 `color:#379AD3`。本仓 `KeyboardView.ets` 的候选行把固定位置和高亮合并成同一个 `candidateAccentColor()`，于是在任何「强调色即选中色」的皮肤上，已固定的候选和当前选中的候选看起来完全一样——而固定位置这个功能的意义就在那个标记。现按来源给固定位置项独立配色，规则收进 `CandidateSkinPolicy.rowTextColor`，四条断言钉住四种组合。

候选管理菜单不改。来源的桌面右键菜单是 置顶 / 固定排位→第 1–5 位 + 取消固定 / 删除；本仓是 优先显示 / 第 1–5 位 / 取消固定 / 删除词条…，把悬停子菜单摊平（触屏上没有悬停），措辞则与 iOS、Android 一致。`platforms/android/README.md` 写明这套顺序与措辞对齐的是 Apple 来源的长按菜单，三个触屏平台共用。HarmonyOS 是触屏平台，改成 Windows 的说法会破坏三端一致并推翻既有决定。「删除词条…」的省略号也有意义：本仓这一项 `confirmationRequired` 为真，来源那条不是。

悬浮工具栏已齐。来源设置页里的 6 个组件 id 与标签（character_set / emoji / fullwidth / punctuation / screen_keyboard / settings）与本仓 `floatingToolbarComponents` 完全一致，加上「中英文切换」这个始终显示项；本仓多一个 `english_mode` 属扩展。缩放、图标尺寸、组件三节的标题也与来源同名同序。

未验证：固定候选的配色只有单测覆盖，没有在设备上目视确认——需要启用输入法、聚焦文本框、输入、长按候选、选固定这一串操作，本次没有完成。

增量记录（2026-09-20，其余各页逐页核对）：把来源剩下的 13 个 partial 与本仓对应页逐项比了一遍。结论是绝大多数已经齐备，先前几次「缺口」判断多半是提取方法的问题——来源用 `class="section-title ai-heading"` 这类组合类名，本仓大量标题由 `{label}` 表达式渲染，两边的朴素正则都会漏。实用功能页的 K/T/U/E/M/J/Y/R 八种模式（`localModeRows`）、皮肤页的「外部皮肤」（在 `skin/external-skins.tsx`）、快捷键页的「简繁切换」、语音页的「录音时静音其他声音」都确实存在且与来源同序；关于页的「Server 端日志」在 Linux 上改称「IBus 宿主日志」，「TSF 端日志」已按 Windows 门控，都是正确的适配。

真正的差异只剩两处措辞，已改：辅助码页两个方案块共用同一句「在候选窗口显示辅助码」，两个 checkbox 的无障碍名完全相同，来源是分别点名的「在候选窗口中显示双拼辅助码 / 全拼辅助码」，现按来源各自命名（移动端保留「候选栏」的说法）；语音页「录音时静音其他音频」改为来源的「录音时静音其他声音」。

本仓「启用 AI 辅助」没有改成来源的「启用 AI 联想」：来源那个开关只管第 3 个候选，本仓这个还管 iOS 键盘 AI 回复与 Android 选中文字润色（描述里写明），改名会把范围说窄。

顺带修了 develop 上先前就存在、与本片无关的 5 个失败用例（在干净 `origin/develop` 上复现过）：

- 豆包识别的测试按钮被 `harmonyPlatform && provider === "doubao"` 收窄，Windows 与 macOS 上不再出现，而这两个宿主的用例一直覆盖它；豆包属于共享探测，已并入 provider 列表。对应测试的期望原本 `...ASR_PROVIDER_DEFAULTS.doubao` 整个铺开，把载荷从不发送的 `documentation` 也断言了进去，改为显式列字段。
- 屏幕键盘用例 `Caps Lock and Shift invert letters` 同步断言按键投递，而投递是排队异步的，读到的是上一个按键；已按同文件另一条用例的写法 `await act`。同一条里 `getByRole("button", { name: "Ctrl" })` 不唯一（左右各一个），改为取第一个。该用例原先还期望 Caps Lock 会把键面变成大写——与来源相反：`ui/demos/msimeui-keyboard-demo/KeyboardPanel.cpp` 第 196 行的键面只取 `shiftActive_`，第 313 行送出的字符才用 `capsActive_ != shiftActive_`。本仓行为本来就与来源一致，是这条期望写反了，已按来源改正。

增量记录（2026-09-20，输入页与来源对齐）：第三片，比对来源 `partials/input.html` 的 29 项。

顺序：来源是 输入模式 → 输入方案 → 双拼/五笔/日语方案 → 翻页方式 → 候选词翻译 → 在线翻译服务 → 以词定字 → 标点若干 → 中英混输 → emoji/颜文字混输 → 默认中英文 → 中英文状态 → 简繁输入 → 云候选 → 拼音方案调频。本仓此前把「默认输入状态」「中英文状态范围」放在页首，把翻译相关放在标点之后，把中英混输排到接近页尾，与来源出入较大。现按来源重排，本客户端独有项贴着同类放：全拼纠错/模糊音/学习选词习惯跟在「以词定字」后，全角输入跟在「中文标点」后，中文标点后按空格转换/数字后直出/字母后直出跟在「重复标点转中文」后，标点锁定跟在「成对标点自动补全」后，中英文切换提示/显示英文释义/英文建议跟在「中英混输」后，手写输入、Android 手写输入、高情商回复与按键反馈分别留在首尾。

叫法：6 处改用来源的说法——候选翻译→候选词翻译、成对标点→成对标点自动补全、默认输入状态→默认中英文、中英文状态范围→中英文状态、繁体中文输出→简繁输入、云联想→云候选。最后一条同时消掉了本仓内部的不一致：emoji/颜文字那两项的描述本来就写作「云候选」。

两处刻意不改，都会把界面写错：来源的「始终使用英文标点」与本仓的「中文标点」绑的是同一个 `chinese_punctuation`，但极性相反，只改名不反转控件即是错标；来源的「在线翻译服务」这个名字本仓已用于 Linux provider 那一节（`index.tsx` 里 `aria-label="在线翻译服务"`），把「翻译服务」改成它会出现两个同名 section。

测试：顺序测试的标题提取改为只读 section-title 自身的文本节点，排除嵌套的 `<small>` 描述——先前用 `startsWith` 会把「中文标点后按空格转换」当成「中文标点」。外观页那条一并改成同一实现。另外「云联想→云候选」让 `findByRole("checkbox", { name: /云候选/ })` 同时命中 emoji 与颜文字开关（它们的描述里就有这三个字），已改为锚定的 `/^云候选/`。新测试已验证在重排前的顺序下失败。

设备证据（MateBook Pro 2in1 模拟器）：输入页首屏为 手写输入 → 高情商回复 → 输入方案（触屏变体），页尾为 简繁输入 → 云候选 → 拼音方案调频（调频方式 / 触发频次(第几次上屏触发) / 线性调频步长）→ 按键反馈，与来源同序。

增量记录（2026-09-20，外观页与来源对齐）：接着侧边栏往里做一层，比对来源 `partials/appearance.html` 的 21 个 section。

措辞：同一项设置两边叫法不同的有 10 处，统一改用来源的说法——全局主题→主题模式、设置窗口主题→设置界面主题、候选窗主题→候选窗口主题、工具栏主题→悬浮工具栏主题、Emoji 面板主题→表情面板主题、手写面板主题→手写识别板主题、语音面板主题→语音输入弹出条主题、候选布局→候选项排列方式、候选字号→候选窗字号、每页候选数量→每页候选项数量。只改共享设置窗，macOS 的 `AppearancePreferences.mm`、fcitx5 与 IBus 菜单里的同名字串不动：那是各平台自己的界面，有自己的参考。「候选窗补充字体」没有跟来源叫「候选窗中文补充字体」，因为本仓这一项也承担非中文回落，且另有「候选窗英文字体」一行，照搬会写错。

顺序：来源是 预览 → 界面渲染 → 跟随光标 → 字体 → 字号 → 颜色 → 每页数量 → 各类主题 → 排列方式 → 预编辑，而本仓把 8 个主题下拉全堆在预览之后，第一屏观感因此完全不同。现按来源重排，本客户端独有的几项贴着同类放——6 个候选配色跟在「候选文字颜色」之后，「双拼预编辑」跟在「候选项排列方式」之后。来源的「界面渲染」是 Windows 专有，不引入；「屏幕键盘主题」本仓在「屏幕键盘」页而非「外观」页，属位置差异，本次不动。新增测试只钉相对顺序，宿主隐藏某一节时不会误报，并已验证它在重排前的顺序下确实失败。

设备证据（MateBook Pro 2in1 模拟器）：外观页依次渲染为 候选窗口预览 → 候选窗口跟随光标 → 候选窗英文字体 → 候选窗主字体 …… → 表情面板主题 → 手写识别板主题 → 语音输入弹出条主题 → 候选项排列方式 → 双拼预编辑 → 行内预编辑 → 候选窗预编辑，与来源同序。

排查记录：中途两次装机后设置窗全白，一度怀疑是本次重排。实为宿主负载过高（磁盘 99%、多个交叉编译并行）时应用被 `THREAD_BLOCK_6S` 强杀，日志里是主线程卡在 `webViewTask`，不是页面报错——腾出空间后同一份产物渲染正常。判据：只含改名不含重排的产物在同样条件下也曾正常，而干净 develop 在磁盘紧张时同样会白屏。

增量记录（2026-09-20，侧边栏与来源对齐）：逐项比对来源 `ui-html/webview2/settings/ime-settings/src/partials/sidebar.html` 的 15 项与共享 `pages`。图标先比过一遍：已引入的 13 个与来源逐字节相同，但 `ai.svg` 与 `voice_input.svg` 当初没引入，代码于是让「语音输入」复用手写识别板的图标、「AI 辅助」复用帮助的图标——侧边栏上因此有两对完全一样的图标，这是引入不完整而不是设计选择。两个图标已补齐并改回各自引用。

顺序也对齐到来源：来源是 外观 → 输入 → 辅助码 → 快捷键 → 词库 → 皮肤 → 语音输入 → 屏幕键盘 → 手写识别板 → 实用功能 → AI 辅助 → 悬浮工具栏 → 帮助 → 关于 → 反馈，此前本仓把语音输入排在手写识别板之后、实用功能与 AI 辅助互换，且把「打字统计」插在输入和辅助码中间。现在 15 项与来源同序，本客户端独有而来源没有的几页（我的、AI 对话、社区、打字统计）整体排在这一段之前而不是插在中间，这也正是移动端宿主提升的那一组。macOS 不受影响：它按 `macosSidebarGroups` 分组，参照的是另一个参考窗。新增一个把这条平铺顺序钉住的测试，与既有的 macOS 分组测试同法，避免以后加页面时悄悄把来源的次序挤散。

设备证据（MateBook Pro 2in1 模拟器）：侧边栏渲染为 我的 → 打字统计 → 外观 → 输入 → 辅助码 → 快捷键 → 词库 → 皮肤 → 语音输入 → 屏幕键盘 → 手写识别板 → 实用功能 → AI 辅助 → 悬浮工具栏 → 帮助 → 关于 → 反馈，语音输入为麦克风、AI 辅助为机器人，每项图标互不相同。同时确认上一片留的开放项：应用图标换成来源标识后，状态栏托盘图标重装时未刷新确属系统对已启用输入法的缓存——模拟器重启后托盘显示的就是品牌标识。

增量记录（2026-09-20，HarmonyOS 失败形状对齐）：承接上一条留下的那类缺陷。共享设置 UI 解码失败的主契约是普通对象上的 `error.code`（`accountMessage`、`dictionaryErrorMessage`、`message` 以及社区、聊天、皮肤编辑器各自的 `switch (error.code)`），只把 `Error` 的 `message` 当兜底文案读。本宿主的 `unwrap` 一直抛 `new Error(reply.error)`，而 `Error` 实例没有 `code` 属性，于是这些表一条都匹配不上：账号的六种失败全都落到同一句「账号服务暂不可用」，取消登录不被识别为取消，词库失败丢掉自己那句具体建议，AI 失败则把机器码本身显示给用户。现改为与桌面端 Tauri 的 `CommandError { code }` 同形，抛 `{ code }`。页面启动失败那一处是唯一自己渲染错误的地方，两种形状都要认，故单独取文案。

偏好保存/读取那条路的错误来自 Rust C ABI，而 C ABI 的错误通道是全仓每个入口共用的单一字符串，里面是 `PreferencesError` 的英文 `Display` 文本而不是码——桌面端是在 Tauri 层按枚举匹配出码的。本片在本宿主的对应层（ArkTS 桥）做同样的事：`PreferencesErrorCode` 把共享 UI 确有文案的那几个变体的文本映回码，其余一律 `storage`，与桌面端对未命名失败的处理一致。文本匹配比按枚举匹配弱，所以刻意做窄：文案漂移只会让该失败退回泛化文案，不会给出错误的文案；并在 `crates/client-core` 加了一个把这些文案钉死的测试，漂移在改文案的地方就会被发现。不改 C ABI——iOS、Linux、Android 都在消费同一个错误通道。

设备证据（同一台 MateBook Pro 2in1 模拟器，同一复现路径）：接口地址填不可达的 `https://127.0.0.1:1/v1` 并填入 token 后点「获取模型列表」，上一版显示机器码 `ai_models_unavailable`，本版显示「获取模型失败，请检查地址、密钥和网络。」，与桌面端一致。合成卡顿在 `inputText` 唤起系统输入法后同样复现，移动窗口即重绘，与上一条记录的判断一致。

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

增量记录（2026-09-20，Linux 本批：先把这个平台编译得出来，再谈功能对照）：本批的起因与 Windows 第三批同形——此前 Linux 的每一条记录都写着「逻辑回归通过」或「仍待 Linux 环境验证」，而事实是**这个平台的两块产物都构建不出来**，且没有任何一个门禁阶段编译过它们。先修构建，再修构建跑起来之后暴露的东西。

1. Tauri 外壳在 Linux 上有 36 个编译错误（`--all-targets` 54 个）。即设置窗口、全部共享面板（表情、剪贴板、手写、屏幕键盘、语音、云词典、云剪贴板）和账号界面在这个宿主上不是「缺某个功能」，而是构建不出来。成因是把面板投递从 crate 根挪进 `panel_input` 那次重构：crate 根与 `panel_window` 仍在无限定地调用被挪走的私有函数，`clipboard_history` 丢了 `linux_clipboard` 与 `Mutex`，四处 `window.label().as_str()` 用到本工具链仍 unstable 的 `str::as_str`，一处 `Vec` 需要元素类型标注，六个面板纯函数用例够不着新模块。为什么没人发现：`cargo check --workspace` 只看宿主 target，而 macOS 上 `msime-desktop` 因为 `tauri.macos.conf.json` 把还没构建的 app bundle 列为资源被整包排除（就是本地每次都打印的那行 `msime-desktop: skipped`）。安卓那条阶段的注释早就写过同一个道理，只是没人给 Linux 加一条（#3218）。
2. 原生宿主同样构建不出来：三个测试的相对 include 比源码移动后的层级少一级，其中一个连自己的 fixture 都引不到，`platforms/linux` 整个 target 配置不出来。修完后 IBus engine、Fcitx5 插件、全部 provider 入口与 18 个测试目标全部通过。跑起来之后发现 `linux-online-provider-contract` 约每五次失败一次，原因是 unix socket 的一个具体语义：`unix_release_sock` 在关闭方接收队列里还有未读数据时会给对端置 `ECONNRESET`，而 provider 客户端把请求正文和结尾换行分成两次写，fixture 的单次 `read` 有时只拿到正文、回复后 `close`，客户端于是在读到已排队的回复之前先拿到 ECONNRESET。两侧都改（客户端整行一次写出、fixture 读满一整行），连跑 30 次 0 失败（#3229）。
3. 两块构建都接进了门禁：有 Docker 时在固定的 `rust:1.97.1-bookworm` 容器里分别 `cargo check -p msime-desktop --all-targets` 和 `platforms/linux/build-container.sh`（编译加 `ctest`），Linux 主机上直接用系统 ibus 开发包跑，两者都没有时跳过并打印命令。两条都做了反向验证：插入只在 Linux 分支成立的错误后，阶段确实报错并 FAIL。
4. 隔离验收此前连启动都不可能：`check-container.sh` 自己算错了仓库根（少一级），`docker build` 拿到的上下文是 `platforms/platforms/linux/tests`；镜像两处 `COPY` 指着测试重组前的位置；`platforms/linux/tests` 下二十来个 Python 测试把根算成 `platforms/linux/tests` 再拼 `scripts/…`，随包在线/语音/剪贴板 provider、凭据测试、豆包鉴权、翻译缓存、录音设备这一整片自那次重组起一个都没跑过。修好之后容器内 `ctest` 19/19，三个 crate 的 Rust 测试、Host API 头导出校验、词典 CLI 与剪贴板验收全部通过，安装产物齐全（#3239）。
5. 跑起来后找到两个真实宿主缺陷。其一：嵌套偏好对象整体可省略（共享 `Preferences` 给默认值）但成员一个都不能少，宿主把单个键补进文档里本来没有的 `mixed_input` / `local_modes` 时写出残缺对象，Host API 判为 invalid options document——没有配置共享偏好目录的部署里，从 IBus 菜单切一下混输候选或任一本地输入模式，会话就再也建不起来。默认值改由新的 `msime_client_default_preferences` 从共享层发布（#3239）。其二：`rendered_view` 在首次渲染前和每次会话重建后都是 null，而 `value()` 在 null 上抛异常、异常被 `guarded` 吞掉，于是中英文切换之后打的第一个字母被静默丢掉；十八处读里有两处没带 `is_object()` 守卫，其中一处还排在会短路的身份栅栏之前（#3245）。

功能侧本批补齐四项，都是「设置页有开关、这个平台不消费」那一类：共享设置页的双拼预编辑选择此前按平台名只给 macOS，而 IBus 与 Fcitx5 都自己把快照的 `preedit` 写进平台预编辑并各自带着原生菜单开关（#3199）；`smart_punctuation_space_convert` 在 IBus 与 Fcitx5 上都是存得下、读不出效果的开关，现按来源规格补上——含来源自己踩过的那条坑，即改写前要回读标点前面的字符核对指纹，因为同一个标点在文档里通常不止一处而窗口内移动光标不是焦点变化（#3206、#3231）；Fcitx5 的「重复标点回切中文」同理从只有开关变为真的生效，并补上退格后重按同键走中文路径的另一半（#3233）。

另有两项是这个平台整块缺失而非字段缺失：桌面外壳的九个账号命令此前只为 Windows、macOS、Android、iOS 注册，Linux 上登录、资料、改名、登出、注销没有宿主可调；补齐后会话存在共享状态目录下的 owner-only 文件里（0600、原子发布、读取前核对普通文件/属主/权限/大小），这弱于 Windows 凭据管理器与 macOS Keychain 的静态加密，接 Secret Service 需要新增依赖、属于另外的决定（#3220）。设置页的「获取模型列表」与「AI 润色测试」也不可用，因为持有 token 的宿主是自己发 HTTP 的，而这个平台按设计把 token 留在 provider 的私有配置里；改为 provider 的两种新请求，并用新能力位 `ai_provider_credentials` 表达「凭据归宿主的 provider」，替掉原先按平台名藏控件的做法（#3254）。

本批的验证边界要说清楚：没有任何一项在真实 Linux 桌面上跑过，没有 IBus daemon 之外的 GTK/Qt 编辑器、没有 X11/Wayland 焦点与选区、没有 Fcitx5 实例。engine smoke 也还没走完——修掉上面第 5 条之后，它稳定停在更后面的位置（passthrough 加偏好热重载那一例里，`nihao` 的后续按键），那是本批修复之后才够得着的位置，单独查。本批后段本机 Docker 停了，因此最后两个切片的容器阶段按设计跳过；它们不触碰 C++。

增量记录（2026-09-20，Linux engine smoke 又往前走了一大段）：修掉「会话重建后第一个按键被静默丢掉」之后，隔离验收的 engine smoke 停在 `phrase()` 的第二次调用。原来的断言只说 "Phrase key not consumed"，而这个 lambda 有 56 个调用点，一句话指不到任何一个；现已改为报出是第几次调用、哪一个键，位置立刻就定住了。

停住的是 `ime_mode_scope` 那个循环（先 `app` 后 `global`）的第一轮，它连续要求三件事：FocusIn 后 `InputMode` 属性为 checked（中文）；`!key(Ctrl_L 按下) && key(Ctrl_L 松开)`，即配置的 Ctrl 快捷键在松开时被消费；紧接着 `phrase()` 打出 `nihao` 并要求仍是中文。这三条一起不可能成立——宿主里 Ctrl 松开被消费当且仅当它真的切了模式（`process_key` 的那一段除了 `toggle_input_mode` 没有别的消费路径），而 `toggle_input_mode` 先翻转 `input_enabled`，再写进按应用的记忆，`open()` 又用 `restore_app_input_mode()` 把刚写进去的新值读回来。带探针实测：Ctrl 按下时 `enabled=1`，松开被消费，随后的 `n` 看到 `enabled=0`，走透传、不被领取。

判据取自本次迁移的准绳：Windows 上配置了 Ctrl 快捷键就会切换中英文，`ime_mode_scope` 决定的是这个状态记在哪儿、而不是快捷键动不动它，宿主实现的正是这一条。所以错的是 fixture 那一侧。改为切两次并各自核对模式：默认中文 → Ctrl 切到透传（断言不再是中文）→ Ctrl 切回中文（断言是中文）→ `phrase()` 组中文候选。覆盖比原来更多，且与 Windows 一致。

改完之后这一整段循环通过，运行又往前走了两段：

其一，「Ctrl+Enter did not commit the rendered candidate translation」。把断言改成会报出它看到了什么之后，一次运行就说清楚了：`handled=1 committed=[synthetic gloss [1]] preedit=0 lookup=1`——译文上屏、组合清掉、预编辑也收了，只有候选窗还在。原因不是缺陷：候选窗的隐藏走的是 `schedule_candidate_hide` 的 24ms 定时器，宿主故意延后，免得组合中途候选列表短暂清空时面板闪一下。断言读的是一个按设计还没到的值，改成按条件等待。

其二（当前停住的位置），「NiuTrans preference change did not request a new translation」。fixture 在 `invoke("Reset")` 之后打开 NiuTrans 并保存 revision 2，然后等 provider 收到第二次请求。但 Reset 之后既没有组合也没有候选，而宿主的行为是「设置热更新后立即调度**当前**候选的翻译」——没有候选就没有要翻的东西。要么 fixture 少了一次重新组词，要么期望的是配置变更对已显示候选的重新请求而 Reset 恰好把它们清掉了。这一条同样是「fixture 写的和宿主做的哪个对」的取舍，本次不猜。

另外记一条：「Online misses did not merge with the displayed offline hits」在三次运行里只失败过一次，另两次走过去了，是时序相关而不是恒定失败。

在此之前的部分全部通过：容器内 `ctest` 19/19、三个 crate 的 Rust 测试、Host API 头导出校验、词典 CLI 与剪贴板验收、完整安装产物，以及 engine smoke 自身在此之前的全部断言（含缺 `mixed_input` 对象那一例、直接输入透传、偏好热重载后不带会话的宿主快捷键重载、`ime_mode_scope` 的两轮、离线释义先于在线回填）。

增量记录（2026-09-20，Linux engine smoke 首次跑完）：隔离验收的 IBus engine smoke 从上一批停住的位置一路走到结尾，`IBus D-Bus shared-runtime acceptance passed`。这一段把宿主缺陷和夹具缺陷分开处理，下面按性质列。

宿主侧三处真实缺陷：

1. **匿名客户端丢失中英文模式。** IBus 从 1.5.27 才报告客户端身份，而且客户端可以不报；此前这两种情况下的模式一律丢弃，于是每次焦点离开再回来都退回配置的默认模式。Windows 上模式挂在 TSF client 上不会这样，最接近的做法是给匿名客户端一个共享槽位——分辨不出来的窗口就当成同一个。
2. **迟到的焦点身份把会话拆了。** 守护进程可能先发一次不带 context/client 的 focus、稍后才补上身份，`focus_in_id` 把第二次当成切换直接 `focus_out`，用户在协商期间打的字就没了。`focus_in` 里本来就写着「IBus may replay focus after negotiating client identity」，这层包装却先把会话拆了。现在当前焦点还没有身份时就地认领，并把屏幕上的模式带进这个身份。
3. **中英标点的偏好改动到不了会话。** 运行时把宿主的标点开关记成一个 override，它压过随后下发的偏好；宿主在绝对偏好目录下走的是保存-读回-`update_preferences`。于是从菜单关掉中文标点之后，界面状态和偏好文件都变了，会话却还在按上一次内联切换留下的值转标点，逗号照样出「，」。三处修：新建会话时把 override 写进传给会话的偏好（否则焦点切换、内容类型变化重建会话后又悄悄退回文件值）、`apply_session_overrides` 同样带上、`apply_live_preferences` 记住会话最后被告知的值并在生效值变化时重新下发。

夹具侧的错误期望，每一条都先拿到证据再改：

- 候选窗的隐藏是 24ms 防闪烁定时器，直接类调用又不走 D-Bus 往返、信号还排在队里。十六处「候选窗应已关闭」和两处翻页断言改成等条件；翻页那两处原先 next-page 读到的还是上一页，previous-page 反因此「通过」，错的方向上互相抵消。
- 查找表只携带面板当前显示的那一页，而夹具把页大小设成 2。「日期模式给出 13 个以上候选」永远不成立——引擎给的是 17 个。改为翻页收集。
- 超级简拼：引擎对 `nh` 的排序是 女孩、你会 在 你好 之前，夹具却按空格提交首选。改为翻页找到候选再点。
- 词频学习：词频排序按用户敲下的切分来，你好吗 按三段词排，永远不会排进 你好 的两段列表。夹具点的就是它，于是「私密会话里不学习」和「普通会话里恢复学习」两条断言都是空的——两边都不动、两边都通过。改成选一个与 nihao 同为两段的候选（这份词库里是 拟好），两条断言这才各自成立。
- `CandidateClicked` 的参数是 `(index, button, flags)`，混合候选那两处写成了 `(0, index, 0)`；宿主要求 button 在 1..5，候选落在本页第 0 位时整个事件被丢弃。
- 绝对偏好目录下的菜单开关是一次保存（写盘、读回、再应用），本地模式禁用和 NiuTrans 那两处在同一轮里就断言，测的是旧偏好。
- 会话重建：这段要验证「重建之后旧会话排队的回调不能再提交文本」，需要一次不跑主循环的同步重建。原来用 ShuangpinProfile 触发，但绝对目录下它只是排一次保存、`apply_live_preferences` 是往现有会话推偏好、根本不重建。改用内容类型切换（private 提示），那是真正的原地 close/open，也是生产里真实存在的路径。

三处时序：在线候选那几处先固定等 1.7 秒再读精确计数，机器一忙就输，改成等请求到达再静置证明没有第二次；在线漏词合并的 2 秒预算不够——放开 provider 之后还要过工作线程读取、idle 合并、500ms 翻译去抖和 150ms settle，放宽到 8 秒，断言的是「最终会合并」而不是「多快」；修饰键绑定那两处把禁用后的偏好注入进来，但快照里带着偏好目录，重载 tick 会把文件里的值放回去，注入的偏好能不能活到按键松开取决于 tick 落在哪儿，改为注入时不带目录。

工具链一处：`build-container.sh` 用固定 tag `:local` 构建门禁镜像，而多个 worktree 会同时构建它——谁最后构建完谁决定所有人跑的是什么。实测表现为同一条命令时灵时不灵。改为按 checkout 路径散列命名，并把 `dbus-bin` 装进镜像（`--no-install-recommends` 下 `dbus` 不会带上它），免得每次手跑 smoke 都要现装。

验证：连跑八次。验证边界不变——仍然没有任何一项在真实 Linux 桌面上跑过，没有 GTK/Qt 编辑器、没有 X11/Wayland 焦点与选区、没有 Fcitx5 实例；engine smoke 覆盖的是 IBus 宿主经 D-Bus 的行为。

增量记录（2026-09-21，Windows 第六批：跟进来源新基线，先补 Windows 从来没记过一个字的打字统计）：来源远端默认分支已推进到 `b1ec3202676163927ff8632126379a42df90294b`，比第五批固定的 `1e4c331d` 多出一批提交，其中「输入统计」是一整个新功能组（DLL 采集、Server 聚合存储、设置页展示），本对照表此前没有任何一行覆盖它。目标起点 `10fba7d75`。

先说清两边不是一回事，免得下次照着来源的文件名找落点：**本仓早就有打字统计**（`crates/client-core/src/typing_statistics.rs` 加 `packages/ui/src/settings/typing-statistics.tsx`，1051 行），而且比来源那一页更宽——它有日历热力图、七日均线趋势、输入方案排行、字符类型饼图，以及来源完全没有的候选命中位置分布（首选命中率）。来源新增的是另外一组指标：活跃时长、打字速度、连续天数、当日 24 小时分布。所以这不是「有没有统计」的问题，是**两套指标各有各的缺口**。

本批只做一件事，因为它是其中最硬的一个：**Windows 上这个页面永远是空的**。`typing_statistics` 能力位对 Windows 声明为 `true`，设置页照常渲染，但 `platforms/windows/` 整个目录没有任何一处调用过 `msime_client_typing_statistics`——macOS、Linux、Android、HarmonyOS 都在各自的上屏出口记录，只有 Windows 没有。Windows 用户看到的不是「统计不准」，是除了 Tauri 面板粘贴之外一个字都没有。

落点选在 Server 而不是 TSF DLL，这一条与来源不同且是有意的：来源把采集放进 DLL，因为它的 Engine 与 DLL 同进程；本仓 Server 是唯一看得到每一条上屏字符串的地方，共享 Host API 也链在这一侧，而文本本来就要作为上屏载荷从 Server 走到 DLL，采集不让它多跨任何一道边界。来源因此需要一条新的统计命名管道（`FANY_IME_STATS_*` 契约、`stats_frames`、`stats_pipe`），本仓一条都不需要。

实现要点三条，每条都有用例：

1. `PendingReply::committed_text` 由七个产生完整上屏的出口填写，**部分选词不填**。本仓的 `prefix_` 是「Engine 已选、DLL 尚未上屏」的暂存，分词选词会连着走好几步 `partial_selection` 才由最后一条 `candidate_commit` 整串上屏；哪一步都记就会把同一个词记好几遍。`reply_composer` 里新加的断言钉的正是这条。
2. 记录发生在投递**确认之后**（`confirm` / `confirm_ui`），不是组好回复的时候。写失败或结果不确定时 pending 保留、不确认，于是也不记——「已上屏」的含义因此是「已送达」而不是「已组好」，和来源在 DLL 的三个组字出口读文档内容是同一个判据。
3. 归属取 `transition.commit_context` 而不是上屏后的 view。上屏会清掉本地模式，只看 view 的话一次 Emoji 模式的上屏会被记成全拼。来源标识与 Linux/Apple 宿主逐个相同，三家写的是同一份文档。

性能上避开一个自己先写错的版本：最初在 `confirm()` 里整份拷贝 `PendingReply` 再判断有没有提交，而 `confirm()` 每个按键都走一次，等于在输入热路径上对含候选列表的 transition JSON 做深拷贝。改成只在确实有提交时取那一小段字符串，`resolve_typing_source_from_transition` 全程按引用取字段。

验证：x86_64 MinGW 交叉构建整套通过（host DLL、TSF DLL、Server、msimeui 与全部原生测试可执行文件，含新增的 `windows-typing-statistics`），i686 语法门禁 249 个源文件通过，`verify-local.sh --quick` 通过。**没有在 Windows 主机上安装运行**，因此没有任何一项声称真实编辑器里打字后统计页出现了数字。

同批顺手修掉一个与功能无关但一直在的问题：`docs/windows-parity.md` 里有六行 `||||||| <sha>`。pre-commit 早就有冲突标记检查，它只匹配 `<<<<<<<` 和 `>>>>>>>`，而 `merge.conflictStyle` 为 diff3/zdiff3 时 git 还会写一行基线标记——手工解决时删掉认得的三种、留下这一种，钩子不出声。钩子的正则补上基线标记（并顺带改成只看新增行：原来的 `-G` 对新增和删除一视同仁，删除标记的那次提交会被它自己拦住），另加 `scripts/test-conflict-markers.py` 扫描整棵已跟踪树并挂进 `--quick`。后者不是重复：钩子看的是差异，只可能看见引入标记的那一次提交，标记一旦进了 HEAD 就再也没有东西看它一眼——这六行就是这么活下来的。两个方向都反向验证过会红。

本批查出但**未动**的三处，记下来以免下次重新推导：

- 来源新增的活跃时长、打字速度（按活跃分钟算，且只数可读字符）、连续天数与当日 24 小时分布，本仓一项都没有。这是下一片，做在共享 `typing_statistics` 与共享设置页里，不做成 Windows 私有的 SQLite 表。其中一处需要单独决定：来源的速度只数 `cjk + latin`，而它的 `latin` 是纯 ASCII 字母、假名落在 `other`，于是日文输入的速度恒为零——本仓有完整日文模式，照抄会得到一个对日文用户明显错误的读数。
- 共享设置页有 11 处以上 `window.confirm`（删词条、清空统计、关闭模糊音、放弃未保存修改等）。来源本批把它换成自绘对话框，理由是在 WebView2 里它是宿主模态窗口、不跟随页面主题、弹出期间页面自己的键盘与焦点处理全被挂起——这三条对本仓的每一个 webview 宿主同样成立。更要紧的是本仓这套页面还跑在 iOS WKWebView、Android WebView 和 HarmonyOS ArkWeb 里，而**全仓没有任何一个宿主注册过 confirm 面板回调**。这几个 webview 在没有回调时是弹窗还是直接返回 false，我没有在设备上验证过，所以这里不写结论；但「返回 false」意味着按钮按下去什么都不发生，正是本表第 789 行那条「死按钮比没有按钮更糟」。需要在 iOS/Android/HarmonyOS 上各按一次删除确认才能定性。
- 来源的第六套辅助码「加加」（`566ff8b8`）与全拼备选切分／调频重排（`1ea01d5e`、`e32eeade`）都在 Engine 及其码表资产里。本仓 Engine 由 `engine-lock.json` 固定独立归档，这些行为要进来只能是提锁，与第五批同一条理由：提锁影响面覆盖全部平台，单独决定。

增量记录（2026-09-21，Windows 第七批：活跃时长、打字速度、连续天数与时段分布）：接上一批留下的第一条。来源仍固定为 `b1ec3202676163927ff8632126379a42df90294b`，目标起点 `50d624ac1`。

这一片补的是两套统计里**本仓缺、来源有**的那一半：本仓的统计页宽在维度（日历热力图、七日均线、方案排行、字符类型饼图、候选命中位置），但没有任何时间轴——不知道打了多久，因此算不出速度，也不知道打在一天里的什么时候。来源新增的正是这两个轴。

落点与来源不同且是有意的：来源把它做成 Windows Server 私有的 SQLite 表（`stats_store.cpp` 662 行，加 `stats_aggregate` / `stats_overview` / `stats_frames` / `stats_pipe`），本仓做在共享 `crates/client-core/src/typing_statistics.rs` 与共享设置页里。理由是这两个轴和「每天多少字」是同一件事的不同维度，而后者早就在共享层、六个宿主都在写同一份文档；为新的两列单开一套 Windows 私有存储，等于让同一个用户的统计分裂成两份。

**活跃时长**按「上一次上屏到这一次之间的间隔」累加，超过 10 秒的间隔算休息。阈值直接取来源基线的 `kActiveGapLimitMs`，它的注释记着校准过程（来源 #429：设成 5 秒会把正常思考停顿算成打字时间）。间隔归属到本次上屏的日与小时，与来源同构。三条边界各有用例：第一次上屏不产生活跃时长；时钟回拨不累加**且不把水位往回移**（否则校正后的第一次上屏会被当成新会话）；同毫秒的两次上屏不是间隔。10 秒边界两侧都断言了。

**小时**由宿主给，理由和日期一样，而且六个宿主每处都从**同一个瞬间**取日和小时——分两次取，跨零点时会把这次上屏记到一天的日期和另一天的小时上。`hour` 在契约里可选：没有小时的宿主照常记字数。越界小时丢弃而不折到相邻桶。

**派生指标**集中在一个纯函数 `activityMetrics`，`todayKey` 由调用方传入。其中一处**与来源有意不同**，即上一批记的那个待决项：来源的速度只数 `cjk + latin`，而它的 `latin` 是纯 ASCII 字母、假名落在 `other`，于是纯日文输入的速度恒为零。本仓有完整日文模式，照抄会给日文用户一个明显错误的读数，所以把 `otherLetter`（假名、谚文等）也算进可读字符。数字与标点仍然不算——一串电话号码不是行文。两边都有用例钉住。

其余判据与来源逐条相同并各有用例：今天还没打字不算断签（今天还没过完）；「最快一天」要求当天至少一分钟活跃时长，否则两秒敲二十个字的那天永远占第一，而平均速度不设这个门槛（它是总量之比不是排名）；「最多的一天」并列取最早。另加一条来源没有的：日期加减走 UTC，因为这些键是日历标签不是时刻，用本地时间算会在夏令时切换那两天把一段没断过的连续记录算断。

保留策略删掉某天时必须连着删掉它的两个新轴，否则刚写完的文档过不了自己的校验、用户会因为一条陈旧条目丢掉整份历史；`reset` 连 `last_commit_ms` 一起清掉，它是重置后唯一还能说出用户情况的字段。两条都有用例。

验证：`cargo test -p msime-client-core typing_statistics` 13 项、`apps/desktop` 全套 91 文件 806 条用例、HarmonyOS 逻辑回归 1204 条断言、Windows 纯逻辑用例全部通过；`cargo fmt` / `clippy` / `tsc --noEmit` 干净；设置页动作门控、配色对照、偏好字段对照三个静态检查通过；HarmonyOS 设置 bundle 已重新生成。渲染断言反向验证过（去掉速度里的 `han` 会让五条用例变红）。

本批的验证空洞两处，写明而不是略过：`apps/desktop/src-tauri` 在本机被整包排除（缺 macOS app bundle 资源），所以 `panel_input.rs` 那处只核对了 `time::OffsetDateTime::hour` 在 vendored `time-0.3.55` 里的实际签名，没有编译过；Android、macOS、HarmonyOS 三个宿主的改动同样没有在各自工具链上编译，本机只有 Windows 交叉与 Rust/TS 这几条路径。没有任何一项在真机上看到过数字。

同批把上一批留的第二条待决项查实了，结论比预想的严重，**修复放在下一片**：共享设置页的 `window.confirm` 在 macOS 桌面和 iOS 上**根本不工作**，按钮按下去什么都不会发生。

这一条不是推断，是在本机量出来的。证据链四段：(1) 本仓 `Cargo.lock` 锁的是 `wry 0.55.1` 加 `tauri 2.11.5`；(2) wry 的 `WryWebViewUIDelegate`（`src/wkwebview/class/wry_web_view_ui_delegate.rs`）只实现了三个 `WKUIDelegate` 方法——文件上传面板、媒体捕获授权、新窗口创建，`runJavaScriptAlertPanel` / `runJavaScriptConfirmPanel` / `runJavaScriptTextInputPanel` 一个都没有；(3) `tauri-runtime-wry` 与 `tauri` 自己不另设 uiDelegate（全仓搜不到）；(4) 照着这个配置写了一个最小 WKWebView 探针（不设 JS 对话框方法）在本机跑，结果是 `confirm()` **2 毫秒内返回 false、什么都不显示**。WKWebView 本身不提供内建 JS 对话框，必须由 delegate 实现，没实现就等同用户点了取消。

受影响的是共享设置页里 11 处以上的确认：删除词条、清空打字统计、关闭模糊音并清空规则、恢复屏幕键盘默认值、放弃未保存修改后重新读取、删除云词条、把云词条加入本机词典、开始新对话等。在 macOS 与 iOS 上它们全部是死按钮——这正是本表第 789 行那条「死按钮比没有按钮更糟，它宣称功能存在」，而那一轮的静态守卫只检查按钮有没有按宿主能力门控，检查不到这一类。

其余宿主逐个核过：Android 走 wry 的 `RustWebChromeClient.onJsConfirm`，会弹真的 `AlertDialog`，功能正常，但按钮文案是写死的英文 `OK` / `Cancel`，与页面的中文界面不一致；Linux（WebKitGTK）与 Windows（WebView2）原生支持，工作正常。HarmonyOS 的 ArkWeb 在 `Settings.ets` 里没有注册 `onConfirm`，其默认行为没有在设备上验证过，这里不下结论。

来源本批（`fcf594e2`）正好把 `window.confirm` 换成了自绘对话框，理由是宿主模态窗口不跟随页面主题、弹出期间页面自己的键盘与焦点处理被挂起。那三条理由对本仓每个 webview 宿主都成立，而上面这条比它们严重得多。下一片按同一方向做：共享一个自绘确认对话框，把这 11 处换掉，顺带解决 Android 的英文按钮。

增量记录（2026-09-21，Windows 第八批：把上一批量出来的死按钮修掉）：接第七批末尾那条。共享设置页 16 处 `window.confirm`，在 macOS 桌面和 iOS 上按下去什么都不发生，证据链见第七批。这一批把它们全部换成页内对话框。

换法是 `useConfirm()`（`packages/ui/src/core/confirm.tsx`）：返回一个可 await 的 `confirm` 和一个要渲染的节点，页面靠使用这个 hook 接入，不用 provider 也不用 portal——共享 UI 是一棵很大的树，为一个对话框加一层上下文提供者要碰的地方比 16 个调用点还多。浮层沿用仓内已有的 `role="dialog"` 样式，Esc 与点遮罩都是取消，焦点进入时落在确认按钮、答完还回原处。

三处边界各有用例，都是自绘对话框特有而宿主模态没有的问题：弹着时再发一个请求直接答否，而不是把对话框从正在做决定的用户眼前换掉；组件在对话框开着时卸载答否，而不是让调用方永远等下去；从对话框内部按下、在遮罩上松开不算取消。

顺带修掉 `panels.tsx` 里的 `confirmAction`：它在 `typeof window.confirm !== "function"` 时**不问直接放行**，即在一个没有 confirm 的宿主上删除云端候选会无声执行。这是与上面相反方向的同一个错误——一个假定宿主对话框一定可用的封装，两种失败形状都被它占全了。

21 处测试原本 stub `window.confirm`，等于在断言一个用户根本看不见的控件；改成回答真正渲染出来的对话框（`apps/desktop/tests/support/confirm.ts`），顺带证明每条流程都确实走到了它。

新增 `scripts/test-no-host-dialogs.py` 挂进 `--quick`，禁止共享 UI 出现 `window.confirm` / `alert` / `prompt`。这个守卫自己先写错一版并且**错得很典型**：判断是否带 `window.` 前缀时看的是匹配位置之前的字符，而 `window` 就在匹配里面，于是它放过了 `window.confirm` 却抓住了 `alert` 和 `prompt`——只测一种写法就会以为它是好的。改看匹配文本后四种写法（含 `window . confirm`）全部拦下，裸 `confirm(`（hook 自己的方法）照常放行。

未做：Android 那边弹窗能出来，但按钮文案是 wry 写死的英文 `OK` / `Cancel`；改用页内对话框之后这个问题一并消失，因为按钮由本页渲染。HarmonyOS 的 ArkWeb 默认行为仍未在设备上验证，不过页内对话框对它同样成立，所以这条不再是缺口而只是一个没查完的事实。真机上按这些按钮仍未做过。

增量记录（2026-09-21，Windows 第九批：跟进来源新基线里剩下的界面项）：来源仍固定 `b1ec3202`，目标起点 `332ea2416`。第五批之后来源新增的提交里，输入统计（第六、七批）和 `window.confirm`（第八批）已做完，这一批把剩下的界面项走完。

**已移植两项，都是取值不变、只改可见文字：**

固定标点（来源 `4f074779` + `38da1e77`）。来源先补回误删的「始终使用中文标点」，再把那对互斥开关改成单选组。本仓**早就**是单值控件——`punctuation_lock` 的三个取值一直在一个下拉里，来源这两步走到的形状这边一开始就是——差的只有文案，四处全部改用来源说法（固定标点 / 跟随中英文状态 / 始终使用中文标点 / 始终使用英文标点），并补上来源那句「切换中英文时的标点形态，三者互斥」。控件保持下拉：来源换 radio 是为了从两个开关表达一个值，这边从来就是一个值，相邻每个单值设置也都是下拉。macOS 原生备用窗的同一控件一并改名，否则同一平台上两个窗口对同一个偏好用两个名字。

日语方案「罗马字」→「罗马音」（来源 `eb512885`），含下面那句说明。来源只改了这一处：实用功能页 R 模式的说明里它自己仍写「按日语罗马字处理」，所以本仓对应那句不动——这类「来源只改了一半」的地方要照着它改一半，否则下次对照会以为是本仓漂移。

两处都钉进 `referenceSections` / `referenceOptions`，反向验证过会红。

**核对确认不适用一项：** 来源 `fcf594e2` 的词库浮层定位。它的根因是 `#content-container` 上有 `contain: layout paint`，于是写在页面片段里的 `position: fixed` 提示条和弹窗退化成相对该容器定位、跟着内容一起滚。本仓逐个查过：`[contain:layout_style_paint]` 只出现在侧栏（`settings-style.ts`），设置外壳是 `flex h-full flex-col overflow-hidden bg-chrome`，云词典各面板根是 `min-h-screen bg-chrome text-body`，都没有 `contain`、`transform`、`filter` 或 `backdrop-filter`——`overflow: hidden` 不产生包含块——所以 `fixed` 照常相对视口解析。第八批新加的确认对话框就渲染在这些根下面，一并核过。带 `backdrop-blur` 的玻璃面板样式确实存在，但用在表情/键盘面板，不在这几个树里。

**不移植，理由同第五批：** 加加辅助码（`566ff8b8`）与全拼备选切分／调频重排（`1ea01d5e`、`e32eeade`）都在 Engine 与其码表资产里，只能通过提 `engine-lock.json` 进来，影响面覆盖全部平台，单独决定。

增量记录（2026-09-21，Windows 第十批：词库维护这一行往下查）：对照表「词库查询、增改删、导入导出、快捷短语」一行点名的四项里，先走 quiesce/resume 与失败恢复，再走导出编码。目标起点 `cb0365752`。

**quiesce/resume 与失败恢复：核对确认已做到，无需改动。** 这里记下结论以免下次重查。桌面侧在收到 `dictionary maintenance busy` 时才握手，成功后重试，然后**无条件**发 resume（注释写明「导入失败总比让输入法没有会话好」）。Server 侧 `quiesce_dictionaries` 成功时设一个 30 秒 deadline，控制线程每 tick 检查、过期就自己 resume——所以一个在 quiesce 和 resume 之间死掉的设置进程，最多让输入停 30 秒而不是停到重启。没有 Server 在听时 quiesce 返回真、resume 返回假，判据是「锁本来就空着，调用方该继续」。三层各自独立，任一层失效另外两层仍然成立。

**导入编码：查出并修掉一处静默损坏。** 云词库文件面板用 `File.text()` 读用户选的文件，它只按 UTF-8 解码；而本地词库导入早就走 `decodeDictionaryBytes`，处理 UTF-8 BOM、UTF-16 两种字节序和 GB18030。同一个文件两个面板两种结果，云端这边更糟：UTF-16 解出来满是 NUL，被 `text.includes("\u0000")` 挡下（至少是拒绝）；GB18030 解出来是一串 `�` 且**不含 NUL**，守卫放行，一份全是替换字符的词库被静默上传到用户云端。实测 `"你好\tni'hao\n"` 的 GB18030 字节按 UTF-8 解码得到 `"���\tni'hao\n"`。改成调用同一个读取器，NUL 检查保留给真正的二进制文件。

顺带修共享导入解析器不剥前导 BOM。目前每个调用方都在更上游剥掉了，所以不是当下可触发的缺陷，但它是公共入口而这条不变量只靠「每个调用方都记得」维持。`str::trim` 不去掉它（U+FEFF 早就不是 White_Space），于是它活到第一行、落在该格式的第一列：词在前的格式里粘在词上，解析通过、存进引擎、永远匹配不上；编码在前的格式里落在编码上，判字母表非法，报一行失败且读者无从得知原因。两种都静默，其中一种损坏数据。

两处都反向验证过。本行剩下的「五笔/英文/快捷短语/翻译各表的字段」与「保留用户数据」尚未走完。

增量记录（2026-09-21，Windows 第十一批：词库各表的字段逐项对照）：接上一批，走对照表「词库」一行剩下的「五笔/英文/快捷短语/翻译各表的字段」。目标起点 `fd1db5f6a`。

逐项与来源 `server/src/settings/dictionary_validation.cpp` 对过，**行为一致**，差异都是本仓更严或更细，记下来免得下次重判：

- 权重缺省 10000：两边相同（来源 `kDefaultCodedImportWeight`）。
- 负权重拒绝：来源要求第三列全是数字（因而排除负号），本仓解析成 `i64` 后判 `weight < 0`，结果相同。本仓另外接受 `+5` 而来源不接受，无实际影响。
- 第三列含 `=` 视为元数据、取缺省：来源对所有格式都这么做，那是它容纳 Rime 文件的方式；本仓有显式的 Rime 格式，把这条规则限定在 Rime 内——比来源更精确，不是缺口。
- 跳过空行、`#` 注释与 `---` / `...` YAML 头：与来源 `ShouldSkipImportLine` 一致。
- 两列或三列、词与编码不得为空：一致。
- 每种码表的键长上限（全拼 256 / 五笔 4 / 快捷短语 32 / 英文 64）是本仓新增的防御边界，来源把长度交给 Engine 判，属于本仓更严。

**查出并修掉一处漂移隐患：快捷短语的长度上限。** 它的权威来源是 Engine 自己的 `contracts/ipc_protocol_limits.h`（`CandidateTextMaxLength` = 199）——短语最终写进的就是那个管道字段，超出即被截断，而故障只在使用时、离输入处很远才显现。这个值此前是**六处裸字面量**，分布在三个 crate 里，没有一处与该头文件相连；提 `engine-lock.json` 恰恰是唯一会改变该字段的操作，而那时没有任何东西会注意到。现收成一个常量并加 `scripts/test-quick-phrase-limit.py` 挂进 `--quick`，比对常量与头文件、同时禁止新的裸字面量。这里记一笔方法上的教训：我先只找到四处就动手，另外两处是守卫第一次运行时翻出来的——这类东西要用检查而不是用眼睛找。

本批查出但**未动**的一处，记下判据以免下次重新推导：新增词条的默认权重，设置页用 100000，而共享导入用 10000、来源的编辑路径缺省是 10。100000 高出一个量级看着像有意为之（手工加的词应当压过批量导入的词），但没有任何地方写明；更要紧的是设置页在宿主没有提供批量导入命令时会走一条逐条 `edit` 的回退循环，那条路径也用 100000——同一个文件在两种宿主上会得到相差十倍的权重。目前 desktop 与 HarmonyOS 都提供了 `import`，所以这条回退是潜在而非现行的。判定它是不是缺口需要来源设置页发送的权重，本批没有取到，因此不下结论也不改动。

本行至此四项走完三项，剩「保留用户数据」。

增量记录（2026-09-21，Windows 第十二批：维护期间保留用户数据）：对照表「词库」一行的最后一项。目标起点 `a5833c5cb`。

**查出并修掉一处数据丢失路径。** 云词库快照激活的形状是「把旧内容搬进 backup、把新内容搬进 current」，任一步失败就回滚。回滚用的 `rename` 是尽力而为（`let _ =`），而紧接着是一句无条件的 `remove_dir_all(backup)`。这两件事凑在一起就是丢数据：回滚的某个 rename 失败，恰恰意味着 backup 里那份是用户词库仅存的副本，而下一行把它整个删掉——发生在一次**已经被扛住**的失败的收尾路径上。改成非递归的 `remove_dir`，它拒绝删除非空目录，而这个拒绝正是要点：回滚干净时目录是空的、照常清掉，回滚没搬干净时目录非空、留在盘上。成功路径那处不动，那里 backup 装的是被有意丢弃的旧内容。

**核对确认已做到，记下以免重查：** `reset_learned_data`（`engine-bridge/native/bridge.cpp`）是同类操作里做得对的那个，可以当参照：先把新内容写进 `.reset.<stamp>` 临时名，再把原件 rename 成 `.backup.<stamp>`，三份（主词库、英文词库、学习日志）**全部发布之后**才删 backup；任一步抛出走 `fail_cleanup`，它撤掉已发布的、从 backup 把原件搬回来，而且**不删 backup**——即使搬回的 rename 失败，数据仍在盘上。上面那处 Rust 回滚缺的正是这最后半句。

派生名一律在 path 自身的 native 字符串上拼接而不过 `path::string()`（第二批 #3059 的结论），`-wal` / `-shm` / `-journal` 三个 sidecar 在发布后删除，否则用户刚清掉的学习数据会在下次打开时回来。sidecar 删除位于 try 块内、发生在新文件已就位之后，抛出会把已成功的清除回滚并报成失败——这一点第二批已记录为已知形状，本批未改。

至此对照表「词库查询、增改删、导入导出、快捷短语」一行的四项全部走完。

增量记录（2026-09-21，Windows 第十三批：云候选与 AI 联想的五个轴）：对照表该行点名的五项「每个提供方、超时、取消、失焦后旧结果、凭据路由」逐条走。目标起点 `93075a413`。

**五项都核对确认已做到**，结论记在这里以免重查：

- 失焦后旧结果有**两道独立的栅栏**。Windows 侧 `FocusedSession::apply_cloud_response` / `apply_ai_candidates` 先 `prepared(lease)` 再 `gate_.with_active(lease, ...)`，过期 lease 的结果直接丢弃；Engine 侧 `OnlineRequestGuard::matches`（`vendor/MSIME-Engine/core/online_request_guard.h`）比对 session id、generation、scheme、identity、query_text、cache_key、分词和两个资格位，所以同一 lease 内「先打 ni 后打 nihao」的旧回复也进不来。共享 Rust 层不另设栅栏是对的——身份归 Engine 所有，多一份副本就是多一处漂移。
- 超时两个 worker 各有各的值且都合理：云候选连接 2000ms / 总计 2000ms，AI 连接 2500ms / 总计 8000ms（LLM 本就更慢，照抄 2 秒会把它全判超时）。两者都是 `CURLOPT_PROTOCOLS_STR="https"`、不跟随重定向、`NOSIGNAL`。
- 取消不只是「丢弃结果」：`CURLOPT_XFERINFOFUNCTION` 接到取消判据上，被取代的请求在传输途中就会中止，write 回调里也再查一次。
- 响应与请求都有界：响应 256 KiB（AI 1 MiB）、query 16 KiB、AI 的 URL ≤ 2048 且必须 https、POST body 有大小上限。
- 提供方路由两边同形：来源 `ai_assistant.cpp` 只对 `deepseek` 特判（多一个 thinking 字段），其余走通用 OpenAI 兼容路径；本仓 `client-core/src/ai.rs` 完全一致。

**查出一处覆盖缺口并补上。** 整个 `platforms/windows/tests/` 里**没有一个文件提到过这三个 worker**——`CloudCandidateWorker`、`AiCandidateWorker`、`TranslationWorker` 的排队、去抖与取消一行覆盖都没有。这属于本表反复出现的「按源码核对为正确实现但零测试覆盖」，而这里出 bug 的表现是「打完字之后旧的云候选才冒出来」，不会在别处被发现。给 worker 加可注入的 fetcher（默认仍是真实那个），补四条用例：结果带对 lease 与 query、去抖窗口内只付一次且付新的那次、在途被取代的请求能看见自己被取代且结果绝不交付、五种非法请求一个都到不了网络。两种破坏分别红在不同断言上。

值得一记的是这条用例**在本机真的跑过**，不只是链接：`FocusGate` / `PipeTicket` 不含 Windows 头，curl 本机就有，用 clang++ 原生编译运行通过。此前 Windows 侧的用例在这台机器上一律只有「链接成功」这一级证据。AI 与翻译两个 worker 的同类用例尚未补。

增量记录（2026-09-21，Windows 第十四批：把「链接了」变成「跑过了」）：本表每一批的验证限制段都写着同一句话——没有 Windows 主机，所以 Windows 的用例只有「交叉构建链接成功」这一级证据。这一批发现那句话的适用范围比以为的小得多。

`platforms/windows/tests/` 绝大部分是策略：对着契约结构体的纯函数，整个翻译单元里没有一次 Win32 调用。这类源文件用**宿主编译器**就能编译、链接、执行。实测 92 个测试源里 59 个可以，约 25 秒跑完，此前它们在这台机器上从未执行过一次。新增 `scripts/test-windows-native-run.py` 挂进 `--quick`。

够格与否是发现出来的不是列出来的：能独立编译链接的，就是不需要 Windows 的。两类正常跳过——缺 Windows 头，或缺它在 Windows 构建里一起链接的其他翻译单元（未定义符号）。其余编译错误一律报失败：让编译不过的东西悄悄退出计数，正是套件消失的方式。两处 `HOST_DIFFERENCES` 各写明理由：`aux_message` 因为 `wchar_t` 在这里是 4 字节、Windows 是 2 字节，用宽字面量拼出来的线上字节形状不同、嵌入 NUL 那条根本表达不出来；`shell_surfaces` 断言的是 Windows 路径与环境块语义。另两处是编译期的宿主差异（`u8string()` 的 `char8_t`、只为 Windows 声明的 `preference_monitor_tests`）。

**这个 runner 第一次真用就查出四个没有任何东西在编译的测试**，全部在 CMakeLists 里从未出现过，与 `known-failures.txt` 记的 msimeui-tests 同型：

- `tests/input/tsf_key_dispatch.cpp`——原样就能通过，本批已注册进构建。
- `tests/clipboard/` 下的 `clipboard_history.cpp`、`clipboard_link.cpp`、`clipboard_presentation.cpp`——编译得起来但**断言失败**，原因是它们写的是已被废弃的旧契约。`normalize_clipboard_text` 的注释写明「只去掉 CF_UNICODETEXT 带来的终止符；换行（含 CRLF）与空白是用户内容，必须原样往返」，而测试期望 CRLF 折成 LF、首尾空白裁掉。实测存进去的正是未规范化的原串。**是测试过时不是代码有错**——行为改的时候没人更新它们，因为没有任何东西会编译它们。这三个是下一片。

顺带记一条方法：写这个 runner 时自己踩了四个坑（把子进程夹具当测试、执行继承调用者 stdin 导致永久阻塞、并行执行饿死等定时器的用例、编译失败被算成跳过因而改坏了也返回 0），每一个都是反向验证暴露的。第四个尤其值得一提——它让这个工具犯了它正要去发现的那个错误。

增量记录（2026-09-21，Windows 第十五批：把上一批查出的四个「没人编译的测试」处理完）：目标起点 `eaae1c858`。

`tsf_key_dispatch` 上一批已接上。这一批是剩下三个：`tests/clipboard/` 下的 history、link、presentation，在任何 CMakeLists 里都没出现过。

`clipboard_link` 与 `clipboard_presentation` **原样就通过**，只是没人编译，注册即可。

`clipboard_history` 编译得起来但断言失败，是测试过时。现行契约由 `normalize_clipboard_text` 的注释写明：只去掉 CF_UNICODETEXT 带来的东西——首个 NUL 起截断、剥掉尾部 `\r`——而换行（含 CRLF）与空白是用户内容、必须原样往返。测试期望的是 CRLF 折成 LF、首尾空白裁掉，那是被有意废弃的旧规则。四处按现行契约重写，每一处都保留原本要测的那件事：往返改为断言一字不差；去重改用只差一个尾部 `\r` 的一对（它们确实规范化成同一条），并补一条反面；「规范化后为空」改用 `"\r"`，因为 `" \t\r\n"` 在新契约下不为空；NUL 那条从「剔除并保留其后 4000 字符」改为断言截断，4000 UTF-16 单位的上限另用干净字符串单独测。三条规则各自反向验证过。

顺带把断言失败改成带行号——90 行里任何一条失败原本都报同一句话，定位这个问题时先吃了一次亏。

本机 runner 现在报「1 not tests」，只剩 `voice_wire_peer.cpp` 那个真正的子进程夹具。至此上一批查出的四个全部处理完毕。

增量记录（2026-09-21，Windows 第十六批：手写这一行）：对照表点名要比「模型打包、笔画缩放、撤销/清空、多候选、原编辑器上屏」。目标起点 `d90195fd4`。本机能验证的四项**全部核对确认已做到**，结论记下以免重查。

- **笔画缩放**做得比预期细。指针坐标不是直接用 `getBoundingClientRect` 换算，而是走 SVG 的 `getScreenCTM()` 逆矩阵，因为边框、viewBox 的留白、窗口缩放和 CSS transform 这几样单靠包围盒表达不出来；结果落在固定的 0–420 viewBox 空间里，与面板实际渲染多大无关。矩阵不可用（画布已分离或不可逆）时的回退按包围盒比例映射到**同一个** 0–420 空间，两条路径给出的坐标可比。
- **采样**同时做了两件事：半单位移动阈值去抖（注释写明与 Windows 面板一致），以及超过 256 点后隔点抽稀但保留原始起点与最新末点。
- **撤销/清空/重做**都在，且撤销后重做受同一个笔画上限约束。
- **多候选**上限 12，中文候选排在其他之前。

两项本机无法验证，仍需 Windows 主机：模型随包分发、以及识别结果提交回原编辑器。

**顺带钉住一处漂移隐患**（与第十一批快捷短语上限同型）：面板与共享契约各自写了三个上限——笔画（32 对 64）、每笔点数（256 对 4096）、候选（12 对 12）。目前面板一律更严或相等，也就是正确的方向，但两边的数字互不相连，靠的是「没人把面板那个数调大」。调大是最坏的那种静默：用户照常画，识别直接什么都不返回，因为请求在到达识别器之前就被拒了。新增 `scripts/test-handwriting-limits.py` 挂进 `--quick`，检查的是单向不变量——面板可以更严，不能更松。三个上限各自反向验证过。

增量记录（2026-09-21，Windows 第十七批：语音热键）：对照表「语音热键、流式/批量 ASR、润色、声音/静音、上屏方式」一行点名的第一项。目标起点 `e9632bfff`。

先按模块查覆盖：`src/voice/` 下 16 个模块里，`VoiceHotkey` 是唯一**零覆盖**的可测模块——`CuePlayer`、`DoubaoAsrClient`、`SystemAudioMuter` 是硬件与网络，本机测不了；其余每个都有用例，且第十四批之后它们在本机是真正执行的。

而这个低层键盘钩子里的规则恰恰是「错一个分支」的类型：修饰键被当作快捷键用过之后漏给应用（每次口述都弹菜单或开始菜单）、用户松手了录音还在继续、Ctrl+F9 只吞了按下而抬起那次仍送进编辑器。钩子本身在 Windows 之外跑不了，所以此前没有任何办法覆盖。

按本仓已有的 `*Policy.h` 做法把决策抽成 `VoiceHotkeyPolicy.h` 的纯函数——不含 `<windows.h>`，状态仍留在控制器的 atomic 里，钩子只改为调用。虚拟键码在策略里具名并在 `.cpp` 里逐个 `static_assert` 对住 Win32 的值，改名或打错不可能通过。

记下几条规则的**理由**，它们从代码里读不出来但改动时必须知道：激活顺序即行为（同时开着 RCtrl+RAlt 和 RAlt 时，单键的若排在前面会把两键的彻底吞掉）；两者对 Ctrl 的要求不对称是有意的（RCtrl+RAlt 要右 Ctrl，Ctrl+Win 任一都认）；压制闩只在**抬起**时清除，按下时清会让抬起那次无人认领地漏给应用；既不是按下也不是抬起的事件不动修饰键状态，否则会把用户还按着的键标成松开。五条反向验证过，各红在不同行。

本行其余四项仍需 Windows 原生验证。

增量记录（2026-09-21，Windows 第十八批：候选右键动作的可用性）：沿对照表「悬浮工具栏、托盘菜单、入口快捷键」一行按模块查覆盖。目标起点 `d889ee820`。

`src/candidate/` 下零覆盖的有六个，其中四个是本机测不了的（两个异步 worker 的网络部分、皮肤资产、窗口阴影的 Win32 绘制）。唯一既零覆盖又完全可测的是 `CandidateActionAvailability`——它决定候选右键那四项（置顶、固定排位、取消固定、删除）要不要给出来。

判据原本是三个裸数字 `source == 0 || 1 || 4`。它们是 Engine `CandidateSource` 枚举的**位置**（0 Database、1 UserDatabase、4 EnglishDictionary），以数值形态过线；Windows Server 经共享 Host API 与 Engine 通信，include 不到 `core/word_item.h`，这一侧在 C++ 里叫不出那个枚举的名字。于是 Engine 往枚举中间插一项，后面每项挪一格，编译一声不响，而「删除」开始被提供给云候选——Engine 随后必定拒绝，菜单里多出一项按下去什么都不发生。新增 `scripts/test-candidate-sources.py` 挂进 `--quick` 把具名常量对住枚举位置，反向验证过。

顺带把注释写准：原注释只说排除云和 AI 投影，而代码实际是**白名单**——快捷短语、Emoji、颜文字、生成项与兜底项同样被排除，因为它们不在这几个动作要编辑的词表里。白名单这一点本身有用例钉住：Engine 新增的 source 默认被拒，而不是默认被提供。

另外核对确认无缺口：单码点候选不提供「删除」这条与来源一致（`CandidateMenu.h` 的注释直接引了来源 `candidate_presenter.cpp` 的行号），且已有覆盖；来源那边不按 source 过滤，本仓这条按 source 的白名单是本仓自己加的一层，方向是更严。

增量记录（2026-09-21，Windows 第十九批：组字期标点的字符表终于有了用例）：沿 `src/ipc/` 与 `src/system/` 按模块查覆盖。目标起点 `5e14446f8`。

两个目录里零覆盖的十一个模块，多数是 Win32 资源或图标字体这类本机测不了的东西。其中**最该有覆盖的是 `PunctuationPolicy`**：它就是 2026-09-20 那批记过的「组字期标点的上屏时机」在本仓的实现，那一批把来源的字符表抄进了记录，却没有任何东西把实现钉住。这个表少一个字符，意味着那个标点不再用高亮候选结束组字——只在打字时看得见。

逐字符与来源 `IsCommitWithHighlightedCandidatePunctuationInCandidateMode` 比对：23 个字符两边完全相同。用例逐个断言，并覆盖三类排除（减号加号及小键盘孪生、逗号句号被配成翻页键、方括号被配成翻页键），以及「配了一对不影响另一对」。

核对了一处写法不同但**结果等价**的地方，记下免得下次误判为缺口：来源的翻页排除额外要求「有活动组字」，本仓没有这个条件；差异只在「没有组字时按逗号」，而来源那时走 `else { ClearState(); return; }`，同样不把标点变成带高亮候选上屏，本仓返回 nullopt 落点相同。

另记一处冗余：策略里的 `wch <= 127` 永远不会是拒绝的原因，因为 `translate_key` 只把 0x21..0x7E 认作字符。这不是缺陷（第二道保证窄化转换拿不到表示不了的值），但用例注释写明了，断言钉的是行为而不是那一行——否则后来的人会以为它承重。这条也是本批唯一一条反向验证**不会变红**的规则，如实记下而不是编一个能红的断言。

顺带一提：交叉构建抓到我自己漏配的 include 目录，本机能编只是因为手动加了参数——这正是那一阶段存在的意义。

增量记录（2026-09-21，Windows 第二十批：哪些键改组字）：接上一批继续走 `src/system/` 的零覆盖模块。目标起点 `25a2325c8`。

`EditPolicy` 的 `edit_kind` 决定一个按键到底改不改组字——字母、手动分隔符、日语长音符、微软双拼的 ing 键、Unicode 模式的数字、退格与光标移动，七类规则挤在一个函数里，零覆盖。这里错一个分支就是一个输入缺陷，只在打字时看得见。

用例把七类都钉住，其中几条的**理由**值得记下：字母要求 keycode 与字符一致（字母键上挂着别的字符不算字母）；退格与方向键只在组字期算编辑，否则是应用自己的键；微软双拼的 ing 键只有当光标落在当前音节内的奇数位时才是字符，且位置从最后一个分隔符算起而不是从头算，光标越界会被夹住；预编辑样式偏好非法值**抛出**而不是退回默认，连大小写不同的 "Pinyin" 也拒。

四条反向验证会红。另两条如实记为**不会红**：`modifiers & ~1u` 与 Unicode 的 Shift+数字早退，都是同一规则的第二次声明——`translate_key` 对 Shift 以外的修饰键已返回 CancelAndForward，Shift+数字落空后本来也返回 None。作为这个函数自己的契约保留是合理的，但注释写明了，断言钉的是行为不是那两行。

这已是本轮第三次遇到同一个形状（第十九批的 `wch <= 127`、本批这两条）：一层纵深防御在它那一层是看不出是否承重的，而给它编一个「能红」的断言等于骗自己。写清楚它由谁真正保证，比让测试看起来更满更有用。

增量记录（2026-09-21，Windows 第二十一批：以词定字，以及纠正覆盖扫描本身）：目标起点 `0988f764e`。

第十四批记的以词定字覆盖在共享运行时一侧；决定「哪个键触发、取哪一端」的 `WordCharacterPolicy` 本身零覆盖。方向就是这个功能本身，而括号那一对同时又是 TSF 的翻页键，所以「什么时候**不**该触发」和「什么时候该触发」一样要紧——用例两面都钉。偏好那一侧有一条容易写反：`enabled` 为假时仍然校验 keys，因为一个写着本构建不认识的键名的配置是需要报出来的分歧，不该因为开关是关的就悄悄当成关闭。五条反向验证过。

**同时纠正一个方法错误，这一轮好几批都受它影响。** 用来找零覆盖模块的扫描只看 `platforms/windows/tests/`，于是把 `PolishPrompt` 误报成零覆盖——它是转发到 `shared/voice/PolishPrompt.h` 的薄头文件，测试在 `shared/voice/tests/`，而且覆盖得很细（槽位优先级、legacy 回退只作用于第一槽、空槽一律回落清理预设，每条还记着它修的是哪个缺陷）。改用全仓测试目录加词边界重扫后，`platforms/windows/src/` 仍无覆盖的是 24 个模块，其中绝大多数是 Win32 资源、图标字体、硬件与网络客户端这类本机测不了的东西；`VoiceHotkey` 仍在其中是对的——第十七批覆盖的是抽出来的 `VoiceHotkeyPolicy`，那个装着钩子的控制器本身依旧只能在 Windows 上验证。

记这一条是因为它改变了前几批结论的可信度等级：「零覆盖」这个判断此前是用一把范围过窄的尺子量出来的。

增量记录（2026-09-21，Windows 第二十二批：回到功能迁移本身）：本轮中段有十几批做的是审计与补测试——那是加固既有代码，不是把来源功能复刻过来。这一批起回到功能级差异：以来源 README 的功能清单为准逐条比，而不是比测试覆盖。

第一条就查出两处从未复刻的东西。来源写的是「输入统计（**默认关闭**）：只在本机记录字符数量与活跃时长，可在设置 → 统计中查看与**清理**」：

- **默认关闭**。来源 `config.default.toml` 与随包配置都是 `enabled = false`，本仓默认开启。对一个统计别人打了什么的功能，默认关闭是正确方向——应当被主动打开而不是需要被关掉。只影响全新档案。实现上有个坑：serde 的默认与 `Default` impl 是两处，文件不存在时走的是后者，改一处不改另一处就等于没改，是新加的用例抓出来的。
- **保留策略**完全缺失。来源是 `retention = forever | 30d | 90d | 180d | 365d`，每天首次写入时删除超窗记录，**非法值按 forever 处理**。这最后一条照搬了：一个本构建看不懂的偏好绝不能被当成删除更多的许可。累计总数与分类不进窗口，只裁剪每日各轴，与来源一致。UI 按来源 `stats.html` 的文案做在共享设置页，宿主不提供该能力时整个控件不渲染。

边界日期自己按历法算（Hinnant 算法），不引日期库也不过本地时区；未来日期保留而不是删掉——另一种选择是因为一块坏表丢掉真实记录。

三条反向验证会红。第四条「每次写入都清理」如实记为不会红：边界只取决于当天，逐次清理用更多功夫得到同一个结果，是开销差异不是可观察差异。这是本轮第四次遇到同一个形状，处理方式一致——写清楚，不编断言。

方法上记一条给下次：本轮前期用「测试覆盖」找缺口效率很高但方向偏了，**功能迁移要拿来源的功能清单逐条比**，覆盖率只是它的下游。


增量记录（2026-09-21，Windows 第二十二批：切到英文时组字怎么处理，以及一条自我纠错）：目标起点 `3e8eb7edc`。

先记纠错。上一批我据来源 Server 的 `ShouldResetCompositionForImeMode` → `ClearState()` 判定「离开中文态应当丢弃组字」，把 `setEnglishInputMode:` 的 `MSIME_FINISH_COMPOSITION` 改成 `MSIME_CANCEL`，结果本仓已有的 Shift 轻点用例立刻变红——那条用例钉的是「组字中途轻点 Shift 上屏的是已输入的原始字母」。读错了：Server 那次 `ClearState()` 是收到客户端状态快照后清自己的后端，TSF 侧早已处理完组字（`IsBackendIndependentCompositionResetKey` 的注释明说「TSF locally consumes these keys and completes/cancels its composition」）。**只读 Server 不读 TSF 客户端，就会把清后端误当成丢用户的字。**

去 `windows/src/` 读客户端，两条规则各自成立，而且**不是同一条**：

- Shift 的中英文切换走 `FUNCTION_TOGGLE_IME_MODE` → `_HandleToogleIMEMode`，提交 `GetKeystrokeBuffer()` 里的原始击键串。本仓 Shift 轻点先发 `MSIME_COMMIT_RAW` 再切，对得上（早前那批已修）。
- 英文输入模式开关（来源是 Ctrl+Shift+E）走 `FUNCTION_CANCEL` → `_HandleCancel`，`_RemoveDummyCompositionForComposing` + `_DeleteCandidateList` + `_TerminateComposition`，**什么都不上屏**。

本仓把第一条的做法抄到了两个入口：菜单「选择英文模式」、Ctrl+Option+Space、悬浮工具栏的切换，全都发 `MSIME_FINISH_COMPOSITION`，也就是把高亮的中文候选提交进文档。用户伸手切英文恰恰是因为屏幕上的候选不是他要的，这时候替他上屏一个没人选的词。改为 `MSIME_CANCEL`，Shift 那条不受影响——它在调用之前已经把原始字母上屏，到这里没有东西可丢。

用例钉的是行为而不是假 session 的默认应答：组字在途时切换，断言发出的是 `MSIME_CANCEL` 且客户端既没有收到 commit 也没有残留 marked text。反向验证过（改回 finish 红在 `TestControlOptionSpace`）。假 session 相应加了 `failCancel` 与 `cancelTransition`，因为「Engine 失败时不得切换模式」这条原来只能让 finish 失败。

同一批里修掉一个自己上一批（#3387）引入的回归，它是被完整 macOS ctest 抓到的，而 #3387 我只跑了 workspace 测试与 `--quick`：来源的座位表 `candidate_selection_policy.h` 每个来源只安排一个候选，因为来源那边每种只有一个；本仓一次可以拿到多个（AI 上限十条），而我把「第一个之后的」归进了本地候选——本地候选是抢第一座的，于是第二条 AI 建议被顶到空格键上，第一条反而靠后。改成按来源分组、整组落座。这条现在有 Rust 用例（`several_candidates_from_one_provider_take_their_seat_as_a_group`），在代码所在的那一层，不必等 macOS 那一侧的集成用例才发现；假引擎为此多了一个 `sources` 字段。注意用例的并行数组必须等长，否则座位表整个提前返回，什么都不验。

教训写在这里而不是留在会话里：**跨进程的功能，只读其中一侧的代码就下结论，必然读错一半。** 来源是 TSF 客户端 + Server 两半，本仓把两半合进一个 controller，于是来源里分属两侧的规则在这里看起来像一条。

（编号说明：「第二十二批」出现了两次。两条记录是同一天在不同 worktree 里并行写的，各自都已合并，谁也不比谁晚；不去改已合并记录的编号，后续从二十四继续。）


增量记录（2026-09-21，Windows 第二十四批：把功能对照变成可执行的检查）：接上一批。目标起点 `e431c8ad9`。

上一批把统计的默认与保留策略迁到共享层，但没同步到 Windows 出厂配置模板。补齐后更要紧的是把**找到它的方法**固化下来：来源的出厂配置是「那个产品能被告知做什么」最完整的一份清单（180 个键、18 个分节），它有而本仓没有的键就是一个没人迁移的功能，而别处不会有任何东西发现——设置页只渲染它知道的，偏好结构体只解析它声明的。新增 `scripts/test-windows-config-keys.py` 挂进 `--quick`，只比键名，本仓多出的不报。

当前结果：**来源 180 个键在本仓全部有对应物，本仓另有 30 个**。也就是说配置契约这一层的迁移是完整的——这比此前「逐项读过」的记录强，因为它每次 `--quick` 都会重新回答。

写这个检查时踩了两个会造成**假通过**的坑，记下来：参照检出按当前 checkout 的同级目录找，而本仓惯例是在 `~/worktrees` 下干活，于是它永远「skipped」、看起来像通过；用本地 `origin/HEAD` 定位参照修订，而那个符号引用是克隆时写一次的、这台机器上指向发布分支 `origin/main`，比默认分支少 30 个键——照它比会在上游多出 30 个键时报告「全部齐备」。现在问远端要默认分支，并始终打印用的是哪个 ref 和哪个 SHA。

**加加辅助码这条要改一下此前的记法。** 前几批把它记为「在 Engine 里，只能提锁」，这不准确：本仓的 `engine-lock.json` 已经带 overlay 脚本机制（当前有两个），技术上完全可以再加一个把 `assets::helpcodes` 从五项扩到六项。真正的阻塞点是那张 7968 行码表本身——来源 `engine/helpcode/NOTICE.md` 写明它是从拼音加加 5.x 安装包内 `fzm.bin` **重建**的非官方数据。把它引进本仓是一次第三方数据的分发决定，而 ARCHITECTURE.md 要求引入新上游资产时连同来源提交、许可证文本、通知位置和分发限制一并提交。这该由仓库所有者定，不是实现层面能顺手做掉的事。记准阻塞点，比记一个听起来更技术性的理由有用。

增量记录（2026-09-21，Windows 第二十五批：Home/End 到的是列表两端，不是当前页两端）：目标起点 `cac0fb423`。接第二十二批的方向，继续读来源的 TSF 客户端一侧。

按来源客户端的 `KEYSTROKE_FUNCTION` 逐项对——这是一份很紧凑的功能清单，正合「拿来源的功能清单逐条比」。Home/End 在来源里分类为 `FUNCTION_MOVE_PAGE_TOP` / `FUNCTION_MOVE_PAGE_BOTTOM`（组字期与候选期两条路径都是），呈现层收到后调 `_SetSelection(0)` 与 `_SetSelection(-1)`，而 `CCandidateSessionState::SetSelection` 把 -1 读成 `Count() - 1`，末尾再 `AdjustPageIndexForSelection()` 把页跟过去。也就是说：**Home 回到整份列表的第一条、End 到最后一条，页码随之改变。**

本仓四个宿主（macOS 的 keyCode 115/119、Linux 的两套、Windows 宿主直接由 `FUNCTION_MOVE_PAGE_TOP/BOTTOM` 转发）都接到同一个共享动作上，而共享层只在当前页内移动高亮。用户已经在看着那一页，按 Home 最多挪几行，按 End 到不了列表末尾——一个几乎什么都不做的按键。改在共享层，四个宿主一起对齐。

动作名原本叫 `FirstCandidateOnPage` / `LastCandidateOnPage`，改完就是句反话，一并改名为 `FirstCandidate` / `LastCandidate`（C 常量同改，取值 104/105 不动，ABI 不变）。

一个来源那边不存在的问题：本仓的 Engine 对短查询只返回前一批候选，其余按需展开，所以 End 必须先展开再取末项，否则它停在「当时缓存里的最后一条」，再按一次还会继续往后走——那不是 End 键该有的行为。用例两条，分别钉「Home 连页一起回到第 0 条」与「End 触发展开后落在真正的末条」，都反向验证过。

顺带修掉 develop 上一处红：`typing-statistics` 这个 macOS 用例在新目录里直接 record，而 #3389 跟随来源把统计默认关成了 off，`record` 在未启用时按设计返回 0。用例先 `set_enabled` 再记，与设置页里的真实次序一致。这类红只在本机 ctest 才看得见（CI 不跑 macOS 原生门禁），所以合入前跑全套仍然是必须的。

本仓 Home/End 在候选窗未显示时移动组字光标（`MSIME_MOVE_HOME` / `MSIME_MOVE_END`），来源在那种情形下是吃掉按键什么都不做。这一条保留：它不与来源冲突，且是 macOS 上编辑光标的常规预期。

增量记录（2026-09-21，Windows 第二十六批：统计页关掉之后长什么样）：目标起点 `6d93278cf`。继续按来源的设置分页逐页比。这次是 `stats.html`——它是来源随统计功能新增的第 15 个 partial，此前几轮逐页对照都没覆盖到它。

逐节比下来只剩两处没迁：

**一、未开启时的引导。** 来源的三个状态由 `stats.ts` 切换：`statsDisabledEmpty` 在**未开启**时显示（有没有历史数据都显示），`statsNoDataEmpty` 在**已开启且无数据**时显示，`statsContent` 在有数据时显示。本仓只有后两者的等价物。前两批把统计默认值改成关闭（来源出厂就是关的），于是这个状态从边缘情况变成了**新用户的第一眼**——现在照来源补上「输入统计已关闭」一节，一句说明加一个启用按钮，放在内容之上；有历史数据时内容照常显示，跟来源一致。

顺带修掉一个因此暴露的错误文案：本仓的 `availabilityMessage` 没有「已开启」这个前提，关闭状态下会说「统计文件已建立，但当前还没有输入记录」，把用户支去多打几个字——而关着的时候打多少都不会被记录。这跟 iOS 上「没开完全访问却让人多打几个字」是同一类错误：**把「功能没开」说成「数据还不够」**。提成 `availabilityNotice()` 并以「已开启」为前提，关闭时返回空串。

**二、打开数据目录。** 来源「数据位置与隐私」一节有 `statsOpenDirectoryButton`。这一页写着「只保存在本机」，这个按钮是让这句话可以被**核对**而不是只能被相信。新增 Tauri 命令 `open_typing_statistics_directory`，复用既有的 `shared/skin_directory.rs`（那个模块本来就只认一个路径参数，不是皮肤专用）；目录由宿主给，webview 指定不了路径。按钮按能力裁剪：`TypingStatisticsClient.openDirectory` 是可选的，iOS/Android 不注入，于是那两个宿主上渲染不出按钮，而不是渲染一个按下去报错的。来源不显示路径文本，本仓也不显示，省掉一条把绝对路径送进 webview 的通道。

来源的 stats.html 其余分节（启用开关、输入速度、日历热力图、今日时段分布、字符分类、按日明细、数据清理的保留策略与清空）在前两批已经迁完。

验证：`--quick` 全绿。其中 harmony 设置包陈旧那道门禁再次生效——HarmonyOS 的设置窗口用的是仓库里预构建的包，改共享 UI 不重新生成，它就会比别的宿主少一截界面，这次它拦下了。本地 `msime-desktop` 此前一直因为缺 `target/macos/` 下的两个产物路径而 `cargo check` 不了（新增 Tauri 命令就没法编译验证），在 `target/` 下补上空目录后可以正常检查了——那是构建产物目录，不进版本库。

**同一批里顺手修掉一个把新检出全部卡住的东西。** 开这个 worktree 时 `--quick` 报 `vendor/MSIME-Engine could not be prepared from engine-lock.json`，栈顶是 `fetch_engine.py` 里的 `DEST.parent.mkdir(parents=True, exist_ok=True)` 抛 `FileExistsError`——`exist_ok=True` 只原谅「已经是目录」，不原谅「存在但不是目录」。

按规矩先查自己：`vendor` 是一个**自己指向自己的绝对路径符号链接** `vendor -> /Users/e-hu/Workspace/oss/ime/msime/vendor`，而且它是**被提交进仓库的**——`git log -- vendor` 指向今天 07:59 的 `dfbfa1c6f`（macOS 英文模式那一批），那次 `git add` 把一个本不该跟踪的条目扫了进去。也就是说每个新克隆、每个新 worktree 检出的都是这个坏链接，引擎根本准备不起来；老的 worktree 之所以没事，是因为它们的引擎在那之前就准备好了。报错信息指向的是「目录创建失败」，离「有人提交了一个符号链接」很远，所以它值得一道门禁而不是一次修复。

新增 `scripts/test-tracked-symlinks.py` 挂进 `--quick`：被跟踪的符号链接必须解析到仓库**之内**，绝对路径一律报错。从 index 读记录的目标而不是走工作树——重点本来就是「记进去的那个字符串」。反向验证：在仍带该链接的主 worktree 里跑是红的（`FAIL vendor -> /Users/…/vendor: an absolute path`），移除后绿。写它时又差点栽在同一个坑里：`ROOT` 取自脚本自身路径，于是在别的目录下跑它其实还在查脚本所在的那个 checkout，第一次「反向验证」得到的是假绿；把脚本复制进主 worktree 再跑才拿到真红。

**移除本身是并行的 #3393 先落地的**，这里记准：本批推上去时 develop 已经带上了那次修复（连同把整个 `/vendor/` 加进 `.gitignore`，比本批原先只去掉尾斜杠的写法更彻底，合并时取了它）。同一个坏链接被两条线各自撞上，恰好说明为什么它需要的是门禁而不是又一次修复——本批留下的是门禁那部分。

增量记录（2026-09-21，Windows 第二十七批：半截词该待在组字里，而不是先进文档）：接第二十五批继续读来源的 TSF 客户端。目标起点 `6d93278cf`。

候选只吃掉部分输入时，引擎会继续组字，并把选中的那一段交回宿主。来源把它留在组字里：`word_for_creating_word` 拼在读音前面显示，光标按它的长度前移（`preeditPrefixLength`），回车时把 `word_for_creating_word + 剩余原始输入` 作为一条提交出去。本仓是**立刻上屏**——用户还在打后半截，前半截已经进了文档：搜索框会拿半个词去搜，编辑器为它记一次撤销。

用真实词库探针确认了两侧行为（`crates/input-runtime/examples/phrase_progress.rs`）：`haitanpaobu` 选「海滩」后，本仓提交「海滩」、继续组 `paobu`；第二次选词只提交「跑步」。所以改成持有之后，两段要合成一条提交。

改在共享运行时。几条边界各自有理由，都钉了用例：

- **取消**丢弃已选的段，与来源 `_HandleCancel` 清 `word_for_creating_word` 一致。
- **失焦**把已选的段上屏。来源那边组字里的文本在 TSF 终止组字时留在文档里；本仓失焦本就取消组字，而在改动之前那一段早就在文档里了——失焦丢掉它是净损失。
- **退格把剩余读音删光**时上屏已选的段。这一条是有意不跟随来源：来源会继续显示「海滩」而读音为空，而本仓的不变式是「持有前缀 ⇒ 组字非空」，宿主里十几处 `[_view[@"editing_text"] length]` 的「是否在组字」判断才不用动。
- **不是选词产生的提交**（例如标点结束组字）不进前缀，否则会被塞到无关文本前面。候选页上按数字选词算选词。

前缀作为 `view.phrase_prefix` **单独一个字段**交给宿主，而不是拼进 `editing_text`：`caret_position` 是进入那串文本的偏移，而各宿主按自己的字符串单位读它（Apple 是 UTF-16，其余按字节）——此前两者一致只是因为编辑文本全是 ASCII，前缀一旦是汉字就不再一致。宿主自己拼、自己按自己的单位移光标。

按宿主分期打开（`HostOptions.phrase_preedit`，默认关=旧行为）。本批只开 macOS：本机能跑完整 ctest，而 Linux/Harmony/Android 三个宿主本机既没有容器也没有工具链，仓库又没有 CI，盲改等于没验。不开的宿主一个字节都没变。

（**紧接着的核对推翻了这句里关于 Windows 的部分**：本仓 Windows 宿主**已经**在自己的 IPC 层做了同一件事——`ReplyComposer` 把共享运行时的增量选词结果累积成整个已选前缀，选词后还有剩余输入时发 `NeedToCreateWord`，全部完成后发含完整前缀的 `Normal`，TSF 侧则沿用来源的 `word_for_creating_word` 显示，并额外有 `_creatingWordRestoreHistory` 在退格跨过边界时恢复上一段。它这样做是因为那半边说的是旧 DLL 的协议。所以 Windows **不该**打开 `phrase_preedit`，打开会双重累积。真正还没对齐的是 Linux 的两套前端、Harmony 与 Android——它们逐段上屏，等能验证时再打开。）
