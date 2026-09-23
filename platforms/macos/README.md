# macOS InputMethodKit 宿主

## 目录结构

macOS 平台源码统一放在 `src/` 下按 `backend/`、`voice/`、`candidate/`、`input/`、`cloud/`、`dictionary/`、`settings/` 和 `core/` 分层；`tests/` 保存测试，`resources/` 保存输入法资源，`scripts/` 保存构建脚本，平台根目录只保留 CMake、资源模板和文档。

本目录提供可复现的 IMK bundle、Rust/C++ 构建和离屏/替身测试，安装与注册核查由 `scripts/install.sh` 和 `scripts/check_input_source.swift` 完成。

## 安装与输入源注册

`scripts/install.sh` 会停掉正在运行的实例、在暂存目录用本机 Developer ID 连同 `resources/VoiceInput.entitlements` 重签名（`--deep`，因为 Sparkle 自带其发布方的签名，hardened runtime 下 Team ID 不一致会导致进程加载失败）、原子替换并保留旧 bundle，任一步失败自动回滚，最后调用 `--register-input-source` 并用 `scripts/check_input_source.swift` 查注册表，而不是只看退出码。LaunchServices 会把每个 worktree `target/` 下的构建产物都按同一个发布 identifier 登记，`install.sh` 因此在注册前只保留已安装的那一条。bundle 本身是否装配正确由 `bundle-contents` 这项 CTest 检查（图标是否真的暂存进去、用途字符串是否每种语言都有、语音提示音 `audios/start.mp3` / `end.mp3` 是否随包、可执行文件是否链接了本地识别器）。

bundle 使用系统已登记的 `app.msime.inputmethod.MetasequoiaIME`，已在列表中的 identifier 原地更新正常：`install.sh` 安装之后，`check_input_source.swift` 稳定报 `app.msime.inputmethod.MetasequoiaIME`、`.Hans` 与 `.Roman` 三条 enabled。

注册结果在刚替换 bundle、刚调用 `--register-input-source` 之后有一段分钟级的不稳定窗口：`TISCreateInputSourceList` 按 bundle id 查不到东西，过一会儿不做任何操作自己会回来，所以同一条 `check_input_source.swift` 隔几秒跑，会先报 not in the registry，再报 enabled。`install.sh` 只查一次就下结论，两个方向的误判都可能出现——判断安装结果时多查几次再看。

换一个新的 bundle identifier 时要知道 macOS 本身的一条限制：一个在本次登录会话开始时不在输入源列表里的 identifier，无论 bundle 内容如何都进不去列表——`TISRegisterInputSource` 返回 noErr 而 `TISCreateInputSourceList` 查不到，重启 `imklaunchagent`/`TextInputMenuAgent`/`TextInputSwitcher`/`keyboardservicesd`、`lsregister -f` 重新登记、`lsregister -r -domain user` 重扫用户域都改变不了。这与签名方式、名字是否 ASCII、plist 是否正确无关：把同机注册正常的输入法整体复制一份、只改 identifier 并用同一张 Developer ID 证书重签，失败方式完全一样。重新登录一次即可，之后同一 identifier 的更新都不再需要。`install.sh` 因此把安装与注册分开——bundle 就位并签名成功即视为安装成功，只报告需要重新登录。

应用支持显式 `--register-input-source` 启动参数：调用 Carbon TIS 注册当前 bundle，按 bundle identifier 找到可启用的输入源并启用自身、停用其他匹配列表中的输入源。`install.sh` 在替换 bundle 后直接调用它，注册和启用两条路径另有注入函数指针的原生测试覆盖。

## 标识与数据目录

这里有两个不同产品进程，不能用同一个概念混写：输入法本体是 InputMethodKit bundle，继续使用系统已经登记的 `app.msime.inputmethod.MetasequoiaIME`；承载共享 React 设置页的设置应用使用 `app.msime.client`。设置应用的默认状态根和输入法读取的原生定位器都在 `~/Library/Application Support/app.msime.client/`，外部皮肤、偏好、统计与 `runtime-options.json` 以此为当前默认来源。

设置应用和原生宿主均以 `app.msime.client` 作为正式客户端标识与默认状态目录；新安装按该标识初始化，不创建额外的预览目录。

SwiftUI 设置同步覆盖 24 个当前宿主偏好：候选皮肤、布局、字号、页大小、输入方案、翻页快捷键，以及纠错、辅助码、中文标点、智能标点、重复标点转中文、成对标点、标点锁定、中英/Emoji/颜文字混输、中英混输阈值、中英文模式、切换快捷键、中英文切换提示、全角、浮动工具栏、繁体输出、五笔自动上屏、双拼提示和手写板主题。浮动工具栏的本地设置还支持分别显示标点、全半角、简繁、Emoji、屏幕键盘和设置按钮，并选择 75/100/125/150% 缩放和 16–28pt 字号；这些字段通过 `preferences.floating_toolbar` 共享。共享 Tauri 与原生备用屏幕键盘都为普通键提供 450ms/75ms 的按住重复，粘滞修饰键不自动重复；键盘和辅助功能激活仍单次发送。macOS Tauri 键盘首次显示及隐藏后重开时使用显示器物理工作区底部居中，不混用逻辑点与 Retina 像素，也能处理负坐标副屏和比面板更小的工作区。云端桌面快照覆盖 Apple 固定提交 `2b0250f4dd7012520392b310dfcc0288c3208a75` 的 20 项字段，并保留客户端新增的 `shuangpin_preedit_uses_raw`、`smart_punctuation` 和 `smart_punctuation_repeat`，共 23 项：两套辅助码方案、候选学习、本地扩展模式、候选布局/尺寸、输入方案、纠错、标点、智能标点、重复标点转中文、英文模式、全角、工具栏、繁体输出、五笔自动上屏和双拼键位图。辅助码方案按稳定枚举索引同步；本地扩展模式的兼容布尔值为全开/全关，应用时写回八个本地模式而不丢弃未知键。布尔字段只接收 JSON 布尔值，旧云端快照缺少新增字段时不会部分应用，可先上传本机完整快照；其他平台云端字段由既有合并逻辑保留。

浮动工具栏沿 Windows 前台策略适配 macOS：输入法激活且用户开启工具栏时显示；检测到前台应用窗口覆盖整块显示器的全屏状态时自动隐藏，退出全屏或切换到普通窗口后恢复用户原来的显示选择。工具栏跟随输入法的选中而不是输入框焦点：切换应用、点桌面或切到没有输入框的窗口时它保持显示，切换到其他输入源或进入全屏应用时隐藏。检测只读取窗口几何，不记录应用名称、窗口标题或输入内容。工具栏最左侧是来源 `#8E8CD8` 的竖条拖动柄，鼠标悬停时显示张开手形光标，按住即可拖动面板，其后是一条分隔线再接按钮；按钮本身不会拖动面板。按钮在悬停与按下时显示圆角底色，深色为白色 0.10、浅色为黑色 0.08 透明度，分隔线深色为白色 0.15、浅色为黑色 0.12。

账户入口走共享设置页的 `settings:account` 路由；桌面设置不可用时回退到随 bundle 加载的 SwiftUI 账户窗口，不要求手填账户 ID。登录、设置同步、云词典、剪贴板、快照及社区资源由共享账户会话管理。云剪贴板入口同样使用该会话：已登录时打开该账户的剪贴板，未登录或读取会话失败时打开登录窗口，不要求手填 access token。本入口不迁移旧 Keychain 条目。`backend-account-entry` 测试验证原生到窗口的分派及接口缺失处理，`backend-library-load` 验证实际 dylib 的账户类与选择器。

## 输入源菜单与输入模式

输入源菜单按 `InputController.mm` 的 `- (NSMenu *)menu` 收敛为输入模式加即时工具：中文输入 / 英文输入 / 英文候选模式（⌃⇧E）/ 简体输出 / 繁体输出 / 悬浮工具栏（带勾选态）/ 水杉表情面板… / 水杉屏幕键盘… / 手写输入… / 开始/结束语音输入 / 水杉输入法设置… / 关于水杉输入法…。账户、词库、更新、帮助这些管理页统一进设置窗口——把它们逐条列进来会让菜单高过屏幕，而收进二级子菜单又会让常用的工具太难够到。默认中文；英文模式不准备 Engine 会话，按键直接放行。切到英文先用共享 Engine finish 完成当前组合并隐藏候选；失败时保留原模式。Shift+空格默认切换中英文，设置中可关闭；竞争 Command/Control/Option 修饰键不触发切换，重复事件消费但不反复更改偏好。英文模式激活后切回中文会恢复保留会话焦点与设置轮询。英文模式与快捷键偏好保存在宿主自身偏好域，不复用混合输入选项或算法状态。中英文状态按 `ime_mode_scope` 按应用或全局记忆；切到其他输入源（如 ABC）再切回时，两种作用域都从 `default_ime_mode` 重新开始，与 Windows 重新激活 TIP 时一致；在本输入法自身的模式之间切换不会清空记忆。macOS 还提供可由 Tauri 设置页开关的非激活 HUD：切换成功后在当前光标附近短暂显示“中”或“英”，自动避让屏幕边缘，不抢焦点、不吞鼠标事件，失活输入源时隐藏。

菜单栏的输入源图标常驻显示当前模式，对应来源托盘语言栏的中 / 英图标：bundle 声明中文模式 `app.msime.inputmethod.MetasequoiaIME.Hans`（图标「中」）与英文模式 `app.msime.inputmethod.MetasequoiaIME.Roman`（图标「英」，名称「水杉输入法 · 英」/「Metasequoia · EN」），两者在系统设置的输入源列表里是两条，Ctrl+空格与地球键轮换也会停在英文条目上。Shift / 快捷键、输入法菜单与悬浮工具栏切换中英文时，控制器用 `selectInputMode:` 选中对应模式；从系统输入法菜单选中某一条或轮换到它时，系统经 `setValue:forTag:client:` 报告模式，控制器随之切换中英文状态。两边共享一份「当前显示的模式」记录（`src/input/InputModeIdentifiers.h`），只重复当前模式的报告和控制器自己请求引起的回报都不算用户选择，因此不会来回回声；中英文状态按 `ime_mode_scope` 按应用或全局记忆，客户端获得焦点时把菜单栏模式对齐到当前作用域的状态；输入法进程重启后各应用从 `default_ime_mode` 开始，菜单栏同样在获得焦点时对齐。英文模式在系统设置里被移除，或旧安装尚未重新登记（`install.sh` 与设置页的「安装 / 更新」以 `--register-input-source` 登记并启用两个模式，设置页的「重启输入法」以 `--reregister-input-source` 重新登记；Sparkle 应用内更新只替换 bundle，不重新登记）时，控制器不请求这个不可选的模式，菜单栏保持「中」图标，行为与只有一个模式时相同。大写锁定用系统自带的指示；日语、全半角与标点显示在悬浮工具栏上。macOS 14 起 `selectInputMode:` 可能弹出系统自己的输入源光标提示，与上面的 HUD 重复时可在设置页关掉 HUD。

打开字符面板同样先完成组合，再请求系统 Character Viewer；测试以替身记录系统入口，不实际打开面板。原生测试覆盖菜单勾选、偏好保存、组合完成/失败、英文按键旁路、七种竞争修饰组合、重复/禁用快捷键、无会话懒加载与焦点恢复。输入法菜单和悬浮工具栏的“检查更新…”优先打开 Tauri 共享 About 页；Tauri 不可用时，有 `SUFeedURL` 的发布包回退 Sparkle 原生更新控制器，未配置 feed 的构建会明确说明不能应用内检查，并在用户确认后打开固定的官方发布页，打开失败也会显示错误，而不是静默无动作。共享 `theme` 与 `candidate_theme` 作用于实际 IMK 候选窗：`dark`/`light` 表面覆盖全局主题，`follow` 继承全局，`system` 通过 `NSPanel.appearance = nil` 交给 AppKit 跟随系统；偏好热更新会保留当前 Engine 组合并重绘候选皮肤。

原生菜单提供“简体输出”（默认）与“繁体输出”，保存到宿主偏好 `MSIMEClientTraditionalOutput`。调用 `msime-host-api` 的 `msime_client_simplified_to_traditional` 导出转换候选显示、完整 tooltip 和最终上屏文本，与 Windows、Linux 及来源同用 OpenCC s2t 词级词典（「头发」→「頭髮」而非逐字的「頭發」），输入不是合法 UTF-8 时保留原文；日语方案与 Unicode 精确码点模式不转换。转换只发生在原生展示/插入边界，Engine 原文、候选 ID、组合与运行时视图保持不变。

## 候选辅助码与纠错

候选辅助码后缀按固定 Apple `CandidateDisplay.h` 接入。桥接层复用 Engine 的 `HelpcodeUtils`，按当前会话自身资源目录与辅助码方案加载不可变映射；仅启用辅助码的全拼/双拼普通模式和超级简拼附加后缀，Unicode、日期、快捷短语等合成模式及五笔/日语不附加。未提供共享或本地覆盖时按 Windows 基线使用全拼自然码且隐藏、双拼蓝天且显示。共享 JSON 候选新增 `annotation` 字符串，原 `text` 和候选 ID 不变；macOS 测量、按钮和 tooltip 使用原文加后缀，再执行繁体展示转换，上屏仍只提交 Engine 原文。映射缺失时后缀为空，不读取其他会话的全局映射。共享偏好现有延迟应用机制确保组合期间不切换映射；旧宿主无 annotation 字段仍显示原文。

全拼的字母错位纠正与邻键误触纠正默认分别关闭，只有对应新字段或原生开关显式开启时生效。旧的单一 `autocorrect` 值继续保留在兼容快照中，但不再作为两项纠错的 fallback。

## 双拼与五笔

双拼键位提示面板迁自固定 Apple `ShuangpinKeymapPanel.h/.mm`，候选设置中提供开关，默认关闭，保存在宿主偏好 `MSIMEClientShuangpinKeymap`。开启后仅在有效会话、双拼组词和有效光标时显示；上屏/取消、失活、英文模式或关闭设置时隐藏。保留 620×203 点布局、四套 Engine 权威键位、微软分号键、零声母说明、末尾字母/分号高亮、明暗配色与可访问文本。面板不接受鼠标事件，以非激活浮动窗口显示；位置按上游规则为候选保留间距，避让屏幕边缘。

五笔四码唯一候选自动上屏默认关闭，使用 `MSIMEClientWubiAutoCommitUnique`。仅当 Engine 明确报告原生五笔候选、四码恰好一个候选且本次按键为小写字母时提交；拼音回退、其他方案、非四码或多候选均不提交。该判断完全依赖 Engine 快照元数据，不从候选文本猜测。

共享 JSON 视图新增 `shuangpin_profile`（实际生效的 xiaohe/ziranma/shoudao/microsoft），不使用尚未应用的偏好绘图；字段缺失时隐藏提示。Rust 测试覆盖四方案元数据和组词期间延迟切换，原生测试覆盖四方案×两外观离屏绘制、设置保存、微软键位、高亮/可访问文本、边界定位以及显示/隐藏条件。检查了微软亮色、小鹤暗色合成图；字体测量按 macOS 系统字体进行，不宣称与 Windows 逐像素一致。

## 全角输入

全角输入按同一固定 Apple 版本的 `FullWidthInput.h` 与控制器回退顺序迁移，默认关闭。候选设置中的勾选框（宿主偏好 `MSIMEClientFullWidthInput`，共享字段 `character_width`）是每个应用的起始值；中文模式下 Option + Shift + H、任意模式下 Control + Shift + Space（来源的 Shift + Space 在 macOS 上是中英文切换）以及悬浮工具栏的全角按钮只切换当前应用、不保存，与来源按线程保存在 TSF compartment 里一致，从本输入法切到别的输入源后所有应用回到起始值，起始值一旦改变所有应用都跟着重置；重复按键只消费不反复切换；Option + Shift + H 遇 Command/Control 竞争修饰键或在英文模式下不触发。按键先交给 Engine，已处理的中文组词、选词与标点不再转换；未处理的按键先完成剩余组合，确认空闲后才将 ASCII 空格变为 U+3000、ASCII 可打印字符变为对应全角字符。无会话、失败响应或组合未完成时不插入全角回退，非 ASCII 字符不转换。原生测试覆盖 95 个字符、快捷键/偏好、Engine 优先、组合提交顺序及失败/未完成排除，使用替身会话驱动。

## 共享运行时视图字段

共享 JSON 视图新增实际 Engine `scheme`（0 全拼、1 双拼、2 五笔、3 日语、255 未知）。有提交的 transition 携带分派前的 `commit_context`（`scheme`、`local_mode`），无提交时为 null；提交后 `view` 可能已清除局部模式或应用延迟配置，因此不能用它推断本次上屏来源。缺失/未知上下文不转换。Rust 测试覆盖五种选词路径、Unicode 模式重置和延迟切换日语；原生测试覆盖转换、排除路径、偏好与菜单、候选 ID/原文不变。

## 候选外观与皮肤

候选设置提供 Apple 固定提交 `b637828e15eafcb5e459edd270a962dd14517285` 的四套内置皮肤：Fluent、微信绿、石墨 Graphite、杨柳青。`CandidateSkin.h/.cpp` 的内置 token 与 `CandidateChrome.h` 的绘制来自该提交，保留明暗配色、边框、圆角、内边距、独立编号颜色及选中标记。跟随系统外观变化重新着色；设置变更立即重绘但不改变组合、候选 ID 或高亮。设置存入宿主自身偏好域。

外部皮肤读取同一固定来源的 `skin.toml` schema 1：元数据、内置 base、supports 布局/主题列表、明暗候选颜色、最小宽度和顶部装饰图。宿主只扫描 `~/Library/Application Support/app.msime.client/skins/<id>/skin.toml`，不读取或改写 MSIME-Apple 产品目录。把包放入该目录后，打开候选设置页或点击“重新读取皮肤”；内置项在前，外部项按名称排序，按 ID 保存选择。`skin.toml` 按完整 TOML 1.0 解析，用的是设置页和其他宿主共用的 client-core 加载器（经 host C ABI 的 `msime_client_skin_package` / `msime_client_skin_catalog` 调用，见 `src/candidate/SkinManifestBridge.mm`），字段校验与 Windows 相同，所以设置页列为有效的包在候选窗和悬浮工具栏里按其配色绘制；输入法内原生皮肤窗口（`SkinSettingsView.mm`）显示的无效原因由该文件换成中文，共享设置页显示加载器给出的原因原文。符号链接的包目录和非普通文件的 manifest 不算皮肤包。无效/缺失包使用 Fluent 渲染但保留用户选择的安全 ID。候选配色与图片缓存于设置快照，不在按键重绘时扫描磁盘。

候选装饰沿用 Apple 顶部右对齐和等比例缩放，宽度与顶部留白来自 manifest；缺失或无法解码的图片不绘制，保留声明的布局。外部 manifest 限 64 KiB，拒绝非普通文件、越界或经符号链接逃逸的包/manifest/资源路径；非法颜色忽略并保留基础配色。`toolbar_stylesheet` 在 macOS 原生悬浮工具栏中采用受限适配：支持颜色、圆角、边框宽度和内边距；按钮的悬停与按下底色固定取来源原生工具栏的常量，样式表里 `:hover`/`:active` 状态的颜色不参与原生工具栏；布局、脚本、图片、滤镜和其他 WebView 专属 CSS 会被忽略，不会注入 AppKit。

皮肤浏览入口优先打开共享 Tauri `settings:skin` 页面，Tauri 不可用时回退到按固定 Apple `SkinSettingsView` 迁移的原生卡片式页面：四套内置皮肤、外部包描述、每卡独立明暗预览与单选启用开关，已启用项再次点击不会关闭。外部包通过“打开目录 → 复制皮肤文件夹 → 刷新皮肤”加载，提供空状态和无效包扫描诊断。固定 macOS 源码没有内置导入/删除按钮，本页保持该目录管理流程，不另外创建导入器。目录打开仅由用户点击触发；宿主目录创建/打开失败会显示错误，不触碰 MSIME-Apple 目录。共享页面与原生回退共用同一受控皮肤目录和设置快照。

macOS 原生候选翻译回退窗口与共享 Tauri 设置保持一致：可直接开关不联网的英文释义，并写入同一 `candidate_english_gloss` 偏好。在线候选翻译关闭但离线释义开启时，主、次目标语言仍可编辑；两种释义都关闭时才禁用语言选择。保存仍使用共享快照的 CAS 版本检查，不放宽凭据验证或并发写入保护。

腾讯、自定义与小牛翻译取回的英文释义与来源的 `PersistGloss` 一致，每次取回成功即写入偏好目录下的用户释义库 `translation-glosses.db`，不必等候选上屏；只存目标语言为英文、格式化后不超过 32 个字符且与原文按 ASCII 忽略大小写不相等的释义，其他目标语言只留在内存缓存。之后的离线释义查询先读这个库，其记录覆盖随包词典中的同词释义；过期的在线回调不写入。托管账号释义不属于来源的服务，仍只在对应候选上屏时写入。

AI 候选与候选释义相互独立：与来源的 `ai_eligible` / `UpdateAiInput` 一致，只由 AI 助手开关 `ai_assistant.enabled`（以及英文模式、特殊模式和纯拼音资格）控制，关闭“显示候选释义”只影响释义与翻译，不阻止或取消 AI 候选请求。与来源出厂模板一致，AI 助手在全新 profile 上默认开启并指向 DeepSeek（`deepseek-v4-flash`）；没有填 Token 时 `chat_completion_http_request` 直接拒绝构造请求，不会产生任何网络流量。

`skin-settings` 原生测试覆盖四卡选择与保持启用、无副作用明暗预览、系统主题标题、外部卡重复刷新无累积、无效包诊断、空状态、打开目录的路径/失败检查，以及入口窗口构造与重复使用。测试目录打开器为替身，不启动 Finder；只操作临时合成目录，卡片离屏图像逐项检查。

设置窗口的候选预览迁自同一固定版本的 `CandidateSkinPreviewView`，随布局、每页数量、字号和皮肤实时更新。使用固定演示样例而非真实输入；竖排最多展示五行并提示剩余项，横排不足时显示省略号。可单独切换预览明暗主题，也可同时展示横排、竖排及状态栏样式；这些预览操作不写偏好或调用输入会话。预览里的状态栏是非交互展示，实际悬浮工具栏由 `FloatingToolbarPanel.mm` 绘制。外部装饰图和长预览在可滚动区域显示。预览使用注入的设置快照与皮肤目录，不读取 MSIME-Apple 产品设置；强制主题的系统文字颜色在对应绘制外观下解析。

`skin-preview` 原生测试覆盖四皮肤 × 两布局 × 三页大小 × 三字号 × 两主题的 144 次绘制，设置控件联动、无副作用的预览主题/展示切换、系统外观跟随、外部包回退、装饰区域可见像素和长内容滚动。原生合成 PNG 使用明确的 RGB 数据与 sRGB 标记，避免透明夹具掩盖绘制缺失；像素断言允许系统 ColorSync 转换，不宣称跨显示器逐像素一致。

皮肤验证包含八组固定配色与几何基准，以及四皮肤 × 两布局 × 两外观的原生离屏绘制、设置保存和组合保留测试。原生 Objective-C++ 构建启用 `-Wall -Wextra -Werror`。

外部皮肤追加固定源解析测试和路径/颜色拒绝测试，以及生成的 PNG、真实设置控件选择与保存、两布局/两主题装饰位置、缓存与显式重载回退的原生测试；只使用临时合成包和独立偏好 suite，不操作用户皮肤目录。

每页候选按 Apple `CandidatePageSize.h` 提供 5/7/9 项，默认及非法值归一化为 9。原生偏好在创建/激活会话及设置变更时请求共享分页覆盖；组合期间保持当前页、高亮和数字选词映射，组合结束后使用最后一次选择。此 macOS 原生覆盖优先于共享偏好中的 candidate_page_size，并在共享 Engine 配置重建后保留；不修改共享偏好文件。视图的 page_size 反映实际生效值。原生设置和 C API 测试覆盖保存、延迟、非法值、重复请求与重载。

布局和字号按固定 Apple 来源的 `CandidatePanelStyle.h`、`CandidateFontSize.h` 与原生设置控件迁移：默认横排/18 点，提供横向排列、纵向列表，以及 16/18/20 点字号。“水杉输入法设置…”打开共享设置页的外观页，Tauri 不可用时回退到原生偏好窗口的同一组设置项。值保存到宿主自身 NSUserDefaults 域，不读取或改写 MSIME-Apple 产品偏好，也不改动共享 Engine 配置。已激活候选立即重绘，组合及页内高亮保留。横排左右键导航、上下键消费；竖排上下键导航，左右键与候选隐藏时一样移动组合光标并刷新候选，对齐 Windows 候选显示时 `VK_LEFT`/`VK_RIGHT` 映射为光标移动。横排过长时按可用屏宽缩放每项展示宽度并截断文字。

## 候选学习与跟随光标

候选设置还提供候选窗口跟随光标开关，以及候选学习与拼音调频：关闭跟随后，在一次组合期间锁定首次有效光标位置；切换输入会话、结束组合或重新开启跟随时重新定位。学习开关以及关闭、置顶、折半、线性、置前五种调频模式，触发次数和线性步长均为 1–10。值保存在宿主偏好域，并按共享 `candidate_follow_cursor`、`learning` / `frequency` 快照合并；输入会话仍由共享 host-api 在组合结束后延迟应用，Engine 继续负责学习数据和调频算法。旧快照缺少这些字段时保持默认值，不改写原文件。Emoji SwiftUI 面板消费共享 `emoji_theme`：显式深色/浅色覆盖全局，`follow` 继承全局，系统主题保持 `nil` 让 SwiftUI/AppKit 自然跟随；旧快照未提供该字段时沿用全局主题。

## 语音输入

原生语音波形面板消费共享 `voice_theme`：显式 `dark`/`light` 覆盖全局主题，`follow` 继承全局，全局主题为 `system` 时使用 `NSPanel.appearance = nil` 并让 AppKit 重绘跟随系统。波形、状态文字、转写预览和确认/取消按钮同步切换明暗 palette；主题热更新只改变展示，不取消录音、识别或润色请求。`voice-wave-overlay` CTest 覆盖四种解析路径、系统外观回退和原有动作/转写边界。

语音设置的原生备用窗口提供 CoreAudio 录音设备选择：只列出有输入流且有稳定 UID 的设备，将当前系统默认置顶，按名称/UID 稳定排序；保存 UID 而非易变的序号或显示名，设备暂时不可用时保留选择并让下一次录音明确失败，不静默切换麦克风。空选择使用系统默认设备。共享 `capture_device` 与该 UID 双向同步；`voice-capture-device` CTest 覆盖输入设备过滤、默认排序、UID 缺失和失败路径。Tauri 设置页通过 `list_voice_capture_devices` 提供刷新列表。

原生备用窗口修改的有效语音字段会回写共享 `voice_input` 偏好，避免与 Tauri 页面形成第二套配置；ASR 与润色 Token 都按 provider 槽位保存，切换 provider 会先保存旧槽位再加载新槽位，缺失槽位继续兼容旧扁平字段。豆包鉴权模式与 Tauri 同步支持新版 API Key 和旧版 App ID + Access Token，缺失模式时按已有 App ID 兼容推断。文本润色开关同时维护 `polish_text` 与兼容的 `polish_enabled`，保证所有原生请求路径一致。损坏的 provider 值回退到安全首项，缺失或非法的本机默认值不会覆盖共享字段。凭据不纳入云端外观同步，CoreAudio 设备仍以稳定 UID 保存。共享快照写进 NSUserDefaults 之前，润色服务的原生回退值统一是 DeepSeek（`https://api.deepseek.com/chat/completions`、`deepseek-v4-flash`，定义在 `SharedVoicePreferences.h`），与共享层在 macOS 上的首次运行默认一致，原生语音设置窗口、备用 provider 窗口与录音请求不会各报一个 provider。

录音提示音是产品自己的 `start.mp3` / `end.mp3`，CMake 直接从 `platforms/windows/installer/assets/audios/` 放进 bundle 的 `Resources/audios/`，仓库里不另存一份。`VoiceCuePlayer.mm` 启动时一次性解码为 `NSSound`，每次播放先 `stop` 再 `play`，与来源 `cue_player.cpp` 一样从头重播。某一个文件缺失或解码失败时该侧回落到系统的 Glass / Pop 并写一行日志，而来源此时不出声：这里宁可保留一个能听见的开始 / 结束反馈。`voice-cue-player` 与 `bundle-contents` 覆盖这两点。

「录音时静音其他声音」按来源的时序：开始提示音播完再静音，结束、取消与失败时先恢复再播结束提示音，所以两段提示音都听得见；录音在开始提示音播完前就结束时不会再去静音。macOS 13（部署目标）没有只静音其他进程的公开接口，`VoiceAudioMuter.mm` 仍静音整台默认输出设备；14.2 起的 CoreAudio process tap 能做到，但要抬高部署目标并申请「系统录音」权限，为一个静音选项不值得。静音期间监听默认输出设备，插拔耳机或连上 AirPods 时恢复原设备、静音新设备；用户自己已静音的设备不接管，事后也不解除。崩溃恢复记录最多同时记 8 台欠恢复的设备，只欠一台时写旧的 `version 1` 格式；仍找不到的设备留在记录里，但不挡住下一次录音静音当前设备。`voice-audio-muter`、`voice-mute-recovery` 与 `http-voice-controller` 覆盖切换、恢复与提示音顺序。

录音时长按实际上传的格式封顶，不再在 60 秒处作废。批量识别上传的是共享层编出的 16 位 WAV，上限与来源同为 20 MiB（`shared/voice/VoiceProviders.h` 的 `batch_upload_sample_limit`，16 kHz 下约 655 秒），再扣掉 SiliconFlow 两端的补静音，保证录满的一段对每家都编得出来；本机 Whisper 按 Engine 自己校验的 60 秒（`local_asr_sample_limit`）。录满上限时宿主像用户松开一样结束录音：浮层转为「识别中...」、播结束提示音、提交已录的部分。来源的做法是攒下全部音频、提交时报「超过 20 MiB 上传限制」并丢掉整段；这里提交前 11 分钟的文字，内存也有界。豆包流式不设长度上限，缓冲只保留尚未发送的样本，只保留 30 秒请求超时与结束后等最终结果的 30 秒，不再有按 60 秒录音估出的 100 秒整场时限。

识别失败时浮层状态行显示类别文案，正文区显示服务商给出的原因，文案逐字取自来源：HTTP 失败取服务商 JSON 的 `error` / `message`（附 `code`），取不到则显示 `HTTP N`，SiliconFlow 5xx 附追踪 ID；豆包分别报连接失败（按新版 API Key 或旧版 App ID + Access Token 提示该检查哪项）、握手失败与带 `code` 的服务端错误。原因来自 `shared/voice` 的 `CloudAsrError` 与 `VoiceFailureMessages.h`，不含 API Key、请求头或请求体；共享错误的 `what()` 不变，Windows 宿主不受影响。没填 ASR Token 且没有共享 provider socket 时，在请求权限和开始采集之前就在浮层提示去设置里填写，不弹模态窗口。来源的失败提示是模态消息框，这里留在浮层上。

浮层的尺寸与布局照来源 `wave_overlay.cpp`：录音时 78×32 的紧凑波形，识别或润色时 112×40 的「识别中...」/「处理中...」胶囊，锁定录音或等待结果时 142×40、两端带圆形「×」/「✓」的操作条，流式转写时 420×112 的转写面板，最多 3 行，放不下时丢掉最早的文字并以「…」开头，切点落在组合字符边界上。12 条波形每 16 ms 刷新，只在浮层显示波形时计时。圆形按钮只在按住录音后按 Space 锁定、或识别与润色进行中出现，点击由透明按钮接收并保留「取消」/「确认」无障碍标签，只有操作条可见时浮层才接收鼠标。浮层位于可用区域底边上方 10 pt。与来源的两处不同：锁定且有转写时操作条内不画转写；三条识别路径停止录音后一律显示「识别中...」胶囊加按钮。

## 菜单主题

原生输入源主菜单和候选右键菜单共同消费共享 `menu_theme`：显式 `dark`/`light` 覆盖全局主题，`follow` 继承全局，`system` 交给 AppKit；菜单每次创建时读取最近一次偏好快照，不改变候选动作或输入会话状态。

## 标点

中文标点的勾选框（宿主偏好 `MSIMEClientChinesePunctuation`，共享字段 `chinese_punctuation`）同样只是每个应用的起始值：Ctrl + . 与悬浮工具栏的标点按钮只切换当前应用、不保存，中英文切换让标点重新跟上模式，对应来源的 `SyncPunctuationWithImeMode`：进入英文模式时标点变为英文（标点锁定固定为中文时除外），回到中文模式时丢掉当前应用的切换、回到起始值；从本输入法切到别的输入源后所有应用回到起始值，普通的焦点切换不会。成对标点和标点锁定跟随 Windows 基线迁移到候选设置。成对标点默认开启，标点锁定默认跟随中文标点，也可固定为中文或英文；设置值分别写入宿主偏好域，并按共享 `paired_punctuation`、`punctuation_lock` 字段同步。输入会话只通过 `MSIMEClientSession` 调用 Engine 的运行时覆盖，重建会话时恢复覆盖值；原生控件和替身会话测试覆盖默认、持久化、非法值和同步路径。

智能标点和重复标点转中文按 Windows 基线适配到 macOS 编辑器上下文：空闲态通过 NSTextInputClient 光标前一个 Unicode scalar 判断逗号、句号和冒号前是否为 ASCII 字母/数字，并按「数字后直出」「字母后直出」两个开关分别决定是否保留 ASCII。智能标点、重复标点转中文和这两个直出开关与来源一样默认关闭，需要用户主动打开。组合态依据高亮候选末尾走 Engine 的 ASCII 标点入口。短时间在同一编辑器重复输入同一标点时，将前一个 ASCII 或全角标点替换为对应中文标点；切换客户端、退格、关闭选项或不满足上下文时清除重复状态。全角输入仍优先转换为全角标点，小键盘物理键路由优先于智能标点。测试使用合成 NSTextInputClient，不保存或记录真实输入。

「中文标点后按空格转换」使用空格作为改写手势：成功时把刚上屏的 `。，！？；：、` 或单独出现的引号、方括号、书名号和圆括号替换成对应 ASCII 字符，并消费空格，不向正文追加空白。宿主在改写前重新读取光标前字符；切换编辑器、夹入其它按键、移动到不同字符、存在组合、全角输入或成对标点仍有自动补全尾部时均放弃改写。该规则与共享 `client-core` 策略及固定 Windows 来源一致。

## 混合输入

中英、Emoji 和颜文字混输设置跟随 Windows 的 `mixed_input` 偏好迁移到 macOS。中英混输默认开启，触发阈值默认 5 个字符，Emoji 默认开启（与来源出厂的 `emoji_mixed_input = true` 一致）、颜文字混输默认关闭；阈值限制为 1–8，关闭中英混输时控件保留数值但暂时禁用。设置写入宿主偏好域，活动组合期间由共享 host-api 延迟应用，平台不复制 Engine 的候选混排算法；原生测试覆盖共享读取、持久化、控件联动和非法值保护。

## 候选窗口翻页按钮与定位

多页候选显示 Apple 风格的 `‹` / `›` 鼠标翻页按钮（28×26 点，竖排底栏 26 点）；单页不显示，首页/末页禁用越界方向，并提供中文可访问标签。页码和候选由共享运行时返回，点击分派既有翻页命令；回调校验会话、组合代次、原页面与焦点，防止旧按钮影响新输入。原生测试覆盖实际按钮点击、方向禁用、单页隐藏和过期回调。滚轮翻页对齐 Windows `candidate_wheel_paging.h` 的累加语义：触控板精确滚动累计满 40 点（WebKit 一格滚轮的距离）才翻一页，多格拆成多次翻页，惯性事件不翻页，反向、手势开始、面板隐藏与候选刷新都清空残留；传统滚轮一个事件翻一页。

候选定位与焦点约束对照同一 Apple 提交的 `CandidatePanel.mm`：无效光标隐藏窗口、以光标垂直中点选屏、与光标相隔 4 点、底部不足时向上放置，超大窗口至少锚定可见屏幕原点。候选窗口不能成为 key/main window，按钮不接受键盘焦点但支持首次鼠标点击。宽度随候选文字变化并受屏宽约束，长文本截断并提供完整 tooltip；候选行按 Windows 四套内置皮肤使用各自的圆角，并区分普通行和选中行的 hover 颜色。

## 构建与本地测试

并行开发时使用独立产物目录，避免其他平台构建覆盖最低系统版本设置：

最低系统版本用 `CFLAGS` / `CXXFLAGS` / `CMAKE_OSX_DEPLOYMENT_TARGET` 分别交给 C、C++ 与 Engine 的 CMake 构建，**不要**改回一个全局的 `MACOSX_DEPLOYMENT_TARGET`。rustc 会把该变量一并应用到为宿主编译的 proc-macro 动态库上，而它随后加载不了自己产出的这个库，于是冷缓存构建以 `can't find crate for zerofrom_derive` 失败；cargo 不把这个变量算进指纹，坏掉的 proc-macro 会留在产物目录里，之后即使不再设置该变量也继续复用，失败因此看起来时有时无。上面的写法只影响真正需要最低版本的 C/C++/CMake 目标，链接时没有版本不匹配告警；Rust 目标文件按 rustc 默认的 11.0 产出，低于 13.0 下限，不会抬高最终 bundle 的最低系统版本。

原生更新控制器依赖固定的 [Sparkle 2.9.6](https://github.com/sparkle-project/Sparkle/releases/tag/2.9.6)，不可省略。下载该发布的 `Sparkle-2.9.6.tar.xz`，用 `shasum -a 256` 校验为 `52bf9e88cdd972fc0c81501377a880e90d47031bd8ca5462488f843e2609e192` 后解压到独立依赖目录。下列 `MSIME_SPARKLE_ROOT` 必须指向包含 `Sparkle.framework` 的目录，不是框架内部；请替换示例绝对路径。CMake 校验框架版本，并将其复制到应用的 `Contents/Frameworks`。构建不会自动下载框架，也不应从其他已安装应用复制依赖。

```sh
CFLAGS="-mmacosx-version-min=13.0" CXXFLAGS="-mmacosx-version-min=13.0" CMAKE_OSX_DEPLOYMENT_TARGET=13.0 CMAKE_PREFIX_PATH="$(brew --prefix)" CARGO_TARGET_DIR=target/macos-cargo cargo build -p msime-host-api --locked
cmake -S platforms/macos -B target/macos-isolated -DMSIME_HOST_LIBRARY="$PWD/target/macos-cargo/debug/libmsime_host_api.a" -DMSIME_SPARKLE_ROOT="/absolute/path/to/Sparkle-2.9.6"
cmake --build target/macos-isolated --parallel
ctest --test-dir target/macos-isolated --output-on-failure
```

原生测试使用不显示窗口的面板子类验证布局、完整 tooltip 和无效光标隐藏，以及纯几何边界和焦点方法。

## 剪贴板本地测试

剪贴板回归注册在本地 CTest 里。完成上述配置后，可单独构建并运行：

```sh
cmake --build target/macos-isolated --target macos-clipboard-tests --parallel
ctest --test-dir target/macos-isolated -L clipboard-local --output-on-failure
```

该标签涵盖历史适配与观察、采样过滤、监听重试与取消、单服务生命周期、行/提示像素、窗口释放、复制与最近记录、开启设置的保留语义。测试仅使用合成回调和独立命名的剪贴板，不启动输入法、不访问系统通用剪贴板或真实历史。Swift 测试以当前构建主机架构和配置的最低 macOS 版本编译，显式保持断言开启；每项有 30 秒超时。

## 表情与剪贴板面板

贴纸和 GIF 按固定 Windows 版本提供首页“更多”入口、主导航页及内容源未接入提示；该版本自身没有媒体内容源，本实现不新增第三方服务。进入这些页面保留搜索文字，使用通用搜索占位提示，不读取目录数据库，不显示分类、分页、键盘选项或插入按钮。首页入口在目录加载中或失败时仍可使用。首页测试覆盖页面标识、提示文字与浅色／深色原生提示渲染。

复制及开启剪贴板反馈采用固定 Windows 版本的底部胶囊提示：持续 1.6 秒，新操作重新计时，切换页面立即关闭，不占内容布局也不拦截点击。复制成功提示去除 CR/LF 后显示最多 24 个 UTF-16 单位的预览和省略号，截断时避免破坏代理对；失败提示不包含复制内容。字体、内边距、高度、底部距离及两种主题透明度按原版 2/3 比例绘制。提示测试使用合成文本及注入的等待函数，覆盖过期计时器隔离、取消、文本边界和原生渲染像素，不访问真实剪贴板。

### 导航与分类

表情主导航只在首页显示，顺序按固定 Windows 的 Page 枚举与图标表校正为首页、表情、贴纸、GIF、颜文字、符号、剪贴板。最近使用属于表情页二级分类：从首页入口或“更多”进入表情时，有最近记录则优先显示最近，无记录则在分类元数据载入后选择第一个分类；从最近切换具体分类保留明确选择。最近使用为空时，共享 Tauri 面板与原生回退面板都按来源 `EmojiPanel.cpp` 显示 `Your recently used items will appear here`（英文原文，来源无本地化），输入搜索时也不变；已有最近记录但无搜索匹配时显示 `No results`。详情页显示返回首页及对应分类／标题，切换保留搜索文字。原生输入源剪贴板采集与来源 `NormalizeClipboardText` 规范化方式一致：剥掉尾部 NUL 与 `\r`，超过 4000 个 UTF-16 单位的复制截取前 4000 个单位保存，不拆开字符（含补充平面字符），因此始终不超过 12000 个 UTF-8 字节，不会整条丢弃；历史适配器和 Tauri 监视器按同一 4000 单位／12000 字节边界接受条目，中日韩文字不会被旧 4096 字节边界提前拒绝。NUL 以外的控制字符（换页、ESC、DEL、C1 等）作为用户内容保存、显示和粘贴，只有含 NUL 的文本被拒绝。输入源采集和 Tauri 监视器按同一份类型表跳过不含纯文本、或带 nspasteboard.org 标记类型（Concealed／Transient／AutoGenerated）及密码管理器与片段工具私有类型（如 `com.agilebits.onepassword`）的剪贴板变更，不记录其内容；读取期间剪贴板计数变化的一次不配对旧类型，留给下次轮询重读。测试覆盖入口顺序、默认路由、异步分类解析、截断与控制字符规范化以及 Unicode 容量边界。


主标签按 `emoji_panel_icons.cpp` 的码位依次解析已安装的 Segoe Fluent Icons / Segoe MDL2 Assets，逐字检查是否存在字形；不下载、捆绑或安装字体。两者都不可用时使用原版中文回退文字，其中首页的可见回退为“最近”，但辅助功能标签及路由仍为首页。标签相对宽度、间距、高度、悬停颜色、选中下划线及字号采用原版 2/3 比例；本地测试强制覆盖缺字回退，检查两种主题的七种选中位置像素。Windows 字体图形在缺少相应字体的主机上走中文回退，不宣称与 Windows 逐像素一致。

表情二级分类使用原版区分大小写的分类名称映射，最近使用显示秒表图标，未知名称使用微笑回退。符号大类按元数据顺序取各大类第一个符号作为图标，默认选择首个有效大类；元数据和图标一并加载，取消页面任务会取消后续图标读取。分类标签宽度不超过原版 52 单位的 2/3，并随可用宽度均分收窄；标题通过辅助功能标签与悬停帮助提供。符号搜索忽略当前大类和子分类，匹配原版全局搜索行为。测试使用合成目录回调验证映射、顺序、缺失／失败、搜索过滤及两种主题的选中下划线像素。

符号内容按目录中连续的子分类分段展示标题及独立六列网格，移除额外的子分类下拉过滤。标题高度、半粗字号、相对缩进和分组尾部留白采用固定 Windows 版本的 2/3 比例；相同标题的非连续分组不合并、不重排。分组内按钮保留完整结果的全局索引，复制和键盘步长不因独立起行而指向其他条目。批次拼接后统一分组，读取批次边界不再拆分标题。合成测试覆盖重复标题、分组边界、全局索引、部分行之间的导航及两种主题的原生尺寸／选中像素。

### 目录读取游标

连续目录读取的宿主接口提供可选 `cursor:true`：`msime_client_emoji_catalog_request` 返回 `items`、`next_offset` 和 `complete`。详情 UI 已移除手动分页，按 `next_offset` 连续读取，仅在 `complete:true` 后一次性显示完整结果，不用返回条数或空数组判断结束。游标按实际扫描的匹配行前进，跳过空文本／无效分类行但不提前终止，保留有效重复条目；恰好满批时再读一批确认结束。切换查询取消后续批次，失败不展示部分结果。读取前后检查数据库及 WAL 的设备、inode、大小和修改时间，普通替换或写入会使本次读取失败；此防护不是跨请求 SQLite 快照，无法保证检测元数据不变的原地修改。未提供该选项的旧分页接口继续逐页去重，响应格式不变。首页预览仍保留各分类数量限制。合成游标测试覆盖空批次继续、重复项、协议错误、取消、失败和文件变化。

首页预览也使用游标接口，按有效条目数读取到预览上限或明确 EOF；空扫描批次继续前进，保留重复项，不再使用旧分页去重结果。批次大小不超过剩余预览配额，达到配额前仍检查取消和文件变化。完整详情仍读取到 EOF，不受预览配额影响。重复条目的 UI 标识增加同文本／同分组的出现序号，绘制、选择及键盘导航共用该标识。合成测试覆盖空批次、重复项、短目录、非法配额、达到配额时文件变化以及重复项导航；文件检查仍非跨请求数据库快照。

### 标题与搜索框

首页标题对齐原版 `Recently used`、`Emoji`、`Kaomoji`、`Symbols`、`Sticker`、`GIF`，采用 32 点标题行、12 点半粗字及 12 点组尾留白，移除额外组间距及空组提示。除最近记录外，整个标题行与右侧箭头均可进入对应分类；箭头按原版几何绘制，24 点点击图形区域使用原版悬停／按下颜色。首页测试覆盖两种主题下六个标题的渲染尺寸。

普通表情详情显示当前分类标题，最近记录标题为 `Recent`，颜文字标题为固定原版目录的 `All`，与符号页共用 32 点标题高度、12 点半粗字及 12 点组尾留白。颜文字移除原版没有的分类下拉框，搜索无匹配时不显示其分组标题。内容仍使用原网格／流式布局及索引，标题不参与键盘条目计数。分组测试覆盖两种主题下三个标题的空／单项／跨行尺寸，并继续检查符号分组顺序、导航和选中像素。

搜索框占位文字对齐固定 Windows 提交的 `UpdateSearchPlaceholder`：首页为 `Search emoji, kaomoji, and symbols`，表情／最近为 `Search emojis`，颜文字为 `Search kaomoji`，符号为 `Search symbols`，贴纸／GIF 为 `Search`，剪贴板为“搜索剪贴板”。普通页输入／占位字号为 14／12 点，剪贴板均为 16 点；搜索修改立即清除复制提示。搜索测试覆盖页面映射、字号配置以及两种主题、两种焦点状态的边框像素。

### 滚动与选择

首页和详情的滚动容器在搜索、页面／分类切换时重建视口，回到顶部；重复点击当前主标签或二级标签也触发重置。只重建滚动内容，不重建搜索框和键盘入口。普通最近记录／剪贴板刷新不改变滚动身份，内容尺寸变化仍可能由系统钳制位置。原生合成测试实际滚动 SwiftUI 内的 NSScrollView，验证查询及重复导航重置到顶部，并验证普通刷新保留滚动位置。

首页重置后的有效选择为首个可见条目，选中样式和键盘导航共用此选择。空分组自动跳过，最近记录优先，异步目录到达后无需先按方向键即可激活首项；第一次右键／下键从首项按原步长移动。显式选择仍按条目标识保持，条目被移除后激活不回退复制其他条目。合成测试覆盖空目录、分组顺序、最近记录、目录到达、初始激活及步长、显式选择和过期选择。

### 面板本地测试

原生宿主游标集成测试 `emoji-host-cursor-test` 直接链接 `apple-client` 与当前构建的 Rust host 静态库，经真实 `MSIMEClientSession.emojiCatalogRequest` 读取临时合成 SQLite 数据库。覆盖表情／颜文字／符号的空扫描批次、重复项、短尾批次、显式 EOF、旧接口去重及响应格式、相对路径拒绝。此测试验证 Objective-C → Rust → SQLite 链路，不使用模拟宿主，不读取真实输入。运行前需从当前提交重新 `cargo build -p msime-host-api`，并将产物传给 `MSIME_HOST_LIBRARY`。

```sh
cmake --build target/macos-isolated --target emoji-host-cursor-test --parallel
ctest --test-dir target/macos-isolated -R '^emoji-host-cursor$' --output-on-failure
```

`emoji-swift-host-test-build` 进一步使用实际 Swift `MacEmojiCatalog`，通过动态类／selector 查找调用真实 Objective-C → Rust → SQLite 链路。临时合成数据库包含首批 255 个无效行、260 个相同有效条目及一个尾项，验证完整读取跨批次推进、18 项预览、搜索无匹配、分类元数据与符号父分类过滤。静态宿主显式 force-load，未定义模拟 `MSIMEClientSession`。这覆盖 Swift 读取器与宿主协议的兼容性。

```sh
cmake --build target/macos-isolated --target emoji-swift-host-test-build --parallel
ctest --test-dir target/macos-isolated -R '^emoji-swift-host$' --output-on-failure
```

表情首页、普通网格与颜文字流式布局同样提供独立的本地测试（搜索框使用 `emoji-search-test-build`，滚动使用 `emoji-scroll-test-build`，同属 `emoji-local`）：

```sh
cmake --build target/macos-isolated --target emoji-home-test-build emoji-flow-test-build emoji-grid-test-build emoji-toast-test-build emoji-main-tabs-test-build emoji-category-tabs-test-build emoji-symbol-sections-test-build emoji-catalog-cursor-test-build --parallel
ctest --test-dir target/macos-isolated -L emoji-local --output-on-failure
```

### 布局度量

首页预览和完整颜文字目录共用文本测量、按宽度换行和长文本缩字逻辑，键盘上下移动使用同一布局的行号及横向中心。间距、留白、最小宽度、字号边界和换行容差以 Windows 固定提交 `04a8df56f86312474a069f4335a1b58da7afaa9e` 为准，应用其 2/3 面板比例；字体测量使用 macOS 系统字体，不声称与 Windows 字体逐像素一致。测试覆盖合成文本的换行、缩字、窄宽度边界、不同宽度下首页导航与流式导航一致性，以及 SwiftUI 原生渲染的尺寸与选中背景像素，不读取真实输入或剪贴板。

普通表情、符号及最近记录使用与该固定 Windows 版本一致的六列网格：原始 84 单位步长及 8% 单元留白应用 2/3 比例，原生点数为 56 步长、51.52 单元尺寸。文本按 UTF-16 长度大于 4 判定为长文本，并按原版字号上下界缩字。选择圆角及边框也应用相同比例。首页和详情页共用网格；剪贴板仍为独立单列列表。网格测试覆盖两种主题的选择填色、边框、间隙和末行留白像素，以及 1/6/7/18/28 项排布与最多 255 项导航边界。原生窗口最小内容宽度包含完整六列和滚动条留白，不强行压缩单元格；字体测量仍为 macOS 平台适配，非 Windows 字体逐像素复现。

## 按键处理与翻页快捷键

Home/End 在候选可见时通过共享运行时移到当前页首/末候选，不改变编辑串、光标或提交文本；最后不足一页时止于实际末项。候选隐藏后沿用编辑光标 Home/End。测试覆盖可见/隐藏状态、完整页及末页、过期候选和全局索引提交。翻页快捷键提供减号/等号（默认）、方括号、Page Up/Page Down 三种设置。字符键仅在候选可见且无 Shift/Command/Control/Option 时按所选键组翻页；未匹配或有 Shift 时将实际字符交给 Engine。Page Up/Page Down 在三种设置下均有效，与 Apple 路由一致。设置保存在宿主原生偏好域，测试覆盖默认、非法值归一化、控件保存、48 种字符组合以及修饰键优先级。

迁移对照固定为 MSIME-Apple 远端默认分支 develop 的提交 `b637828e15eafcb5e459edd270a962dd14517285`。Command、Control、Option 快捷键沿用其 `MetasequoiaInputController.mm` 行为：先通过 Engine finish 提交当前高亮对应组合，再放行快捷键。原生控制器测试覆盖三个修饰键的分派、提交、清空预编辑和返回未处理，使用替身会话驱动。

真实 IMKServer / IMKInputController 入口，静态链接共享 Rust/C++ 运行时。平台代码负责系统按键、文本插入、预编辑和不激活候选面板。分页、高亮、会话代次、候选选择与组词仍由共享层负责。

按键处理覆盖 ASCII 输入、退格、移动编辑光标、空格选择、回车原文、Esc 取消、候选上下移动和翻页、鼠标选词，以及由共享运行时处理的当前页数字选词与标点结束组词。候选面板显示对应数字；Engine 优先接收字符，保留 Unicode 等输入模式与拼音分隔符。未被 Engine 接收的 ASCII 标点先按当前高亮完成组词，再复用 Engine 中文标点转换；关闭中文标点时保留 ASCII。设置后台重读、输入法菜单和 Tauri 安装入口均已接入。原始 ASCII 编辑串用于内联预编辑，光标单位与 Engine 一致；日语等美化预编辑另行处理。

## 词库准备与 Tauri 设置应用

先下载锁定词库，然后在隔离的开发状态目录中准备工作词库；该步骤要求相关会话已停止，不用于对现有输入法在线升级：

```sh
CFLAGS="-mmacosx-version-min=13.0" CXXFLAGS="-mmacosx-version-min=13.0" CMAKE_OSX_DEPLOYMENT_TARGET=13.0 CMAKE_PREFIX_PATH="$(brew --prefix)" cargo run -p msime-host-api --example prepare_host -- <已校验资源目录> target/macos-state
CFLAGS="-mmacosx-version-min=13.0" CXXFLAGS="-mmacosx-version-min=13.0" CMAKE_OSX_DEPLOYMENT_TARGET=13.0 CMAKE_PREFIX_PATH="$(brew --prefix)" cargo build -p msime-host-api --locked
cmake -S platforms/macos -B target/macos -DMSIME_OPTIONS_FILE="$PWD/target/macos-state/runtime-options.json"
cmake --build target/macos --parallel
ctest --test-dir target/macos --output-on-failure
```

打包 Tauri macOS 设置应用前，还要把同一份已校验资源暂存到应用 bundle：

```sh
platforms/macos/stage-resources.sh <已校验资源目录>
```

打包时如果 `cargo` 报某个过程宏 crate「can't find crate for `xxx_macros`」，看它前面一行的 dlopen 错误：本机遇到过 `mis-aligned LINKEDIT string pool`，即过程宏的 dylib 被产出成 dyld 拒绝加载的形状。那不是依赖缺失，也不是版本不匹配——同一个目录再构建仍然失败，而换一个干净的 `CARGO_TARGET_DIR` 就通过。macOS 的 CMake 构建与 cargo 共用 `target/` 时更容易碰上；打包设置应用用独立的 `CARGO_TARGET_DIR` 最省事。

`tauri.macos.conf.json` 会把 `target/macos/EngineResources` 嵌入为 `EngineResources`；不要直接把未校验的词库目录配置到 bundle。资源目录缺少 `others.db` 或 `dict_japanese.dat` 时，宿主会安全关闭对应的 Emoji、颜文字或临时日语触发键，而不会吞掉普通大写字母。

Tauri macOS 设置宿主首次启动时，如果应用数据目录中没有 `runtime-options.json`，会从 bundle 内的 `EngineResources` 调用共享 Host API 准备默认用户词库、缓存和配置，并以同目录原子发布配置；已有配置不会被覆盖。`MSIME_CLIENT_HOST_OPTIONS`（兼容 `MSIME_IBUS_OPTIONS`）显式指定配置时不会触发自动准备，`MSIME_CLIENT_STATE_DIR` 仍可指定偏好与用户状态根目录。资源校验或准备失败会以通用错误终止本次设置宿主启动，不泄露路径、输入或 Host API 诊断内容。

产物为 `target/macos/水杉输入法.app`。可选开发配置包含本机绝对路径，不得对外分发。未嵌入开发配置时从客户端的应用数据目录读取 `runtime-options.json`；配置缺失时不拦截输入。Tauri macOS bundle 会把同一 IMK bundle 随应用资源打包；设置页的“安装 / 更新”先在 staging 目录完成校验和原子替换到 `~/Library/Input Methods/水杉输入法.app`，再直接启动 bundle 的 `--register-input-source`，失败不会删除旧安装，也不会替用户切换当前输入源。静态库与宿主均以 macOS 13 为最低构建目标，必须使用同一架构。

`prepare_host` 生成的配置包含 `preferences_directory`。宿主激活时立即后台读取此目录，之后每秒检查一次，前一次未完成时不重叠读取；失活后停止定时器。文件锁和读取不占用会话主线程，应用仍在主线程且有组合时延迟；读取错误保留原配置。旧配置没有此字段时不自动重读，需要重新准备开发配置（先停止该开发宿主）。

从仓库根目录让设置页写入同一份隔离配置：`MSIME_CLIENT_STATE_DIR="$PWD/target/macos-state" pnpm --filter @msime/desktop tauri dev`。保存后活跃宿主通常在下一次轮询收到快照，当前组词结束后生效；无需 Tauri 常驻。

## 词库维护

词库增改删、导入和清除学习记录需要独占维护锁，而每个打开的 IMK 会话都持有共享锁（IMK 为每个输入客户端各建一个控制器，各持一个会话）。设置窗口拿不到锁时，与 Linux 宿主同一套做法：在用户数据目录写入带过期时间的 `.msime-dictionary-quiesce` 租约（最长 30 秒，格式与读取见 `platforms/common/DictionaryQuiesceLease.h`），随即发出 `MSIMEDictionaryMaintenanceWillBeginNotification` 分布式通知（`DeliverImmediately`，后台输入法进程也立即收到），在约 2.5 秒内重试，仍取不到锁才返回 busy。超过单次请求上限的导入分批发送时，租约与通知只在第一次遇到 busy 时各发一次，租约在各批之间保持并在每批前续期，整次操作结束后立即删除。

输入法收到通知后，只有租约确实存在时才让出：取消语音与在途的云候选和翻译，把当前组合上屏（上屏失败则清掉预编辑），关闭所有控制器的会话。没有租约的通知什么也不丢。租约存在期间按键直接交给应用、不打开新会话；租约删除后的下一次按键重新打开会话，并恢复让出前的专用英文模式。通知丢失时，每秒一次的偏好定时器发现租约后同样让出；设置进程中途退出时，租约过期后输入最多停 30 秒。

输入法内的原生词库窗口在同一进程里走同一条路：自己写租约、在主线程同步发出本地通知、在 2.5 秒内重试后删除租约。`dictionary-quiesce-controller` 测试用两个持有真实会话的控制器覆盖让出、租约期间不重开、租约删除后恢复专用英文，以及过期租约不再挡住输入。

## 数据目录迁移

发行设置页的“关于 → 数据目录”可以把词库、学习记录、偏好、统计、剪贴板历史、皮肤和缓存移动到另一块磁盘。设置 bundle 与 IMK bundle 各自在固定 Application Support 目录保留一个小型 `runtime-options.json` 定位器，二者指向同一个可移动状态根；bundle 内只读资源不搬。迁移会先停掉 IMK 进程，只接受真实的空目录，在目标卷完成复制和按最终路径重新准备后原子切换两个定位器，最后才清理旧目录。失败保持旧目录有效；无 `.metasequoiaime-data` 所有权标记的非默认源目录不会自动删除。成功后设置窗口关闭，重新打开即可从新目录继续。

## 文本适配与维护快捷键

文本适配测试验证提交、ASCII 光标和清除预编辑。

维护快捷键只在水杉输入法当前 IMK 上下文中处理，不安装全局键盘监听。`Control+Shift+Option+1–8` 删除当前候选页对应槽位，`Control+Shift+Option+C` 通过共享 Host API 清除当前会话 Engine 缓存，`Control+Shift+Option+R` 用独立 helper 实例重新注册当前输入源并退出旧进程，`Control+Shift+Option+T` 退出当前输入法进程。物理键位不受当前键盘布局字符影响，Command 明确排除，Caps Lock 可共存，重复事件只消费一次。macOS 设置页相应使用 Option 与输入上下文文案；桌面重新注册命令按输入法 bundle identifier 定位目标，而不是重新打开设置应用。

## 快照激活测试

完整词库快照激活集成测试需显式运行，因为它要一份已校验的词库目录，不自动下载资源：

```sh
cmake --build target/macos --target snapshot-activation-test
target/macos/snapshot-activation-test /absolute/path/to/verified-desktop-resources
```

资源必须匹配仓库根目录的 `resources/desktop-dictionary.lock.json`，测试通过生产校验器检查文件。它在新建临时目录中准备用户数据和暂存快照，验证真实激活、英文模式开启/关闭的保留、导入词条候选与提交；成功后删除测试状态，不修改传入的资源目录或实际用户词库。
