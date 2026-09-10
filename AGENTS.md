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
- 用户已要求暂停私有仓库 CI 以控制费用；GitHub CI workflow 已手动禁用。继续执行本地验证，不得自行启用、手动触发或新增自动 CI；恢复需用户明确要求。
- 用户最新要求以 MSIME-Windows 完整功能为基线迁移 Linux，并适配 Linux 平台特性；当前优先推进 Linux。保留已合并的平台成果，不复制相邻仓库未提交内容。每部分本地验证后及时合并，不堆积 PR；完整迁移仍需 Linux 原生宿主与产品验收。
