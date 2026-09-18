# 变更记录

本文件记录共享客户端的公开变更。平台功能和验证范围以各平台 README 及 [实施记录](docs/implementation.md) 为准。

## [Unreleased]

### 新增

- 建立不依赖 Tauri、React 或平台宿主的 Rust 共享层，提供配置、资源安装、输入运行时和版本化宿主接口。
- 通过 CXX 接入固定版本的 MSIME-Engine；输入算法和组合状态继续由 C++ Engine 管理。
- 提供 Android、iOS、macOS、Linux、Windows 与 HarmonyOS 的平台目录、构建入口和迁移文档。
- 增加贡献指南、安全策略、行为规范、问题模板、拉取请求模板和开源发布清单。

### 验证范围

- 共享 Rust/C++ 边界、资源校验、配置冲突和宿主接口具备本地测试与快速验证入口。
- macOS、Linux、Android、iOS、Windows 与 HarmonyOS 的当前证据和未完成项目分别记录在平台 README 中。
- Windows 原生 TSF、Linux 图形桌面、移动真机、HarmonyOS 设备、签名、安装包和真实编辑器验收不因源码或交叉编译存在而视为完成。

### 发布说明

- 源码使用 GPL-3.0-only；第三方依赖、固定 Engine 归档、词库、模型和平台 SDK 仍须遵守各自许可证与通知要求。
- 提交前请执行 `bash scripts/verify-local.sh --quick`，并按 [开源发布清单](docs/open-source-release.md) 检查敏感文件、来源和平台发布边界。
- CI 按仓库策略保持停用；本地验证结果是合并和发布前的主要依据。

[Unreleased]: https://github.com/metasequoiaime/msime/compare/develop...HEAD
