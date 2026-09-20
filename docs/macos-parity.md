# macOS 功能迁移对照

## 范围与固定基线

目标是迁移 MSIME-Apple 的 macOS 完整功能，而不是只移植设置页或能在当前机器运行的子集。公共业务放共享层、公共管理界面放 Tauri；输入算法与组合状态仍归 C++ Engine；平台特性按 macOS 自身的机制适配，不照搬来源的实现形态。每部分本地验证后提交合并，不要求用户逐项确认，不恢复私有仓库 CI。

2026-09-20 本次对照使用以下不可变对象：

- 来源：`metasequoiaime/MSIME-Apple`，通过 `git ls-remote --symref origin HEAD` 确认默认分支 `develop`，远端 HEAD `663d7db619e45ebf3750db7c216438edd800f696`。实际读取的是本机检出 `63c51eddb5bc82c574ba7f8ca41db453e129db81`，它比默认分支多一个已提交改动（候选行宽适配：`CandidateRowFit.h`、`CandidatePanel.mm`、`CandidatePanelTests.mm`）。该检出 `git status --porcelain -- platforms/macos shared` 为空，未读取未提交内容；多出的那一项已由本仓库 #3029 覆盖。
- 目标：`metasequoiaime/msime` 的 `develop`，固定提交 `17ab45eb4234418faf2635fd6bf960d9c73f68f8`。

来源功能入口以该检出的 `platforms/macos/src/`（73 个文件）、`shared/apple-bridge/`、`shared/backend/`、`shared/backend-ui/` 交叉核对，并以 `PreferencesWindowController.mm`（3323 行）作为用户可见设置面的索引。索引只是入口，后续仍须逐字段、逐动作下钻；本表不是穷尽行为的完成证明。

## 证据等级

- **有调用链**：已找到目的地的真实调用代码；不等于原生系统行为已验证。
- **有强制检查**：除调用链外，另有 CTest 或门内检查持续保证该项不回退。
- **明确缺口**：可由未消费配置、缺失运行时路径或实测结果直接证明。

本文不计算完成百分比，也没有以窄范围测试或构建成功代替安装后交互验证。

## 三次机械比对的结果

| 维度 | 方法 | 结果 |
| --- | --- | --- |
| 共享偏好 | 解析 `Preferences` 结构体全部字段，检查 macOS 宿主与共享运行时是否消费 | 82 项中 71 项有消费；其余 11 项必须在 `preference_coverage.py` 的清单里写明平台为何不适用，清单双向校验 |
| 用户可见文案 | 抽取来源 macOS 全部源文件的中文字面量，去掉可访问性标签后逐条在目标中检索 | 623 条；未命中的均为措辞差异或已由 Tauri 页以不同表述覆盖，逐簇核实后无功能缺口 |
| 符号 | 抽取来源 ObjC 方法、C/C++ 函数、Swift 函数名，逐个在目标中按名与按文本检索 | 938 个；未命中项经逐簇核实后归为三类：目标以不同命名实现、按架构下沉到 Engine 或共享运行时、仅 iOS 使用 |

## 功能分组与目的地入口

以下路径均相对目标仓库；“来源入口”相对固定的来源检出。

| 功能组 | 来源入口 | 目的地证据 | 当前结论 |
| --- | --- | --- | --- |
| IMK 事件路由、候选面板、输入源注册 | `MetasequoiaInputController.mm`、`CandidatePanel.mm`、`InputSourceRegistration.mm`、`InputControllerKeyRouting.h` | `platforms/macos/src/input/InputController.mm`、`candidate/CandidatePanel.mm`、`input/InputSourceRegistration.mm`、`input/InputControllerPhysicalKeys.h` | 有调用链；目标另行处理来源未覆盖的小键盘数字与标点物理键 |
| 候选翻页、以词定字、方向键导航 | `MetasequoiaCandidateKeyOptions`、`ClassifyConfiguredControllerKey` | 共享 `NavigationPreferences`、`WordCharacterPreferences`；宿主逐项消费 `minus_equal`/`comma_period`/`brackets`/`tab`/`page_up_down`/`arrows`/`mouse_wheel` | 有调用链；来源的互斥开关在目标是各自独立的布尔项 |
| 设置界面 | `PreferencesWindowController.mm` | 主编辑器为 Tauri `packages/ui/src/index.tsx`；原生回退 `settings/AppearancePreferences.mm`、`voice/VoiceProviderSettings.mm` | 有强制检查（`preference-coverage`、`voice-provider-settings-keys`）；按「公共 UI 放 Tauri」重构形态，非逐窗复刻 |
| 语音输入 | `VoiceInputService.mm`、`VoiceSettings.mm`（云端 + 本地 Whisper） | `platforms/macos/src/voice/`：豆包流式、HTTP 批量、macOS 系统识别、本地 Whisper（#3014）；`shared/voice/` 提供 `recognize_local_asr` | 有强制检查（`bundle-contents` 校验可执行文件确实链接了本地识别器） |
| 候选释义与翻译 | `TranslationClient.mm`、`CandidateGlossClient.swift`、第二语言、Option/Control 取列上屏 | `cloud/CustomTranslationBatch.mm`、`cloud/TranslationCache.mm`、`commitCandidateGlossColumn:`、共享 `translation_secondary_language` | 有调用链；目标另有腾讯、NiuTrans、账号释义与离线优先 |
| 智能标点 | `PairedPunctuation.h`、重复标点转中文 | 共享 `punctuation::route` 消费 `direct_digit`/`direct_letter`（#3075）；空格回转 ASCII（#3081） | 有强制检查（`smart-punctuation-space`） |
| 词库与用户词条 | `DictionaryInstaller.mm`、`PersonalDictionaryStore.mm`、`PersonalDictionaryView.mm` | `dictionary/DictionaryInstaller.mm`、`dictionary/DictionaryWindowController.mm`；词条增删改查与导入导出在 Tauri 词库页 | 有调用链 |
| 学习数据清除 | `ResetMetasequoiaLearnedData` 及其标记/恢复协议 | `crates/host-api/src/dictionary.rs` 的 `Operation::Reset`，经 `DictionaryAccess::try_maintenance` 加锁后交 `msime_engine_bridge::reset_learned_data` | 有调用链；按「输入算法与词库归 Engine」下沉，宿主不再自建标记恢复协议 |
| 软件更新 | `UpdateController.mm`（Sparkle 2.9.6） | `core/UpdateController.mm`；非应用 bundle 进程拒绝启动 Sparkle（#3014），并有 `update-controller` 覆盖（#3025） | 有强制检查 |
| 卸载 | `Uninstaller.mm` | `crates/host-macos/native/uninstaller.mm`，`shared-uninstaller` CTest | 有强制检查 |
| 输入菜单图标、本地化、TCC 权限 | `MetasequoiaIMEMenuIcon.tiff`、`render_menu_icon.swift`、`Info.plist` 用途字符串 | `resources/MSIMEClientInputMethodMenuIcon.{svg,tiff}`、`scripts/render_menu_icon.swift`（#3021）；语音识别用途字符串及其本地化（#3015、#3052） | 有强制检查（`info-plist-icons`、`info-plist-usage`、`bundle-contents`） |
| 账号、云剪贴板、云词典、快照、社区 | `shared/backend/*.swift` | `shared/backend/` 为来源的超集（另有 `BackendAiClient.swift`），并带 Swift 测试 | 有调用链 |

## 目标具备而来源没有的部分

屏幕键盘、手写识别板、AI 辅助与 AI 对话、社区资源与皮肤、打字统计、悬浮工具栏皮肤编辑、双拼键位提示面板、输入模式 HUD。这些不属于本次迁移范围，此处只说明两侧差集不是单向的。

## 仍需签名产品包验收的部分

本地构建的 bundle 在本机 macOS 27 上**注册不上输入源**（见 `platforms/macos/README.md` 的实测记录：`--register-input-source` 返回 1，按 bundle id 过滤的输入源列表为空，而同机 Developer ID 签名的正式版两个源正常启用；改动前就已安装在那里的那份构建同样失败）。因此下列三项无法用本地构建验收：

1. 输入菜单与菜单栏中图标的实际观感；
2. 麦克风与语音识别的 TCC 权限弹窗文案；
3. 真实编辑器中的组合、标点转换与本地 Whisper 识别行为。

bundle 自身是否装配正确由 `bundle-contents` 持续检查：图标是否真的暂存进 `Resources`、菜单图标是否带 16×16 与 32×32 两页、每条用途字符串是否在每种已暂存语言中都有、可执行文件是否链接了本地识别器。

## 不回退的保证

以下检查在 `ctest --test-dir <build>` 中运行，新增偏好、新增 TCC 调用、图标改名或本地识别器被关掉都会直接失败，而不是等到安装后才发现：

- `preference-coverage`：共享偏好要么被 macOS 宿主消费，要么在清单中写明不适用的理由。
- `bundle-contents`：产物 bundle 的图标、本地化与本地识别器链接。
- `info-plist-icons`、`info-plist-usage`：模板 plist 的图标引用与 TCC 用途字符串（含每种语言的本地化）。
- `voice-provider-settings-keys`：原生语音窗口的每个文本字段都对应一个运行时读取的默认键。
