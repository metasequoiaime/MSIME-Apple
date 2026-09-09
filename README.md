# MSIME-Client

水杉输入法共享客户端，渐进迁移中的新工程。React 管理界面通过 Tauri 调用普通 Rust 业务库；原生输入法宿主接入共享输入运行时；输入算法继续由 MSIME-Engine 提供。

目前不能替代已发布的平台输入法。各阶段实现和验证记录见 [实施记录](docs/implementation.md)。

## 模块边界

- `crates/client-core`：已实现本地配置和固定资源分代安装；账号与同步待迁移，不依赖 Tauri、UI 或平台宿主。
- `crates/input-runtime`：会话编排、焦点取消、候选分页和带代次的选择；不复制 Engine 组词状态机。
- `crates/engine-bridge`：通过 CXX 调用固定上游 C++ Engine 的公共 Session。
- `crates/host-api`：版本化 C 接口、线程绑定的会话句柄和显式响应释放。
- `packages/ui`、`apps/desktop`：共享 React 设置页与 Tauri 应用壳，已接入真实本地配置。
- 后续 `platforms/`：系统入口；Windows 保留 TSF DLL / Server 隔离。

共享库可以加载进不同宿主进程；不要求启动 Tauri 才能输入。跨进程设置变更需要明确的持久化与通知机制。

## 开发

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

设置通过 `app.msime.client.preview` 应用数据目录中的 `preferences.json` 保存。当前四个字段仅属于预览客户端，尚不作用于已安装输入法。多个设置窗口保存时通过 revision 检测冲突，用户须显式重新读取后决定是否覆盖。

每个可验证的功能单独 commit。新实现接入并通过行为回归之前，各平台现有实现继续运行。

## Engine 桥接

```sh
git submodule update --init --recursive
# 安装 Engine 的 Boost、fmt、spdlog、SQLite3 和 CMake 依赖后：
cargo test -p msime-engine-bridge --locked
# macOS Homebrew 环境可能需要：
CMAKE_PREFIX_PATH="$(brew --prefix)" cargo test -p msime-engine-bridge --locked
```

Engine 由 gitlink 固定；CXX 生成互操作代码，CMake 构建原有 C++ 引擎，Cargo 链接静态引擎与系统 SQLite。会话不实现 Send/Sync，C++ 异常在桥接边界转成 Result。路径由宿主明确提供，字符输入目前为 Engine 支持的 ASCII 动作。测试中的 Unicode 模式使用真实 Engine，但不代表完整拼音词库、移动交叉编译或安装验证通过。

## 原生宿主接口

`cargo build -p msime-host-api --locked` 产出静态库和动态库。头文件为 `crates/host-api/include/msime_client.h`，C 消费示例为 `crates/host-api/tests/native_smoke.c`。调用链为 C 宿主 → host-api → input-runtime → CXX → C++ Engine，无 Tauri 运行时依赖。

宿主创建会话后须显式传入焦点状态，将 `handled` 映射为系统吃键，将 `commit` 通过系统 API 上屏，将值快照渲染为候选。候选选择携带返回的 generation 和全局 index。全部会话操作在创建线程执行；过期、销毁或错误线程句柄返回错误。每个 UTF-8 JSON 响应必须通过 `msime_client_string_free` 释放一次。此版本优先验证互操作正确性；逐键快照 JSON 的延迟和分配成本尚未测量。

## 固定词库资源

`resources/desktop-dictionary.lock.json` 固定已发布 `dict-v1.0.0` 的来源、长度和 SHA-256，保留日语授权文件。首次下载约 184 MB。开发准备命令：

```sh
cargo run -p msime-client-core --example install_resources -- target/resources
```

安装器通过注入的流读取资源，限制长度并校验摘要；全部成功后才发布到内容标识目录。再次使用时检查缓存字节；损坏缓存报错，失败安装不替换旧代。这里只准备不可变发布资源，不激活现有输入法，不迁移用户学习数据。它使用独立文件 Release，不冒充尚未发布的完整 Engine ZIP。
