# macOS InputMethodKit 预览宿主

迁移对照固定为 MSIME-Apple 远端默认分支 develop 的提交 `b637828e15eafcb5e459edd270a962dd14517285`。Command、Control、Option 快捷键沿用其 `MetasequoiaInputController.mm` 行为：先通过 Engine finish 提交当前高亮对应组合，再放行快捷键。原生控制器测试覆盖三个修饰键的分派、提交、清空预编辑和返回未处理；使用替身会话，不代表系统安装后的端到端验收。

真实 IMKServer / IMKInputController 入口，静态链接共享 Rust/C++ 运行时。平台代码负责系统按键、文本插入、预编辑和不激活候选面板。分页、高亮、会话代次、候选选择与组词仍由共享层负责。

当前预览支持 ASCII 输入、退格、移动编辑光标、空格选择、回车原文、Esc 取消、候选上下移动和翻页、鼠标选词，以及由共享运行时处理的当前页数字选词与标点结束组词。候选面板显示对应数字；Engine 优先接收字符，保留 Unicode 等输入模式与拼音分隔符。未被 Engine 接收的 ASCII 标点先按当前高亮完成组词，再复用 Engine 中文标点转换；关闭中文标点时保留 ASCII。设置后台重读已接入，菜单与正式安装尚待完成。原始 ASCII 编辑串用于内联预编辑，光标单位与 Engine 一致；日语等美化预编辑另行处理。

先下载锁定词库，然后在隔离的开发状态目录中准备工作词库；该步骤要求相关会话已停止，不用于对现有输入法在线升级：

```sh
MACOSX_DEPLOYMENT_TARGET=13.0 CMAKE_PREFIX_PATH="$(brew --prefix)" cargo run -p msime-host-api --example prepare_host -- <已校验资源目录> target/macos-state
MACOSX_DEPLOYMENT_TARGET=13.0 CMAKE_PREFIX_PATH="$(brew --prefix)" cargo build -p msime-host-api --locked
cmake -S platforms/macos -B target/macos -DMSIME_OPTIONS_FILE="$PWD/target/macos-state/runtime-options.json"
cmake --build target/macos --parallel
ctest --test-dir target/macos --output-on-failure
```

产物为 `target/macos/MSIMEClientInputMethod.app`。可选开发配置包含本机绝对路径，不得对外分发。未嵌入开发配置时从新客户端的应用数据目录读取 `runtime-options.json`；配置缺失时不拦截输入。构建过程不安装、不注册、不切换系统输入法。静态库与宿主均以 macOS 13 为最低构建目标，必须使用同一架构。

新的 `prepare_host` 配置包含 `preferences_directory`。宿主激活时立即后台读取此目录，之后每秒检查一次，前一次未完成时不重叠读取；失活后停止定时器。文件锁和读取不占用会话主线程，应用仍在主线程且有组合时延迟；读取错误保留原配置。旧配置没有此字段时不自动重读，需要重新准备开发配置（先停止该开发宿主）。

从仓库根目录让设置页写入同一份隔离配置：`MSIME_CLIENT_STATE_DIR="$PWD/target/macos-state" pnpm --filter @msime/desktop tauri dev`。保存后活跃宿主通常在下一次轮询收到快照，当前组词结束后生效；无需 Tauri 常驻。此为代码和原生桥接层已验证的链路，尚未验证系统安装后的设置窗口到编辑器全程交互。

文本适配测试验证提交、ASCII 光标和清除预编辑；它不是系统输入源安装后在编辑器中的验收。系统级焦点、候选位置和键盘输入仍需真实宿主验证后才能标为完成。
