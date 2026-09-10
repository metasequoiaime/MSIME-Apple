# macOS InputMethodKit 预览宿主

布局和字号按固定 Apple 来源的 `CandidatePanelStyle.h`、`CandidateFontSize.h` 与原生设置控件迁移：默认横排/18 点，提供横向排列、纵向列表，以及 16/18/20 点字号。输入法菜单中的“候选设置…”打开已迁移的设置项；这是渐进迁移的外观设置入口，尚未复刻完整上游设置窗口。值保存到新宿主自身 NSUserDefaults 域，不读取或改写原 Apple 产品偏好，也不改动共享 Engine 配置。已激活候选立即重绘，组合及页内高亮保留。横排左右键导航、上下键消费；竖排反之。横排过长时按可用屏宽缩放每项展示宽度并截断文字。

多页候选显示 Apple 风格的 `‹` / `›` 鼠标翻页按钮（28×26 点，竖排底栏 26 点）；单页不显示，首页/末页禁用越界方向，并提供中文可访问标签。页码和候选由共享运行时返回，点击分派既有翻页命令；回调校验会话、组合代次、原页面与焦点，防止旧按钮影响新输入。原生测试覆盖实际按钮点击、方向禁用、单页隐藏和过期回调，不替代系统输入源端到端验收。

候选定位与焦点约束对照同一 Apple 提交的 `CandidatePanel.mm`：无效光标隐藏窗口、以光标垂直中点选屏、与光标相隔 4 点、底部不足时向上放置，超大窗口至少锚定可见屏幕原点。候选窗口不能成为 key/main window，按钮不接受键盘焦点但支持首次鼠标点击。宽度随候选文字变化并受屏宽约束，长文本截断并提供完整 tooltip；皮肤尚未完整迁移。

并行开发时使用独立产物目录，避免其他平台构建覆盖最低系统版本设置：

```sh
MACOSX_DEPLOYMENT_TARGET=13.0 CMAKE_PREFIX_PATH="$(brew --prefix)" CARGO_TARGET_DIR=target/macos-cargo cargo build -p msime-host-api --locked
cmake -S platforms/macos -B target/macos-isolated -DMSIME_HOST_LIBRARY="$PWD/target/macos-cargo/debug/libmsime_host_api.a"
cmake --build target/macos-isolated --parallel
ctest --test-dir target/macos-isolated --output-on-failure
```

原生测试使用不显示窗口的面板子类验证布局、完整 tooltip 和无效光标隐藏，以及纯几何边界和焦点方法；它不是系统安装后编辑器验收或逐像素外观验收。

Home/End 在候选可见时通过共享运行时移到当前页首/末候选，不改变编辑串、光标或提交文本；最后不足一页时止于实际末项。候选隐藏后沿用编辑光标 Home/End。测试覆盖可见/隐藏状态、完整页及末页、过期候选和全局索引提交。翻页快捷键提供减号/等号（默认）、方括号、Page Up/Page Down 三种设置。字符键仅在候选可见且无 Shift/Command/Control/Option 时按所选键组翻页；未匹配或有 Shift 时将实际字符交给 Engine。Page Up/Page Down 在三种设置下均有效，与 Apple 路由一致。设置保存在新宿主原生偏好域，测试覆盖默认、非法值归一化、控件保存、48 种字符组合以及修饰键优先级。

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
