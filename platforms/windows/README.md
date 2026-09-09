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

`bash platforms/windows/tests/check-cross.sh /absolute/nlohmann-include-root` 使用 x86_64/i686 MinGW 分别编译适配器、测试源和固定上游 IPC 契约，验证 32/64 位 COFF 和 Windows SDK 键码断言；不链接 Windows Rust 库，不执行 Windows 二进制。测试覆盖真实 Unicode 输入、锁定词库第二页数字选词、配置延迟、客户端/焦点/线程拒绝及本地取消不回复。

## 下一步

继续 Windows 的回复编码、Named Pipe 收发、认证与路由接入，以及实际 TSF DLL 消费、断管恢复和 x86/x64 编辑器验证。当前 `KeyResult.transition` 是内部共享结果，不是新的 IPC 线格式；不能将 JSON 直接发送给现有 DLL，也未完成 CommitExactText/分段组合/UILess 的回复映射。候选 HWND、设置自动重读、打包和安装同样未完成，不替换旧产品。CI 保持关闭，Windows 优先于 macOS、iOS、Linux。

键码依据 [Microsoft Virtual-Key Codes](https://learn.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes)，线格式直接包含 vendor/MSIME-Engine/contracts，不另造 opcode 或改协议能力声明。
