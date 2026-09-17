# MSIME-Client

遵循 metasequoiaime/.github 的组织约定。用户已授权按共享客户端设计渐进实施，每部分验证后独立 conventional commit。

- client-core 不依赖 Tauri、React、Engine 或平台宿主；平台能力通过接口注入。
- 输入算法和组合状态归 C++ Engine；输入运行时只维护宿主编排和展示状态。
- 平台库不得依赖桌面应用；iOS 键盘扩展不依赖常驻桌面服务。
- 保留 Windows TSF DLL / Server 的进程和协议边界。
- 日志、测试、提交中不得包含真实输入、凭据或私人资料。
- 上游来源以远端实际默认分支和固定提交为准；不复制相邻仓库未提交内容。
- 修改 Rust 运行测试、fmt、clippy；UI 修改运行类型检查和构建。未执行原生宿主验证不能声称完成平台接入。
- 只暂存明确路径。提交格式 type(scope): 摘要，不添加自动生成标记。
- 后续任务一律使用独立 git worktree，从已更新的远端默认分支创建；不得在共享主工作区切分支或混入其他会话改动。细则见下方 Worktrees 一节。
- CI 已由仓库所有者停用以控制费用，这是常设政策不是临时要求：不得启用、手动触发或新增自动 CI；恢复需用户明确要求。本地验证取而代之——合并前跑 `scripts/verify-local.sh --quick`，声称功能完成前跑完整版。每个阶段都拿失败项与 `scripts/known-failures.txt` 比对，只有不在基线里的才算回归。
- 首次克隆后执行 `git config core.hooksPath .githooks`：提交时检查冲突标记和暂存 Rust 文件的格式，合并与推送时跑 `--quick` 编译门。曾有六次编译中断因「合并了但没构建合并结果」进入 develop，`8f35bd20` 的冲突标记也是这样进去的。
- 用户最新要求以 MSIME-Windows 完整功能为基线迁移全平台，并适配平台特性，不用验收，不要以平台缺少环境为借口中断工作。保留已合并的平台成果，不复制相邻仓库未提交内容。每部分本地验证后及时合并，不堆积 PR。

## Worktrees

This repository is developed with many short-lived worktrees, one per task. They accumulate quickly and each one carries its own build output, so placement and cleanup matter.

- Create every worktree **outside** the repository, under `~/worktrees/<feature>/` or a dedicated `worktrees/` directory on a secondary disk. Never inside the repository, next to the main worktree, or on the Desktop.
- **Never use `/tmp` or `/var/tmp`.** Those directories belong to the system, which is free to purge them at any time, and uncommitted work placed there has been lost this way.
- Name `<feature>` in kebab-case, derived from the branch name or issue number. Do not prefix it with `wt-`; the parent directory already says what it is.
- Commit as you go rather than saving everything for the end. The branch is the first line of defence, the directory only the second: a work-in-progress commit costs nothing and survives anything that happens to the checkout.
- Remove the worktree as soon as its branch is merged or abandoned: `git worktree remove <path>`, then `git branch -D <branch>`. Run `git worktree prune` if a directory was deleted by hand.

Cleanup is not optional bookkeeping. A stale worktree keeps its full build tree alive — `target/`, `node_modules/` and `gradle-home/` each run to several gigabytes — and a few dozen forgotten worktrees are enough to fill a disk.

Before deleting a worktree, confirm it is safe: its branch is merged into `develop` (an ancestor of `origin/develop`, or every commit reported as already applied by `git cherry origin/develop <branch>`), and `git status --porcelain` shows no tracked modifications. Leave anything else alone; another session may still be working in it.
