# Contributing to MSIME-Client

感谢参与水杉输入法共享客户端。提交改动前，请先阅读 [AGENTS.md](AGENTS.md) 了解模块边界、平台约束、验证命令和提交要求，并查看 [变更记录](CHANGELOG.md) 了解当前公开范围。

## 开发流程

1. 从远端实际默认分支（当前为 `origin/develop`）创建独立分支或 worktree，放在仓库外的 `~/worktrees/<feature>/` 下；不要在共享主工作区切换分支。
2. 保持改动聚焦；目录或命名整理应同步更新构建文件、测试和文档引用。
3. Rust 改动运行相关测试、`cargo fmt` 和 `cargo clippy`；前端改动运行类型检查和构建；原生宿主改动在可用平台上运行对应验证。目录整理必须同时更新构建文件、测试路径和平台 README。
4. 提交前运行 `scripts/verify-local.sh --quick`，并检查 `git diff --check`。
5. 使用 Conventional Commits，例如 `fix(linux): ...`、`refactor(android): ...` 或 `docs: ...`。每个可验证切片独立提交；合并前运行 `bash scripts/verify-local.sh --quick`。

不要提交真实输入、凭据、个人资料、生成目录或本机配置。测试数据应使用合成值。

## Pull request

描述问题、行为变化和验证结果。平台环境不可用时请明确列出跳过的检查，不要把静态检查表述为设备或系统验收。CI 由仓库策略停用，本地验证是合并前的主要检查。

GitHub 的 issue 和 PR 模板会提醒贡献者使用合成输入、列出实际验证并补充第三方许可证信息。安全漏洞、凭据泄露、真实输入或进程边界问题不要通过公开 issue/PR 报告，请按 [安全策略](SECURITY.md) 私下提交。
