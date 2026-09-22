# 架构与工程约束

这份文档说明水杉输入法共享客户端的分层方式，以及哪些边界是有意为之、不能顺手打破的。修改代码前请先读这里；具体流程见[贡献指南](CONTRIBUTING.md)，公开发布前的检查见[开源发布清单](docs/open-source-release.md)。

## 分层

仓库按「谁拥有什么状态」分层，而不是按语言或平台分。

```
平台宿主 (platforms/)          系统输入法入口，各自进程
    ↓  C ABI / JNI / CXX / Objective-C++
crates/host-api                版本化 C 接口，线程绑定会话句柄
    ↓
crates/input-runtime           会话编排、焦点、候选分页、带代次的选择
    ↓
crates/engine-bridge           CXX 桥接
    ↓
msime-engine (C++, 固定版本)   输入算法与组合状态
```

`crates/client-core` 与上面这条链路平行，负责本地配置和固定资源的分代安装，不参与按键处理。`packages/ui` 与 `apps/desktop` 是共享的 React 设置页和承载它们的 Tauri 层，各平台共用同一个 Rust 入口库与同一套页面。

**产品本体是 `platforms/<os>` 的原生宿主。** Android、iOS、HarmonyOS、Linux、macOS、Windows 一律如此：最终安装、启动、被系统识别为输入法的都是原生宿主。Tauri/React 是跨平台共享功能与界面的公共组件，由原生宿主按需承载，不单独作为某个平台的产品去启动或验收。`apps/desktop` 的目录名和 Tauri 生成的工程都不改变这一点。

## 四条不能打破的边界

**输入算法归 C++ Engine。** 组词状态机、候选排序、学习回放都在 Engine 里。`input-runtime` 只维护宿主编排和展示状态——它知道当前是第几页、焦点在不在、这次选择属于哪一代快照，但它不知道「ni hao」应该出什么词。在 Rust 侧复制一份组词逻辑，就等于让两份实现开始漂移。

**`client-core` 不依赖 Tauri、React、Engine 或平台宿主。** 平台能力一律通过接口注入。这条保证了它可以被链进任何宿主进程，包括没有 Tauri 运行时的键盘扩展。

**平台库不依赖桌面应用。** iOS 键盘扩展不依赖常驻桌面服务，Android 的 `:ime` 进程不需要设置窗口活着。设置窗口关闭不能结束输入法进程；跨进程的设置变更需要明确的持久化与通知机制，不能靠共享内存里的一个全局变量。

**Windows TSF DLL 与 Server 的进程和协议边界保持不变。** TSF DLL 被系统加载进每个宿主应用的进程，Server 是独立进程，两者之间是显式协议。把逻辑从一侧挪到另一侧之前，先确认它在新的一侧还能满足 TSF 的线程和生命周期要求。

## 上游 Engine

Engine 由 `engine-lock.json` 固定：锁文件记录 Engine 及其第三方源码归档的 commit 和 SHA-256。`scripts/fetch_engine.py` 校验并展开这些归档到被忽略的 `vendor/MSIME-Engine/`，不使用 gitlink、`.gitmodules` 或递归 Git checkout；`crates/engine-bridge` 的 build.rs 在编译前调用它。离线构建可用 `MSIME_SKIP_ENGINE_FETCH=1` 跳过。

引入新的上游代码、字体、图标、模型或服务 SDK 时，同时提交来源提交、许可证文本、通知位置和分发限制。

## 验证

GitHub Actions 负责 macOS、iOS、仓库契约、workflow 质量和依赖审查；`ci-platforms.yml` 在对应平台或共享层有改动时检查 Android（宿主契约与 JVM 冒烟）、Linux（固定容器内构建并跑 ctest）、HarmonyOS（类型检查与键盘逻辑测试）和 Windows（MinGW x64 交叉构建）。Rust workspace 测试和桌面前端测试目前不在 CI 里，只由本地验证覆盖；本地验证也是提交前的快速反馈：

```sh
bash scripts/verify-local.sh --quick   # 只编译，合并前的门禁
bash scripts/verify-local.sh           # 全量
```

Windows 的编译门禁不需要 Windows 机器。装好 MinGW（`x86_64-w64-mingw32-g++`）后，在主工作区跑一次 `platforms/windows/build-cross.sh x64` 把 vcpkg 引导到清单基线，整台机器就位了：之后 `verify-local.sh` 在任何一个 worktree 里都会自动接管这条路径，把 host DLL、TSF DLL、Server 与全部原生测试链接一遍（vcpkg 树从 `MSIME_VCPKG_ROOT`、本工作区的 `target/tooling/vcpkg`、主工作区的同名目录依次查找；编译好的依赖放在该 vcpkg 树旁边共用，不必每个 worktree 各自把 curl 和 boost 再编一遍）。没有这套环境时该阶段仍然跳过，但会把这行命令打出来——它曾经在每台机器上都只打印「skipped」，而背后的原生构建同时坏了六处。

Linux 的 Tauri 外壳同理，只要机器上有 Docker 就不需要 Linux 机器：`verify-local.sh` 会在固定的 `rust:1.97.1-bookworm` 容器里装上 webkit2gtk/gtk3/libsoup 后 `cargo check -p msime-desktop --all-targets`。这一阶段的由来和 Windows 那条一样——`cargo check --workspace` 只看宿主 target，而 macOS 上 `msime-desktop` 因为缺少它当资源列出的 app bundle 被整包排除，于是 Tauri 外壳里所有 `#[cfg(target_os = "linux")]` 分支从来没被任何东西编译过，攒到 36 个编译错误：Linux 的设置窗口、全部共享面板和账号界面根本构建不出来。没有 Docker 时该阶段跳过并打印命令。

Linux 的原生宿主也一样，由 `platforms/linux/build-container.sh` 在同一个容器里编译 IBus engine、Fcitx5 插件、全部 provider 入口和单测并跑 `ctest`。这一条同样是补洞：此前没有任何阶段构建过 `platforms/linux`，而它已经不能配置了——三个测试的相对 include 比源码移动后的层级少一级，其中一个连自己的 fixture 都引不到。这不是单元测试的覆盖问题，是这个平台的产品本体构建不出来。Linux 主机上直接用系统的 ibus 开发包跑，其它主机走容器；两者都没有时跳过并打印命令。这一阶段只编译并跑单测，`platforms/linux/tests/tools/check-container.sh` 仍是需要已验证词库和真实 IBus daemon 的验收运行。

关键在于基线，不在于通过率。几个测试套件有长期存在的失败，所以单看「几个失败」没有意义；合并前唯一要回答的问题是「这次改动有没有弄坏原本能用的东西」。脚本因此把每一阶段失败的**测试名**与 `scripts/known-failures.txt` 对照，只有不在基线里的名字才算回归。那个文件里的每一行都是债务而不是豁免：修好一个就删一行，不要为了让运行变绿而新增。

首次克隆后执行一次：

```sh
git config core.hooksPath .githooks
```

三个钩子分工明确。`pre-commit` 是亚秒级的，只检查冲突标记和暂存 Rust 文件的格式——编译得起来的检查放在后面两个里，因为耗时一分钟的提交钩子会被关掉，然后一个都不剩。`pre-merge-commit` 在合并提交产生的那一刻跑 `--quick`，`pre-push` 作为没走合并路径的提交的兜底。曾有六次编译中断因为「合并了但没构建合并结果」进入 `develop`，`--quick` 正是为此存在。

Rust 改动另需 `cargo fmt` 与 `cargo clippy`；UI 改动另需类型检查和构建。

## 证据分级

平台验证必须按实际执行的层级陈述，不能跨级：

1. 源码与单元测试
2. 跨目标编译或容器构建
3. 模拟器运行
4. 真机或系统入口
5. 安装、签名与真实编辑器验收

交叉编译通过不等于系统入口可用，模拟器跑通不等于真机验收完成。各平台当前处在哪一级，见 [README](README.md#平台目录与状态) 的表格和各平台 README。
