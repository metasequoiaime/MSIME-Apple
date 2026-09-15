# Windows 功能迁移对照

## 范围与固定基线

目标是迁移 MSIME-Windows 的完整功能，而不是只移植语音、设置页或能在当前机器运行的子集。公共业务放共享层、公共管理界面放 Tauri；输入算法与组合状态仍归 C++ Engine；Windows 保留 TSF DLL / Server 进程及协议边界。已合并的其他平台成果不回退。每部分本地验证后提交合并，不要求用户逐项确认，不恢复私有仓库 CI。

2026-09-14 本次对照使用以下不可变对象，未读取相邻仓库未提交内容：

- 来源：`metasequoiaime/MSIME-Windows`，通过 `git ls-remote --symref … HEAD` 确认默认分支 `develop`，固定提交 `30a22e6f3d47adf783e8f038b1dafbd71edbb4f1`。
- 目标：`metasequoiaime/MSIME-Client` 的 `develop`，固定提交 `ca663cbf6b7d9a0f95e7a50687489a479ffed04d`。
- 来源 Engine 已内嵌为 `engine/`，其 `UPSTREAM.md` 记录导入提交 `c810d201f549b337ae0c4a65a9d694103f1c1754`。目标仍使用独立 `vendor/MSIME-Engine` gitlink。两者不能因目录名或协议名相同而视为内容相同，也不能把来源 Server 的新接口记为目标已接入。

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
| 全拼、四种双拼、86 五笔、日语、辅助码 | README 对应指南、`engine/`、设置 `input.ts` / `helpcode.ts` | `crates/engine-bridge/`、`crates/input-runtime/`、`platforms/windows/SessionPump.cpp`、共享 `preferences.rs` | 待逐项对照；固定词库版本，分别核对方案、大小写辅助码、临时日语与独立日语，不能从 Engine 能编译推断等价。 |
| 候选分页、高亮、调频、preedit、以词定字 | README 候选调频/preedit/标点指南 | `CandidateWindow.cpp`、`CandidateAction.h`、`SessionController.cpp`、`ReplyCodec.cpp` | 有调用链；检查分页键、鼠标与键盘行为、调频持久化和旧候选请求拒绝。 |
| 中英文状态、独立英文候选、全半角、简繁、智能标点 | `server/src/english/`、设置 `input.ts` / `shortcut.ts` | `SharedConfigKeybindings.h`、`PunctuationPolicy.h`、`ReplyCodec.h` 中的 TsfLocalConfig、共享偏好与 Engine 桥接 | 待逐项对照；分别核对按应用/全局状态、CapsLock、标点重复、成对补全与热更新。Windows 已按宿主进程排除 Excel 的成对标点光标移动，并有大小写进程名回归覆盖。 |
| K/T/U/E/M/J/Y/R 快捷模式、混输 | README 实用功能快捷模式 | Engine 桥接、共享偏好及 `packages/ui/src/index.tsx` | 待逐项对照；每种模式必须有输入到提交样例，快捷短语维护不能替代 K 模式运行验证。 |
| 谷歌云候选与 AI 联想 | README 云/AI 联想、设置 `ai-settings.ts` | `CloudCandidateWorker.cpp`、`AiCandidateWorker.cpp`，由 `SessionController.cpp` 构造并投递输入队列 | 有调用链；核对每个提供方、超时、取消、失焦后旧结果以及凭据路由，勿只验证 UI 保存。 |
| 候选中英释义、腾讯云翻译、自定义翻译 | README 候选翻译/自定义翻译 | `TranslationWorker.cpp` → `SessionController.cpp` → 候选展示；共享 `translation.rs` / `translation_store.rs` | 有调用链；仍需比较本地优先级、腾讯请求签名、词库编辑与缓存失效。 |
| 设置读取、保存、热更新与窗口行为 | `settings_app.cpp`、`config-sync.ts` | Tauri `load_preferences` / `save_preferences`，`PreferenceMonitor.cpp` 与 `main.cpp` 发布回调；macOS 云端桌面快照覆盖 Apple 20 项基线字段并保留客户端新增双拼预编辑字段 | 有调用链；逐字段核对默认值、冲突/损坏保护、当前组合期间延迟生效。macOS 云端快照现补齐两套辅助码方案、候选学习和本地扩展模式；本地扩展的兼容布尔值应用为八个本地模式的全开/全关。不能因配置字段存在就标记功能接通。 |
| API 凭据测试 | `settings_app.cpp::apiCredentialTest` → `ApiCredentialTest::Run` | Tauri `test_api_credential` → `client-core::credential_*`（Windows/macOS） | 有调用链；Windows 已接入聊天、批量 ASR、豆包 WebSocket、腾讯云/NiuTrans/DeepLX 等共享凭据测试。仍需逐项核对来源字段与真实服务行为。 |
| 词库查询、增改删、导入导出、快捷短语 | `dictionary_manager.cpp`、设置 `dict.ts` / `tools-settings.ts` | Tauri `dictionary_request` / `dictionary_maintenance_handshake`，共享 `dictionary_access.rs` / `dictionary_import.rs` | 有调用链；验证 quiesce/resume、失败恢复、五笔/英文/快捷短语/翻译各表的字段和导出编码，保留用户数据。 |
| 语音热键、流式/批量 ASR、润色、声音/静音、上屏方式 | `server/src/voice-input/`、设置 `voice.ts` | `main.cpp` → `VoiceHotkeyController` / `VoiceInputSession` → Engine 语音模块与 TSF；`VoiceSessionEpoch.h` | Windows Tauri 语音面板与 `recognize_voice` 已接入；全提供方、取消及焦点行为仍需 Windows 原生验证。 |
| 录音设备选择 | 需继续比对来源具体支持范围，不假定来源已支持 | Tauri `list_voice_capture_devices` 与共享 `capture_device/capture_backend`；Windows `VoiceInputConfig` / `VoiceInputSession`、macOS 原生备用设置通过 `MSIMEListVoiceCaptureDevices` 枚举输入流 | Windows 已按稳定设备 ID 完成枚举、偏好保存和 `AudioCapture::start(..., device_id)` 透传，并有 `voice_capture_selection` 覆盖 backend/device 选择；macOS 的目标内部断链已补齐。真实硬件权限、安装后切换及来源设备标识范围仍待产品级验证。 |
| 手写 | 来源设置 `handwriting-settings.ts` 和模型资源 | `ShellSurfaces.h` / `main.cpp` → Tauri `recognize_handwriting` / `submit_handwriting_candidate`，共享 `panels.tsx` | 有目的地入口；比较模型打包、笔画缩放、撤销/清空、多候选及原编辑器上屏。 |
| 屏幕键盘 | 来源设置 `screenkb-settings.ts` | `main.cpp` → Tauri keyboard route、`desktop-keyboard.tsx`、Windows `send_key` 分支 | 有调用链；核对布局、修饰键按下/释放、自动重复、焦点恢复及 DPI。 |
| Emoji、颜文字、符号、剪贴板历史 | README 与来源 `clipboard_history.cpp` | `ClipboardMonitor.cpp` / `ClipboardHistory.cpp`、Tauri `load_emoji_catalog` / `paste_clipboard_text`、共享 `panels.tsx` | 有入口；核对历史存储格式、去重/清理、开关同步及点击后目标窗口，不能以普通 SendInput 冒充 TSF 定向提交。 |
| 悬浮工具栏、托盘菜单、入口快捷键 | 来源 `window/*presenter*`、`ui-html/webview2/ftb` / `menu` | `FloatingToolbarWindow.cpp`、`TrayMenuWindow.cpp`、`MaintenanceHotkey.cpp`、`ShellSurfaces.h` / `ShellLauncher.cpp` | 有调用链；设置/手写/键盘/语音/云剪贴板/云词库等启动共享 Tauri，低延迟不抢焦点宿主保留原生。来源和目标菜单项、禁用条件需逐项比对。 |
| 皮肤、主题、字体、外观预览 | 来源 `appearance.ts` / `skin.ts`、`candwnd/skins` | 共享 `packages/ui/src/upstream/`、`skin_catalog.rs`、`CandidateSkin.h`、`CandidateWindow.cpp` | Windows 已消费候选字体/回退字体、主题颜色、横竖排布局和阴影字段；`candidate_font_reload`、`candidate_palette` 与 shadow 回归覆盖非法值回退。仍需逐主题运行时截图、外部资源和字体回退逐项比较。 |
| 更新、关于、帮助、反馈、重启 | 来源 `about-settings.ts` / `feedback-settings.ts` / `update-manifest.ts`，`restartServer` | 共享 `update-manifest.ts` / `index.tsx`，Tauri `open_external_url` / `restart_input_method` | Windows 重启使用固定 UTF-16LE `RestartServer` Aux payload 并有回归覆盖；更新 manifest/release 链接要求干净 HTTPS，外链 opener 拒绝无主机与 shell 字符。安装包信任、来源、失败反馈及原生安装仍待逐项对照。 |
| 服务守护、安装、升级、卸载、资源打包 | 来源 README 服务守护、`installer/`、构建脚本 | `platforms/windows/installer/`、`tests/runner_regression.ps1`、TSF 注册代码 | 待产品级验证；安装脚本/产物清单不证明注册成功、重启恢复、升级保留数据或卸载清理正确。 |

共享账号、社区、统计、云词库等已有成果继续保留；不能用它们抵消上表来源功能缺口。是否属于固定 Windows 基线及字段级等价，须另外找来源运行时证据，不能只根据目标页面名称推断。

## 下一批实施顺序

增量记录（目标基线之后）：Windows `ai.assistant` / `voice.polish` 已从共享设置按钮接到 Tauri `test_api_credential` 的 Windows 分支及 `client-core::credential_test`。共享实现注入传输，生产 HTTPS 请求禁用重定向，5 秒连接/15 秒总时限、256 KiB 响应上限，公开错误不携带响应原文。Linux provider 路径保持不变。合成请求测试和共享模块 Windows 交叉检查不能替代 Windows 原生设置窗口或真实服务验证；ASR 与三类翻译凭据测试仍待迁移。上表的明确缺口描述保留为固定目标提交时的状态。

1. **API 凭据测试真实接入**：来源已有独立设置任务队列；目标先复核可共享的提供方测试实现，补 Windows 路径和失败分类。测试只用合成凭据与本地模拟传输，不把真实凭据写入日志。
2. **Tauri 语音运行链**：明确控制器与输入目标是两个身份。OS 对端认证、有限消息/队列/关闭时限、request ID 与代际、事件与最终结果都必须连起来。Tauri 面板收结果后提交和原生直接提交只能有一个最终提交所有者，防止双重上屏。
3. **字段级配置与设备选择**：从来源 `ime_config.h` / `ime_config.cpp`、设置模块逐字段映射到共享偏好，再确认每个字段的原生消费者；设备选择单独验证稳定 ID 和实际采集。
4. **输入与面板产品行为**：按上表方案、在线候选、翻译、词库、面板、外观、服务/安装分组补差异与本地回归，每组及时合并。不因缺少一种验证环境而停止可执行的实现工作，也不声称未执行的原生验证通过。

## 语音传输必须保留的边界

翻译凭据测试增量：Windows 腾讯云、NiuTrans、自定义 DeepLX 测试现由 Tauri 调用 `client-core::credential_translation`，复用共享签名及解析。腾讯设置按钮传递当前编辑的 SecretId/SecretKey/地域；Linux 的 provider 请求保持原样。测试要求真实译文字段，不把任意 HTTP 2xx 当作成功；返回结果不包含服务端原文。自定义服务保留 HTTP/HTTPS 支持，禁止重定向。此项不改变固定基线记录，也不代表真实服务或 Windows 原生窗口验证完成；ASR 凭据测试仍待接入。

- hello 中的 `client_id` 不是认证；控制器进程不能复用 TSF 目标进程 ID。必须由 OS 对端信息验证控制器，再单独绑定目标焦点租约。
- `PipeRegistry` 注册代际不等于激活 epoch。排队前检查还不够，执行时仍需检查焦点、会话及代际。
- 不能把未握手的 Aux 通道当成可接收凭据、识别文本的认证语音通道。
- `VoiceControlMessage` codec、来源仓库的派发包装、端点常量或 Engine gitlink 更新都不是目标监听器、Tauri 客户端与流式结果已经接通的证据。
- #2228 / #2230 修复的是已有原生语音失败提示与旧完成回调隔离，不证明 Tauri 语音功能完成，也不证明 SendInput 回退焦点安全。

## 验证入口与本次限制

豆包凭据测试增量（来源仍为 `30a22e6f3d47adf783e8f038b1dafbd71edbb4f1`，本次目标起点 `91c5dc8b`）：Windows 设置已通过 Tauri 接到共享 `credential_doubao`，提供新版 API Key 与旧版 App ID/Access Token 的互斥认证头；新版忽略残留 App ID。传输接口可注入，生产 WSS 不跟随重定向，连接阶段 5 秒、总时限 15 秒，消息/累计响应 1 MiB、最多 64 条消息，解压复用有界共享解码器。只发送一秒合成 PCM 静音，要求有效终态 JSON，不返回服务端诊断或识别文本。内存 WebSocket、本地 TCP 重定向/超时和 UI 编辑值回归均使用合成数据；没有真实豆包凭据或原生 Windows 窗口验证。下段保留先前批量 ASR 增量时点记录；本项不补齐 Tauri 录音控制与最终上屏链。

批量 ASR 凭据测试增量：OpenAI、SiliconFlow、Groq 的 Windows 设置按钮现连接到 Tauri 和共享 `credential_asr`。请求使用内存生成的一秒 16 kHz 单声道 PCM16 静音 WAV，以 multipart 上传，不访问麦克风；界面提示可能计入服务用量。生产传输使用 HTTPS、禁止重定向、5 秒连接/15 秒请求时限及 256 KiB 响应上限。豆包需要独立 WebSocket 握手与最终协议响应，目前未借用批量入口，也未宣称豆包凭据测试或完整语音运行链已完成。

- 原生协议/会话：`platforms/windows/tests/pipe_io.cpp`、`server_smoke.cpp`、`session_pump.cpp`、`tsf_key_dispatch.cpp`。
- 配置/外观/启动：`preference_monitor.cpp`、`shared_config_keybindings.cpp`、`candidate_skin.cpp`、`shell_surfaces.cpp`。
- 语音：`voice_control_message.cpp`、`voice_providers.cpp`、`voice_session_epoch.cpp`；这些不覆盖 Tauri→Server→麦克风→ASR→编辑器全链。
- UI：`apps/desktop/src/credential-test.test.tsx`、`voice-recognition-client.test.ts`、`dictionary-safety.test.tsx`、`handwriting-pointer.test.tsx`。组件模拟测试不能证明 Windows 条件编译分支可用。
- 本次是源码对照与文档更新，不新增原生运行通过声明。GitNexus 索引已重建；概念查询遇到只读 FTS 错误，改为按固定提交文件与调用点核对。提交前仍运行 staged detect-changes。

后续修改本表时同时记录所用来源和目标提交。若来源默认分支变化，重新核对实际默认分支并固定对象；不静默把浮动 HEAD 的新功能算入旧基线已完成项。
