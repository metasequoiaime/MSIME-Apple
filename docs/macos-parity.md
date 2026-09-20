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

### 这三次比对看不见什么

2026-09-20 追加。上面三项都是**存在性**比对：某个符号、某条文案、某个偏好在两边都有。它们查不出「两边都有、但行为不同」的那一类，而这类恰恰是最影响实际使用的。重跑一遍并按行为逐条核对后，确实找出两个：

- 组合中途单击 Shift，目标上屏的是高亮候选，来源上屏的是已输入的原始字母（#3179）。两边都有这个快捷键、都有对应偏好、符号也都在，只是做的事不一样——而这个手势存在的意义正是把词库里没有的词原样送出去。
- 以词定字与候选翻页可以被同时指到同一对键上，翻页先执行，于是显式绑定的以词定字在它自己的键上毫无反应（#3182）。两边都有这两个功能，来源用互斥开关避免了冲突，目标的原生 setter 也互相拒绝，但共享快照路径不做检查——而那正是 Tauri 设置页写入的路径。

有效的办法是**读来源注释里解释「为什么这样做」的段落**，再去目标里验证同一条理由是否成立。来源在这类非显然决策处几乎都写了理由，而理由是存在性比对抽不出来的信息。后续继续核对时应以此为主，不要把上表当作完成证明——它本来也不是。

## 第四次比对：行为层（2026-09-20）

前三次都是存在性比对，补一次按行为核对，方法是读来源解释「为什么这样做」的注释，再回目标验证同一条理由是否成立。本轮覆盖与结论：

| 核对对象 | 结论 |
| --- | --- |
| 来源纯逻辑头（`InputModeRouting.h`、`InputControllerKeyRouting.h`、`WubiCommitPolicy.h`、`CandidateSelectionState.h`、`InputBehaviorPreferences.h`） | 找出 2 个缺口，已修；其余等价或目标更严 |
| 设置窗口侧栏 14 个分区 | 全部有 Tauri 归宿；「五笔」在目标是输入页内按方案条件显示的分区，不单列侧栏项 |
| 来源 macOS 全部源文件的中文字面量 | 643 条，精确未命中 204 条。滤掉以「卡片 / 行 / 页」结尾的可访问性标签后余 164 条，再滤掉有 5 字以上子串命中的余 151 条；从中挑出最像功能而非措辞的 5 条（主题模式、候选窗补充字体、离线优先、Whisper 模型、复制反馈报告）逐条直查，**全部已实现**，仅标签措辞不同 |
| 偏好键常量（来源 29 个 `k*Key`） | 按目标命名（snake_case / camelCase）逐条核对，全部有消费方 |
| 来源 74 个 macOS 源文件 | 按名未命中 12 个，逐个核实后均为命名差异或已下沉到共享层；`PersonalDictionaryStore` / `PersonalDictionaryView` 对应目标的共享词库 ABI + Tauri 词库页，且目标为超集（分页、按类过滤、查询、导入导出、失败重试） |

本轮修掉的两个行为缺口：

- **#3179** 组合中途单击 Shift：目标上屏高亮候选，来源上屏已输入的原始字母。两边都有快捷键、偏好与符号，做的事相反——而这个手势的用途正是把词库里没有的词原样送出去。
- **#3182** 以词定字与候选翻页可被指到同一对键上，翻页先执行，显式绑定的以词定字静默失效。来源用互斥开关规避，目标的原生 setter 也互相拒绝，但 `applySharedCandidatePreferences:` 不检查——而那是 Tauri 设置页写入的路径。

## 第五次比对：能力与产物（2026-09-20）

第四次按行为核对之后又补了一轮，针对的是「两边都有、但目标这边用户够不着」这一类。找出并修掉两个：

- **#3216** macOS 设置页隐藏了表情、颜文字、临时日语三个本地模式开关，理由写的是「预览包只发 msime.db 和 english.db」。但 `others.db` 与 `dict_japanese.dat` 自 `780a9381b`（2026-09-09）就在 `resources/desktop-dictionary.lock.json` 里，比那条过滤早十天，而 `tauri.macos.conf.json` 整目录打包已校验的资源集——三个能用的模式在设置里没有任何办法打开。同样受资源门控的「临时英文」一直显示着，这个不一致本身就说明前提错了。资源真缺时由 `apply_local_mode_resource_gates` 关掉该模式、触发键原样插入大写字母，比隐藏开关更好。
- **#3212** 本地 Whisper 模型只能手填绝对路径，而来源有 `browseVoiceModel:` 文件选择器。webview 的 file input 给的是内容不是路径，所以共享设置页答不了，改为向宿主要一个可选能力（`pickVoiceModelPath`），原生实现放在 `crates/host-macos/native/`，不引入新依赖；宿主不提供就不显示按钮，手填照旧。

本轮核过且确认等价或目标更强的：来源 12 个共享后端文件目标全有（另有 `BackendAiClient`）；四个原生视图（剪贴板、词库、账号、设置同步）文案差集为空；云词库备份视图逐字一致；输入法菜单条目集合一致；引擎选项写入面一致（来源的嵌套字段对应目标的扁平字段，自动纠错来源是一个总开关、目标拆成换位与邻键两项，覆盖引擎仅有的两个位）；`HostSurface` 各能力位 macOS 均已开启，唯一未开的 `number_row_selection` 来源没有该功能；`preference_coverage.py` 的「不适用」清单双向校验、无陈旧项。

## 符号比对的重跑（2026-09-20，双方当前 HEAD）

前面那次符号比对做在固定提交上，而两边此后都前进过，所以在来源 `63c51ed`（比之前的固定检出多出候选行宽适配等改动）与目标当时的 `develop` 上重跑了一遍，方法与结论都记下来，便于下次复核而不是重新发明：

- 从来源 `platforms/macos/src/` 抽出 ObjC 方法、C/C++ 函数与 Swift 函数名共 **572 个**，逐个在目标的 `platforms/macos`、`shared`、`crates`、`packages/ui/src`、`apps/desktop/src` 全文检索。
- 按名未命中 **173 个**。自动消解 `Metasequoia*` → `MSIME*` 的改名与 camelCase → snake_case 之后，余 **164 个**。
- 这 164 个按来源归类：绝大多数是原生设置窗口的 action selector 与偏好访问器（`schemeChanged`、`voiceProviderChanged`、`storedWubiCodeHintEnabled`、`refreshVoiceControls` 一类），按「公共 UI 放 Tauri」本就不该在目标存在对应物；其余是被下沉的实现细节（词库安装与学习数据重置的标记/恢复协议 `WriteResetMarker`、`RecoverLearningReset`、`InstallMetasequoiaDictionary` 等，在目标由引擎与共享 Rust 承担）与内部小工具（`MsimeHex`、`FailWithErrno`、`RemoveIfPresent`）。
- 其中不属于上述两类、最像功能的一组逐个核过并都已覆盖：Option/Control + 数字取释义（`CandidateGlossRequestForModifiers` → `commitCandidateGlossColumn:`）、待上屏列（`setArmedGlossColumn` → `_armedGlossColumn` 与其夹取）、候选置顶（`MetasequoiaTogglePinnedWord` → `MSIMESetCandidatePinned`）、释义调度（`scheduleCandidateTranslations` → `synchronizeCandidateGloss` / `synchronizeAccountGloss` 与空闲延迟）、反馈诊断（`copyFeedbackReport` → Tauri 反馈页的「复制报告」）、学习数据清除（`ResetMetasequoiaLearnedData` → Tauri「清除学习数据」→ `resetLearnedData` 能力 → `reset_learned_data` → 引擎）。
- 单点对照另外确认：`ActionForSolitaryShift` 对应 #3179 之后的单击 Shift 行为，`NextArmedGlossColumn` 对应 `cycleArmedGlossColumnBackwards:`，`browseVoiceModel` 对应 #3212 新增的 `pickVoiceModelPath`，`MetasequoiaCandidateWantsOnlineGloss` 对应 #3156 的 `MSIMEOnlineGlossCandidates`。

## 当前完成度

代码侧的迁移按上述五次比对已无已知缺口；macOS `ctest` 全通过，`scripts/known-failures.txt` 无 macOS 条目。

曾经挂着的两条跨平台取舍，现已各自归位：

- **语音整理的请求预算**：是 macOS 缺口，已修（#3224）。目标此前沿用 Windows 的 3 秒总预算，而来源实测 3 秒下整理「永远来不及返回」并使用 30 秒；配合 `HTTPVoiceRequest.mm` 吞掉失败的写法，结果是转写已经发给服务商、清理后的答案每次都被丢弃、界面毫无提示。现在预算是带默认值的参数，默认仍是 Windows 的 3 秒，只有 macOS 显式传 30 秒——Windows 行为一字未动。代价也一并写在提交里：整理与转写在同一条路径上，慢的服务会推迟文字上屏本身，这与来源的取舍相同，且好过「发出去再把回答扔掉」。
- **离线释义的查询顺序**：**不是 macOS 迁移缺口**。`msime_client_candidate_gloss_request` 是所有宿主共用的 C ABI，`candidate_glosses_with_user` 的顺序在 macOS、Windows、Linux、HarmonyOS 上完全一致，macOS 并不落后于本产品的任何宿主。与来源的差异是整个产品层面的一个刻意选择：引擎把顺序设计成构造参数（custom_translations → 随包 → 联网缓存），来源直接用四参数构造，而目标另开 `translation-glosses.db` 先查，并由 `crates/engine-bridge/src/lib.rs` 的 `unsafe_learned_glosses_fall_back_to_packaged_values` 明确断言「learned 优先于随包」。

  此处此前记过一条「用户手写的释义会被自动学来的盖过、需要引擎侧改动」——**那是错的**，实测推翻：不改一行桥接代码，用户写的条目就已经排在最前。路径值得写下来：`translation-glosses.db` 与设置页写的 `custom_translations.txt` 同在用户目录下，而 `EnglishDictionary` 在没有显式 translations 路径时会读取数据库旁边的 sidecar，于是 learned 那个对象本身就带着用户手写的条目，`query_*_gloss` 又先查 custom。所以优先级是「两个文件恰好同目录」带来的涌现性质：挪动其中任何一个，或给 learned 传一个显式 translations 路径，都会把用户的释义静默降到最后。`crates/engine-bridge/src/lib.rs` 的 `hand_written_glosses_outrank_learned_and_packaged_ones` 现在固定住了这一条。

因此当前只剩一项未完成：

**安装后的交互验收**——不是代码缺口，见下一节，需要一次重新登录才能把新的输入源 identifier 加进本次登录会话的列表。

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

## 仍需重新登录一次才能验收的部分

这一项此前记为「需要签名产品包」，是错的。实测（见 `platforms/macos/README.md`）：把同机注册正常的那份输入法复制一份、只换 bundle identifier、用同一张 Developer ID 证书重签后注册，失败方式完全一样——`TISRegisterInputSource` 返回 noErr 而 `TISCreateInputSourceList` 查不到。真正的判据是**该 identifier 在本次登录会话开始时是否已在输入源列表里**：唯一能被列出的那份，其安装时间早于本次会话的开始；重启 `imklaunchagent`、`lsregister` 重新登记与重扫用户域都无效。所以本项目的 bundle 在这一点上与那份能用的输入法表现一致，不是装配缺陷，签名产品包也绕不过去。下列三项需要重新登录一次之后才能验收：

1. 输入菜单与菜单栏中图标的实际观感；
2. 麦克风与语音识别的 TCC 权限弹窗文案；
3. 真实编辑器中的组合、标点转换与本地 Whisper 识别行为。

bundle 自身是否装配正确由 `bundle-contents` 持续检查：图标是否真的暂存进 `Resources`、菜单图标是否带 16×16 与 32×32 两页、每条用途字符串是否在每种已暂存语言中都有、可执行文件是否链接了本地识别器。

## 基线状态

2026-09-20：`ctest --test-dir <build>` 在 macOS 上 120/120 全通过，`scripts/known-failures.txt` 中不再有任何 macOS 条目。此前长期挂着的 `local-mode-preferences`、`text-client`、`shortcut` 三条被一并记为「引擎答案与测试断言不一致」，逐条查下来没有一条是引擎：分别是测试没有提供被资源门控的可选词库、测试断言的恢复路径在组合期守卫加入后已不可达、以及一长串因套件提前中止而从未执行过的陈旧断言。因此这套测试从现在起才第一次真正是门，而不是一个总在红的名单。

## 不回退的保证

以下检查在 `ctest --test-dir <build>` 中运行，新增偏好、新增 TCC 调用、图标改名或本地识别器被关掉都会直接失败，而不是等到安装后才发现：

- `preference-coverage`：共享偏好要么被 macOS 宿主消费，要么在清单中写明不适用的理由。
- `bundle-contents`：产物 bundle 的图标、本地化与本地识别器链接。
- `info-plist-icons`、`info-plist-usage`：模板 plist 的图标引用与 TCC 用途字符串（含每种语言的本地化）。
- `voice-provider-settings-keys`：原生语音窗口的每个文本字段都对应一个运行时读取的默认键。
- `entitlements-guard`：签名用的权限文件不含受限权限（`com.apple.developer.*` 整族都需要 provisioning profile 背书，Developer ID 签名给不了，AMFI 会在 exec 时拒绝启动，表现为输入法从输入菜单里消失而签名本身校验正常），且 `install.sh` 拿到这样一份文件时会在动任何东西之前拒签。对应来源侧 #465 在发布打包脚本里的同名拦截。
