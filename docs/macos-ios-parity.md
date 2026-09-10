# iOS → macOS 功能覆盖核对

本清单针对“把 iOS 的功能扩展到 macOS，但适配 macOS 原生特性”。依据是本分支的 iOS 产品入口和实现，不把其他后端路线图中尚未接入 iOS 的 API 自动扩充为本任务要求。源码接入、自动化测试和真实宿主验收分别记录。当前状态：**未完成验收，不应据此发布或宣称完整迁移。**

## 已接入的对应流程

| iOS 来源 | macOS 对应实现 | 验证与边界 |
| --- | --- | --- |
| `OnboardingView.swift`、`InputSchemePreference.swift`：全拼、四种双拼、五笔、日语、简繁与模糊音 | `PreferencesWindowController.mm`、`MetasequoiaInputController.mm`；原生输入菜单、候选窗及工具栏 | 会话与控制器自动化覆盖；方案/偏好在组合结束后生效。日语实机键盘和标点仍待验收。九键已接入数字组合与拼音菜单，实机交互待验收。 |
| `ReplyKeyboardView.swift`、`KeyboardChatView.swift`、`ServiceSettingsView` | `BackendWritingView.swift`、`NativeWritingWindow.swift`、`BackendChatView.swift`、`CustomWritingSettings.swift` | 后端和自定义服务、回复/润色、模型、模板、取消、账号绑定有合成测试。共享九种回复风格。选区恢复与替换必须补真实跨应用验证。 |
| `KeyboardVoiceView.swift`、语音服务设置 | `VoiceInputService.mm`、`VoiceSettings.mm` | 原生麦克风采集、识别和可选润色；控制器检查焦点/组合代次。当前改动仍需真实录音与宿主插入验收。 |
| `PersonalDictionaryView.swift`、`PersonalDictionaryImportView.swift`、词库设置 | `PersonalDictionaryWindow.swift`、`DictionaryMutation.swift`、`DictionaryRuntime.mm` | 本地增删改和导入预览；固定 Engine 负责算法，跨进程词库租约和代际切换有测试。首次迁移的交互延迟待实测。 |
| `CloudDictionaryView.swift`、文件/目录/候选管理、快照流程 | `BackendDictionaryView.swift`、共享 `CloudDictionaryCatalogView` / `CloudCandidatesView`、`BackendSnapshotView.swift` | 有协议、文件边界及本机应用测试；不能把合成测试当作全部生产账号验收。 |
| `AccountSettingsView.swift`、验证码登录、`SettingsSyncView.swift` | `BackendAccountWindow.swift`、`BackendSettingsView.swift` | Keychain、刷新协调、退出/注销、显式设置同步、冲突和其他平台字段保留；真实登录依赖签名和服务端启用渠道。 |
| 云剪贴板和键盘本地历史 | `BackendClipboardView.swift`、`ClipboardHistoryWindow.swift` | 显式捕获/上传，搜索、固定、删除/清空；私有剪贴板与临时目录测试，无默认监听系统剪贴板。真实窗口待检查。 |
| `TypingStatisticsView.swift` | `TypingStatisticsWindow.swift`、控制器实际插入边界计数 | 本机统计，不上传；空统计窗口曾做视觉检查，计数边界有自动化测试。 |
| `CustomSkinEditorView.swift`、本地皮肤库 | `SkinEditorWindow.swift`、`SkinSettingsView.mm`、`SkinLibrary.h`、`SkinPackageRevision.swift` | 原生配色/横幅预览，保存、重开、分享、重命名、废纸篓、原位更新已接入；有真实临时文件测试。对话框、回退和实际窗口布局尚待验收。 |
| `AISkinGenerationView.swift`、`SkinGenerationView.swift` | `AISkinGalleryView.swift`、`SkinGenerationView.swift`、共享 `AISkinService.swift` | 三方案、三插画任务、进度/取消；另有深浅配色生成。测试覆盖任务释放、账号绑定和预览文件完整性。没有使用真实账号生成或发布作品。 |
| `SkinCommunityView.swift`、已发布作品 | `CommunitySkinView.swift`、`SkinPublicationView.swift` | 搜索、分页、我的作品筛选、预览、下载应用、评分、下架、显式发布；已下载皮肤用原生候选布局和顶部插画展示。 |
| `CommunityResourcesView.swift`：词包与回复模板 | 共享 `BackendCommunityResourcesView.swift`、`ReplyTemplateStore.swift` | 全部/我发布的/我收藏的；模板显式下载并在桌面回复中使用。异步输出检查模板是否已变。 |
| 输入安装与设置入口、帮助 | 原有安装器、输入源注册、独立设置启动器和关于页 | 发布包测试已跑过；新用户从安装到选中输入源的实际流程仍需纳入最终验收。 |

## 尚需落实或确认的功能覆盖

1. **九键的真实桌面交互验收。** macOS 全拼设置新增本机“数字九键”开关：2–9 交给固定 Engine 的九键会话；原生候选窗用拼音菜单消歧，Tab 可打开菜单，方向键和空格用于候选选择。拼音选择检查当前快照索引与文本，组合结束后才应用开关变化。控制器的数字输入、拼音选择和提交测试已通过；菜单鼠标/键盘跟踪、实体数字小键盘及真实宿主仍需验收。
2. **移动触控行为的桌面对应。** `KeyboardLayoutPreference.swift` 明确只改变 UI 键位，不改变 Engine：键距、侧栏宽度、字母缩进和底栏布局由桌面实体键盘及候选窗横/竖布局替代。九键组合另行迁移，不能归入纯布局。iOS 键帽形状、材质用于绘制虚拟按键；桌面保留实体按键并把配色/图片用于候选窗。`KeyboardFeedbackPreference` 的按键音已接入本机默认关闭开关，只在 Engine 处理按键后播放系统轻提示音，自动重复不重播；真实听感待检查。iOS 的 `UIImpactFeedbackGenerator` 键盘振动依赖触控设备硬件，桌面不模拟为鼠标/触控板振动。滑动空格的移动光标能力由实体方向键、系统选区操作承担；真实宿主的组合/光标行为仍需下项验收。
3. **真实宿主验证。** 至少覆盖候选点击/翻页/提交、中文与日语方案、活动组合中的偏好变化、失焦取消、润色选区恢复/替换，以及语音结果插入。现有模拟客户端与控制器测试不能单独证明跨应用行为。
4. **真实窗口与辅助功能。** 检查本次新增窗口、滚动区域、对话框、键盘导航和可访问标签。CUA 按路径读取曾返回 `cgWindowNotFound`；后续通过 Orca 按实际 PID 查询，已确认设置窗口存在、未最小化且在屏幕内。但窗口辅助功能读取返回 `permission_denied`，尽管权限状态显示已授予。用户继续后重启本任务的旧设置进程，Orca 与 CUA 读取均恢复。已检查键盘页、个人词库空列表及添加表单，验证 Escape 取消；修正九键/按键音间距、日语说明、空列表提示和显式辅助功能标签。其余新增窗口、完整键盘导航、VoiceOver 朗读与跨应用行为仍待验收。

## 最近验证记录

- 写作助手在等待原应用激活后再次核对账号、模板和服务配置，并在写入前复核取消状态和选区；新增回归覆盖复核拒绝与取消时不插入文本。当前通用 Release 构建和完整 48 项 macOS CTest（不含打包）通过。
- 当前构建的 `release_package` 测试通过，用时约 132 秒；与上述 48 项合计，49 项 macOS 测试通过。打包复测曾因磁盘耗尽失败，测试现于各阶段断言完成后清理临时副本，保留全部回滚与失败恢复断言。它验证打包流程，不代表已签名、公证、发布或安装到用户环境。
- 当前共享代码已通过完整 iOS arm64 模拟器 Debug 应用/扩展构建，以及测试目标的 `build-for-testing`。集成构建发现并修正了 `AppServicesBridge.mm` 被输入引擎静态库目录扫描重复纳入的问题。45 项 iOS 工程配置检查通过；测试目标已编译，尚未据此宣称测试运行通过。
- 本清单核对中补出的“我的皮肤筛选”和回复风格修改：通用构建、`backend_account` / `preferences_window` / `release_configuration` 三项回归、45 项 iOS 工程配置检查通过。共享回复模型通过 Swift 6 类型检查；随后完整 iOS 应用、扩展和测试目标构建也已通过（见上一条）。

完整验收还应检查整个变更集、iOS 兼容性、构建/打包以及上述未通过项。本任务在隔离分支 `feat/macos-backend-account` 进行；不应覆盖原工作区的其他改动，也不应把本地代码称为已合并发布。

- 最新窗口修整通过通用 Release 构建及 `backend_account`、`preferences_window` 两项回归；设置页脚边界回归曾发现 44 点新增行过高，已改为 28 点并复测通过。截图保存在本任务 `build/macos-account/ui-review/`。CUA 已读出个人词库各按钮名称；Orca 简化树未显示这些名称，因此不以该简化树作为标签缺失的唯一判断。
