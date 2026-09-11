# 完整词库快照接入：未完成

此记录界定当前缺口，不代表功能交付。总体目标仍是完整功能迁移；不能以个人词条导入替代完整快照恢复。

## 已核对证据

- MSIME-Windows 远端实际默认分支为 `develop`，本次查询固定头为 `04a8df56f86312474a069f4335a1b58da7afaa9e`。该版本是后续完整功能对照基线，不表示本文已完成 Windows 全功能审计。
- `BackendSnapshotView.swift` 的 `downloadForLocal` / `applyLocal` 调用 `BackendLocalSnapshot.swift`，后者动态查找 `MSIMEMacDictionarySync`。
- 此类仅在保留的 `DictionaryRuntime.mm` 内实现；当前 `CMakeLists.txt` 的 app 编译 `ClientDictionaryRuntime.mm`，不编译该文件。Swift 编译成功不能证明本地恢复可用。
- 旧实现依赖 `RuntimePaths::legacy()`、bundle 词库摘要和 `MetasequoiaInputController.suspendForCloudDictionarySwitch`；当前宿主是 `MSIMEInputController`，会话由 host-api 管理。直接加入旧文件不构成正确接入。
- `shared/apple-bridge/DictionarySnapshotBridge` 有准备记录流、计算状态版本和丢弃非活动代次的参考实现；不能绕过现有共享资源/词库访问边界直接发布旧宿主安装。
- `crates/host-api/include/msime_client.h` 与 `shared/apple/MSIMEClientSession.h` 尚未提供完整词库准备、激活、清理接口。
- `engine-bridge` 的 `EngineSession.snapshot()` 返回编辑串/候选等输入状态，不是词库快照；`host-api/src/cloud_dictionary.rs` 的请求校验也不是恢复实现。

## 必须完成的接入链路

1. 在 Engine/engine-bridge 边界实现完整快照记录流准备，保留个人词条、基础覆盖/删除、固定位置及选择计数语义。复用已校验资源和隔离的客户端用户目录，不读取旧产品目录。
2. 在 host-api 提供拥有明确生命周期的准备句柄：创建、提交、丢弃；拒绝无效/过期句柄。凭据和网络请求继续留在 Swift 后端，不能进入 client-core。
3. 读取一致的本地版本；在预览后发生本地学习、编辑或代次切换时拒绝覆盖。准备阶段不能修改活动词库。
4. 激活必须协调现有所有会话与跨进程词库访问锁，拒绝繁忙组合或采用可验证的延期方案；探测新代次成功后原子发布，重建当前运行时会话并使旧候选回调失效。失败保留旧安装可用。
5. 通过 `MSIMEClientSession` 暴露给 macOS 的同步适配器，接通现有 SwiftUI 预览/确认/取消流程；不使用旧 C++ 宿主的静态全局会话。
6. 明确取消、应用失败、应用成功及窗口关闭后的 staging 清理策略；不得删除活动代次。

## 验收证据（均仍待补齐）

- 合成记录覆盖全部记录类别、四种词库、删除/固定位置/调频恢复；不能只验证词条数量。
- 超限、截断、损坏摘要、非法资源路径、重复/冲突记录在发布前被拒绝。
- 预览后本地版本变化、跨进程锁竞争、非空组合、会话重建失败时原词库保持可用。
- 取消、重复清理、过期句柄、重复提交和激活后的清理不损坏活动代次。
- 当前原生 app 实际包含同步适配器且调用真实 host-api；selector 存在本身不足以证明恢复成功。
- 隔离资源下，在已确认当前输入源 ID 的真实编辑器中，恢复前后候选/上屏变化来自目标 MSIME 会话；恢复环境和原输入源也需确认。
- 修改 Rust 后执行测试、fmt、clippy；Swift 与原生宿主执行对应构建/测试。GitHub CI 保持暂停。

## 当前结论

云端备份/恢复与本地词库替换是不同链路。已有 Swift 模型测试、dylib 加载测试、设置窗口观察均不能用于宣称本地完整词库替换已接通。本项在上述证据齐全前保持未完成。
