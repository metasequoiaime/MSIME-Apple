# MSIME-Client

水杉输入法共享客户端，渐进迁移中的新工程。React 管理界面通过 Tauri 调用普通 Rust 业务库；原生输入法宿主接入共享输入运行时；输入算法继续由 MSIME-Engine 提供。

目前不能替代已发布的平台输入法。各阶段实现和验证记录见 [实施记录](docs/implementation.md)。

## 模块边界

- `crates/client-core`：配置、账号、同步与资源业务，不依赖 Tauri、UI 或平台宿主。
- 后续 `crates/input-runtime`：会话编排与候选展示模型；不复制 Engine 组词状态机。
- 后续 `crates/engine-bridge`：固定上游 C++ Engine 的互操作层。
- 后续 `crates/host-api`：原生宿主入口与明确的对象生命周期。
- 后续 `packages/ui`、`apps/desktop`：共享 React UI 与 Tauri 应用壳。
- 后续 `platforms/`：系统入口；Windows 保留 TSF DLL / Server 隔离。

共享库可以加载进不同宿主进程；不要求启动 Tauri 才能输入。跨进程设置变更需要明确的持久化与通知机制。

## 开发

```sh
cargo test --workspace --locked
cargo fmt --all --check
cargo clippy --workspace --all-targets --locked -- -D warnings
```

每个可验证的功能单独 commit。新实现接入并通过行为回归之前，各平台现有实现继续运行。
