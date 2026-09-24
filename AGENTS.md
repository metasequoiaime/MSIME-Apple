# AGENTS.md

给在本仓库工作的编码代理的操作约定。**架构边界、验证流程和各平台的验证覆盖面在 [ARCHITECTURE.md](ARCHITECTURE.md)，贡献流程在 [CONTRIBUTING.md](CONTRIBUTING.md)——先读那两份，这里只写它们没有覆盖的操作细节。**

## 改动范围

- 只暂存明确列出的路径，不用 `git add -A`。
- 不复制相邻仓库的未提交内容；上游来源以远端实际默认分支和固定提交为准。
- 日志、测试和提交中不得包含真实输入、凭据或私人资料，测试数据使用合成值。
- CI 会在 Pull Request 上运行，提交前仍先跑本地 quick 门禁。发布 workflow 一律手动触发，不要在任务没有明确要求发布时去碰它们。
- **不要把 Tauri 生成的工程当成某个平台的产品去启动、调试或验收。** 每个平台的产品本体都是 `platforms/<os>` 下的原生宿主，Tauri/React 只是它承载的公共组件（见 ARCHITECTURE.md）。装机、启动和设备验收一律针对原生宿主；`apps/desktop` 的目录名和 Tauri 生成工程里自带的 bundle id 都不构成例外。

## 工具链

- **Xcode 27 的模拟器界面是 `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`，`Simulator.app` 已经不存在了。** `open -a Simulator` 和 `open -b com.apple.iphonesimulator` 都会失败，而 `xcrun simctl` 的 boot、install、launch、screenshot 全都照常工作——于是很容易把「窗口没出现」误判成「模拟器没起来」。设备真实状态以 `xcrun simctl list devices` 为准，要看画面才需要开 DeviceHub。

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
- **`vendor/MSIME-Engine` 必须是真实目录，不能是符号链接**，哪怕是指向另一个 checkout 里已经准备好的那一份。`crates/engine-bridge` 的头文件用 `../../vendor/MSIME-Engine/...` 这样的相对包含，编译器要从 `vendor/MSIME-Engine` 用 `..` 爬回仓库根；`..` 跨过符号链接后去的是**物理**父目录，于是爬到链接目标那边，头文件当场找不到。省磁盘就用硬链接复制（同一文件系统上 `cp -al`，几乎不占额外空间），别用 `ln -s`。
- **只用仓库规定的产物目录，不要自己另起 `CARGO_TARGET_DIR`。** 规定的目录是 `target/`，以及各平台脚本和 README 固定下来的 `target/<platform>-cargo`（`macos-cargo`、`android-cargo`、`ohos-cargo` 等）。每多一个目录，整棵依赖树就要从头再编一遍、再占几个 GB。2026-09-24 有一个 worktree 为不同平台和子任务分别建了 `build/rust-local-asr`、`build/macos-local-asr`、`build/tauri-local-asr`、`build/macos-crossfix`、`build/ios-local-asr`，单它一个就堆到 34 GB；另一个在 `target/macos-cargo` 旁边又建了 `target/macos-isolated`，比规定目录还大一倍。这类目录和另外五六个并行的 worktree 一起，一小时内把 461 GB 的盘写满了三次。产物目录里的东西坏了（典型是 `platforms/macos/README.md` 说的过程宏 dylib），删掉坏的那部分让它重编，不要换一个新目录绕开它。

清理不是可选的杂务。一个残留的 worktree 会让它完整的构建树一直活着——`target/`、`node_modules/` 和 `gradle-home/` 各自都是几个 GB——几十个被遗忘的 worktree 足以填满一块盘。

删除前先确认安全：分支已并入 `develop`（是 `origin/develop` 的祖先，或者 `git cherry origin/develop <branch>` 报告每个提交都已应用），并且 `git status --porcelain` 没有已跟踪文件的修改。其它情况一律不动，可能还有别的会话在里面工作。
