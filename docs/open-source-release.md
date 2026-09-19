# 开源发布清单

这份清单描述仓库可以公开发布的源代码范围，以及生成二进制或平台安装包前仍需完成的工作。它不把本地构建、交叉编译或模拟器测试描述成产品发行验收。

## 源码树检查

- 只提交源代码、锁文件、构建脚本、测试夹具和必要的许可证/通知文件；`target/`、`node_modules/`、Xcode `Pods/`、HarmonyOS `entry/libs/`、本机配置和临时报告由 `.gitignore` 排除。
- 不提交真实输入、账号资料、访问令牌、私钥、证书、签名配置或包含私人路径的运行时 JSON。测试使用合成值，并在日志和诊断中去除输入正文。
- 上游 Engine 及其归档依赖由 `engine-lock.json` 固定提交和 SHA-256；`scripts/fetch_engine.py` 准备到忽略的 `vendor/MSIME-Engine/`，不会把相邻仓库的未提交内容带入本仓库。
- 提交前检查 `git status --short`、`git diff --check`、冲突标记和敏感文件列表；只暂存明确路径。
- 改动涉及出网路径时，同步核对[网络请求与数据流向](../PRIVACY.md)：新增或改变了发送内容、目的地、默认开关的，必须在那份文档里同时更新，并确认与 <https://msime.app/privacy/> 的隐私政策不冲突。

## 许可证与通知

根目录 `LICENSE` 是 GPL-3.0-only。Rust workspace、Linux 元数据和共享客户端默认使用同一许可证，但上游代码、Gradle、ML Kit、Engine 资源、词库、模型和系统 SDK 仍以各自许可证和通知为准。

用了谁、各自什么许可、通知文件在哪，汇总在[第三方组件清单](third-party.md)；下面几条是它没有覆盖的发布动作。

- Android Gradle 模板的 Apache-2.0 文本在 `apps/desktop/src-tauri/gen/android/gradle/LICENSE-2.0.txt`，来源说明在同目录 `NOTICE.md`。
- iOS ML Kit 依赖通知在 `platforms/ios/SharedResources/MLKit-NOTICES.txt` 和 `MLKit-Dependencies.txt`。
- Windows 依赖通知由 `platforms/windows/Collect-Notices.ps1` 生成；使用说明和限制见 `platforms/windows/Notices.md`。生成器不是完整许可证审计，不能用空通知文件代替上游材料。
- `engine-lock.json` 中的每个上游归档、固定词库和离线模型都必须在发布包中保留对应的版权、许可证和来源说明。资源锁文件只校验内容，不授予额外分发权。
- 日文词库 `dict_japanese.dat` 的许可证要求是硬性的：IPAdic 与 ICOT 的条款都规定许可证文本必须随词库分发，所以发布物中必须包含 `mozc_dictionary_oss_README.txt`。逐条构成见[第三方组件清单](third-party.md#日文词库的分发义务)。
- 整句重排模型的训练语料署名嵌在 `sentence-model.safetensors` 的 safetensors `__metadata__` 头里。原样分发该文件即满足要求；重新导出、量化或转换权重时必须把 `attribution` 字段带过去，见[第三方组件清单](third-party.md#整句重排模型的署名要求)。
- 引入新的上游代码、字体、图标、模型或服务 SDK 时，同时提交来源提交、许可证文本、通知位置和分发限制；不要只在 README 写一个链接。

## 验证与发布边界

合并前执行 `bash scripts/verify-local.sh --quick`；声称功能完成前执行完整版，并把失败项与 `scripts/known-failures.txt` 对照。Rust 改动还需测试、fmt、clippy，UI 改动还需类型检查和构建。CI 按仓库所有者政策停用，不手动触发、恢复或新增 workflow。

平台证据必须按范围写明：源码/单元测试、跨目标或容器构建、模拟器运行、真实设备/系统入口、安装/签名和真实编辑器验收是不同层级。缺少后两层时，不得把交叉编译、静态检查或模拟器结果写成 Windows TSF、Linux 桌面、iOS 键盘扩展、Android 真机或 HarmonyOS 产品已完成。

## 发布前人工确认

1. 确认远端默认分支、版本号和变更日志与待发布提交一致。
2. 重新检查 `README.md`、各平台 README、`docs/implementation.md` 和本清单中的路径、命令与当前目录一致。
3. 生成对应平台的第三方通知和资源许可汇总，确认不包含本机绝对路径、凭据或未授权模型/词库。
4. 对每个平台分别记录构建工具版本、签名状态、安装方式、设备/编辑器范围和未执行项目；开发签名、测试账号和测试资源不得进入正式发布物。
5. 发布源代码时附带 `LICENSE`、第三方通知和固定上游来源；发布二进制时同时提供对应的源代码、许可证和重新构建说明。

安全问题通过 [安全策略](../SECURITY.md) 的私下报告入口提交，不要在公开 issue、PR 或发布附件中披露秘密或真实输入。
