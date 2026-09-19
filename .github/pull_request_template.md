## 摘要

<!-- 说明用户可见的问题和改动后的行为。保持范围聚焦。 -->

## 影响范围

- [ ] 共享 Rust / client-core
- [ ] React / Tauri 界面
- [ ] Android
- [ ] iOS
- [ ] macOS
- [ ] Linux
- [ ] Windows TSF / Server
- [ ] HarmonyOS
- [ ] 文档或构建工具

## 验证

<!-- 列出实际执行的命令和平台检查。把源码/构建证据与真机或系统验收分开写，级别见 ARCHITECTURE.md。 -->

- [ ] `bash scripts/verify-local.sh --quick`
- [ ] `git diff --check`
- [ ] 下面列出相关的测试、类型检查、fmt、clippy 和原生检查

## 安全与发布

- [ ] 不包含真实输入、凭据、个人资料、私人路径、生成产物或签名材料。
- [ ] 新引入的上游代码、资源、模型和依赖都附有来源与许可证/通知信息。
- [ ] 未执行的平台验证已明确列出。

<!-- 安全漏洞请走私下的 security advisory 流程，不要开公开 PR。 -->
