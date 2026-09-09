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
