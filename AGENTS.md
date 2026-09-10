# MSIME-Apple

组织职责见 [组织规范](https://github.com/metasequoiaime/.github/blob/main/AGENTS.md)。平台代码负责 InputMethodKit/UIKit、焦点和系统文本插入；输入算法来自固定 Engine。iOS bridge 与 macOS 控制器均使用 `<metasequoia/session.h>` 的动作与快照。平台保存界面选择和产品偏好，不复制输入组合状态机。

本仓默认分支是 `develop`，日常改动从 `develop` 切分支并合回 `develop`；`main` 是发布分支，只在发版时由维护者从 `develop` 合入，`release.yml` 也只监听 `main`。特性分支直接提到 `main` 会被 `Branch guard` 拦下。规则见[组织 AGENTS.md 的分支模型](https://github.com/metasequoiaime/.github/blob/main/AGENTS.md#分支模型)。

辅助码按会话配置，macOS 候选提示使用控制器持有的同方案只读码表；不要调用全局选择器来切换活动会话，也不要在每次按键上重新加载码表。macOS 安装器保留原有数据目录；未同步时使用 `RuntimePaths::legacy()`，已有完整快照时按原子发布标记恢复独立词库代际。输入会话持有共享读锁，发布前必须全部空闲并释放会话，独占锁内复核本地版本并确认新会话可创建，之后才切换标记；重建会话仍使用现有偏好。清空学习数据也必须作用于当前代际。iOS 启动时校验随包资源，使用 Engine `prepare_runtime_paths` 恢复私有目录中的用户日志并准备词库代际；成功后原子记录活动代际，失败保留原词库。会话显式持有这些路径，切换方案和学习偏好不得退回全局目录。

桌面词库使用 product-lock.json 的已发布数据及摘要。`vendor/MetasequoiaImeEngine` 同时提供输入引擎、`helpcode/helpcodes/` 和根 `build_profile.py` 移动构建入口；禁止另行检出 Dict/HelpCode 或在 Apple 复制数据算法。Engine gitlink 与已发布词库源提交仍分别记录，不能把构建器提交冒充下载数据的来源。词库格式验证器从固定 Engine 复制，CI 比较字节防止漂移。

macOS 每次 Engine 动作完成后更新值快照；候选选择必须用当前快照校验索引与词条。
活动组合继续使用创建时的偏好，组合结束后才按新的 SessionOptions 重建会话。
高亮候选的自动提交调用 Session::finish(index)，剩余分段仍由 Engine 完成。

`InputSchemePreference.scheme` 的 setter 在目标方案不在 `enabledSchemes` 中时静默替换为 `enabledSchemes[0]`，赋值失败不报错；`enabledSchemes` 存在 app group，跨进程与跨 test bundle 持久化。依赖某个方案的测试必须先在 `setUp` 中接管整个方案集合（`enableAllInputSchemes()`），隐藏方案的 UI 测试必须在 `defer` 中经 `--reset-input-schemes-for-ui-tests` 恢复可见性，否则它留下的状态会让后续 bundle 静默跑在错误方案上。

iOS 个人词库通过 Engine `<metasequoia/personal_dictionary.h>` 校验和编辑；SharedUI 同步文件仅传递用户操作、确认和分页快照，不复制拼音解析或 SQL。键盘仅在完全访问开启且会话空闲时处理队列，写入前释放会话，完成后保留方案、九键和学习偏好重建。操作 UUID 作为 Engine 事务回执 ID，确认文件写入中断后的重试必须复用它。

发布构建：push 到 main 保留 version.txt 的语义版本，仅递增独立 build，以 v<version>-build.<build> 发布 Pre-release。正式升版本通过 release.yml 的 workflow_dispatch（bump_version=true、tag 留空）调用 release-please；tag 输入用于发布已有 draft；tag 与 bump_version 都留空时按 platform 输入新建 draft，这是主动只发布某一个平台的唯一入口。发布覆盖哪些平台：push 由改动路径判定，`platforms/ios` 与 `platforms/macos` 各自只到一个平台，共用代码、Engine、构建系统和发布自动化到两个，未识别的路径也到两个；workflow_dispatch 没有路径区间可判定，改由 platform 输入决定，而 tag 带 `macos-` / `ios-` 前缀时以 tag 为准——draft 的名字在创建时就已经承诺了它装什么。只覆盖一个平台的 build 以 `macos-` / `ios-` 作为 tag 前缀，覆盖两个平台的保持裸名；前缀只属于 tag，产物名不重复携带，release-please 与 Sparkle 读取的正式版本 vX.Y.Z 永远是裸名，所以 bump_version 与带前缀的 tag 都不接受非 both 的 platform 输入。macOS、iOS 和 Sparkle 使用同一 METASEQUOIA_BUILD_NUMBER，安装器版本也使用 build。正式发布后仍须将 main 回合到 develop。
