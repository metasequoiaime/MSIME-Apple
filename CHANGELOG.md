# 变更记录

本文件记录共享客户端的公开变更。平台功能和验证范围以各平台 README 及 [实施记录](docs/implementation.md) 为准。

## [Unreleased]

### 新增

- 建立不依赖 Tauri、React 或平台宿主的 Rust 共享层，提供配置、资源安装、输入运行时和版本化宿主接口。
- 通过 CXX 接入固定版本的 MSIME-Engine；输入算法和组合状态继续由 C++ Engine 管理。
- 提供 Android、iOS、macOS、Linux、Windows 与 HarmonyOS 的平台目录、构建入口和迁移文档。
- 增加贡献指南、安全策略、行为准则、问题模板、拉取请求模板和开源发布清单。
- 增加面向贡献者的[架构说明](ARCHITECTURE.md)，集中说明分层、四条不可打破的边界、本地验证流程和平台证据分级；`AGENTS.md` 收敛为编码代理的操作约定。
- 行为准则改用 Contributor Covenant 2.1，并提供举报联系方式。
- 增加[网络请求与数据流向](PRIVACY.md)，逐项记录每个联网功能的发送内容、目的地、默认开关和对应代码位置，并指向 <https://msime.app/privacy/> 的隐私政策。云联想默认开启且会把正在组的拼音发给 Google 输入工具这一既有行为，此前只写在 Android 平台 README 里。
- 增加 `.editorconfig`，记录仓库既有的缩进与换行约定。
- 增加[第三方组件清单](docs/third-party.md)，汇总固定上游、随包资源、各平台 SDK 的许可证与通知文件位置，并标出尚未记录来源的部分。README 现在也明确声明本项目为 GPL-3.0-only。

### 验证范围

- 共享 Rust/C++ 边界、资源校验、配置冲突和宿主接口具备本地测试与快速验证入口。
- macOS、Linux、Android、iOS、Windows 与 HarmonyOS 的当前证据和未完成项目分别记录在平台 README 中。
- Windows 原生 TSF、Linux 图形桌面、移动真机、HarmonyOS 设备、签名、安装包和真实编辑器验收不因源码或交叉编译存在而视为完成。

### 发布说明

- 源码使用 GPL-3.0-only；第三方依赖、固定 Engine 归档、词库、模型和平台 SDK 仍须遵守各自许可证与通知要求。
- 提交前请执行 `bash scripts/verify-local.sh --quick`，并按 [开源发布清单](docs/open-source-release.md) 检查敏感文件、来源和平台发布边界。
- CI 按仓库策略保持停用；本地验证结果是合并和发布前的主要依据。

[Unreleased]: https://github.com/metasequoiaime/msime/compare/develop...HEAD
