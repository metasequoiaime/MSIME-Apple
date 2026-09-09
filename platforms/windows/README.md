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

PreviousCandidate/NextCandidate/PreviousPage/NextPage 路径消费共享导航结果：普通模式发送 Engine 契约中的对应导航 opcode 和空文本，即使已在边界也保留导航意图；UILess 返回共享视图的完整候选页及高亮。导航不清除已选前缀、不允许夹带 commit，确认前仍禁止下一次 Engine 操作。配置驱动的导航键分类仍由后续原生策略接入，本层不复制分页算法。

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

## 激活确认门禁

`FocusGate` 保存一个当前 FocusLease，分别携带完整传输票据、Server 单调 activation epoch 和 TSF focus token。begin 返回旧 lease 与新 pending lease，供输入队列取消旧组合并激活新会话；它本身不操作 Engine。只有 acknowledge 的 worker 写入回调完整成功才进入 ready，失败或异常清除该激活；过期确认和重复确认不会执行写入回调。

with_active 在同一焦点锁内验证并执行动作，避免检查后焦点已切换却继续发送；动作须短或有界，不得递归调用该门禁。涉及管道时锁顺序固定为 FocusGate → PipeRegistry，注册器仍在写入时核对传输代次；不能只凭 focus lease 绕过注册验证。旧 lease 的 deactivate 和旧票据的 invalidate 不影响新激活。已确认激活仍不证明应用实际插入了文本，ReplyComposer 投递确认保持独立。

这只是状态与同步机制，不会从任意状态通知推断系统焦点。可信 ClientActivated、KeyEvent、FocusRestored、挂起与停用的事件路由策略，以及旧/新 ServerSession 的输入队列切换仍由后续分发器接入。系统焦点事件未接入前，不能仅调用 begin 就宣称完成焦点授权。

本机新增 windows-focus-gate 测试，验证 pending/ready、坏票据、旧确认、失败/异常、失焦失效与并发动作互斥；连同原有三项 CTest 共四项通过。原生管道测试把门禁组合到 worker 焦点确认和回复发送，并在重连后失效旧 lease；x86/x64 编译链接通过，未 Windows 实测。

## 焦点约束的输入队列会话

`FocusedSession` 为一个已登记客户端组合 ServerSession、ReplyComposer 与 FocusGate，全部方法必须在创建它的输入队列线程执行。控制器先 begin 新 lease，再在队列 prepare：只有当前 pending 激活能准备 Engine，新的 epoch 会取消旧组合并替换旧回复编排；准备成功后才把 worker 焦点确认交给 I/O 线程。适配器不执行管道 I/O，也不自行判断 OS 焦点。

key 必须匹配已准备的完整 lease，并在 with_active 内调用真实 Engine；确认前或过期任务返回空结果，不推进 Engine。ReplyComposer 的待回复门禁继续阻止重复执行。返回的 PendingReply 是独立副本，供 I/O 队列处理；复制/传输失败时可通过 pending 取回暂存结果而不重跑输入，但这不是不确定投递的重发许可。成功写入或已核实本地处理后，confirm 回到输入队列并重新检查 lease；旧确认不能推进新会话前缀。

cancel 只清理匹配 lease 的 Engine/编排状态，即使全局焦点已切走也可清理旧客户端，不会清掉新激活。控制器仍负责将 FocusChange.previous 的取消发送给旧客户端队列；不能只准备新客户端而遗漏旧组合。ReplyPath 与本地完成文本由实际 TSF 路径显式提供，候选点击、配置文件监听及生命周期事件策略尚未装配到这一适配器。

本机测试调用真实 Rust/C++ 会话验证 Unicode 提交结果与编码、确认前阻止输入、待回复时不重跑 Engine、暂存结果读取、过期输入/确认拒绝、新激活清空旧组合、过期取消与线程拒绝。焦点写入完成使用测试回调，未执行系统上屏或 Windows 端到端链路；x86/x64 仅编译适配器对象，独立原生管道测试仍未 Windows 运行。

FocusedSession 的 update_preferences 同样检查完整 lease 与队列线程；回复待确认时返回空结果，不修改 Engine，调用方应在确认后重试最新配置快照。没有待确认回复时直接复用共享层的版本与组词延迟规则，不在 Windows 重写它们。本机实际会话测试覆盖待回复拒绝、组词中 deferred、提交后应用和旧焦点拒绝；文件监控及队列重试调度仍由后续控制器接入。

### Main 消息进入控制器前的校验

PipeRegistry::read_main 在返回完整帧前复核 packet.client_id 与登记客户端一致，并通过 MainFrame 校验已知 Main 事件、pinyin 长度及终止符、状态快照字段和非零激活 token。Aux 专用事件和未知 opcode 不进入分发；key 同时拒绝零与 NO_REQUEST_ID，激活 token 则允许完整 uint64 范围。失败返回 MalformedFrame 且不携带原始帧，注销匹配主注册，旧票据不可继续发送。重复 ClientHello 保留为后续控制器忽略的兼容事件，不重协商；这一校验不证明前台焦点，也不取代 lease 检查。

字段规则依据 MSIME-Windows develop 固定提交 6e03f5774777e40c921930fd90a76e5425c66d89 的 Main 接收路径，key 的 NO_REQUEST_ID 限制与本仓 ServerSession 一致。纯测试可本机执行；真实管道测试另覆盖同进程伪造 client_id、越界长度与 Aux 事件导致连接弃用，仍需 Windows 执行验收。

### 生命周期路由策略

FocusRouter 在单一控制/输入队列上管理有界登记表，并作为 FocusGate 唯一的激活策略写入方。connected 只接收 Registry 已协商且仍有效的完整 ticket；消费登记通知时仍须复核 Registry，不能重新加入已注销后迟到的登记。重复登记无操作，旧代次不能覆盖现存新链。disconnected/failed 返回精确 cleanup lease，旧连接或旧激活不能清掉新链；关闭时先断开登记、处理清理，再销毁队列和会话。

dispatch 按各 Main 流原始顺序处理消息。显式激活引入非零 token；同一当前 token 不重置 Engine，新 token 或其他客户端激活产生新 epoch。被挤走客户端只有已完成 worker 确认的 token 可用于 KeyEvent/FocusRestored 恢复；key request_id 从不冒充 token。StatusSnapshot 和候选窗/模式消息不抢焦点。当前客户端挂起清除恢复 token，之后必须显式激活；终止事件可获取挂起时的精确清理身份。后台挂起不改变前台归属，后台终止清理也不是隐藏新客户端工具栏的授权。策略依据固定上游 6e03f5774777e40c921930fd90a76e5425c66d89 的激活与失活路径。

FocusRoute.activation 表示新激活：先将 cleanup 交给旧 FocusedSession.cancel，再 prepare 新会话，I/O worker 经 gate.acknowledge 写焦点 fence；成功通知回到控制队列后调用 confirmed，再执行输入。fence 表示上游要求确认标记：pending 路由等待已安排的确认，不重复 acknowledge；ready 路由重发标记通过 gate.with_active 和 Registry 票据检查。准备、确认或发送失败调用 failed 并处理 cleanup，不能重放不确定写入。gate 切换时原子记录 previous_ready，避免遗漏已成功确认但通知尚未处理的 token。route 可能仍为 pending，不是立即执行 Engine 的授权，实际执行与发送仍复核 gate。

本机测试覆盖策略状态和真实 FocusedSession 跨客户端组合清理；Windows 管道测试已串入路由、worker 确认与回复发送，但未原生运行。专用队列见下节，可执行控制器仍未装配，未接管系统焦点或注册 TSF。

### 专用输入线程与有界任务队列

InputQueue 的单一 worker 拥有 InputState、FocusRouter 和各客户端 FocusedSession，包含创建和销毁；从不把 Rust 线程局部会话迁移给管道 worker。InputState.connected 创建或更新登记会话，dispatch 自动执行旧 lease 清理和新 lease 准备，disconnected/failed 自动清理匹配会话。后续输入、回复确认和配置快照通过 key、delivered、update_preferences 进入同一线程；confirmed 只记录外部 I/O worker 已成功写出的焦点确认。key 前仍需 dispatch 得到正确路由；ReplyPath 由原生控制器提供，不能仅靠 VK 推断。

submit 非阻塞接纳任务，容量 1–4096 限制等待任务数，客户端容量 1–1024；捕获数据大小仍由控制器限制。满队列、停机或空任务返回空结果，调用方必须撤销相应传输/焦点，不能静默丢键或在 I/O worker 直接执行 Engine。每个已接纳任务都有 Completed/Failed/Cancelled future；Completed 只表示回调正常返回，不表示消息被接受、输入已上屏或网络发送成功。实际结果必须按任务返回的数据和会话接口判断。回调不得做管道 I/O、等待队列 future、保留 InputState/会话引用，或捕获可能过期的管道缓冲区；控制器应复制已验证的有界数据。

request_stop 可从回调调用，不 join；stop 由外部控制线程调用，等待当前短任务结束，取消未执行任务并结算 future，在原 worker 撤销路由和销毁全部会话。任务异常先清理全部会话、停止接纳，再返回 Failed，其余任务得到 Cancelled，不传播原始诊断。禁止在 worker 调用 stop 或销毁队列；对同一队列的并发外部 stop 会串行 join。Gate 及回调依赖必须活到 stop 返回，产品停机还应先停止外部发送/接纳，不能在队列结束后继续调度 I/O。

本机测试执行专用线程真实 Unicode 提交、焦点切换和停机销毁，另验证多生产者顺序、满队列、取消、异常和自 join 拒绝。仍需原生控制器把 PipeService 接纳、读取、焦点确认、回复发送及失败回执串接到此队列，包含逐客户端等待与配置重试；这不是已经可安装的 Windows 输入法。

### 已登记 Main 连接处理循环

SessionPump 在外部 I/O worker 运行一个完整 ticket 的消息循环，通过 MainTransport 接口连接实际 PipeMainTransport/PipeRegistry。登记通知消费时检查 current，再在 InputQueue 创建会话；每条 Main 消息经过路由与 prepare、worker 焦点确认、队列确认、Engine 输入、回复发送、队列回执之后才读下一条。队列任务复制单帧数据，管道读取和写入都在外部 worker；禁止从输入队列调用 run，入口会拒绝自等待。

PipeMainTransport 的 read 复用 Registry 的可取消空闲等待与消息校验；send 要求显式有限超时，仅完整成功返回 true。is_current 只是登记快照，不证明进程存活或焦点；实际读写继续复核身份/代次，发送同时经过 FocusGate。正常焦点切换导致的过期任务和输出被丢弃，不视为连接故障；确实尝试但失败的写入、无法编码的回复、身份/请求不匹配的分发结果和队列故障终止循环，不重放输入或不确定写入。重复 hello 无操作。退出撤销匹配焦点与主注册，并在队列清理会话；若连清理也无法入队，停止共享输入队列，宿主还必须停止其他管道循环。

KeyHandler 在输入队列上使用真实 TSF 模式/消费路径选择 ReplyPath，并且只调用一次 state.key；测试里的 Unicode 专用分发不是生产 VK 推断器。EventHandler 必须显式提供，用于发布携带 lease 的模式/候选 UI 工作；有活动 route 时回调处于焦点锁内，不得重入 gate、调用 Engine 或执行 I/O。清理类通知没有新前台授权，不得隐藏其他客户端 UI；异步消费者仍须检查 lease。无编码帧的返回只能表示 ReplyComposer 已验证的本地完成或无回复路径，不能拿它绕过待回复门禁。

本机确定性传输测试运行同一个 SessionPump 和真实 Rust/C++ 输入线程，验证 Unicode 完整回复、确认顺序、失败不重放、错误路由拒绝、旧焦点输出丢弃、重复 hello 和自等待拒绝。Windows 原生管道测试使用实际 PipeMainTransport 检查读写与旧 ticket 关闭不影响新登记；尚未在 Windows 运行，也尚未把 Windows Rust 与真实管道完整链接验收。剩余原生控制器负责有界 worker 生命周期、接纳回调、取消/join、实际 KeyHandler/EventHandler、模式输出和配置重试；目前不启动生产管道。

### 有界连接工作线程

SessionWorkers 为 1–64 个固定连接槽位预建 I/O worker，每槽最多一个活动 SessionPump 和一个待替换 ticket。重复完整票据不会启动第二个读取者；同客户端重连取消旧读取并覆盖待替换票据，旧循环完成队列清理后原线程接替新连接。不同客户端超过槽位容量、旧代次或停机后提交会被拒绝并关闭匹配主注册，不按每次重连无限创建线程。

submit 供外部控制线程消费已协商的登记通知，先检查 MainTransport.current；取消可能等待有限时间的在途写入，不得直接放进要求非阻塞的 PipeIntake 回调或输入/gate 回调。原生控制器还需提供有界登记通知入口。request_stop 标记停止、关闭活动和待替换票据以取消读取；stop 从外部线程串行 join，不能从输入队列或自身 worker 调用。依赖的传输、Gate、输入队列和处理器须活到 stop 返回；正常退出顺序是停止接纳、取消/join 连接循环、停止输入队列，再释放传输服务。输入队列故障被循环观察到时会停止其余槽位；全部连接空闲时仍需宿主监控输入队列/服务状态并主动取消，不能依靠空闲读取自行发现故障。

本机测试组合实际 SessionWorkers、SessionPump、InputQueue 和真实会话，使用可取消的空闲传输验证并发读取上限、重复登记、容量拒绝、重连线程复用、连续替换合并、旧关闭隔离与并发 stop。仍未执行 Windows 原生组合，也未完成服务启动装配、实际 TSF/UI 处理器与安装验收。

### 原生服务装配与故障监控

WindowsServer 现在组合 RegistrationInbox、PipeService、PipeMainTransport 和 SessionController。构造需要显式管道名、能力掩码、共享宿主选项及 KeyHandler/EventHandler，会真正启动指定名称的管道，但不注册 TSF 或修改输入源；本阶段未启动生产名称。登记收件箱先于监听器构造，Main 握手通知只复制 ticket 入有界队列，满队列/关闭返回 false，由 PipeIntake 注销匹配登记；反向管道就绪不启动 Main 读取。构造失败时按成员依赖顺序释放已启动资源。

SessionController 持有输入队列、连接 worker 和独立控制线程，消费登记通知时由管理器再次验证票据。无通知时默认每 100ms 检查服务、输入队列和连接管理器状态，因此全部客户端空闲也能触发故障退出。request_stop 只置位并关闭/唤醒收件箱，可从输入回调调用；实际取消与 join 留给控制线程：停止服务接纳和握手、关闭 Registry 端点、join 连接循环，再停止输入队列。stop 由外部调用并等待整个顺序结束，禁止从自身控制线程或输入线程 join。故障仅暴露分类，不记录原始异常、输入或路径。

WindowsServer 的回调可能在构造返回前运行，捕获依赖须事先初始化，不能访问尚未构造完成的 server。通用 SessionController 的 healthy/stop_service 回调在控制线程运行；stop_service 必须关闭所有登记端点（包括尚未消费的收件箱票据）并等待服务线程结束，服务和收件箱须活到 controller 停止之后。

本机测试增加有界登记队列、空闲时服务故障、输入异常全局停机，以及持有焦点锁的事件回调请求退出。原生 windows-server-smoke 使用唯一测试名称运行实际 WindowsServer，发送反向握手、Main 协商、激活及 Unicode 输入，并验证完整提交和空闲停机；测试源码已提供，尚未在 Windows 执行。Windows 上需完整同架构 Rust 导入库构建（不能用 MSIME_WINDOWS_PIPE_ONLY），再运行 `ctest --test-dir target/windows-boundary -C Debug -R windows-server --output-on-failure`。固定 Unicode 测试处理器不代表真实 TSF 模式/候选 UI 已实现，产品分发、设置/模式同步、原生链接与 TSF 编辑控件验收仍待完成。

### Windows GNU 完整链接构建

`bash platforms/windows/build-cross.sh x64` 在已具备 Git、MinGW、Rust、CMake 的主机上准备固定 vcpkg、安装锁定依赖，构建真实 Rust/C++ 宿主 DLL，再链接全部 Windows 原生测试（包含 windows-server-smoke.exe）。vcpkg 固定 ef7dbf94b9198bc58f45951adcf1f041fcbc5ea0；默认使用 target/tooling/vcpkg，缺失时由 bootstrap-vcpkg.sh 从官方仓库获取固定提交并关闭指标收集进行 bootstrap。会访问网络下载工具与依赖。也可设置绝对 MSIME_VCPKG_ROOT，显式提供的目录必须已准备好，脚本不重置或自动修复它。脚本会安装相应 Rust 标准库和清单依赖，依赖安装根按架构隔离，避免 vcpkg 切换 triplet 时移除另一架构的库；同一 vcpkg checkout 不并发执行。GNU 桥接通过 MSIME_WINDOWS_DEPS 指向同架构依赖前缀，禁止 CMake 搜索主机库；Windows 补链 UUID 库以解析 Engine 的已知文件夹标识。

bootstrap 只管理默认工具缓存，已有错误版本、跟踪文件改动、符号链接或非预期目录均拒绝，不覆盖用户内容。目录锁拒绝并发准备；失败的独立 staging 目录保留供检查，不递归删除。若遗留锁，先确认原进程已结束再清理空锁目录。可单独执行 `bash platforms/windows/bootstrap-vcpkg.sh`，已有固定版本且可执行时复用；离线拒绝路径测试为 `bash platforms/windows/tests/bootstrap-vcpkg.sh`，测试只操作新建的隔离目录。本机 x86 SJLJ 工具链会在网络准备前被拒绝。

本机已完成 x64 宿主 DLL、会话测试及完整原生管道集成测试的 PE32+ 链接，产物位于 target/windows-full/x64。脚本只复制宿主 DLL，不打包 MinGW 运行时 DLL，运行前还需同工具链的 libstdc++、libgcc 和 libwinpthread 及系统运行时；这不是安装包或运行验收。x86 完整链接在当前 Homebrew SJLJ MinGW 下失败（Rust 展开符号缺失），脚本提前拒绝该组合；不能通过 panic=abort 改变既有错误隔离契约。x86 的既有 C++ 对象检查仍通过，但完整 Rust 链接须匹配异常展开工具链后重验。MSVC 构建和 Windows 实机 TSF 验收仍未执行。

### 本地原生测试目录

完整 x64 构建后运行 `bash platforms/windows/stage-runtime.sh x64`，脚本从同一 MinGW 工具链定位 libstdc++、libgcc、libwinpthread，复制到 target/windows-full/x64，并逐项检查测试 EXE、宿主 DLL 和递归运行时导入的架构。未分类依赖或缺失运行时立即失败，不从网络或任意系统目录猜 DLL；工具链的额外运行时目录可显式通过 MSIME_MINGW_RUNTIME_DIR 提供。该目录仅用于本地验证，不是带完整许可证/源码交付的发布包，不得据此发布产品。

可将验证目录复制到匹配的 Windows 测试机，在其中运行 `powershell -File .\run-smoke.ps1`。脚本预检十个固定测试程序，逐个执行并限制超时，失败立即停止；不要求 CMake，也不注册 TSF 或修改输入源。仅运行隔离临时目录/唯一管道名的合成测试，不等价于真实编辑器验收。本机只验证目录依赖及构建，PowerShell 脚本和 Windows 二进制尚未实际执行。原生集成测试与本机回归共用完整测试配置，避免遗漏共享宿主必需字段。

### 配置投递后的自动重试

`InputState::queue_preferences(lease, snapshot)` 供设置通知在输入队列中提交最新快照。无待回复时直接交给共享宿主；有待回复时每个活动会话最多保存一份 16 KiB 以内的快照，较新 revision 替换旧值，相同内容幂等，较旧或同版本冲突拒绝。只有当前焦点的成功投递确认才会自动交付保存的快照，错误确认不能触发；焦点取消和新激活清除尚未交付的旧快照。

返回 true 表示已接纳，不代表设置已生效：平台仅验证大小、格式版本、revision 和对象外形，完整偏好校验及组合期间延迟应用仍归共享宿主。交付失败抛错，输入队列按既有失败路径撤回授权，不能重放已投递的键。调用方应使用共享设置存储产出的有效快照；已有 update_preferences 保留手动接口。

`PreferenceSnapshot::load` 直接调用共享 PreferencesStore 读取/完整校验，可能等待磁盘或文件锁，必须在设置工作线程执行，不得放进输入任务。不可由任意 JSON 直接构造该发布值；加载失败只返回通用异常，不暴露共享错误原文。`InputState::publish_preferences` 接受其副本，保留一份全局最新值，拒绝旧版本/同版本冲突，向当前已确认焦点交付；无焦点时仍保留。新激活及断开重连的新会话在 confirmed 后、按键前自动接收最新值，不因其初始 options 较旧而回退。尚未确认的焦点只等待，不被配置发布授予输入授权。低层单会话更新接口不应与另一套 revision 来源混用。

WindowsServerOptions::preferences_directory 显式启用共享配置轮询，空值表示关闭。SessionController 持有 PreferenceMonitor，默认每 250ms 在单独线程尝试读取；最多一个待完成发布任务，未变化快照不重复入队。锁忙、坏文件、旧版本/同版本冲突与队列满保留旧配置并稍后重试；发布失败或输入队列不可用成为终止故障，不重放输入。preferences_status 暴露分类状态，不包含路径/原始错误；Current 仅表示最新快照已交给队列，不保证正在组合的会话已经应用。

轮询停机使用条件变量唤醒，不等待整个间隔；已提交任务只捕获快照值，不引用监听器，监听器停机不等待输入 future。控制器先请求监听器停止，再停止服务/连接 worker/输入队列，最后 join 设置线程；对象仍保留输入队列到 join 完成。设置线程禁止从输入任务 join，request_stop 可请求退出。初次轮询异步执行，启动仍须提供经过共享准备的 host_options；系统级文件变化通知不是本阶段实现，当前使用轮询。

监听器使用 `PreferenceSnapshot::try_load`：调用新增共享 C ABI msime_client_try_load_preferences，锁竞争返回空值（ok:true,value:null），成功返回完整已校验快照，坏文件/权限错误仍报错。空值只表示忙，保留之前发布值并稍后重试，不能恢复默认配置。底层仍使用同一稳定锁文件及共享验证，没有旁路读 JSON；不会等待写者释放锁，但磁盘 I/O 仍可能阻塞，因此不能在输入队列调用，也不能据此宣称任意存储故障下停机都有时限。宿主库与 Windows 适配器需成套更新到含新符号的版本。

### 显式导航绑定入口

`InputState::navigate(lease, packet, bindings)` 在同一个输入队列/焦点门禁下贯通 FocusedSession、ReplyComposer 和 ServerSession。NavigationBindings 是调用方提供的值快照，分别启用减号等号、逗号句号、方括号、Tab、PageUp/PageDown、上下候选；全部默认关闭，不暗设产品偏好。Tab 根据 Shift 判定方向，UiLess 从原始包读取；Unicode 的 + 仍交给共享字符输入。回复未确认时禁止再导航或输入，失效焦点不会推进 Engine。

该入口必须在 TSF 上下文已排除标点提交、以词定字等优先路径后调用。已消费的导航键即使绑定关闭也返回 PendingReply：普通模式使用 NavigationIgnored，UILess 返回未变的候选页；不调用 Engine command，不改变组合、代次、页码或高亮，仍等待投递确认，禁止再回退旧 VK 映射。返回空只表示非导航键、快捷键、Unicode +、空组合或失效焦点等不适用情况。设置监听和产品 KeyHandler 尚未接入，本接口不证明默认产品行为已完成。

### TSF 中文开关同步

SessionPump 在输入队列内自动处理当前焦点的 IMESwitch、StatusSnapshot 与 FocusRestored，先同步 keycode 表示的中文开关，再调用外部事件回调。关闭时经共享宿主清空 Engine 组合与旧回复前缀；关闭期间迟到按键不再推进 Engine，重新开启从空组合输入。相同状态通知不重复改变 Engine 代次，每个客户端会话保留开关至再次通知；过期焦点不能修改状态，未确认回复阻止切换。外部事件回调仍在焦点锁内，不得重入 Engine/焦点门禁。

这里只连接每客户端键盘开关，不实现上游全局模式作用域或全半角 UI 状态同步；完整产品按键分类与 Windows 原生验收仍未完成。出站模式请求见下文。

### 配置相关按键分流

InputState::configured_key 先执行 basic_key，再在已开启输入且 Engine 模式已知、组合非空时处理候选标点与导航。逗号/句号和方括号按 NavigationBindings 决定是否保留为翻页；OEM 和数字键盘加减键不走候选标点。返回空仍表示未处理，不能直接作为 SessionPump 的最终处理结果。调用方必须先完成以词定字、Microsoft 双拼分号和配置专属快捷键等原生优先规则；空组合标点仍由 TSF 本地处理。本入口不是完整产品 KeyHandler。

新增 ABI 1 附加符号 msime_client_punctuation，适配器与宿主库必须成套更新。它显式复用共享运行时的高亮候选完成与 Engine 标点转换，避免 Unicode 等局部模式把普通 character 调用标记为已处理却未完成标点提交。非 ASCII 标点参数在状态推进前拒绝；普通/UILess 标点完成均发送 CommitExactText，保留已有焦点、待回复与投递确认门禁。

### TSF 标点开关同步

PuncSwitch 的 keycode 与 StatusSnapshot/FocusRestored 的 pinyin_length 同步到当前会话的中文标点开关。经共享 C ABI 调用固定 Engine 的运行时 setter，不重建会话，不改变组合、光标、候选代次或引号配对。待回复和过期焦点仍不能修改状态。TSF 开关是每会话临时覆盖，不写入配置文件，并在共享偏好替换 Engine 时重新应用；未收到覆盖的会话继续使用持久化偏好默认值。

新增 msime_client_set_chinese_punctuation 为 ABI 1 的附加符号，适配器和宿主库须成套更新。其返回值为未变化的 View；关闭时空组合 ASCII 标点由宿主透传，组合中标点仍按共享运行时的完成策略处理。该接口不代表全局作用域或原生产品键路由已完成。

### 发往 TSF 的模式请求

WindowsServer/SessionController::request_mode(lease, mode) 提供中英文、中文/ASCII 标点、全/半角六种命令，线格式使用固定 Engine worker opcode 与清零的 404 字节帧，不支持任意 opcode 或文本。调用方从已确认焦点事件获取 lease，并在外部线程调用；输入/事件/控制回调内调用会拒绝，避免递归焦点锁。有限时写入可能阻塞，不宜直接占用 UI 线程。

发送在焦点锁内核对 lease 与当前连接；失效、未就绪、停机或非法模式返回 Rejected。Sent 只证明完整投递，不证明 TSF 已应用；实际中英文/标点状态经 TSF 回报再进入共享会话，不提前改变 Engine。写入失败或异常返回 WriteFailed，撤销连接焦点并关闭连接，不重发不确定命令。旧线格式不携带服务端 epoch，不能据此宣称 TSF 消费时的端到端确认已实现。模式请求与对象析构仍须由调用者管理生命周期。

固定上游 TSF 的 _HandleCompositionDoubleSingleByte 在编辑会话内转换并上屏全角字符，Server 不重复转换。全半角回报目前交给外部事件回调，候选窗/工具栏显示与产品 UI 尚未接入；此入口没有注册或修改本机输入源。

### 编辑键与 TSF 预编辑回复

InputState::basic_key(lease, packet, style, local_text) 统一基础分发：复用 edit 的预编辑规则，按 Engine 模式识别空格/数字选词，处理 Shift/Esc 本地清理及忽略的修饰键，并将 Enter 交给 LocalCommit 前置校验。原生配置相关优先路径必须先处理；返回空表示尚未处理的快捷键、标点或导航，不清空组合，调用方必须继续其他路径而非把空结果直接交给 SessionPump。Enter 的 local_text 必须来自宿主实际完成观察，不能从 Engine 返回结果拼造。本入口已经用于会话泵回归，但还不是完整产品 KeyHandler。

普通模式的无修饰 1..9 与 Unicode 模式的 Shift+1..9 均按 VK 槽位选择当前共享候选 ID，不依赖 wch；例如非美式布局数字键产生 & 时仍选词，Unicode 裸数字仍编辑。小键盘按同样规则归一化。空候选返回未提交状态，不把布局字符作为替代文本上屏。

LocalCommit 分发先验证该包确为原始文本提交键，且调用方提供的本地完成文本等于已选前缀加 Engine 当前 editing_text，再执行共享提交；缺少文本、内容不符或错误键型抛错，并保留组合和待回复状态。stage 的提交后校验仍保留，调用方不能用 Engine 返回值反过来伪造本地已上屏的证明。拒绝并不能撤回 TSF 已经错误插入的文本，仍需宿主处理协议分歧。

InputState::edit(lease, packet, style) 按 Engine 当前模式判定字母、组合中的手动分隔符、Unicode 裸数字/加号、Backspace/Delete 和左右光标移动，并在同一焦点/待回复门禁中推进会话。非编辑键、快捷键、空组合删除、关闭输入或 unknown 模式返回空，不调用 Engine；调用方继续其余原生分发，不能将空结果当作完成了一次输入。

调用方显式提供与 TSF 相同的 Local/Pinyin 预编辑样式，UILess 从包标志读取。Local 编辑不回包；普通 Pinyin 的字符与未清空组合的删除返回 Preedit，左右移动和删除到空组合不回包；UILess 编辑统一返回候选页，包括清空状态。非空 PendingReply 即使没有 encoded 帧也必须通过 SessionPump 确认，不能重跑 Engine。该入口不处理 Enter、取消、候选选择、标点、Microsoft 双拼分号或配置优先导航，尚未组成完整产品 KeyHandler。

### Engine 模式与 Unicode 数字选词

数字候选判定前将 VK_NUMPAD0..9 归一化为 0..9，与固定上游 Server 边界一致；不修改原始请求包。Unicode 模式的 Shift+小键盘 1..9 因此与主键盘一致，越界选择保持原组合；无 Shift 的小键盘数字（包括 0）仍用于 Unicode 编码输入，Ctrl/Alt 快捷键不会被误当作选词。

共享 View 新增 local_mode，由固定 Engine 的 SessionSnapshot.local_mode 显式映射并透传，不从 editing_text/preedit 猜测；快照失败时的 unknown 不能当作普通输入模式使用。模式变化不会沿用旧模式候选高亮。宿主与共享库应成套构建，Windows 不对缺失模式字段做前缀回退。

依据固定上游 TSF 消费规则，ServerSession 在 Unicode 模式下把 Shift+1..9 解释为当前页候选选择，即使 wch 已被键盘布局翻译为 ! 等标点；通过视图提供的 generation/global index 调用共享 select，越界槽位不改变组合。非 Unicode 模式仍使用原始 wch 和共享标点处理，不将所有 Shift+数字都强制选词。UiLess 标志不干扰修饰键判定，模式快照只在该数字分支读取，不给普通字符路径增加一次完整视图查询。原生分发处理器仍须选择 Selection 回复路径，其他 TSF 键路由未因此自动完成。
