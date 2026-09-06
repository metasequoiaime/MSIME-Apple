# MSIME-Apple

组织职责见 [组织规范](https://github.com/metasequoiaime/.github/blob/main/AGENTS.md)。平台代码负责 InputMethodKit/UIKit、焦点和系统文本插入；输入算法来自固定 Engine。iOS bridge 使用 `<metasequoia/session.h>` 的动作与快照，macOS 暂用兼容 `InputSession`。新平台代码优先使用公共 Session 接口。

辅助码按会话配置，macOS 候选提示使用控制器持有的同方案只读码表；不要调用全局选择器来切换活动会话，也不要在每次按键上重新加载码表。当前安装器仍提供原有数据目录，`RuntimePaths::legacy()` 在会话创建时捕获该布局；这不表示已接入新的完整资源包或资源代际切换。

桌面词库使用 product-lock.json 的已发布数据及摘要。`vendor/MetasequoiaImeEngine` 同时提供输入引擎、`helpcode/helpcodes/` 和根 `build_profile.py` 移动构建入口；禁止另行检出 Dict/HelpCode 或在 Apple 复制数据算法。Engine gitlink 与已发布词库源提交仍分别记录，不能把构建器提交冒充下载数据的来源。词库格式验证器从固定 Engine 复制，CI 比较字节防止漂移。
