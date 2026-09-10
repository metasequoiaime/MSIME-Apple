# macOS InputMethodKit 预览宿主

输入源菜单迁移固定 Apple `InputMenu.h` / `InputModeRouting.h` 的中文、英文和“表情与符号…”入口。默认中文；英文模式不准备 Engine 会话，按键直接放行。切到英文先用共享 Engine finish 完成当前组合并隐藏候选；失败时保留原模式。Shift+空格默认切换中英文，设置中可关闭；竞争 Command/Control/Option 修饰键不触发切换，重复事件消费但不反复更改偏好。英文模式激活后切回中文会恢复保留会话焦点与设置轮询。英文模式与快捷键偏好保存在新宿主域，不复用混合输入选项或算法状态。

打开字符面板同样先完成组合，再请求系统 Character Viewer；测试以替身记录系统入口，不实际打开面板。原生测试覆盖菜单勾选、偏好保存、组合完成/失败、英文按键旁路、七种竞争修饰组合、重复/禁用快捷键、无会话懒加载与焦点恢复。繁简、更新及语音菜单尚待对应功能迁移，未添加不可用占位项；候选设置仍是渐进迁移入口，不是完整上游偏好窗口。

候选设置现提供 Apple 固定提交 `b637828e15eafcb5e459edd270a962dd14517285` 的四套内置皮肤：Fluent、微信绿、石墨 Graphite、杨柳青。`CandidateSkin.h/.cpp` 的内置 token 与 `CandidateChrome.h` 的绘制来自该提交，保留明暗配色、边框、圆角、内边距、独立编号颜色及选中标记。跟随系统外观变化重新着色；设置变更立即重绘但不改变组合、候选 ID 或高亮。设置存入新宿主自身偏好域。

外部皮肤读取同一固定来源的 `skin.toml` schema 1：元数据、内置 base、supports 布局/主题列表、明暗候选颜色、最小宽度和顶部装饰图。新宿主只扫描 `~/Library/Application Support/app.msime.client.preview/skins/<id>/skin.toml`，不读取或改写旧 Apple 产品目录。开发时将包放入该目录后，打开“候选设置…”或点击“重新读取皮肤”；内置项在前，外部项按名称排序，按 ID 保存选择。无效/缺失包使用 Fluent 渲染但保留用户选择的安全 ID。候选配色与图片缓存于设置快照，不在按键重绘时扫描磁盘。

候选装饰沿用 Apple 顶部右对齐和等比例缩放，宽度与顶部留白来自 manifest；缺失或无法解码的图片不绘制，保留声明的布局。外部 manifest 限 64 KiB，拒绝非普通文件、越界或经符号链接逃逸的包/manifest/资源路径；非法颜色忽略并保留基础配色。`toolbar_stylesheet` 只保留元数据，不执行 CSS。

“浏览所有皮肤…”打开按固定 Apple `SkinSettingsView` 迁移的卡片式页面：四套内置皮肤、外部包描述、每卡独立明暗预览与单选启用开关，已启用项再次点击不会关闭。外部包通过“打开目录 → 复制皮肤文件夹 → 刷新皮肤”加载，提供空状态和无效包扫描诊断。固定 macOS 源码没有内置导入/删除按钮，本页保持该目录管理流程，不另外创建导入器。目录打开仅由用户点击触发；新宿主目录创建/打开失败会显示错误，不触碰旧 Apple 目录。此页暂以独立窗口接入，完整偏好窗口导航及社区功能仍待迁移。

`skin-settings` 原生测试覆盖四卡选择与保持启用、无副作用明暗预览、系统主题标题、外部卡重复刷新无累积、无效包诊断、空状态、打开目录的路径/失败检查，以及入口窗口构造与重复使用。测试目录打开器为替身，不启动 Finder；只操作临时合成目录。卡片离屏图像已检查，仍不替代实际系统编辑器验收。

设置窗口的候选预览迁自同一固定版本的 `CandidateSkinPreviewView`，随布局、每页数量、字号和皮肤实时更新。使用固定演示样例而非真实输入；竖排最多展示五行并提示剩余项，横排不足时显示省略号。可单独切换预览明暗主题，也可同时展示横排、竖排及状态栏样式；这些预览操作不写偏好或调用输入会话。状态栏仅为固定源的非交互展示，不代表实际悬浮状态栏已接入。外部装饰图和长预览在可滚动区域显示。当前预览使用注入的设置快照与皮肤目录，不读取旧 Apple 产品设置；强制主题的系统文字颜色在对应绘制外观下解析。

`skin-preview` 原生测试覆盖四皮肤 × 两布局 × 三页大小 × 三字号 × 两主题的 144 次绘制，设置控件联动、无副作用的预览主题/展示切换、系统外观跟随、外部包回退、装饰区域可见像素和长内容滚动。原生合成 PNG 使用明确的 RGB 数据与 sRGB 标记，避免透明夹具掩盖绘制缺失；像素断言允许系统 ColorSync 转换，不宣称跨显示器逐像素一致。

皮肤验证包含八组固定配色与几何基准，以及四皮肤 × 两布局 × 两外观的原生离屏绘制、设置保存和组合保留测试。原生 Objective-C++ 构建启用 `-Wall -Wextra -Werror`；没有 TypeScript UI 改动。离屏绘制不等同于系统安装后的逐像素外观或编辑器验收。

外部皮肤追加固定源解析测试和路径/颜色拒绝测试，以及生成的 PNG、真实设置控件选择与保存、两布局/两主题装饰位置、缓存与显式重载回退的原生测试；只使用临时合成包和独立偏好 suite，不操作用户皮肤目录。

每页候选按 Apple `CandidatePageSize.h` 提供 5/7/9 项，默认及非法值归一化为 9。原生偏好在创建/激活会话及设置变更时请求共享分页覆盖；组合期间保持当前页、高亮和数字选词映射，组合结束后使用最后一次选择。此 macOS 原生覆盖优先于共享偏好中的 candidate_page_size，并在共享 Engine 配置重建后保留；不修改共享偏好文件。视图的 page_size 反映实际生效值。原生设置和 C API 测试覆盖保存、延迟、非法值、重复请求与重载。

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
