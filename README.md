# 水杉输入法

水杉输入法共享客户端，渐进迁移中的新工程。React 管理界面通过 Tauri 调用普通 Rust 业务库；原生输入法宿主接入共享输入运行时；输入算法继续由 MSIME-Engine 提供。

> **关于名称**：MSIME 是 Metasequoia IME（水杉输入法）的缩写，与 Microsoft IME 无关，也与微软没有任何关联。代码、包名和仓库名中的 `msime` 一律是这个含义。设置中的 `shuangpin_profile: microsoft` 是「微软双拼」方案，与小鹤、自然码、首道并列的四个键位方案之一，供习惯该键位的用户选择，同样不代表任何关联。

目前不能替代已发布的平台输入法。分层方式和不能打破的边界见 [架构说明](ARCHITECTURE.md)，当前公开变更见 [变更记录](CHANGELOG.md)，各阶段实现和验证记录见 [实施记录](docs/implementation.md)；平台目录、构建入口和已知缺口见各平台 README。

**输入法能看到你输入的一切，所以这个问题应该有一个能逐条核对的答案：[哪些数据会离开设备](PRIVACY.md)。**简短版本：默认配置下只有云联想一个功能会把正在组的拼音发出去（发给 Google 输入工具，可关闭），其余联网功能都要你自己填凭据才会工作，仓库里没有任何遥测或统计 SDK。

## 模块边界

- `crates/client-core`：已实现本地配置和固定资源分代安装；账号、同步等业务契约按模块迁入，不依赖 Tauri、UI 或平台宿主。
- `crates/input-runtime`：会话编排、焦点取消、候选分页和带代次的选择；不复制 Engine 组词状态机。
- `crates/engine-bridge`：通过 CXX 调用固定上游 C++ Engine 的公共 Session。
- `crates/host-api`：版本化 C 接口、线程绑定的会话句柄和显式响应释放。
- `packages/ui`、`apps/desktop`：共享 React 设置页与 Tauri 承载层，各平台使用同一个 Rust 入口库、commands 与 React 页面；目录名暂沿用 desktop。Rust 入口按 `platform/{android,ios,linux,macos,windows,desktop}`、`shared/`、`tests/` 分层。**Tauri 是公共组件，不是任何平台的产品本体**：最终安装、启动、被系统识别为输入法的，始终是 `platforms/<os>` 下的原生宿主，Tauri/React 由它按需承载。
- `shared/apple/`：macOS 与 iOS 共用的 Foundation / Objective-C++ 桥接，不包含系统输入法入口。
- `platforms/`：各系统入口和适配层。Android、iOS、macOS、Linux、Windows 与 HarmonyOS 均保留自己的宿主边界；共享输入算法和组合状态仍在 C++ Engine。Android 15 arm64 模拟器已验证系统输入和共享设置，Linux arm64 容器已验证 IBus daemon 输入链路，Windows 已完成跨目标与本地边界测试，HarmonyOS 目前只有源码/交叉构建入口。真机、Linux 图形桌面、Windows 系统入口、HarmonyOS 设备以及 iOS 签名和设备验收仍待完成。

## 平台目录与状态

| 平台 | 入口目录 | 当前可复现证据 | 尚未完成 |
| --- | --- | --- | --- |
| [Android](platforms/android/README.md) | `platforms/android/` | API 35 arm64 专用模拟器、Tauri/IME 合包和共享设置 | 真机、x86_64 合包、完整生命周期 |
| [iOS](platforms/ios/README.md) | `platforms/ios/` | Swift/配置测试；模拟器 App 与真机 `.ipa` 的未签名构建，两者都内嵌键盘扩展和固定词库 | 签名、设备安装与键盘扩展启用验收 |
| [macOS](platforms/macos/README.md) | `platforms/macos/` | IMK 预览 bundle、Rust/C++/CTest 和离屏 UI 测试 | 安装输入源、真实编辑器和权限验收 |
| [Linux](platforms/linux/README.md) | `platforms/linux/` | arm64 容器中的 IBus daemon、Fcitx5 构建和隔离测试 | 图形桌面、安装包和 Wayland/X11 端到端 |
| [Windows](platforms/windows/README.md) | `platforms/windows/`、`platforms/windows/tsf/` | x86/x64 交叉编译、管道/Server 边界测试 | Windows 原生运行、TSF 注册和编辑器验收 |
| [HarmonyOS](platforms/harmony/README.md) | `platforms/harmony/` | ArkTS 逻辑测试和 OpenHarmony NDK 构建入口 | DevEco/HAP 设备运行和系统输入验收 |

共享库可以加载进不同宿主进程；不要求启动 Tauri 才能输入。Android、iOS、HarmonyOS、Linux、macOS 与 Windows 一致：产品形态是 `platforms/<os>` 的原生宿主，Tauri 只提供跨平台共享的功能与界面，不单独作为产品启动。跨进程设置变更需要明确的持久化与通知机制。

## 开发

贡献代码前请阅读 [架构说明](ARCHITECTURE.md)、[贡献指南](CONTRIBUTING.md)、[安全策略](SECURITY.md)、[网络请求与数据流向](PRIVACY.md) 和 [行为准则](CODE_OF_CONDUCT.md)。准备公开源代码或平台构建物时，再阅读 [开源发布清单](docs/open-source-release.md) 和[第三方组件清单](docs/third-party.md)；它们列出第三方通知、资源许可、敏感文件检查和验证边界。仓库当前仍处于渐进迁移阶段；请以每个平台 README 和本地验证结果为准，不把未执行的原生宿主验收当作已完成。

```sh
cargo test -p msime-client-core --locked
cargo fmt --all --check
cargo clippy -p msime-client-core --all-targets --locked -- -D warnings
pnpm install --frozen-lockfile
pnpm --filter @msime/desktop test
pnpm build
pnpm tauri dev
```

桌面构建需要 [Tauri 平台依赖](https://tauri.app/start/prerequisites/)。`pnpm tauri build --debug --no-bundle` 构建开发二进制；暂不签名、安装或发布。普通浏览器中只显示无法访问本地配置的提示，不模拟保存成功。

桌面设置默认通过 `app.msime.client.preview` 应用数据目录中的 `preferences.json` 保存，也可用绝对路径环境变量 `MSIME_CLIENT_STATE_DIR` 指向隔离开发目录。新 macOS 预览宿主可后台读取同一目录，输入中延迟应用；这不修改旧产品的已安装输入法。多个设置窗口保存时通过 revision 检测冲突，用户须显式重新读取后决定是否覆盖。

Android 合包构建和设备测试见 [Android 宿主](platforms/android/README.md#tauri--react-共享设置合包)。Tauri 设置与原生 `:ime` 服务同包、不同进程，共享私有 files/bootstrap/state；关闭设置窗口不结束输入法进程。iOS 的产品宿主是 `platforms/ios` 的原生 App，它嵌入原生键盘扩展并通过 App Group 共享状态；Tauri/React 在 iOS 上只作为共享功能与界面的公共组件，不作为独立 App 启动。签名和设备验收边界见 [iOS 宿主](platforms/ios/README.md)。

每个可验证的功能单独 commit。新实现接入并通过行为回归之前，各平台现有实现继续运行。

共享设置支持 shuangpin_profile：xiaohe（小鹤）、ziranma（自然码）、shoudao（首道）、microsoft（微软）。旧配置缺省按小鹤读取且不自动改写，未知值拒绝；设置页在非双拼方案下禁用此选择但保留已选值。方案更改沿用组词结束后替换 Engine 的规则。新宿主会写出此字段，旧版本严格解析器可能拒绝新配置，设置端和宿主应成套更新，不得通过删除未知字段强行降级。

Linux 本地构建和隔离 D-Bus / IBus 测试见 [Linux 宿主](platforms/linux/README.md)。宿主已支持设置文件自动重读；图形桌面安装和真实编辑器验证仍需分别执行。

平台迁移以 MSIME-Windows 完整功能为行为基线，逐项把公共业务和界面接入共享层/Tauri，同时保留 Windows TSF DLL / Server 的进程和协议边界。Android、iOS、macOS、Linux 与 HarmonyOS 按各自系统能力适配；目录整理或跨目标编译不等于系统入口、签名、安装和设备验收完成。

## Engine 桥接

```sh
# 构建时自动准备；也可手动跑一次
python3 scripts/fetch_engine.py
# 安装 Engine 的 Boost、fmt、spdlog、SQLite3 和 CMake 依赖后：
cargo test -p msime-engine-bridge --locked
# macOS Homebrew 环境可能需要：
CMAKE_PREFIX_PATH="$(brew --prefix)" cargo test -p msime-engine-bridge --locked
```

Engine 由 `engine-lock.json` 固定：锁文件同时记录 Engine 及其第三方源码归档的 commit 和 SHA-256，`scripts/fetch_engine.py` 校验并展开这些归档，不使用 gitlink、`.gitmodules` 或递归 Git checkout；`crates/engine-bridge` 的 build.rs 在编译前调用它。离线构建可用 `MSIME_SKIP_ENGINE_FETCH=1` 跳过。CXX 生成互操作代码，CMake 构建原有 C++ 引擎，Cargo 链接静态引擎与系统 SQLite。会话不实现 Send/Sync，C++ 异常在桥接边界转成 Result。路径由宿主明确提供，字符输入目前为 Engine 支持的 ASCII 动作。测试中的 Unicode 模式使用真实 Engine，但不代表完整拼音词库、移动交叉编译或安装验证通过。

## 原生宿主接口

`cargo build -p msime-host-api --locked` 产出静态库和动态库。头文件为 `crates/host-api/include/msime_client.h`，C 消费示例为 `crates/host-api/native/native_smoke.c`。调用链为 C 宿主 → host-api → input-runtime → CXX → C++ Engine，无 Tauri 运行时依赖。

宿主创建会话后须显式传入焦点状态，将 `handled` 映射为系统吃键，将 `commit` 通过系统 API 上屏，将值快照渲染为候选。候选选择携带返回的 generation 和全局 index。全部会话操作在创建线程执行；过期、销毁或错误线程句柄返回错误。每个 UTF-8 JSON 响应必须通过 `msime_client_string_free` 释放一次。此版本优先验证互操作正确性；逐键快照 JSON 的延迟和分配成本尚未测量。

`msime_client_select_edge(session, generation, index, edge)` 是 ABI 1 附加接口，适配器与宿主库须成套更新。方向使用 `MSIME_FIRST_HAN` / `MSIME_LAST_HAN`；共享层核对候选所属会话、代次和当前页，C++ Engine 提取首／尾汉字并在成功后清空整个组合。候选没有汉字时返回未处理并保留组合，不自动选词或追加标点；这类有效调用仍更新视图代次，宿主后续操作必须使用新快照。非法方向和失效身份在状态推进前拒绝。Windows 适配库已有配置键路由、无汉字回退与 TSF 回复编码，生产 KeyHandler 已接线，实机验收仍待完成，不能把共享能力已暴露视为产品按键已可用。

## 固定词库资源

`resources/desktop-dictionary.lock.json` 固定已发布 `dict-v1.0.0` 的来源、长度和 SHA-256。其中 `mozc_dictionary_oss_README.txt` 是日文词库的许可证全文，IPAdic 与 ICOT 的条款都要求它随词库一同分发，重新打包时不可省略；详见[第三方组件清单](docs/third-party.md#日文词库的分发义务)。首次下载约 184 MB。开发准备命令：

```sh
cargo run -p msime-client-core --example install_resources -- target/resources
```

安装器通过注入的流读取资源，限制长度并校验摘要；全部成功后才发布到内容标识目录。再次使用时检查缓存字节；损坏缓存报错，失败安装不替换旧代。这里只准备不可变发布资源，不激活现有输入法，不迁移用户学习数据。它使用独立文件 Release，不冒充尚未发布的完整 Engine ZIP。

`engine-bridge::prepare_options` 调用 Engine 权威的工作词库准备与学习回放入口，调用方必须先验证资源并暂停相关会话。以下探针使用临时用户目录和缓存，验证已发布词库中的 `nihao` 查询、选词提交及首／尾汉字选择：

```sh
cargo run -p msime-engine-bridge --example query_dictionary -- <上一步返回的资源目录>
```

macOS 原生 IMK bundle 的开发构建、隔离状态目录与验证边界见 [macOS 宿主](platforms/macos/README.md)。目前不提供自动安装，也未完成系统输入源切换后的编辑器验收。

## 许可证

源码为 **GPL-3.0-only**，全文见 [LICENSE](LICENSE)。

上游代码、词库、模型和各平台 SDK 以各自许可证和通知为准，其中 Android 与 iOS 的手写识别使用 Google ML Kit，按其服务条款授权而非开源许可证。完整对照见[第三方组件清单](docs/third-party.md)。
