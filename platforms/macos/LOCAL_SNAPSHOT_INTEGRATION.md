# 完整词库快照的本地接入

云端备份/恢复与本地词库替换是两条不同的链路。这份文件说明后者：一份完整的词库快照怎么从 SwiftUI 界面走到 Engine，以及这条路上的边界由谁负责。

## 链路

`BackendSnapshotView.swift` 的 `downloadForLocal` / `applyLocal` 调用 `BackendLocalSnapshot.swift`，后者按名字动态查找共享的 `MSIMEClientSession`，用 `snapshotVersion:`、`prepareSnapshot:`、`applySnapshot:`、`discardSnapshot:` 四个选择器完成整个流程；激活前先用 `snapshotActivationReady` 确认会话空闲。

`shared/apple/MSIMEClientSession.{h,mm}` 把这些选择器转成 `crates/host-api/include/msime_client.h` 里的 C ABI：`msime_client_snapshot_version`、`msime_client_snapshot_inspect`、`msime_client_snapshot_prepare`、`msime_client_snapshot_discard`、`msime_client_snapshot_activate`、`msime_client_snapshot_restore` 和 `msime_client_snapshot_queue`。记录流由宿主以 `msime_client_snapshot_next` 回调逐条同步喂进去：正数表示一条 UTF-8 JSON 的长度，0 只在校验过的 EOF 处返回，负数表示取消或损坏，回调本身不得抛出或栈展开。

Rust 侧的实现在 `crates/host-api/src/dictionary_snapshot.rs`（记录解析在 `dictionary_snapshot/record.rs`）。`inspect` 先校验完整的 NDJSON 信封——头尾顺序、整段 body 的校验和、分类顺序和记录边界都属于云端格式的一部分；Engine 记录更深一层的、按方案区分的校验放在 prepare 阶段。准备句柄登记在进程内的注册表里，`activate` 只接受未过期的句柄并比对期望版本，发布前做原子替换，失败时把原目录搬回来；回滚之后留下的空备份目录才会被删掉，`remove_dir` 对非空目录的拒绝正是这里要的保护——那时备份可能是用户词库仅剩的一份。

`shared/apple-bridge/DictionarySnapshotBridge.{h,mm}` 是 macOS 宿主与 iOS 键盘共用的那层记录流/状态版本适配，`shared/snapshot`（Swift Package）负责快照文件格式本身的校验与上传。

凭据和网络请求留在 Swift 后端，不进入 `client-core`。`engine-bridge` 的 `EngineSession.snapshot()` 返回的是编辑串/候选这类输入状态，与词库快照无关。

## 边界

- 准备阶段不修改活动词库，只在隔离的客户端用户目录里落暂存数据，用的是已校验资源。
- 预览之后发生本地学习、编辑或代次切换时，版本比对会让本次覆盖失败，而不是静默覆盖。
- 激活要与现有会话和跨进程词库访问锁协调：探测到新代次成功后才原子发布，并重建当前运行时会话、使旧候选回调失效。失败保持旧安装可用。
- 取消、应用失败和窗口关闭都走 `discardSnapshot:`，清理只动 staging，不碰活动代次。

## 本地验证

`snapshot-activation-test` 链接 `apple-client`，需要显式运行并传入一份与 `resources/desktop-dictionary.lock.json` 匹配的已校验资源目录：

```sh
cmake --build <build-dir> --target snapshot-activation-test
<build-dir>/snapshot-activation-test /absolute/path/to/verified-desktop-resources
```

它在新建的临时目录里准备用户数据和暂存快照，验证真实激活、英文模式开关的保留、导入词条的候选与提交，成功后删除测试状态，不修改传入的资源目录或实际用户词库。Rust 侧的单元测试在 `crates/host-api/src/dictionary_snapshot/tests.rs`，覆盖信封校验、记录边界、句柄生命周期与激活失败路径。

上游对照：MSIME-Windows 远端默认分支 `develop`，本文写作时查询到的头为 `04a8df56f86312474a069f4335a1b58da7afaa9e`。
