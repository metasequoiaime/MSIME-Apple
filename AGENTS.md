# AGENTS.md

给在本仓库工作的编码代理的操作约定。**架构边界、验证流程和证据分级在 [ARCHITECTURE.md](ARCHITECTURE.md)，贡献流程在 [CONTRIBUTING.md](CONTRIBUTING.md)——先读那两份，这里只写它们没有覆盖的操作细节。**

## 改动范围

- 只暂存明确列出的路径，不用 `git add -A`。
- 不复制相邻仓库的未提交内容；上游来源以远端实际默认分支和固定提交为准。
- 日志、测试和提交中不得包含真实输入、凭据或私人资料，测试数据使用合成值。
- 不启用、手动触发或新增自动 CI。CI 由仓库所有者停用以控制费用，恢复需要所有者明确要求。

## 提交

- 格式为 `type(scope): 摘要`，遵循 Conventional Commits。
- 每个可独立验证的切片单独提交。
- 不添加自动生成标记、AI 署名或 `Co-Authored-By` 水印。

## Worktree

本仓库以大量短生命周期的 worktree 开发，一个任务一个。它们积累得很快，而且每个都带着自己的构建产物，所以放在哪里和什么时候清理都很重要。

- 一律建在仓库**外部**，放在 `~/worktrees/<feature>/` 或副盘上专门的 `worktrees/` 目录下。不要建在仓库内部、主工作区旁边或桌面上。
- **不要用 `/tmp` 或 `/var/tmp`。** 那些目录归系统管，随时可能被清理，放在那里的未提交工作已经因此丢失过。
- `<feature>` 用 kebab-case，从分支名或 issue 编号推出；不要加 `wt-` 前缀，父目录已经说明了它是什么。
- 一路提交，不要把所有东西攒到最后。分支是第一道防线，目录只是第二道：一个 WIP 提交不花什么代价，却能扛住检出目录出的任何事。
- 分支合并或废弃后立刻移除 worktree：`git worktree remove <path>`，然后 `git branch -D <branch>`。目录被手工删掉的话跑一次 `git worktree prune`。

清理不是可选的杂务。一个残留的 worktree 会让它完整的构建树一直活着——`target/`、`node_modules/` 和 `gradle-home/` 各自都是几个 GB——几十个被遗忘的 worktree 足以填满一块盘。

删除前先确认安全：分支已并入 `develop`（是 `origin/develop` 的祖先，或者 `git cherry origin/develop <branch>` 报告每个提交都已应用），并且 `git status --porcelain` 没有已跟踪文件的修改。其它情况一律不动，可能还有别的会话在里面工作。
