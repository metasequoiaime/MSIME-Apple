# 渐进实施记录

## 目标与验收

一个客户端工程，共享 Rust 业务、React 管理界面与输入运行时，各端保留系统入口。C++ Engine 继续负责输入算法。完成新仓不代表现有五端均已迁移。

实施阶段（按功能提交，不能用空目录冒充实现）：

1. 工程边界与 Rust workspace。
2. 共享配置：校验、持久化、并发更新冲突与失败保护。
3. Tauri + React 设置页接入真实共享配置。
4. 固定 C++ Engine，建立可运行的桥接与输入运行时。
5. 原生宿主接口，先验证一个真实消费端，再逐端推进。
6. 账号、同步、资源下载等业务按现有后端契约迁入共享层。
7. 五端适配、原生行为验证与组合 CI；已接入部分才删除重复实现。

## 当前证据

CI 已按用户要求暂停，远端 workflow 为手动禁用；后续仅执行本地验证，未经明确要求不恢复运行。

后续实施优先级由用户明确为 **Windows → macOS → iOS → Linux**。已合并的 Android/Linux 增量保留，Linux 自动重读尚未开工，暂停继续追加；接下来先推进 Windows 的共享运行时接入，保留 TSF DLL / Server 边界，再按上述顺序推进其他端，不以本机验证便利性替代产品优先级。下方各条记录是历史成果，不代表后续排期。

- 初始工作区中没有 MSIME-Client，GitHub 同名仓查询不存在。
- 组织远端 AGENTS 提到 Engine develop，但实际 GitHub 默认分支仍为 main，develop 查询为 404；依赖锁定必须按实际远端执行。
- 相邻平台和 Engine 工作树包含其他任务修改；本工程不导入这些未提交内容。

### 第一条功能：本地配置

`client-core::preferences` 提供配置值、格式版本、revision 和文件存储。宿主传入新工程的私有目录；不导入或覆盖旧平台配置。它不是后端 preferences 协议，云端字段映射会作为独立迁移实现。

同目录临时文件替换避免半写 JSON；独立锁文件协调多个实例；revision 比较拒绝覆盖过期设置。损坏文件、未知字段和未来格式均报错并保留原文件。没有宣称断电级目录持久性保证。

macOS 本地：4 项测试通过，覆盖持久化、过期保存、非法值、损坏/未来文件保护和并发写入；fmt、clippy 通过。三桌面平台 CI 已定义，远端运行结果另行记录。

### 第二条功能：共享设置界面

React 组件只依赖 `SettingsClient` 接口。Tauri commands 注入应用数据目录，在 blocking pool 中调用 client-core，文件锁不会阻塞主界面线程。读取失败不构造可保存的虚假默认值；冲突保留用户编辑，显式重新读取会提示放弃未保存修改。

本地前端类型检查、Vite 构建和 3 项组件测试通过，覆盖保存 revision、冲突保护和初始读取失败。macOS Tauri Rust 检查通过。原生窗口交互、Windows/Linux 二进制与五端输入宿主接入仍需独立验证。

### 第三条功能：真实 Engine 桥接

固定 Engine main 的 f53e030542f4bc7d2cd311a7d6f23d6b6109596f，通过 CXX 建立拥有型 Session。C++ 异常转 Result，值快照复制到 Rust，不传出借用候选指针。Rust 明确禁止会话跨线程共享。macOS 上非法路径/方案异常测试和真实 Engine Unicode 输入到提交测试均通过；此测试无需生产词库，因此不冒充拼音质量回归。

用户授权本地验证后先合并，CI 后台执行。配置与设置页已由 PR #1 合入 develop；不因 CI 排队暂停后续模块。

### 第四条功能：共享输入运行时

运行时缓存 Engine 值快照；界面读取不再次推进引擎。分页、高亮归共享运行时；候选 ID 包含会话、视图代次和全局索引，拒绝跨会话、旧视图和当前页以外的选择。失焦取消组词，未聚焦按键透传。3 项本地行为测试覆盖分页上屏、旧候选和焦点切换；真实 Engine 测试继续由桥接层执行。线上请求编排、配置延迟切换和各原生平台接入尚未完成。

### 第五条功能：原生 C 宿主入口

提供 ABI 1 头文件、静态库和动态库。会话用线程局部注册表中的整数句柄表示，错误线程和已销毁句柄不会解引用陈旧对象指针。响应是库拥有的 UTF-8 JSON，配套释放入口。输入缓冲区有效性和输出指针单次释放仍是 C 调用方的责任。

macOS 上 2 项 host-api 测试通过，覆盖真实 Unicode 输入链路、错误线程、失效句柄、非法缓冲区和命令。另用系统 C 编译器编译独立 native_smoke.c，链接实际动态库，执行创建、焦点、Unicode 输入、提交和销毁，输出通过。这证明真实跨语言消费链路，不证明 TSF/IMK/IBus/Android/iOS 系统宿主接入完成。

### 第六条功能：Apple Foundation 适配器

共用桥接位于 `shared/apple`，macOS 专属 InputMethodKit 宿主位于 `platforms/macos`；iOS 键盘扩展尚未实现。

提供可供 Swift 使用的 Objective-C++ 会话对象，负责 C 响应释放、Foundation 值转换、主线程约束和对象销毁。macOS 使用系统 clang++ 编译并链接实际动态库；Unicode 上屏结果、后台线程拒绝和关闭后拒绝测试通过。这是 Apple 原生消费边界，不是已安装的 InputMethodKit 输入法，也不是 iOS 扩展构建验收。

### 第七条功能：Android JNI 边界

Java NativeClient 经 JNI 调用同一个 C API，避免 JNI modified UTF-8。macOS 系统编译器和 JDK 21 构建本机 JNI 动态库及 Java 消费者，包含非 BMP 字符的资源路径和 Unicode 提交回归通过。尚无 Android NDK 构建、InputMethodService 或 APK 验证；本机 JVM 只证明互操作和编码边界。

### 第八条功能：共享资源安装

ResourceStore 读取受信任产品锁，通过宿主注入的传输流安装平面文件集合。严格长度与摘要、跨平台文件名约束、独立文件锁和临时目录发布防止半安装；不覆盖旧资源代。4 项新增测试覆盖坏摘要/长度、缓存篡改、失败升级和路径别名。client-core 共 8 项测试通过。

真实下载已完成：dict-v1.0.0 的六个文件均匹配提交中的固定长度/摘要，并通过固定 Engine 的 `contracts.dictionary.product.verify_product` 检查。真实数据源是 d0dc0c2b594b5540b5de99ad12085c786410626e，与 Engine 代码来源分别记录。资源仅存放在忽略的 target/resources，未修改现有安装。

### 第九条功能：真实词库准备与输入验收

通过 CXX 暴露 Engine 的 `prepare_runtime_paths`，复用其数据库复制、学习回放与目录发布流程。macOS 上使用已校验的真实 Release 资源和临时用户/缓存目录，`nihao` 查询得到并成功提交“你好”。这比无需词库的 Unicode 探针增加了真实数据库集成证据，但不代表完整词库质量或系统宿主验收。独立 published-dictionary CI 在后台下载、用上游 verifier 校验、执行输入探针并复核不可变资源。

### 第十条功能：宿主准备与结束组合

`prepare_host_configuration` 验证固定资源并调用 Engine 准备工作目录，再读取共享偏好生成 ABI 1 配置。`prepare_host` 开发工具原子写入运行配置，不安装输入法。新增 Finish 动作直接调用 Engine 的 finish(highlighted_index)，保留剩余分段完成逻辑；运行时增加对应回归，4 项测试通过，host-api 2 项测试及 clippy 通过。

### 第十一条功能：macOS IMK 预览宿主

新增真实 IMKServer / IMKInputController 与开发 bundle，静态链接 Rust/C++ 库。平台只负责按键映射、预编辑、上屏与不激活候选面板；共享层负责分页、高亮和候选代次。文本适配以 ASCII 编辑串保证源光标偏移与 UTF-16 对齐。Rust 和 CMake 统一使用 macOS 13 最低目标。

本机构建成功，文本适配 CTest 通过，使用已校验词库生成隔离状态与开发配置。未安装输入源或切换用户当前输入法；系统焦点、真实候选位置、设置热更新与正式安装仍未完成。配置文件含本机路径，仅存放在忽略的 target 目录，不可对外分发。

### 第十二条功能：共享数字选词

Engine 优先处理字符，未处理的 1–9 再映射到当前候选页的全局索引。不存在的数字槽位被消费且不跳回首页；空闲数字透传。macOS 候选面板显示页内数字，平台无需实现选词规则。运行时 6 项测试和宿主接口 2 项测试通过；真实锁定词库探针覆盖第二页数字选择、分段结束、空闲透传及 Unicode 数字输入，纳入 published-dictionary CI。macOS 构建、文本适配测试及 clippy 通过；尚未进行安装后的系统键盘验收。

### 第十三条功能：共享标点编排

未被 Engine 字符入口处理的 ASCII 标点先调用 finish(highlighted)，再调用 Engine punctuation，避免其默认选择首候选。字符解释、分段完成和中文标点映射仍归 C++，Rust 只编排调用与合并提交。ASCII 模式及未映射符号在已有提交后追加原符号；空闲时透传。完成后若标点调用失败，保留已完成提交、追加原符号并返回诊断。

运行时 9 项、桥接 2 项及宿主接口 2 项测试通过。真实词库 runtime_dictionary 探针覆盖第二页高亮的完整提交、中英文标点、空闲标点、交替引号与原有数字/Unicode 回归；探针命名与 Engine 示例分离以避免 Cargo 输出冲突。macOS 原生构建和文本适配测试通过；不代表安装后的编辑器端到端验收。

### 第十四条功能：共享配置延迟应用接口

C API 接收版本化 PreferencesSnapshot，Apple 与 JNI 桥接同步暴露。活跃组合期间只保留最新快照，结束组合或失焦后应用；拒绝旧 revision、同 revision 不同内容和非法配置。替换 Engine 前验证新实例，保留会话句柄和焦点、更新视图代次；快照读取失败不能被当作空闲。重建失败保留旧会话、待应用配置和已完成提交，后续重试。

本地运行时 11 项、宿主接口 5 项测试通过，覆盖延迟切换、版本冲突、页大小、失败保护、句柄与候选代次；Foundation/JNI 消费测试覆盖配置延迟及应用后的 ASCII 标点。macOS 构建和文本适配测试通过。此阶段只完成共享应用接口，尚未连接设置文件监听与 Tauri 保存后的自动更新；当前重建在宿主线程进行，耗时需后续真实词库测量与优化。

### 第十五条功能：macOS 配置后台重读

无会话句柄的 C 文件读取接口复用 PreferencesStore；Apple 桥接后台读文件/锁，主线程应用快照。macOS 活跃期间每秒轮询且不重叠，失活停止；bootstrap 显式记录偏好目录。Tauri 支持绝对路径 MSIME_CLIENT_STATE_DIR，开发时可与宿主共享隔离配置，无需复制字段或依赖 Tauri 常驻。

宿主接口 6 项测试、Foundation 异步读取和损坏文件保护测试、macOS 构建与文本适配测试通过。真实词库 preferences_latency 探针验证新页大小和 ASCII 标点，本次本机 debug 单次创建 2.58 ms、重建 1.57 ms；非统计基准或跨平台性能保证。尚未安装系统输入源验收设置窗口到编辑器的完整交互，移动平台文件分发与其他系统宿主仍待接入。CI 继续禁用。

### 第十六条功能：Android 系统服务源码

新增 InputMethodService、BIND_INPUT_METHOD manifest、软键盘和共享候选/翻页入口；InputConnection 只负责提交和预编辑，EditorBridge 维持写入顺序与失败短路。密码/无建议/非文本字段不创建 Engine，禁用个性化学习的编辑器关闭学习。外部选区变化结束标记并取消引擎组合，避免空组合覆盖编辑器新选区。

本机 Android API 35 全部 Java 编译、aapt2 manifest/resource 检查通过；JVM 文本适配测试验证分段提交、取消、失败、外部选区与敏感字段策略。没有本机 NDK，不提供 Android 原生库或可安装 APK；桌面 JNI 不作为设备证明。资源准备、各 ABI 原生构建、APK 与设备生命周期/编辑器验收继续待办，CI 未启用。

### 第十七条功能：Android 原生交叉构建

安装固定 NDK r28c，vcpkg 2025.06.13/ef7dbf94 固定 Boost、fmt、spdlog 和 SQLite 依赖。Android CMake 使用 NDK 工具链及独立依赖前缀，不改 Engine 子模块；SQLite 静态进入宿主库，JNI 动态消费宿主库并随包携带 NDK libc++。各 ABI 使用独立 vcpkg 安装根，避免切换 ABI 时删除上一套依赖；Android CMake 重新配置清理旧依赖路径缓存。

arm64-v8a 与 x86_64 release 库已构建，ELF 架构、16 KB LOAD 对齐、动态依赖白名单及 C/JNI 导出校验通过；错误 ABI 负例被拒绝。本机 macOS 桥接/宿主 8 项回归及 clippy 通过。NDK/vcpkg 许可声明复制到构建输出，分发前仍需完整 Rust/Engine/词库许可汇总。无可安装 APK 或设备运行证据，CI 保持禁用。

### 第十八条功能：Android 开发 APK 与首次准备入口

增加共享 C/JNI bootstrap，复用锁定资源校验和 Engine 工作目录准备；启动 Activity 后台解包 APK 资源，首次成功后原子发布私有运行配置，已有配置不覆盖。开发构建脚本用 SDK 编译 Java/DEX、打包双 ABI 和六份资源、16 KB zip 对齐及开发签名；不执行安装、启用或切换输入法。

本地 SDK 源码检查、双 ABI 原生导出检查、APK 签名/对齐/包结构检查通过。共享核心与宿主 14 项测试、真实资源 C bootstrap 探针、桌面 JNI 回归、fmt/clippy 通过。当前 APK 约 92 MiB，只是开发产物；未进行设备安装、首次准备及系统输入验收，也未完成正式分发的完整许可材料，CI 保持禁用。

### 第十九条功能：Android 模拟器系统输入验收

新增独立 arm64 Android 15 AVD、合成编辑器 APK、跨窗口 instrumentation 与共享核心 Cargo 设备 runner；脚本校验设备类型和专用 AVD 名称，不操作用户现有真机。实际首次准备发现标准库 File::lock 在 Android 不支持，改用 rustix 安全 flock，保留其他目标标准库锁与 unsafe 禁令；同时修复启动页 ActionBar 覆盖内容、系统导航栏覆盖软键盘底部操作的问题。

专用模拟器上安装、首次资源准备及重复准备通过，真实软键盘点击经 JNI/共享运行时/Engine/InputConnection 提交“你好”、退格得到“你”、密码字段直接输入通过。测试等待窗口稳定后从最新节点取坐标，读取全部交互窗口，不以只含前台 Activity 的 dump 代替 IME 观察。Android 上共享核心 8 项测试通过，包括配置并发单赢家、缓存校验与失败升级保护；macOS 核心/宿主 14 项测试、fmt、桌面和 Android 核心 clippy、SDK 编译、双 ABI 打包/签名/对齐通过。尚未覆盖真机、x86_64 运行、完整生命周期和五端迁移，CI 保持禁用。

### 第二十条功能：Android 共享配置自动应用

补齐无会话 JNI PreferencesStore 读取接口；后台单次读取、主线程应用、代次丢弃旧结果和停止轮询连接实际 InputMethodService。平台不复制 revision 或组词延迟规则；快照复用共享更新入口，失败保留会话和文件。禁止个性化学习的编辑器对后续快照同样强制关闭学习。文件未变化时不重复重建相同候选控件。

SDK/JVM 调度回归验证异步读取、停止/重启、旧结果拒绝、不重叠和错误重试；桌面 JNI 验证带非 BMP 字符的配置目录、后台读取和坏文件保护，宿主/运行时 17 项测试、fmt/clippy 通过。Android 15 arm64 专用模拟器实测组词中更改配置延迟到提交后应用、2 项候选页、英文标点、坏文件下继续拼音上屏，原坏文件保留；有效配置恢复后重新应用中文标点，原有系统输入回归继续通过。此阶段仍不是 React 移动设置页或完整生命周期验收，CI 保持禁用。

### 第二十一条功能：Android Tauri / React 设置与 IME 合包

Tauri commands 移入桌面与移动共用入口库，React 页面保持唯一实现；Android 直接使用同包私有 bootstrap/state 配置目录。纳入固定 Gradle Android 工程，直接引用现有 JNI/Java/图标与锁定资源。首次启动接已有资源准备页，准备后进入共享设置；不会自动启用输入法。开发包与旧原生测试包保持相同开发签名和 versionCode 1，未作正式发布。

实际发现 Tauri 最后一个窗口关闭会退出进程，故原生 InputMethodService 隔离到同包 :ime 进程；不引入设置服务依赖，跨进程仍用既有共享配置锁。Android 15 arm64 模拟器验证真实 React 表单保存、revision 增长、重新读取及另一进程的实际标点上屏；独立控制端连续两次打开/关闭设置，:ime PID 不变且继续输入，系统记录设置进程 EXIT_SELF/0。原有上屏/退格/密码和配置延迟/损坏保护回归通过。

前端 3 项组件测试、类型检查/生产构建、macOS Tauri Rust 构建检查和测试、共享核心 8 项测试、fmt/clippy、arm64 Tauri 合包签名/16 KB ZIP 对齐及原生 ELF 16 KB 对齐通过。x86_64 Tauri 合包、真机、其他系统宿主与完整生命周期仍未验证，CI 继续禁用。

### 第二十二条功能：Linux IBus 预览宿主

新增动态注册的独立 IBus 宿主，通过共享 C API 创建主线程会话；系统层只映射按键、焦点、预编辑、上屏与候选点击，不复制输入业务。当前页、全局候选索引和代次取自共享视图，auxiliary text 标示页码；密码/PIN/数字/电话字段透传，private/no-spellcheck 会话关闭学习。失焦/reset/禁用清除组合，修饰键与 key-up 不触发取消，快捷键取消后透传；错误日志不含响应或输入内容。

Debian bookworm arm64 容器构建真实共享 Rust/C++ 动态库和 IBus 1.5.27 宿主。独立 D-Bus 调用实际 Engine 对象，验证固定词库的预编辑/候选/提交信号、第二页候选点击、标点、数字小键盘、敏感字段和焦点边界；实际可执行文件经隔离 IBus daemon/factory 向独立输入上下文提交合成词语。Linux 共享核心/运行时/宿主共 25 项 Rust 测试通过，容器不连接宿主桌面，源码与词库只读挂载。

目前仅用启动配置快照；Linux 设置自动重读、GTK/Qt 实际编辑器、X11/Wayland、panel 原生翻页按钮与安装打包仍待完成，不据此宣称 Linux 产品迁移完成。未复制相邻 Linux 仓库的未提交内容，CI 继续禁用。

### 第二十三条功能：Windows Server 共享会话适配

按新优先级转入 Windows。ServerSession 消费固定上游 TSF 键包并调用共享 C API，限定 Server 输入队列线程、客户端和 activation epoch；不在注入的 TSF DLL 加载引擎。候选选择和偏好延迟仍归共享层；忽略包中复制的拼音状态，采用布局转换后的 wch，数字小键盘规范化后走共享选词，既有 TSF 的本地 Shift/Escape 取消不回按键回复。

macOS 链接真实 Rust/C++ 库运行边界测试通过，覆盖 Unicode 上屏、真实固定词库的第二页数字选词、配置延迟应用和线程/客户端/焦点拒绝；Windows x86/x64 MinGW 对象交叉编译验证适配器、测试与上游线格式断言。本机没有已配置的 Windows 虚拟机，未执行 Windows Rust 链接、TSF 注册或系统编辑器验收。Named Pipe、回复编码、路由发送前复核和原生候选窗仍是后续 Windows 工作，不将本阶段当作 Windows 端已完成。CI 继续禁用。

### 第二十四条功能：Windows 旧协议回复编码

依据现有 TSF 的候选、标点、分段与 UILess 消费路径，新增显式回复编码器，不更改固定上游 opcode。UTF-8 严格转 UTF-16，容量按 199 个 UTF-16 单元计数；超长、坏编码、NUL 和无法无歧义表示的分隔字段明确失败，不截断文本。发送字节逐字段以小端生成，零填充协议空隙，不直接发送结构体填充区。

本机两项 CTest（会话与编码）及真实固定词库会话回归通过；编码测试覆盖两种完整提交类型、分段字段、UILess 页、高亮、字节序、代理对和容量边界。x86/x64 MinGW 编译上游契约和适配器，并成功链接纯编码测试 PE；未执行 Windows 二进制，不代表实际 TSF 验收。回复路径选择、增量提交到旧 DLL 完整前缀的编排和 Named Pipe 收发仍待实现，继续优先 Windows，CI 保持禁用。

### 第二十五条功能：Windows 分段回复与确认编排

ReplyComposer 为已认证的单次客户端激活保存旧协议尚未上屏的选词前缀，剩余输入与选词仍由 Engine 负责；分段、最终候选、标点、预编辑和 UILess 使用各自回复语义。LocalCommit 只有提供的本地完成文本与前缀加共享结果一致时才允许无帧确认，取消不重复上屏。待发送结果在确认前保留，dispatch 在调用 Engine 前阻止新按键越过待确认回复；编码失败保留原始结果，不能被确认成成功。

本机三项 CTest 及真实固定词库回归通过：nihao 实际选“你”后剩余输入仍活跃，再选“好”生成唯一完整回复“你好”；待确认期间再次 dispatch 不改变 Engine 视图。编排测试覆盖多段、标点、UILess、本地完成文本不匹配、取消、旧确认和超长保留；Windows x86/x64 编排对象交叉编译通过。原生 ReplyPath 选择、完整 Pipe 写入确认、发送前路由复核及实际 Windows 系统输入仍待接入，不据此宣称 Windows 已完成，CI 保持禁用。

### 第二十六条功能：Windows 原生管道帧 I/O

新增仅用于独占 overlapped 消息管道的工作线程读写层，校验固定帧长、拒绝短帧和超长帧；超时或取消后等待实际 I/O 结束才释放缓冲区，超时不是硬性返回时限。未成功完成的已提交写入标记 delivery_uncertain，不自动重发或确认 Engine 回复；失败后由后续路由层关闭连接，避免读取残余消息。此层不创建生产管道、不认证客户端、不注册 TSF。

新增使用独立测试管道的 Windows 测试，覆盖上游协议结构体帧长、畸形消息、取消、超时和断连。Windows 可运行 `cmake -S platforms/windows -B target/windows-pipe -DMSIME_WINDOWS_PIPE_ONLY=ON`、`cmake --build target/windows-pipe --config Debug`、`ctest --test-dir target/windows-pipe -C Debug --output-on-failure`，无需先构建 Rust 宿主库。本机三项既有 CTest 和真实词库回归通过，x86/x64 测试 PE 交叉链接通过；新增管道测试未在 Windows 执行，不宣称运行验证通过。后续仍优先 Windows 的认证、路由复核、原生分发与 TSF 系统验收，再推进 macOS、iOS、Linux；CI 保持禁用。

### 第二十七条功能：Windows 管道进程身份绑定

新增 PipePeer：按系统返回的管道客户端进程与会话检查 client_id 高位，比较客户端与 Server 进程的账户 SID，查询失败明确拒绝。绑定后保留不可继承的进程句柄，主/反向端点复核使用完整 client_id、会话和原进程存活状态，不只比较可复用的 PID。它不替代生产 DACL、拒绝远程连接、版本握手、管道角色或焦点代次授权，调用方仍负责端点生命周期。

独立 Windows 测试增加同进程主/反向端点绑定、错误完整 ID、伪造 PID、零 ID、错误方向句柄、无效句柄和断开端点拒绝。x86/x64 MinGW 交叉链接及 pipe-only CMake 构建通过，本机既有三项 CTest 通过；新增 Windows 测试、跨账户/会话、进程退出和提升权限宿主尚未实测，不宣称完整认证或 Windows 输入接入完成。继续 Windows 生产连接、协议握手与路由接入，CI 保持禁用。

### 第二十八条功能：Windows 管道协议握手

主连接和反向端点握手接入 PipeIo/PipePeer。反向端点先验证角色和进程，再发送对应 PipeReady；主连接复用固定 Engine 协商，并在读取后再次复核主/回复端点，通过回复管道发送协议确认，保留旧 hello 无额外 ACK 的行为。角色确认帧与协议确认共用显式字段编码、清零填充；能力由实际分发调用者显式提供，不默认声称支持语音。Ready 仅表示该握手完成，不等于全局注册或焦点授权，端点生命周期和注册代次仍由下一步生产路由器负责。

三项本机 CTest 及真实锁定词库回归通过，编码测试增加注册帧大小、零填充、字节序、协议能力与请求限制；x86/x64 MinGW 及 pipe-only CMake 构建通过。原生测试增加两类反向管道确认、主协议确认、必需能力不兼容拒绝、旧 hello 无 ACK、错误客户端/角色和取消；未在 Windows 执行，不宣称管道或 TSF 系统验收完成。继续 Windows 的生产访问控制、监听和注册路由，不提前转其他平台；CI 保持禁用。

### 第二十九条功能：Windows 安全管道监听

新增单工作线程 PipeListener 和独占 PipeConnection，账户 SID 构造明确 DACL，保留上游受限 AppContainer 权限与低完整性标签，拒绝远程连接。首次创建拒绝占用名；accept 交出连接前补建下一实例，持续持有名字。连接使用 overlapped 事件和取消后完成等待，失败/取消后断开竞态客户端，避免释放尚在使用的 OVERLAPPED；不使用非阻塞旧模式冒充异步。

全部原生管道测试切到实际监听器，新用例检查超时与取消后恢复、名字占用、RAII 生命周期、不可继承句柄和实际 DACL。x86/x64 交叉链接、pipe-only CMake 构建和本机三项既有 CTest 通过；Windows 原生测试尚未执行，不宣称系统安全或 UWP 兼容性验收。当前仅为库，未启动生产 Server、创建正式管道或注册输入法；后续继续 Windows 的有界连接调度、注册代次与输入路由，CI 保持禁用。

### 第三十条功能：Windows 端点注册与传输代次

PipeRegistry 接管真实管道连接，限制已登记客户端容量，反向端点完成身份握手后登记，主端点在对应客户端锁内经回复管道确认后发布完整票据。三角色各有单调注册代次，替换反向端点使主注册失效并取消旧读取；旧票据发送和旧角色清理均不能作用于新端点。每客户端独立串行写入，主管道读取保留端点引用、允许并发取消，并在返回前复核注册和身份。未完成主握手不可普通发送，失败写入不重试。

新增原生集成测试经过实际监听、注册握手及读写，检查代次错配、重连取消、旧任务拒绝、容量回收和 shutdown；x86/x64 MinGW 链接及 pipe-only CMake 构建通过，本机既有三项 CTest 通过。新增注册器测试尚未 Windows 执行，不宣称并发或系统端到端验收完成。外部 intake/握手工作池仍须限流，输入焦点/activation、Engine 队列与 ReplyComposer 投递确认尚未装配；继续优先 Windows，CI 保持禁用。

### 第三十一条功能：Windows 有界握手工作池

PipeIntake 将监听连接交给固定线程与有容量上限的队列，队满/停止/非法角色直接关闭新连接；主 hello 精确读取后交给 Registry，反向连接按角色登记。取消事件贯穿握手，stop 清空队列、取消进行中的 I/O 并等待线程退出；完成回调必须非阻塞，下游拒收或抛错时按代次撤销未交付登记，不记录输入或异常正文。

原生测试覆盖静默客户端、队列饱和、停止取消、停止后拒收、三角色完整投递及回调拒收/异常清理。x86/x64 MinGW 和 pipe-only CMake 构建通过，本机三项既有 CTest 通过；新增工作池测试未在 Windows 执行，不宣称原生并发验收。生产监听循环、焦点状态机与 Engine/ReplyComposer 队列仍需装配，继续 Windows 优先，CI 保持禁用。

### 第三十二条功能：Windows 三角色传输服务

PipeService 统一拥有三条监听、有界握手池和注册器，按显式管道名与能力配置启动，不隐式发布产品命名空间。监听自动将连接交给工作池；不可恢复错误保存首个错误码并请求停止全部监听/握手。控制线程 stop 统一等待线程、关闭注册器并释放监听器，启动失败也回收已取得的资源；不会接管已有 Server 的管道。

原生测试从三条实际监听完成反向确认和主协商，不再手动调 accept/submit，另测重复启停、幂等停止和第三个名称冲突后的回收。x86/x64 MinGW、pipe-only CMake 构建及本机三项既有 CTest 通过；原生服务测试未在 Windows 执行，不宣称系统接入完成。继续 Windows 焦点/activation 状态与 Engine/ReplyComposer 输入链路，未启动生产服务、安装输入法或恢复 CI。

### 第三十三条功能：Windows 主管道可取消空闲等待

修正主管道只能有限超时读取、空闲超时会注销主注册的接口限制。新增必须携带取消事件的长期读取入口，注册器默认使用它；重连/移除/shutdown 可取消待读取，握手和写入仍强制有限超时。原生用例覆盖空闲后读取、重连取消及参数限制，断言失败清理会先取消长期读取。

x86/x64 MinGW、pipe-only CMake 构建与本机三项既有 CTest 通过；新增原生测试未 Windows 执行。仍需接入焦点/activation 与 Engine 输入链路，不宣称 Windows 端完成，CI 保持禁用。

### 第三十四条功能：Windows Worker 焦点确认编码

依据固定上游 TSF/Server 消费路径，FocusSessionReady 回显 TSF 激活请求的 focus token，而非 Server epoch。新增纯编码器，拒绝零，完整支持 uint64 十进制 UTF-16，并清零帧尾和终止符。焦点授权、注册代次和发送顺序仍由后续路由状态机负责。

本机三项 CTest 通过，编码新增精确字节与 32/64 位边界测试；原生注册器测试增加 worker 确认帧发送/读取，x86/x64 交叉链接通过，未 Windows 执行。继续 Windows 焦点状态与 Engine 输入链路，CI 保持禁用。

### 第三十五条功能：Windows 激活确认门禁

新增可本机执行的 FocusGate，分离传输票据、Server activation epoch 与 TSF token。新激活先 pending，worker 确认回调完整成功后才 ready；失败/异常保持关闭，旧确认/旧失焦不能改变新激活。授权动作与激活切换共用焦点锁，发送仍同时受 Registry 代次检查；输入组合与旧会话取消不移入门禁。

新增本机状态与并发测试，四项 CTest 全部通过；Windows 原生测试组合门禁、实际 worker 确认和回复发送，x86/x64 交叉链接通过，但未 Windows 执行。ClientActivated/FocusRestored 等真实事件策略和 ServerSession 输入队列切换仍待接入，不宣称完成系统焦点授权。继续 Windows，CI 保持禁用。

### 第三十六条功能：Windows 焦点会话与 Engine 队列适配

FocusedSession 在输入队列组合 FocusGate、真实 ServerSession 和 ReplyComposer。pending lease 才可 prepare，确认完成后 key 才进入 Engine；过期输入/确认在调用共享层前拒绝，待回复仍阻止重跑。暂存结果可读出而不重执输入，新激活清空旧组合，旧取消不会清掉新准备的会话。管道写入留在 I/O 线程，确认回到输入队列，仍需控制器按序调度旧客户端取消和新激活。

四项本机 CTest 及真实锁定词库回归通过，新增用例执行真实 Rust/C++ Unicode 提交与回复编码，覆盖准备/确认门禁、暂存结果、过期任务和线程约束；焦点确认使用测试回调。x86/x64 适配器对象编译通过，未链接 Windows Rust 库或执行 TSF 系统验收。生命周期策略、实际输入队列调度与完整端到端链路仍待接入，继续 Windows 优先，CI 保持禁用。

### 第三十七条功能：Windows 焦点会话配置更新

将共享配置更新接入 FocusedSession 的队列与 lease 检查，待回复未确认时不允许配置修改 Engine；确认后可重试最新快照，组词中的延迟应用继续由共享层处理。新增真实会话测试验证待回复拒绝、deferred、提交后应用与旧焦点拒绝，四项本机 CTest 通过，x86/x64 适配器对象编译通过。配置文件监听、队列重试与系统生命周期调度仍未装配，未 Windows 原生验收，CI 保持禁用。

### 第三十八条功能：Windows Main 消息验证与身份固定

将 MainFrame 验证直接接入 PipeRegistry::read_main，补齐逐帧 client_id 固定、Main 事件白名单、字符串边界和生命周期字段检查；畸形帧不交给控制器，清空返回数据并使匹配主注册失效。字段规则来自固定上游 Main 接收路径，不更改 Engine 线格式；保留重复 hello，key 的保留请求编号检查与 ServerSession 一致。

新增纯字段测试及实际管道拒绝用例，覆盖身份切换、越界长度和 Aux 事件。五项本机 CTest、x86/x64 交叉编译及独立测试链接、Windows 管道 CMake 交叉构建通过；未在 Windows 执行原生测试。此阶段仍不包含生命周期策略或可运行的完整 Windows 输入产品；继续 Windows → macOS → iOS → Linux，CI 保持禁用。

### 第三十九条功能：Windows 生命周期路由策略

FocusRouter 将登记票据、显式激活、真实按键/焦点恢复、挂起、终止与断连映射到 FocusGate 和精确会话清理任务。已确认 token 可在临时焦点挤占后恢复，状态快照不抢焦点；同 token 不重复重置 Engine，旧登记及失败通知不能影响新激活。FocusGate 原子记录被替换激活的 ready 状态，处理确认通知尚未回队列的竞态。

六项本机 CTest 与真实锁定词库会话回归通过，包含真实 Engine 跨客户端组合清理；x86/x64 交叉编译及独立测试链接、Windows 管道 CMake 交叉构建通过。Windows 管道测试已组合路由与实际确认发送，未原生执行。仍需有界输入队列、可执行控制器、Windows Rust 链接与 TSF 系统验收；继续 Windows 优先，CI 保持禁用。

### 第四十条功能：Windows 专用输入线程

InputQueue 在单一 worker 创建、使用、销毁真实共享会话，并通过 InputState 自动执行生命周期路由的旧会话清理与新会话准备。有界入队明确报告容量拒绝；已接纳任务都有完成、失败或取消回执。停机结算等待任务并在原线程释放会话；任务异常先撤销授权并清理共享会话，再报告失败，不输出原始诊断。管道读写继续留在独立 I/O 侧。

新增多生产者、容量、取消、异常、重复停机与自 join 拒绝测试，实际会话回归覆盖专用线程 Unicode 提交、焦点切换和销毁。七项本机 CTest、队列测试连续二十次和真实锁定词库回归通过；x86/x64 队列及测试对象编译通过，尚未链接 Windows Rust 库或执行原生队列测试。仍需装配原生控制器、逐客户端 I/O 等待/回执和配置重试，再完成 Windows 原生链接与系统验收；不跳到其他端，CI 保持禁用。

### 第四十一条功能：Windows Main 会话处理循环

SessionPump 将已登记 Main 连接串到真实 InputQueue：消费登记、路由/准备、焦点确认、输入、回复发送、队列回执按顺序完成，当前回复未结算不读取下一键。PipeMainTransport 直接复用 Registry 的认证、校验、取消读取和有限写入；MainTransport 接口用于同一循环的确定性本机测试。过期焦点输出丢弃，真实发送失败关闭匹配连接且不重放；清理任务无法入队时停止共享队列。实际 TSF 分发和 UI/模式事件由显式处理器提供，不从 VK 臆测。

新增真实 Rust/C++ Unicode 会话循环测试，覆盖完整线格式、确认顺序、首次确认/回复失败、错误分发关联、畸形输入、焦点切换及自等待拒绝；原生管道测试接入实际传输适配器。七项本机 CTest、会话测试连续十次和真实锁定词库回归通过，x86/x64 交叉编译及独立管道测试链接通过。完整 Windows Rust/管道组合和系统验收尚未完成，下一步仍是有界原生控制器、真实分发与模式输出，CI 保持禁用。

### 第四十二条功能：Windows 有界连接工作线程

SessionWorkers 用固定线程槽位运行 SessionPump，每客户端最多一个活动连接和一个待接替连接；重复登记不多开读取者，连续重连只保留最新票据，旧循环清理完成后复用原线程。容量拒绝、过期登记和停机后提交关闭匹配连接；停机先取消读取再 join，输入队列保留到会话清理完成。输入线程与自身 worker 的 join 被拒绝。

新增真实队列/会话与可取消空闲传输组合测试，覆盖读取上限、重复登记、容量、线程复用、连续替换、旧关闭隔离及并发停机。七项本机 CTest、会话测试连续二十次与真实锁定词库回归通过，x86/x64 管理器及测试对象编译通过；未 Windows 原生运行。仍需有界登记通知入口、服务启动及故障监控装配、原生 TSF/UI 分发和 Windows 系统验收，继续 Windows 优先，CI 保持禁用。

### 第四十三条功能：Windows 服务装配与故障监控

RegistrationInbox 将握手回调与可能等待取消的连接管理分离；SessionController 持有输入队列、连接 worker 和控制线程，消费登记并在空闲时检查故障。WindowsServer 装配实际 PipeService、传输和控制器，使用显式名称及能力，早到的通知进入预先构造的有界收件箱。退出顺序固定为停止服务/Registry、join 连接循环、停止输入队列；输入回调只发出停止请求，不 join。

新增本机收件箱、空闲服务故障、输入异常与回调请求停机测试；八项本机 CTest、会话回归连续二十次与真实锁定词库回归通过。WindowsServer 及使用唯一测试管道、真实握手/激活/Unicode 提交的原生集成测试源码通过 x86/x64 对象编译，独立管道测试交叉链接和管道 CMake 构建通过。尚未执行 Windows 原生组合或 TSF 系统验收，生产分发、UI/模式/设置同步仍待实现，继续 Windows 优先且 CI 保持禁用。

### 第四十四条功能：Engine 模式透传与 Windows Unicode 选词

对照固定上游 TSF 后复现 Unicode 模式 Shift+1 被当作 !、无法选词的问题。共享桥接/视图新增来自 Engine 的 local_mode，模式切换不沿用旧高亮；Windows 使用真实模式和当前页候选 ID 处理 Shift+1..9，不复制选词算法，不从 U 前缀猜模式。越界选择保留组合，非 Unicode 模式继续使用翻译后的标点字符。

回归包含修复前失败、修复后提交、UiLess 修饰位、越界与模式复位；28 项 Rust 单元测试、fmt/clippy、八项本机 CTest、真实锁定词库回归及 x86/x64 适配器编译检查通过。完整生产分发与 Windows 原生验收仍待完成，CI 保持禁用。

### 第四十五条功能：Windows 候选导航回包

ReplyCodec 显式映射共享契约的导航 opcode；ReplyComposer 新增上下候选及前后翻页路径。普通模式返回无文本的导航意图，边界不移动也保留该指令；UILess 返回共享候选页、高亮及已选前缀。导航拒绝 commit 增量，沿用投递确认门禁，不在 Windows 复制分页逻辑。

新增编码字段/非法枚举、部分选词前缀保留、待投递门禁与真实词库导航回归，覆盖首屏边界、翻页和高亮往返。八项本机 CTest、真实锁定词库回归、x86/x64 交叉编译及独立管道测试链接通过；未执行 Windows 原生运行或完整 Rust 链接。后续仍需配置感知的 TSF 键分类、UI/模式/设置同步和产品验收，按 Windows → macOS → iOS → Linux 推进，CI 保持禁用。

### 第四十六条功能：Windows 小键盘 Unicode 选词一致性

真实共享会话回归复现 Shift+小键盘越界选词反而改写 Unicode 组合的问题。按固定上游 Server 的 NormalizeNumpadDigitKey 规则，在候选判定前统一数字键身份，保留原始请求与共享选词代次校验。普通和 UILess 路径均覆盖小键盘输入、越界不变、Shift 选中及模式清理，另验证 0 仍可输入和 Ctrl+Shift 不误选词。

修复前回归失败，修复后八项本机 CTest、真实锁定词库回归及 x86/x64 交叉编译检查通过；不涉及 Rust 源码。Windows 原生运行和完整生产按键分发仍未完成，继续 Windows 优先，CI 保持禁用。

### 第四十七条功能：Windows 显式导航绑定贯通

新增 NavigationBindings 值快照，按固定上游键规则表达减号等号、逗号句号、方括号、Tab/Shift+Tab、PageUp/PageDown 和上下候选。InputState::navigate 经焦点校验及投递门禁调用共享导航命令，再自动选择普通导航 opcode 或 UILess 候选页；不要求调用方另外猜回复类型。Unicode +、快捷键、空组合和关闭绑定不被此入口消费，原始请求不改写。

每组绑定独立启用的真实词库回归覆盖前后翻页、高亮、禁用不变、快捷键排除和两种回包；真实输入队列覆盖 Unicode + 排除、边界导航、失效焦点和待回复门禁。八项本机 CTest、锁定词库回归及 x86/x64 交叉编译检查通过，未执行 Windows 原生运行。此入口仍需完整 TSF 上下文判定排除标点/以词定字优先路径，关闭绑定后的忽略/转发不能无条件回退旧 VK 映射；设置监听和产品 KeyHandler 尚未接入。继续 Windows → macOS → iOS → Linux，CI 保持禁用。

### 第四十八条功能：Windows 禁用导航明确回包

补齐上一阶段关闭绑定时的消费结果：已进入 TSF 导航路径的键返回 NavigationIgnored，UILess 返回原候选页，而不是空结果交回调用方。NavigationAction 使用可空 command 表达不执行 Engine 操作，ReplyComposer 新增 IgnoredNavigation 并保留已选前缀及投递门禁。Unicode +、快捷键和非导航键仍不进入该路径。

真实词库回归逐组验证关闭绑定时整个视图不变、两种回包及确认前禁止继续；组合器回归覆盖部分选词前缀、UILess 页和非法 commit。八项本机 CTest、锁定词库回归及 x86/x64 交叉编译检查通过，未执行 Windows 原生运行或完整 Windows Rust 链接。设置监听、完整产品分发和 Windows 原生验收仍待完成，不扩展其他端，CI 保持禁用。

### 第四十九条功能：Windows 配置投递自动重试

InputState::queue_preferences 在真实输入队列内提交配置通知；FocusedSession 为待回复的活动焦点保留一份有界最新快照，合并较新 revision、接受相同内容、拒绝旧值和冲突。成功投递确认后自动交给共享宿主，继续使用共享偏好完整校验及组合期间延迟应用。焦点取消/重新准备清理尚未交付的快照，旧焦点不能影响新会话。

真实队列回归覆盖最新快照合并、错误确认不触发交付、旧版本/冲突/大小/失效焦点拒绝、共享延迟应用及焦点清理。八项本机 CTest、锁定词库回归与 x86/x64 交叉编译检查通过；没有 Rust 源码改动，未执行 Windows 原生运行或完整 Windows Rust 链接。文件监听与新焦点快照发布仍待接入，继续 Windows 优先且 CI 保持禁用。

### 第五十条功能：Windows 共享配置发布与新焦点继承

PreferenceSnapshot 在设置线程通过已有共享 C ABI 读取并完整校验 PreferencesStore，封装为可复制发布值；InputState 保留全局最新快照，拒绝旧值及同版本冲突，向活动焦点交付并复用待回复重试。新焦点确认后、首个按键前自动收到当前快照，断开重连创建的新会话不再只使用旧启动 options。未确认的焦点不会因设置发布得到输入授权。

回归通过共享存储实际加载合成快照，覆盖坏文件/非法设置拒绝、发布版本顺序、当前组合延迟、新激活及完整会话重建后的继承。八项本机 CTest、锁定词库回归及 x86/x64 交叉编译检查通过，未执行 Windows 原生运行或完整 Windows Rust 链接；设置文件监听和工作线程生命周期尚未装配，完整 Windows 原生产品仍待验证，CI 保持禁用。

### 第五十一条功能：共享配置锁竞争无等待读取

为 Windows 设置监听准备 PreferencesStore::try_load 和新增 C ABI msime_client_try_load_preferences；同一稳定锁文件被占用时返回忙状态，不等待写者、不旁路校验、不恢复默认值。Windows PreferenceSnapshot::try_load 映射为空值并保留加载错误语义。文件缺失仍返回共享默认快照，坏文件仍报错且不覆盖。磁盘操作本身可能阻塞，仍须设置线程调用，不能宣称任意存储故障下停机有界。

锁竞争/释放恢复、缺失/坏文件区分及 C ABI 忙状态回归通过；30 项 Rust 单元测试、fmt/clippy、八项本机 CTest、锁定词库回归与 x86/x64 交叉编译检查通过。新符号要求宿主库与适配器成套更新，未执行 Windows 原生运行或完整 Windows Rust 链接。设置监听线程仍待装配，继续 Windows 优先，CI 保持禁用。

### 第五十二条功能：Windows 配置轮询线程装配

PreferenceMonitor 以单个设置线程定期调用共享 try_load，最多保留一个待完成的输入队列发布任务，已发布的相同快照不重复入队。坏文件/锁忙/过期版本/队列满保留旧配置并重试，输入不可用或发布失败成为终止故障。WindowsServer 通过显式 preferences_directory 启用，SessionController 管理状态与停机；设置任务只捕获快照值，不借用监听器，停机唤醒轮询且不等待发布 future。

测试覆盖队列满恢复、去重、坏文件与旧版本保护、恢复新值、输入停止、重复停机及输入线程 join 拒绝；带监听器的真实控制器测试覆盖服务/输入故障和回调请求停机。八项本机 CTest、锁定词库回归、x86/x64 交叉编译检查通过，未执行 Windows 原生运行或完整 Windows Rust 链接。初次读取异步，启动仍使用共享准备的 options；磁盘 I/O 故障可能延迟 join，不宣称任意存储故障下停机有界。完整 TSF 分发、候选 UI/模式输出和产品验收仍待完成，继续 Windows 优先，CI 保持禁用。

### 第五十三条功能：Windows x64 完整宿主交叉链接

新增固定 vcpkg 清单及完整 GNU 构建脚本，架构独立依赖安装根；Rust 桥接为 Windows GNU 限定同架构库搜索前缀并静态链接 SQLite。完整链接发现已知文件夹标识缺少 UUID 库，确认符号后补链。x64 Rust/C++ 宿主 DLL、会话测试及 WindowsServer 原生集成测试均完成 PE32+ 链接，不再仅为对象编译。

30 项 Rust 单元测试、fmt/clippy、八项本机 CTest 与锁定词库回归通过；x86 完整链接实际尝试失败，本机 MinGW 的 SJLJ 展开与 Rust 展开符号不兼容，脚本已添加提前拒绝，未用 panic=abort 绕过。运行时 DLL 未打包，Windows 原生执行、MSVC 和 TSF 系统验收均未完成。继续 Windows 优先，CI 保持禁用。

### 第五十四条功能：Windows 本地原生测试目录

新增运行时准备脚本，为完整构建的 x64 测试目录复制同工具链 MinGW DLL，并递归验证导入依赖与架构；未分类或缺失依赖失败，不假设目标机器 PATH 已配置。PowerShell 入口预检十个合成测试、逐个执行并限制超时，不依赖构建机 CMake 路径，不注册输入法。

发现原生 server_smoke 配置遗漏共享宿主必需的页大小和标点字段，修正并提取共享测试配置；本机验证原缺项被拒绝、完整配置能创建真实宿主。八项本机 CTest、锁定词库回归、x64 完整测试重新链接和运行时依赖检查通过。Windows 程序及 PowerShell 入口尚未执行，目录不含完整发布合规材料，不作为发布包。x86 展开工具链问题及真实 TSF/UI 产品验收仍待处理，继续 Windows 优先且 CI 保持禁用。

### 第五十五条功能：Windows 中文开关同步

主连接三类中文开关通知自动进入输入队列，受当前焦点与待回复门禁保护。关闭中文输入清空共享组合及旧选择前缀，迟到按键不推进 Engine；同状态通知幂等，客户端重新激活保留开关。新增实际 SessionPump 消息序列、重复通知、关闭后按键、重开提交、待回复和过期焦点回归。

八项本机 CTest、锁定词库回归、x64 完整交叉链接及运行时依赖检查通过；未执行 Windows 二进制或真实 TSF 验收。仅接入每客户端中文开关，全局作用域、标点/全半角及出站模式通知尚未实现。顺序保持 Windows → macOS → iOS → Linux，不推进其他平台，CI 保持手动禁用。

### 第五十六条功能：Windows 标点开关同步

Engine PR #87 先合入 main，再固定到 e637e3db59669caf29e257f0c21bfd6c35413a03，暴露内部已有的无损标点开关。共享桥接、运行时和 C ABI 透传；Windows PuncSwitch/StatusSnapshot/FocusRestored 自动同步每客户端临时标点状态，保留组合与候选代次，受待回复及焦点门禁保护。临时覆盖不写配置，并在偏好替换 Engine 时保留。

31 项 Rust 单元测试、fmt/clippy、八项本机 CTest、重新校验的锁定词库回归与 Windows x86/x64 对象编译通过。上游新接口已有 21 项 Engine CTest 通过的证据。Windows 原生执行与 TSF 验收仍未完成；本轮完整交叉构建入口因本地固定 vcpkg 缓存缺失而未运行成功，不沿用旧完整链接结果。全半角、全局作用域及出站模式通知仍待接入，继续 Windows 优先，客户端 CI 保持禁用。

### 第五十七条功能：Windows 出站模式请求

WindowsServer/SessionController 增加携带焦点 lease 的六种模式请求，复用固定 worker opcode 与 404 字节零填充编码；不能发送任意命令或文本。外部调用在焦点锁内核对当前连接后执行有限时写入，回调重入拒绝，失效/停机请求丢弃；不确定写入撤销焦点并关闭连接，不重放。完整投递与 TSF 实际应用严格区分，Engine 只接受后续状态回报，不提前切换。

上游全角字符转换由 TSF 编辑会话执行，Server 不重复转换。八项本机 CTest、锁定词库回归及 Windows x86/x64 对象编译通过；覆盖六种线格式、过期焦点/连接代次、停机、非法命令、回调重入以及写入失败/异常。未改 Rust；没有 Windows 原生执行或本轮完整交叉链接。工具栏接线、全半角 UI 状态及全局模式作用域仍待实现，继续 Windows 优先且 CI 保持禁用。

### 第五十八条功能：Windows 固定工具缓存准备

完整交叉构建入口自动准备默认固定 vcpkg 缓存，从官方仓库按准确提交获取并关闭指标收集 bootstrap；已有目录只校验和复用，不重置错误版本或跟踪文件改动。非预期目录、符号链接、并发锁均拒绝；显式外部根不自动修改。失败 staging 保留供检查，未递归删除。宿主和 x86 展开检查在工具网络准备前执行。

从缺失缓存实际完成固定工具准备、依赖安装、最新 x64 Rust/C++ 宿主 DLL 和所有原生测试程序链接，运行时导入检查通过，补齐第五十六/五十七阶段缺失的完整链接证据。ShellCheck、脚本语法、四类离线拒绝路径、缓存复用及八项本机 CTest 通过；x86 SJLJ 被提前拒绝。未执行 Windows 二进制或 TSF 验收，测试目录仍不是发布包。CI 保持禁用，继续 Windows 优先。
