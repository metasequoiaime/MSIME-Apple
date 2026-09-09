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

继续 Windows 的原生回复路径选择、生产 Server 对监听/握手的装配与注册路由接入，以及实际 TSF DLL 消费、断管恢复和 x86/x64 编辑器验证。当前 `KeyResult.transition` 是内部共享结果，不是新的 IPC 线格式；不能将 JSON 直接发送给现有 DLL，也未完成全部输入路径的端到端回复映射。候选 HWND、设置自动重读、打包和安装同样未完成，不替换旧产品。CI 保持关闭，Windows 优先于 macOS、iOS、Linux。

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

## 安全监听与连接所有权

`PipeListener::create` 仅接受本机管道名，从当前进程 TokenUser 构造受保护 DACL：当前账户与 LocalSystem 完全访问，AppContainer 只有上游定义的 0x12019b 连接权限，不包含创建管道实例权限；保留低完整性标签，并设置 PIPE_REJECT_REMOTE_CLIENTS。账户获取失败不降级为默认 ACL。当前账户仍是信任边界，这不是对同账户恶意进程的完整隔离，也不能据此宣称跨会话/UWP 可用。

首次创建带 FILE_FLAG_FIRST_PIPE_INSTANCE，名字已占用时明确失败；不终止旧 Server 或夺取既有产品管道。监听器保留待连接实例，accept 成功后先创建替代实例，再返回独占 RAII PipeConnection，避免全部业务连接关闭导致名字失去持有者。返回连接保持 overlapped、消息读取和 PIPE_WAIT 模式，32 KiB 双向缓冲区为内核提示值，不是无限队列；Server 后续还必须设置连接数量和工作队列上限。

accept 只在单一监听工作线程调用，使用手动事件等待连接，处理客户端先连入的 ERROR_PIPE_CONNECTED。超时/取消会取消并等待操作完成，再断开可能竞态连入的客户端，保留句柄供下次监听；它不是硬性返回时限。析构前须停止 accept，并保证连接没有未完成的借用 I/O。连接成功不等于可信客户端，仍必须经过握手、进程绑定与注册代次检查。

原生测试使用唯一测试名称调用实际监听器，覆盖预连接和异步连接、超时/取消后的恢复、重复名字拒绝、连接保留名字、句柄不可继承及内核 DACL 的 AppContainer 权限和无 Everyone ACE。现有帧、身份与握手用例也改用同一监听器；目前仅通过 x86/x64 编译链接，没有执行 Windows 测试、创建生产管道名、安装或 TSF 注册。

## 有界端点注册与传输票据

`PipeRegistry` 接管 PipeConnection 所有权，按客户端保存主、回复和 worker 三条连接。反向端点握手后才能登记；主入口接收 intake 工作线程已按精确帧读取的 ClientHello，核对主/回复/worker 的进程身份，并在该客户端锁内执行协议确认和发布。握手前不允许普通发送，失败不会保留可用于输入的主注册。独立客户端不共用长时间 I/O 锁；同客户端写入与端点替换串行化。

PipeTicket 保存三条端点的不可复用注册代次；发送须匹配完整票据，清理只删除指定角色的匹配代次。反向端点变化使主注册失效，必须重新主握手；旧任务不能发往替代连接，也不能通过过期清理关闭替代连接。主读取持有共享端点引用但不占用客户端锁，移除/重连发出取消信号；I/O 完成后再验证注册与身份，旧帧不返回给调用方。写入失败停用该发送端点与主注册，不自动重试。

容量限制针对已登记客户端数量；握手尚未识别 client_id 时由外部 intake 保有连接，因此 Server 仍须限制待握手连接和工作线程。verify_reverse 只验证身份并返回 Verified，不发送成功确认；注册器先检查容量和代次，再在客户端锁内发送 PipeReady 并发布端点，避免客户端收到确认后主连接却查不到登记的竞态。容量不足或过旧的并发注册直接关闭，不发成功确认。没有默认后台线程或全局 Server。shutdown 先停止新登记并取消已登记读取；外部握手使用调用方取消事件，调用方必须停止 intake、取消握手、等待所有 I/O 工作线程退出后再析构注册器。

这里的 Ready 和票据只证明传输登记，不授予输入焦点，也不确认客户端已经处理上屏。进入 Engine 队列和发送前的 activation/focus 校验、FocusSessionReady、ReplyComposer 确认及真实 TSF 生命周期仍需接入。原生测试连通监听→反向注册→主协商→注册器读写，覆盖未主握手禁止发送、代次错配、重连取消待读取、旧发送/旧清理拒绝、容量耗尽与回收；目前仅 x86/x64 编译链接通过，未 Windows 运行。

## 有界握手工作池

`PipeIntake` 取得监听连接的所有权，使用固定 1–32 个线程及 1–1024 个等待槽位，由调用方选定。队满、角色非法或停止后直接拒绝并关闭新连接；池内未完成连接最多为等待容量加线程数，监听实例和 Registry 已登记连接另计。不为每个连接新建线程，也不在握手线程长期运行主管道输入循环。

主 hello 精确读取后交给 Registry，反向端点按角色登记。完成回调必须短且非阻塞，将结果放入下游有界队列；返回 false 或抛错时，池按代次撤销未交付登记，不误删替代端点。统计只含数量，不记录输入、帧或异常正文。控制线程 stop 会停止接收、清空队列、取消握手并 join；stop 返回后没有回调，已开始的回调可能在 join 期间结束，因此依赖须保持存活，禁止在回调内 stop 或析构池。

停止 intake 不删除已成功交给下游的登记。Server 关闭时应先停止监听和 intake，再取消 Registry I/O、等待输入线程退出后析构 Registry。超时/取消需等待实际 I/O 完成，不承诺硬性返回时限。原生测试覆盖静默客户端、队列饱和、停止清理、三角色投递及回调拒收/异常；目前仅通过 x86/x64 编译链接，尚未 Windows 运行，也尚未装配生产监听循环、焦点状态机或 Engine 队列。

## 三角色传输服务装配

`PipeService` 拥有 Registry、一个有界 PipeIntake 和三条独立监听线程。调用方显式提供 Main/ToTsf/worker 名称与已实现能力位，不会默认发布产品管道名。启动时先验证工作池配置并建立监听器，任一步失败都会取消并等待已启动的线程、释放已取得的管道，不接管占用名。回调依赖必须在构造前准备好，监听线程开始工作后即可触发回调。

各监听循环把连接所有权交给同一有界池，队满连接由池关闭。空闲超时和客户端在 accept 前断开可恢复，不可恢复错误仅保存首个 Win32 错误码并 request_stop 全部监听和握手；控制线程观察 failure 后调用 stop 完成 join 和回收。request_stop 不等待，可从完成回调请求停止；stop/析构只能由控制线程调用，不能在完成回调内等待自身退出。

stop 幂等地停止监听、等待握手池、shutdown Registry 并释放监听器。若外部线程使用 registry() 读取输入，stop 会取消其注册 I/O，但外部线程仍须 join 后才能析构整个服务。客户端仍持有旧句柄时，旧管道名可能仍占用，重启仍按首次创建规则失败，不绕过占用保护。

原生测试不手动调用 accept/submit，而用三条实际监听连接完成反向确认和主协商；另外覆盖重复启停、幂等 stop、第三个名称占用导致启动失败及前两个名称回收。x86/x64 编译链接通过，未在 Windows 执行。此类仍是传输服务库，不是已启动的生产 Server，也没有接入焦点状态机、Engine 输入队列、TSF 安装或系统编辑器验收。

## 主管道空闲等待

已登记主管道的 `read_main(ticket)` 默认通过 `read_frame_until_cancel` 等待输入，不因用户空闲而按固定时间注销主注册。这个入口必须带有效取消事件，重连、移除及 Registry shutdown 会发出取消并等待 I/O 完成；握手 `read_frame` 和所有写入仍拒绝无限超时。显式指定有限 read_main 超时只用于诊断，超时后仍弃用该连接，避免取消竞态下丢失的消息被当成下一帧。

新增原生测试覆盖空闲等待后正常读取、重连取消长期待读取、直接取消，以及禁止无取消事件长期读取和无限握手/写入；测试清理也主动取消，避免断言失败时 future 析构无限等待。当前仅交叉编译通过，尚未 Windows 运行验证。

## Worker 焦点确认编码

`focus_ready_bytes` 生成固定上游 FocusSessionReady worker 帧，将 TSF 激活请求的非零 focus token 以无区域设置影响的十进制 UTF-16 编码；支持完整 uint64 范围，拒绝零标记，保留终止符并清零全部剩余字节。这个字段不是 Server 的 activation epoch，也不是传输注册代次。调用者仍须确认当前焦点、client/activation/注册所有权，并保证确认先于后续 worker 输出；编码函数不授予焦点，也不自动激活 Engine。

本机编码测试验证零拒绝、跨 32 位值和 uint64 最大值的精确字节；原生注册器测试增加真实 worker 路由发送与完整帧读取，但仅交叉编译，未 Windows 实测。焦点激活状态机仍是下一步接入工作。
