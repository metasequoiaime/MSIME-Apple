# Android 输入宿主预览

`NativeClient` 提供 Java/Kotlin 到共享运行时的 JNI 传输。UTF-8 字节数组保留非 BMP 字符，避免 JNI modified UTF-8 损坏候选或资源路径。JNI 负责释放 C API 响应；上层解析 ok/value，负责会话线程和生命周期。

`MSIMEInputService` 提供实际 InputMethodService 源码、系统 manifest 和输入法元数据；最小 Android 28，编译目标 35。软键盘、硬件 ASCII 键、候选点击和翻页调用同一 JNI；Engine 提交与剩余编辑串通过 `EditorBridge` 按顺序映射到 InputConnection。宿主不实现输入算法或分页规则。密码、非文本和无建议字段直接输入，不创建 Engine；IME_FLAG_NO_PERSONALIZED_LEARNING 关闭当前会话学习。宿主不记录输入；网络权限只供用户明确启用并确认发送的 AI 请求使用。

软键盘的主按键区按 Apple 键盘的基础层次拆成字母层和符号层；字母层支持可见的 Shift 状态，符号层保留标点、括号和数字，两个层次均通过无障碍描述暴露当前按键。层次排列由无 Android 依赖的 `KeyboardLayout` 提供，便于在主机测试中验证布局不被宿主生命周期改变。

编辑器上下文按固定 Apple 来源的边界适配 Android `inputType`：URI、邮箱、密码和明确禁用建议的字段临时进入英文输入，允许 Engine 的字段使用 dedicated English 模式，敏感字段继续绕过 Engine；离开后恢复进入前的中英状态，同一字段内用户通过“中/英”手动切换后，输入重启回调不会再次覆盖。英文模式始终展示完整 26 键，即使底层方案为九键或手写；数字和标点会在完成英文组合后由宿主直接提交，空格会完成候选并保留实际空格。`TYPE_TEXT_FLAG_CAP_CHARACTERS`、`CAP_WORDS` 和 `CAP_SENTENCES` 分别映射为全大写、单词首字母和句首自动大写，URI/邮箱强制关闭；规则只读取最多 128 个光标前字符并在内存中即时判断，不记录或持久化编辑器内容。缺失上下文安全回退为关闭自动 Shift。

英文大小写状态继续对齐 Apple：中文态点按 Shift 会先完成组合并进入英文的单次大写；单次 Shift 输入一个字母后自动回到小写，350 ms 内连续点按两次进入 Caps Lock，再次点按关闭。编辑器自动 Shift 与手动单次 Shift 使用同一三态状态机，但不会覆盖 Caps Lock；按钮以 `⇧` / `⇪`、选中态和“关闭 / 下一字母 / 自动开启 / 开启”的无障碍状态区分。切换符号层保留当前大小写，硬件 Shift 和本地模式触发使用每次事件自己的修饰状态，不污染软键盘状态；英文模式禁用中文本地输入工具。

顶部“简 / 繁”快捷键消费共享 `traditional_chinese_output` 偏好，并按固定 Apple 来源只在 Android 展示与插入边界使用系统 ICU `Simplified-Traditional` 转换：Engine 候选原文、候选身份、组合文本和输入算法保持不变。候选条、展开候选面板、Engine 最终提交和手写候选使用同一规则；日语方案、临时日语和 dedicated English 保留原文。快捷键通过共享 revision CAS 乐观刷新当前候选，冲突或写入失败恢复最近接受值；顶部语音入口开启时让出同一快捷位，高情商回复优先于语音。Android `Transliterator` 从 API 29 提供，API 28 保留原文并禁用快捷键，不伪装已转换。

回车键按当前 Android `EditorInfo` 显示并执行前往、搜索、发送、下一项、完成或上一项动作；无明确动作、未知动作或编辑器设置 `IME_FLAG_NO_ENTER_ACTION` 时显示“换行”并提交换行符。执行前仍先通过共享 Engine 完成当前组合，标题和 dispatch 条件由同一个纯 Java 契约提供，避免展示与行为不一致。

工具栏“空格”支持轻点选词或插入空格，也可左右滑动向编辑器发送有界方向键事件以移动光标。滑动开始时先完成 Engine 组合，距离累积器绑定当前 `InputConnection` 身份；输入目标变化、手势取消、非有限坐标或异常跳变都会终止移动，不读取或持久化编辑器文本。

键盘工具栏的“设置”面板在保留已迁移的间距和 Android 语音入口基础上，以远端默认分支固定来源 `MSIME-Apple@3d300cdc62fe0d09565b30bd3e4165571fb91562` 增加键盘高度调节。高度在平台默认键区基础上支持 -12–+48 dp，并以整数写入共享 `touch_keyboard_height_adjustment`；26 键三行均分增量，九键整体增减，手写把增量用于书写与工具区。间距仍分别支持 3.0–6.0 dp 和 4.0–10.0 dp，并以 0.1 dp 精度写入共享 `touch_key_spacing_tenths` / `touch_row_spacing_tenths`。拖动时直接更新已有 View 的高度或 margin，不重建按键树、Engine 或丢失当前组词与手写笔迹；松手、无障碍调节及切换语音入口后通过共享 revision CAS 保存，冲突或写入失败会恢复最近一次已接受快照。

语音结果按 Android 平台能力适配：独立 Activity 调起用户设备上的系统语音识别服务，录音由该服务持有，MSIME 只接收有界文本。主应用进程与独立 `:ime` 进程通过应用私有目录中的非阻塞文件锁交接最新一条结果；结果最多 10,000 个 Unicode 码点、10 分钟有效，并在插入前一次性 claim，避免两个键盘实例重复插入。键盘“更多”工具页提供与 Apple 同级的语音结果入口，结果面板内提供 Android 平台的系统语音识别入口；共享 `touch_voice_shortcut` 开启后，候选栏显示直达语音结果按钮。存在 Engine 组合或本地模式时拒绝打开结果，确认插入前还会比对 InputConnection 身份、选择位置 generation 及光标前后/选中文本快照；真实上下文仅短暂保存在内存，不写日志或交接文件。系统识别器可用性、Activity 返回后的键盘恢复和真实编辑器插入仍需设备产品验收。

AI 润色对齐固定 Apple 来源的确认式流程：仅在 Engine 空闲且编辑器存在非空选区时显示入口，输入和输出各限制 10,000 个 Unicode 码点。全屏面板明确展示 HTTPS 目标 origin、模型和待发送文字，用户再次点按后才发起 Chat Completions 请求；单线程请求队列容量为 1，关闭面板或点击取消会中断任务并断开连接，响应限制为 1 MiB。请求前、响应后及最终替换前均校验 InputConnection、选区 generation、光标前后文本和完整 AI 配置；过期结果不会展示，结果也绝不自动插入。操作按钮固定在面板底部，长文本不遮挡取消或替换。共享设置按规范化的 endpoint origin（HTTPS 主机和端口）保存 Token，同主机不同路径可复用，主机或端口变化时不会沿用；日志、测试和诊断不包含选区、结果、Token 或原始响应。当前仅完成源码、JVM 契约和构建检查，真实服务、外部编辑器选区与设备生命周期仍需 Android 原生产品验收。

打字统计按固定 Apple 来源只记录成功上屏的 Unicode 扩展字符簇，空格、换行和未上屏按键不计，组合表情计为一个字符。提交内容只在 Rust 内存中分类，持久化文件只含日期、字符类别、提交来源和数量，不保存输入原文。分类覆盖汉字、拉丁字母、其他文字、数字、标点、表情、其他符号与旧版未分类；来源覆盖全拼 26/9 键、四种双拼、五笔、日语、手写、英文、本地输入、AI 润色、高情商回复和语音。累计数据持续保留，每日计数与分类只保留最近 366 个有记录日期；启停与清空使用同一跨进程文件锁，清空不会重新启用统计。写入通过容量 32 的单线程队列离开输入主线程，队列满或存储失败不保留待写文字，且每个输入会话只显示一次脱敏错误提示。

Android Tauri 设置仅在 Android WebView 注入统计能力，桌面设置不显示入口。页面提供 7 天、30 天和累计范围、最近 7/30 日趋势与单日下钻、字符类型/语言模式/输入方案占比、刷新、即时启停和确认清空；统计页独立于 Preferences 草稿和“保存设置”。主应用与独立 `:ime` 进程共享 `files/bootstrap/state/typing-statistics.json`，由锁文件串行读写；页面会区分从未写入和已清空状态，并明确说明本机只保存聚合计数。完整 arm64 Tauri 合包已在专用 API 35 arm64 AVD 验证实际上屏聚合、文件不含合成输入文本、页面跨进程读取、禁用后不增长、取消/确认清空、清空保留禁用状态和重新启用后累计；真机触控、系统回收和长期统计仍需产品验收。

“高情商回复”是独立 Android 宿主方案，底层固定映射到 Engine 的全拼 26 键，不向共享输入算法增加 AI 状态。选中后显示覆盖整个 IME 区域的专用键盘：顶部提供“帮你回/帮润色”、输入方案、社区模板、共享触屏键盘皮肤和收起入口；正文通过用户明确点按读取当前文本剪贴板，限制 10,000 个 Unicode 码点，并提供九种内置风格、删除、清空、取消、生成和同风格“换一句”。回复请求复用 AI 润色的 HTTPS transport、容量 1 队列、取消和 1 MiB 响应边界，但每次使用 Apple 对应风格 prompt；候选去重、最新在前且最多三条，服务结果绝不自动上屏，只有点按候选且 InputConnection、光标上下文、Engine 空闲状态、当前方案和完整 AI 配置仍匹配时才插入。插入后面板让出编辑器，候选栏“回复”入口可重新打开。切换模式、修改源文字、切换方案、编辑器上下文或 AI 配置变化都会取消请求并废弃迟到结果。

社区回复模板只从应用私有 files 目录的 `CommunityLibrary.json` 读取，该文件用于主应用向独立 `:ime` 进程显式共享已收藏资源，不包含凭据或源消息。读取拒绝符号链接、非 UTF-8/非法 JSON、超过 4,000,000 字节、超过 50 项或无效字段，仅展示 `kind == reply` 且含 prompt 的条目；发起请求时重新读取，已移除模板不会复用。高情商回复与其他触屏输入方案统一由共享 `touch_keyboard_schemes` 管理可见性和选择；只有旧快照尚无该字段时，原 IME 私有开关与选择才作为迁移兼容来源。真实 provider、剪贴板系统限制、不同聊天编辑器插入、皮肤菜单和进程重建仍需 Android 原生产品验收。

候选区独立显示当前组合文本、当前页和候选按钮；Engine 候选超过当前页容量时显示展开入口。用户打开面板后，宿主通过按需 host API 一次复制当前 generation 的完整 Engine 候选，在顶部显示 preedit、候选总数和收起入口，候选 chip 按实际测量宽度自动换行且不绘制序号；全局序号只保留在无障碍描述中。展开面板没有分页按钮，点按页外候选通过独立的全代次选择 API 交回 Engine。普通候选栏继续使用分页 `View` 和当前页选择边界，每次按键不会携带完整列表；两条选择路径都校验 session、generation 和全局索引，宿主不复制候选算法或组合状态。

候选英文释义按固定 Apple 来源 `MSIME-Apple@d117009573a1a619cfb1702645f38c3b4c378a78` 渐进迁移，并通过共享 `candidate_english_gloss` 偏好选择性开启，默认关闭。开启后，Android 只在 IME 主线程复制当前 generation 的完整候选；无 session 的有界 worker 请求由 C++ Engine bridge 只读访问随包 `english.db`，Java 不实现输入算法也不读取 SQLite。完成结果返回主线程后必须同时匹配 session、generation 和生命周期 epoch，才会调用共享 `apply_translations`；停止输入、替换会话、偏好变化与服务销毁都会使旧结果失效。Engine 的五笔等候选提示优先占用次要文本位置，离线释义仅在没有 Engine 提示时显示；候选条与展开面板以较小的皮肤兼容文字和不同无障碍说明展示，候选身份、点击选择和上屏原文不变。查询失败静默保留普通候选，不记录候选文字；关闭偏好会立即隐藏已返回释义，缺失资源不会创建数据库或用户数据。

触屏键盘皮肤以固定 Apple 来源 `MSIME-Apple@11c950a63ec57656cd78b3f75aa621c293bfe453` 为基线，按相同顺序提供水杉绿、海盐蓝、浅蔷薇、素白瓷、纸上时光、奶油桃桃、霓虹夜航和工程蓝图。共享 `touch_keyboard_skin` 与桌面候选窗的 `candidate_skin` 完全独立；React 屏幕键盘页、普通输入方案和高情商回复键盘消费同一个选择。Android 适配保留 Apple 的明暗调色、圆角、边框、阴影、等宽字体以及网点、网格和波纹背景，`screen_keyboard_theme` 优先于全局 `theme`，两者都跟随系统时读取 Android 夜间模式。键盘内选择通过共享 revision CAS 保存，失败恢复最近一次已接受皮肤；设置热更新只重新应用视觉样式，不重建 Engine 会话。未知 ID 安全回退到水杉绿，不把用户设置值当作颜色或资源名直接使用。

命名自定义皮肤图库沿用同一固定 Apple 来源，最多保存 12 套设计，名称去除首尾空白后限制为 32 个扩展字素。图库独立保存到共享状态目录的 `CustomSkins/library.json`，文件上限 9,000,000 字节；照片仍受单张 512,000 字节边界约束。Tauri command 每次在独立文件锁内读取最新文件，再原子执行新建、重命名、用当前设计更新或删除，避免多设置窗口以旧整表覆盖。图库操作不会增加 preferences revision，也不会进入输入法每次读取的热路径；新建设计会把当前页面草稿选择为 `custom`，应用、编辑和选择仍需通过页面底部“保存设置”写入普通共享偏好。损坏或超限文件不会被默认值覆盖。

“我的皮肤”继续使用同一固定 Apple 来源的 `CustomKeyboardSkin`、`SkinKeySurfaceView`、背景绘制和 `CustomSkinEditorView`。共享 `custom_touch_keyboard_skin` 保留 Apple 的 camelCase 字段和默认值，颜色限制为 24 位 RGB，圆角、边框、阴影、键帽透明度、纹理强度、照片压暗与位置均按 Apple 范围验证；照片只接受有界 base64 图像，解码后最多 512,000 字节。React 编辑器提供九种背景预设、14 套固定设计模板、渐变方向、照片缩放缩略图、三种纹理、文字对比度提示与优化、四种键帽造型、四种材质、撤销/重做和“使用皮肤”；当前设计随普通设置保存。Android 原生键盘不是只显示预览，而是实际绘制照片铺满与压暗、渐变、纹理、卵石/票券/胶囊/圆角轮廓和哑光/立体/玻璃/纸张键帽，并在同一 `custom` ID 的设计变化后原地重绘。Apple 的最多 12 套命名图库已使用上一段所述独立有界文件，避免把多张照片带入每次键盘读取的偏好；社区发布下载和 AI 皮肤抽卡尚未迁移，是后续独立切片，不得把当前设计编辑器与命名图库视为完整皮肤生态迁移。

“更多”入口现在使用与 Apple 同层级的全键盘工具页：顶部返回，剪贴板历史、AI 润色和语音结果为单列 48 dp 卡片，按键反馈为两列，轻/中/强振动为三列，本地输入为两列并可纵向滚动。选中、启用、禁用和不可用状态通过按钮状态与无障碍描述同步暴露，不再依赖锚定底栏的系统弹出菜单。按键、候选、翻页和面板操作共用反馈路径；设置保存在输入法私有的 `keyboard-feedback` 偏好中，默认按键音开启、振动关闭；振动使用 Android `VibrationEffect`，没有振动器时回退到系统键盘触觉反馈。

独立表情浏览器以远端默认分支固定来源 `MSIME-Apple@41c5db42184f505bb889f6efb88cf17d7e58901e` 为行为基线，在空闲候选栏和“更多”工具页提供入口。打开前先由 Engine 完成已有组合，面板提供返回、删除、固定 Unicode 顺序的笑脸／人物／动物／食物／旅行／活动／物品／符号／旗帜分类，以及每行八个的可滚动网格。Android 不复制 SQLite 读取器或内置 1,935 条表情，而是在后台通过共享 host API 以 64 行游标页读取已验证 `others.db`；异常响应、超限字段、停滞或倒退游标会被拒绝。选择通过本地输入来源写入普通 InputConnection，成功后将去重、最近优先且最多 24 项的历史保存到输入法私有偏好；删除也走正常宿主编辑路径。API 35 arm64 专用 AVD 已验证组合完成顺序、分类切换、跨页加载、插入、删除、返回、最近使用和 IME 重绑后的持久化；真机触控、旋转和系统回收后的产品验收仍待完成。

“更多”工具页的“本地输入”分组接入共享 `local_modes` 偏好和 Engine 的 Shift 触发契约，按 Apple 顺序提供 Unicode、日期时间、超级简拼、快捷短语、英文补全、表情、颜文字和临时日语入口。禁用项或不支持本地工具的五笔/日语方案会置灰；宿主只发送触发字符，不实现本地模式算法。

键盘工具栏与 Android 设置按 Apple 固定顺序共享全拼 26 键、全拼 9 键、小鹤/自然码/微软/首道双拼、86 五笔、日语 9 键、日语 26 键、手写和高情商回复。`touch_keyboard_schemes.enabled` 控制快捷切换中可见的卡片并至少保留一种，`selected` 保存当前方案；隐藏当前方案时按固定顺序回退到第一种可见方案，设置与输入法进程重启后继续生效。键盘内切换先由 Engine 完成当前组合，再在后台通过共享 PreferencesStore 的 revision CAS 同步 `scheme`、`last_chinese_scheme`、`shuangpin_profile`、平台无关的 `touch_keyboard_layout` 及嵌套方案选择，保存成功后才更新当前会话；冲突或存储失败保留原方案。旧偏好默认全部可见和 26 键，并在第一次键盘内切换时迁移；`View.touch_keyboard_layout` 只报告已应用值，外部设置延迟时不会提前换布局。

全拼 9 键使用与 Apple 相同的分词/ABC–WXYZ 九宫格、常用中文标点、删除、重输和数字 0 分区，并显示 Engine 返回的拼音消歧条。数字和拼音选择都进入共享 Engine，拼音选择携带当前 generation，过期选择不会作用于新输入；数字语义严格跟随 Engine 的 `View.nine_key`。九键英文候选按固定来源 `MSIME-Apple@1a0d7194bba6ae1ee4555a7d2866bfb06a9fca6b` 和 `MSIME-Engine@15ff08fc50ff9b469dae0f4bdabeae76c2a66b91` 接入，继续由共享 `mixed_input.english` 与 `minimum_prefix` 控制，Android 只发送数字、展示并选择 Engine 候选。合成加权词典回归验证完整编码 `65` 的 `ok` 排在更高频前缀词 `old` 前；当前锁定的 `dict-v1.0.0` 尚未包含 Engine 构建脚本新增的英文权重，因此设备验收只要求 `ok` 存在于完整候选面板并可原样上屏，不把其首屏位置作为已证明的生产排序。

日语 9 键复刻 Apple 的 10 组五向假名：轻点输入中间假名，向左、上、右、下滑动选择其余假名，长按显示该键全部选项；“小゛゜”菜单提供小假名、浊音和半浊音，括号、长音和波浪号作为文字直接提交。Android 只把对应罗马字逐字符发送给日语 Engine，不在宿主实现假名组合或转换。

手写迁移提供 Android 原生画布和平台识别器注入边界：画布限制 64 笔、每笔 512 个采样点，支持单笔撤销、清空、坐标夹取和尺寸变化失效；识别请求复制不可变笔画快照，并以 session/revision/generation 拒绝过期结果，候选去重后最多 12 项。Tauri Android 适配器使用 ML Kit Digital Ink Recognition 19.0.0 和 `zh-Hani-CN` 模型，执行模型检查/下载、书写区域与时间戳笔画转换；轻量原生预览不依赖 ML Kit，缺少适配器时显示明确状态。与固定 Apple 来源 `MSIME-Apple@13cb320eb4ef662bbce0be3c73a5f34d68e86d80` 的平台取舍一致，Android 原生构建明确排除未调用的 Engine zinnia 识别器及其模型路径，桌面宿主继续保留共享 Engine 离线手写后备。手写方案、键盘内候选确认、无墨迹删除及退出清理已接入；有墨迹且候选已就绪时，软/硬件空格与回车确认第一候选，硬件退格和底部退格优先撤销最后一笔。专用 API 35 AVD 已验证模型下载或既有模型就绪、真实触摸笔迹识别、第一候选确认、符号层往返和方案恢复，真机触控手感与产品验收仍待完成。

中文候选在支持个人词典管理的方案中提供与固定 Apple 来源一致的长按菜单顺序：优先显示、固定到首位、取消固定和删除词条；删除操作要求 Android 确认对话框。固定位置通过共享 host API 限制为 1–5，本界面固定到首位时只传入位置 1。候选身份仍由 Engine 返回的 session/generation/index 传入 JNI，generation 或候选身份过期后不会修改当前会话；五笔、日语和本地输入模式不展示管理菜单。

候选 UI 现在消费共享的 `candidate_layout`（兼容旧的 `candidate_orientation`）、`candidate_font_size` 和 `candidate_preedit_font_size`；偏好热更新成功后立即调整候选排列和字号，不重建 Engine 会话。字号只接受核心偏好允许的 12–32 范围，非法值回退到 16。

“更多”工具页提供键盘内剪贴板历史面板。与 Apple 一致，只有用户点按“保存当前剪贴板”时才读取 Android 文本剪贴板，不后台监听；最多保存 50 条，支持去重、固定、删除、确认清空和点按插入。历史放在输入法私有偏好中，应用禁用备份且不记录内容；共享 `clipboard_history` 关闭时立即清空并禁用入口。非文本、空白或超过 10,000 UTF-16 单元/40,000 UTF-8 字节的内容不会保存。

配置缺失、原生库不可用或输入连接错误会显示状态并退回直接输入。服务从应用私有 files 目录读取 `runtime-options.json`，路径必须指向已在设备上准备的词库与私有用户目录，不能复制 macOS 的配置路径。开发 APK 的启动页提供首次资源准备；源码、打包与签名检查通过不代表设备运行通过。

本地检查：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/check-host.sh`。需要 JDK 17+、Android API 35 和 build-tools 35.0.0。脚本编译全部服务 Java、执行不依赖 Android 运行时的文本/敏感字段策略测试，并校验 manifest/resource；中间资源包随临时目录清理，不作为 APK 交付。

桌面 JVM/JNI 冒烟仍只证明跨语言消费。后续需真机上的焦点/选区/编辑器动作和完整生命周期验收。当前键盘和首次准备页是原生预览布局；React 设置页的 Android 合包与验证见下文。

## Tauri + React 共享设置合包

推荐本地构建入口：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-client-apk.sh <已锁定词库目录> [arm64-v8a|x86_64]`。默认 arm64-v8a，产物仍为 target/android/msime-client-preview.apk；需要先完成根目录 pnpm install --frozen-lockfile，准备 JDK 21、Android API 36、build-tools 35、固定 NDK/vcpkg 与 Rust Android target。Gradle 8.14.3 使用官方分发摘要固定，AGP/Kotlin 版本由项目固定。参数 --ci 仅用于 Tauri CLI 的非交互模式，不运行 GitHub CI。

apps/desktop/src-tauri/src/lib.rs 是桌面与移动共用的 Tauri commands/入口，Android 调用同一个 client-core PreferencesStore，指向应用私有 files/bootstrap/state，与 bootstrap 和 IME 监控目录一致。packages/ui 的 React 页没有 Android 副本。生成的 Android 工程已纳入源码，Gradle 直接引用 platforms/android/java、共享图标与暂存的锁定资源；不把原生宿主代码复制到 gen。不要重复执行 tauri android init 覆盖本仓定制。gen 中的本机路径、生成 Kotlin 绑定、native symlink、构建输出和本机配置仍忽略。

应用首次启动、缺少运行配置时进入已有 SetupActivity，准备成功后点击“打开共享设置”；不会自动启用或选择输入法。系统输入法设置入口也可打开共享设置页。Tauri 使用主进程，InputMethodService 使用同 UID 的独立 :ime 进程，通过文件锁和 revision 协作，不依赖设置窗口存活。这样 Tauri 退出最后一个窗口不会结束输入服务；不是通过让隐藏设置窗口常驻来维持输入。

此合包是本地开发产物，使用原开发签名和 versionCode 1，便于覆盖安装同一预览包，不代表正式发行的版本策略；不得发布开发密钥。原 build-apk.sh 保留为不含管理 UI 的原生宿主测试包入口。合包 arm64 已构建并设备验证；x86_64 合包入口尚未验收，不用以前的原生 x86_64 构建冒充 Tauri 合包证据。分发前还需完整 Rust/Tauri/Gradle/Engine/词库许可审计。

在专用 AVD 上运行 `ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/tests/device/smoke.sh emulator-5580 --settings --statistics --handwriting`：保留原有输入与配置热更新测试，并在真实 Tauri WebView 中操作 React 表单，验证保存、共享 revision、内置与自定义键盘皮肤、重新读取与另一个进程中的实际标点上屏；测试不是直接调用保存 command 代替表单行为。设置套件先选择内置霓虹夜航，再打开真实编辑器应用“奶油桃桃”模板，通过 Tauri IPC 对独立命名图库执行新建、重命名、更新、应用和删除，并确认图库写入不会提前修改普通 preferences；随后检查 `custom` 选择及卵石、立体、圆角、纹理字段落盘，并在重绑的 `:ime` 进程中通过皮肤按钮无障碍状态确认实际消费“我的皮肤”。测试前后恢复图库和偏好文件。独立控制端还连续两次打开/关闭设置，验证 :ime PID 不变且仍能上屏。统计套件通过真实 InputConnection 与 React 页面验证聚合文件、启停、清空和跨进程读写，固定失败阶段不输出编辑器内容，并恢复测试前文件。手写套件需要网络以首次下载 ML Kit 模型，随后使用合成触摸轨迹验证离线识别与真实 InputConnection 提交；模型已存在时直接验证就绪路径。测试恢复原输入方案和偏好文件，不输出候选或编辑器内容；instrumentation 的强制停止与普通设置窗口关闭分开处理。

移动入口布局依据 [Tauri 移动应用入口约定](https://v2.tauri.app/start/migrate/from-tauri-1/#preparing-for-mobile)。本地观察到最后一个 Tauri 窗口关闭时主进程正常退出，故使用 :ime 隔离；不依赖在同进程中禁止退出后的未验证窗口重建行为。

## 共享设置热更新

新 bootstrap 配置包含绝对路径 `preferences_directory`。输入会话启动后，Android 后台读取该目录的共享 PreferencesStore，之后每秒重试；不在输入主线程等待文件锁，不重叠读取，切换编辑器或结束输入后丢弃旧读取结果并停止旧轮询。已有配置没有目录字段时保留原行为，不猜测其他应用的数据目录。

JNI `loadPreferences` 只读取共享层，快照回到会话主线程后调用同一个 `updatePreferences`；键盘侧写入通过 `savePreferences` 进入同一共享 CAS 边界。revision 校验、组词期间延迟应用和重建失败保护仍在 Rust 中。更新只刷新候选视图，不用空预编辑覆盖现有编辑器内容。相同视图和状态不反复重建键盘控件。密码等直接输入字段不启动配置轮询；禁止个性化学习的编辑器在创建和每次快照应用时均强制关闭学习，同时内存中保留未经隐私覆盖的已接受磁盘快照，避免键盘写入意外永久关闭全局学习设置。

读取或应用失败保留当前输入会话，显示非阻断提示，后续继续重试；不写入默认值覆盖坏文件。共享 React 设置页在上述 Tauri 合包中使用同一个存储；完整移动产品、真机与其他平台仍待验收。

## 原生库交叉构建

固定 NDK r28c (`28.2.13676358`)、Android API 28 与 vcpkg `ef7dbf94b9198bc58f45951adcf1f041fcbc5ea0`。vcpkg manifest 固定 Boost/fmt/spdlog/SQLite 来源；依赖和构建产物放在忽略的 target 下，不修改 Engine 子模块。需要先自行安装对应 SDK/NDK 和 Rust Android 目标；脚本不自动接受许可或启用 CI。

```sh
git clone --depth 1 --branch 2025.06.13 https://github.com/microsoft/vcpkg.git target/tooling/vcpkg
target/tooling/vcpkg/bootstrap-vcpkg.sh -disableMetrics
rustup target add aarch64-linux-android x86_64-linux-android
ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-native.sh arm64-v8a
ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-native.sh x86_64
```

可用 `MSIME_VCPKG_ROOT`、`MSIME_ANDROID_NDK` 指定绝对路径。脚本校验固定版本后安装锁定依赖，构建 release Rust/C++ 宿主和 JNI，SQLite 静态链接；产物为 `target/android/jniLibs/<abi>/{libmsime_host_api.so,libmsime_android.so,libc++_shared.so}`。验证脚本检查 ELF 架构、16 KB LOAD 对齐、动态依赖白名单与宿主/JNI 导出。NDK 和 vcpkg 声明复制到 `target/android/notices/<abi>`，正式分发还需汇总 Rust/Engine 与词库许可材料。

当前提供 arm64-v8a 与 x86_64 构建路径；没有 32 位 ABI、Windows 构建脚本或设备运行保证。原生库不能直接当作 APK，需使用下述脚本打包并进行运行验收。

## 开发 APK 与首次准备

本地构建：`ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/build-apk.sh <已锁定词库目录>`。需要前述 NDK/vcpkg/JDK/Rust 工具及 zip；脚本先通过共享 ResourceStore 校验资源，再构建双 ABI 库，用 SDK aapt2/d8/zipalign/apksigner 生成并验证 `target/android/msime-client-preview.apk`。APK 含六份锁定资源和原生许可声明；仅供本地开发测试，完整分发许可审计仍未完成，不发布到应用商店。签名前进行 16 KB zip 对齐，签名后再验证。

开发密钥在忽略的 `target/android/development.keystore`，不得用于正式发行；清理该文件会改变后续开发签名，不能直接覆盖安装由旧密钥签名的包。构建临时文件留在 target/android 便于排查，不触碰任何设备。

用户打开启动页并点击“准备词库”后，后台任务在私有目录解包资源，调用共享 Rust/C++ 校验与工作数据准备，成功后通过 AtomicFile 发布配置。已有配置一律不覆盖，失败可重试；不支持在线升级已运行的词库。解包和工作词库复制需要额外存储空间。启动页只提供手动进入系统设置/选择器的按钮，不自动启用或切换输入法。

本地已验证 APK 包结构、双 ABI、启动 Activity、IME 声明、签名与对齐；Android 15 arm64 专用模拟器已验证安装、首次准备、已有配置不覆盖，以及软键盘通过系统 InputConnection 上屏、退格和密码直接输入。x86_64 仍只有交叉构建证据，不代表真机或完整生命周期验收。工具契约参考 [d8](https://developer.android.com/tools/d8)、[zipalign](https://developer.android.com/tools/zipalign) 与 [apksigner](https://developer.android.com/tools/apksigner)。

## 专用模拟器验收（仅本地）

预先安装 `system-images;android-35;default;arm64-v8a`，在一个终端运行 `ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/tests/device/start-emulator.sh`。脚本在忽略的 target/android/avd-home 中创建 msime-client-test，固定 emulator-5580，不使用已有个人 AVD；目标端口属于其他 AVD 时拒绝运行。需要额外磁盘空间，测试结束后应停止该专用模拟器以释放内存；脚本不会下载系统镜像、自动接受许可或启动 CI。

完成上述 APK 构建、等待系统启动后，在另一终端运行 `ANDROID_SDK_ROOT=<SDK绝对路径> bash platforms/android/tests/device/smoke.sh emulator-5580`。该命令会安装预览包和独立合成编辑器、准备资源，并在专用 AVD 上启用和选择 MSIME；拒绝非模拟器或名称不符的设备，不对现有真机执行操作。测试不会清空应用数据，重复执行覆盖已有配置路径而非重新模拟首次安装。

独立 instrumentation 读取编辑器与输入法的交互窗口，等待窗口稳定后重新定位并注入触摸，断言“你好”提交、退格、“直接输入”状态和密码框字符长度；不记录编辑器原文。普通 uiautomator dump 只用于准备 Activity，不能用它缺少输入法节点推断键盘未显示。APK fixture 不随产品打包。

同一 smoke 脚本还执行同开发签名的 PreferencesDeviceSmoke，instrumentation 以预览应用为目标，直接在其私有测试目录原子发布合成设置，无需给产品增加导出的测试写接口。目标进程重启后重新绑定专用 AVD 的 IME；测试组词延迟、提交保留、页大小与标点生效、损坏文件保护以及恢复重试。结束时恢复原偏好文件（原本不存在则删除测试文件），不清空资源和用户数据。该测试必须经专用 AVD 检查的 smoke 脚本执行，不安装在个人设备。

KeyboardHeightDeviceSmoke 通过键盘内真实无障碍调节动作验证 -12、0 和 +48 dp 档位：正负调整必须改变实际字母键边界，调节和保存期间已有 Engine 组合不得丢失，保存值在 IME 进程重启后必须继续生效。`--settings` 还让 SettingsDeviceSmoke 在真实 React WebView 中修改并保存同一高度字段，再由独立输入法进程消费；两项测试结束时都恢复原偏好文件。

共享核心单元测试也可在该 AVD 实际执行（从仓库根运行，以下工具链为 macOS 主机）：

```sh
export ANDROID_SDK_ROOT=<SDK绝对路径>
android_toolchain="$ANDROID_SDK_ROOT/ndk/28.2.13676358/toolchains/llvm/prebuilt/darwin-x86_64/bin"
CC_aarch64_linux_android="$android_toolchain/aarch64-linux-android28-clang" \
AR_aarch64_linux_android="$android_toolchain/llvm-ar" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$android_toolchain/aarch64-linux-android28-clang" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_RUNNER="bash $PWD/platforms/android/tests/device/run-core-test.sh" \
cargo test -p msime-client-core --lib --target aarch64-linux-android --locked
```

8 项测试在 Android 上通过，包含独立 PreferencesStore 的并发冲突和资源失败保护。Android 标准库文件锁不可用，共享锁封装在该目标使用 rustix 安全 flock，其他目标保留标准库锁；不放宽共享核心的 unsafe 禁令。Android 15 的启动页和软键盘均应用系统栏 inset，避免操作被 ActionBar 或导航栏遮挡。后续仍需真机、其他 Android 版本、旋转/系统回收后的完整进程重建、外部选区及候选翻页验收。

系统契约参考：[InputMethodService](https://developer.android.com/reference/android/inputmethodservice/InputMethodService) 与 [InputConnection](https://developer.android.com/reference/android/view/inputmethod/InputConnection)。
