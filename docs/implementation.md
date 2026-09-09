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

本机构建成功，文本适配 CTest 通过，使用已校验词库生成隔离状态与开发配置。未安装输入源或切换用户当前输入法；系统焦点、真实候选位置、数字选词、标点路由、设置热更新与正式安装仍未完成。配置文件含本机路径，仅存放在忽略的 target 目录，不可对外分发。
