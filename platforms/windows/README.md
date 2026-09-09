# Windows Server 会话适配

本阶段将固定 Engine 的 `FanyImeNamedpipeData` 键包接到 `msime-host-api`，不是完整 Windows 输入法。共享库只进入独立 Server，不能加载到注入应用的 TSF DLL 中。后续仍保留 TSF DLL / Server 进程隔离、现有版本化 Named Pipe 契约及 UI 原生窗口所有权。

`ServerSession` 由 Server 输入队列线程创建和销毁，不可复制或移动；所有操作检查线程。上层路由器须在构造前完成客户端认证与协议握手，并分配递增的 activation epoch；适配器拒绝错误客户端、未聚焦、过期代次、非法请求 ID 和长度。新的激活代次先取消旧组合。键结果携带 client/epoch/request 元数据，供后续回复队列在发送前再次验证所有权，不能绕过路由检查直接发给当前任意客户端。

输入文本使用 TSF 已按当前键盘布局转换的 wch，不在 Server 重跑 ToUnicode，不用 TSF 的 pinyin_string 覆盖 Engine 组合状态。数字小键盘交给共享数字选词，UiLess 标志不当作修饰键；既有 TSF 的 Shift/Escape 本地消费通知只取消后端，不生成按键回复。共享候选代次和配置延迟应用接口直接复用，不复制其规则。

## 本地验证

依赖 CMake 3.25+、C++17、nlohmann-json 3.11+ 以及为运行平台构建的 msime-host-api。下面测试驱动真实共享 Rust/C++ 库；在 macOS/Linux 运行不等于 Windows 宿主验收：

```sh
cargo build -p msime-host-api --locked
cmake -S platforms/windows -B target/windows-boundary -DMSIME_HOST_LIBRARY=/absolute/path/to/libmsime_host_api.dylib
cmake --build target/windows-boundary
ctest --test-dir target/windows-boundary --output-on-failure
target/windows-boundary/windows-session-smoke /absolute/verified-resources
```

Windows 构建时 MSIME_HOST_LIBRARY 应指定同架构 Rust DLL 的导入库，运行时需可找到对应 DLL；Linux 本机边界测试使用 .so。MSVC 工程配置已提供，但本阶段未在 Windows 上构建或执行，不能拿 MinGW 对象编译代替它。

`bash platforms/windows/tests/check-cross.sh /absolute/nlohmann-include-root` 使用 x86_64/i686 MinGW 分别编译适配器、测试源和固定上游 IPC 契约，验证 32/64 位 COFF 和 Windows SDK 键码断言；另将不依赖 Rust 的编码测试链接为 Windows PE。不会链接 Windows Rust 库，也不执行 Windows 二进制。会话测试覆盖真实 Unicode 输入、锁定词库第二页数字选词、配置延迟、客户端/焦点/线程拒绝及本地取消不回复。

## 旧协议回复编码

`ReplyCodec` 直接构造上游定义的 Normal、CommitExactText、Preedit、NavigationIgnored、NeedToCreateWord 和 UiLessComposition。Normal 用于既有候选完成路径，CommitExactText 表示无需 DLL 再补标点的完整提交，不能将两者无条件互换。分段格式为 remaining-raw、整个已选前缀、显示预编辑，以 tab 分隔；UILess 为显示预编辑、逗号分隔当前候选页、页内高亮序号，以 tab 分隔。候选包含协议分隔符时明确报错，不伪造转义或静默删除候选。

UTF-8 严格转换为 UTF-16，拒绝过长编码、孤立代理、超范围标量和嵌入 NUL；按既有 199 个 UTF-16 单元容量检查，非 BMP 字符计两个单元，不截断。`wire_bytes` 显式按小端写入协议成员和零填充字节，发送方不直接发送 C++ 结构体内存。失败结果不能生成可发送字节。macOS 本地编码测试覆盖精确布局、字节序、代理对、尾部清零、长度边界、坏编码和字段歧义；真实共享会话的完整提交也接到编码器测试。

编码器只负责已选定语义的表示，不自动决定每个 TSF 输入路径应读取何种回复，也不维护分段输入状态。

## 分段回复编排与发送确认

`ReplyComposer` 按已认证 client/activation 创建，将共享运行时的增量选词结果累积为旧 DLL 需要的整个已选前缀。该前缀只是旧协议尚未上屏的展示状态；输入字符、剩余拼音和候选选择仍归 Engine。Selection 路径在有剩余输入时生成 NeedToCreateWord，全部完成后生成含完整前缀的 Normal；Punctuation 路径发送完整 CommitExactText，预编辑/UILess 路径在显示文本前保留已选前缀。

正常按键通过 `dispatch` 进入共享会话，它在推进 Engine 前检查上一条回复是否仍待确认。`stage` 保存原始 KeyResult、待发送帧和下一前缀；完整写入后才调用 `confirm_delivery` 更新前缀。写入失败或结果不确定时保留 pending，不得再次执行原始输入，也不能在未确认是否已送达时盲目重发。编码失败保留原始提交，并禁止成功确认；失焦或明确的传输取消才调用 cancel 丢弃旧路由状态。发送端仍须在实际写入前检查最新路由所有者，局部的确认元数据匹配不能替代该检查。

旧 TSF 的 Enter 本地完成不应收到第二次上屏帧。LocalCommit 要求调用方提供实际本地完成文本，与前缀加共享提交匹配后才允许无帧确认；缺失或不匹配保留错误结果。LocalCancel 清除前缀而不回复，NoReply 保留未完成前缀。每个 TSF 路径选择何种 ReplyPath 仍由后续原生分发接入决定，不能单凭 VK 数字判断选词，例如 Unicode 模式数字仍是编辑。

本机三项 CTest 和真实固定词库回归通过。真实 nihao 会话先选“你”产生剩余输入和 NeedToCreateWord，再选“好”产生唯一完整 Normal“你好”；测试还验证待确认时再次 dispatch 不推进 Engine。独立编排测试覆盖多段前缀、标点、UILess、Enter 文本一致性、取消、错误确认与超长结果保留。仍未执行 Windows Named Pipe 或 TSF 编辑器端到端测试。

## 下一步

继续 Windows 的原生回复路径选择、生产 Named Pipe、协议握手与路由接入，以及实际 TSF DLL 消费、断管恢复和 x86/x64 编辑器验证。当前 `KeyResult.transition` 是内部共享结果，不是新的 IPC 线格式；不能将 JSON 直接发送给现有 DLL，也未完成全部输入路径的端到端回复映射。候选 HWND、设置自动重读、打包和安装同样未完成，不替换旧产品。CI 保持关闭，Windows 优先于 macOS、iOS、Linux。

## 管道 I/O 与进程身份绑定

`PipeIo` 在工作线程执行固定帧消息读写，连接须由调用者保证为 overlapped、消息读取和 PIPE_WAIT 模式，且不能并发关闭或重新连接。短帧、超长帧、断连、超时和取消均不产出可用输入帧；取消后等待 I/O 完成再释放缓冲区。未成功的已提交写入可能已经影响对端，不得自动重发；失败连接须关闭，避免残余消息污染下一帧。

`PipePeer::bind` 仅接收服务端管道句柄，读取系统提供的客户端 PID 和登录会话，验证 client_id 的高 32 位、当前 Server 登录会话及进程 TokenUser 的账户 SID。查询或进程访问失败直接拒绝，不降级放行、不请求调试权限。成功后保留不可继承的进程句柄；`matches` 检查完整 client_id、绑定进程是否仍存活以及主/反向管道 PID 和会话是否相符，避免已经建立的绑定在原进程退出后转到复用 PID 的其他进程。

调用方必须先配置正确的生产 DACL 与 PIPE_REJECT_REMOTE_CLIENTS，在客户端存活时完成绑定，并在路由/端点生命周期保护下进行复核。进程绑定不证明同进程中的具体线程，不检查程序签名，不替代协议版本协商、管道角色、registration/activation epoch 或输入焦点授权，也不消除复核后进程立即退出的可能。受保护进程、UAC 提升进程、AppContainer 及不同会话的兼容性仍需 Windows 原生实测；不能为了兼容直接跳过拒绝检查。

Windows 原生独立测试入口：`cmake -S platforms/windows -B target/windows-pipe -DMSIME_WINDOWS_PIPE_ONLY=ON`，随后 `cmake --build target/windows-pipe --config Debug` 与 `ctest --test-dir target/windows-pipe -C Debug --output-on-failure`。不需要 Rust 库，也不注册输入法。当前只完成 x86/x64 交叉链接；新增帧 I/O 和身份绑定测试未在 Windows 执行，跨账户、跨会话、进程退出/PID 复用及实际 TSF 验收仍待执行。

键码依据 [Microsoft Virtual-Key Codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes)，线格式直接包含 vendor/MSIME-Engine/contracts，不另造 opcode 或改协议能力声明。

## 主连接与反向端点握手

`accept_reverse` 按固定大小读取 FanyImePipeHello、检查监听端预期角色并绑定真实进程，发送该角色专属的 PipeReady 后才返回 Ready 和进程绑定。回复端点是 416 字节，worker 端点是 404 字节；确认帧显式写字段并清零填充，不发送 C++ 内存填充区。此函数不修改全局注册表，调用者只能在成功后发布端点，失败需关闭端点。

`accept_main` 依赖已经 Ready 的 ToTsf 回复端点及其进程绑定，读取主连接 ClientHello、复用固定 Engine 的 Negotiate，再次复核两条端点身份后，经回复端点发送 ProtocolReady 或 ProtocolMismatch。旧版 unversioned hello 不额外发送协议确认；非法客户端或无法表示的请求 ID 不发送确认。只有 HandshakeStatus::Ready 可进入下一注册步骤，单独的 negotiation.accepted 或 io.complete() 不代表握手成功。能力位必须由已实现的分发层显式提供，没有默认启用语音或字符集快捷键。

两函数仅用于 I/O 工作线程，超时按每次 I/O 计算；调用方须保证借用句柄有效，在握手期间排除同端点的其他写入、关闭与替换，并把返回结果绑定到同一 registration generation。这里不建立路由注册表，也不赋予焦点所有权。主握手传入的回复管道必须确实是已注册 ToTsf 而不是 worker，不能只因 PID 相同就任意替换；生产注册器仍待接入。测试覆盖编码字节、两类 PipeReady、版本协商、未实现的必需能力拒绝、旧握手无 ACK、错误客户端/角色及预取消；编码测试已本机执行，管道握手测试仅交叉编译，尚未 Windows 运行验收。
