# MSIME-Apple

组织职责见 [组织规范](https://github.com/metasequoiaime/.github/blob/main/AGENTS.md)。平台代码负责 InputMethodKit/UIKit、焦点和系统文本插入；输入算法来自固定 Engine。iOS bridge 与 macOS 控制器均使用 `<metasequoia/session.h>` 的动作与快照。平台保存界面选择和产品偏好，不复制输入组合状态机。

本仓默认分支是 `develop`，日常改动从 `develop` 切分支并合回 `develop`；`main` 是发布分支，只在发版时由维护者从 `develop` 合入，`release.yml` 也只监听 `main`。特性分支直接提到 `main` 会被 `Branch guard` 拦下。规则见[组织 AGENTS.md 的分支模型](https://github.com/metasequoiaime/.github/blob/main/AGENTS.md#分支模型)。

辅助码按会话配置，macOS 候选提示使用控制器持有的同方案只读码表；不要调用全局选择器来切换活动会话，也不要在每次按键上重新加载码表。macOS 安装器仍提供原有数据目录，`RuntimePaths::legacy()` 在会话创建时捕获该布局。iOS 启动时校验随包资源，使用 Engine `prepare_runtime_paths` 恢复私有目录中的用户日志并准备词库代际；成功后原子记录活动代际，失败保留原词库。会话显式持有这些路径，切换方案和学习偏好不得退回全局目录。

桌面词库使用 product-lock.json 的已发布数据及摘要。`vendor/MetasequoiaImeEngine` 同时提供输入引擎、`helpcode/helpcodes/` 和根 `build_profile.py` 移动构建入口；禁止另行检出 Dict/HelpCode 或在 Apple 复制数据算法。Engine gitlink 与已发布词库源提交仍分别记录，不能把构建器提交冒充下载数据的来源。词库格式验证器从固定 Engine 复制，CI 比较字节防止漂移。

macOS 每次 Engine 动作完成后更新值快照；候选选择必须用当前快照校验索引与词条。
活动组合继续使用创建时的偏好，组合结束后才按新的 SessionOptions 重建会话。
高亮候选的自动提交调用 Session::finish(index)，剩余分段仍由 Engine 完成。
