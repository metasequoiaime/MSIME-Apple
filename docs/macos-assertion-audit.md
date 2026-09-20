# macOS 迁移：来源测试断言逐条核对

`docs/macos-feature-inventory.md` 回答「每个源文件去了哪」。这一份回答下一个问题：**来源用测试钉住的每一条行为，在这边是什么状态。** 这是四条比对轴里唯一出过货的一条——另外三条（截图、23 个控制项标识、27 个运行时偏好键）都没有新发现，而这一条找出了「恢复默认设置」。

范围是来源 `platforms/macos/tests` 下全部 93 条 `require(...)` 断言，按测试文件分组。核对方式（可重跑）：

```sh
ref=/path/to/MSIME-apple
grep -rhoE 'require\([^,]*,\s*"[^"]+"' "$ref"/platforms/macos/tests/*.mm "$ref"/platforms/macos/tests/*.cpp \
  | sed -E 's/.*"([^"]+)"/\1/' | wc -l   # 93
```

结论先写在前面：**91 条已对齐，1 条曾是真缺口（已补），1 条是刻意分歧。**

## PreferencesWindowTests.mm（40 条）

设置界面。绝大多数逐条对得上，以下四条值得单独记。

| 断言 | 状态 |
| --- | --- |
| The settings footer restore button was not found. | **曾缺，已补（#3280）。** 这是 93 条里唯一一个真缺口——参考每页底部都有「恢复默认设置」，目标只有「保存设置」。 |
| Selecting Shuangpin left the schema menu disabled. | **曾不一致，已改（#3298）。** 参考是 `_shuangpinSchemeButton.enabled = storedScheme == 1`，目标此前一直可改。 |
| The Wubi settings row remained visible after another scheme was selected. | 已对齐。参考 `_wubiSettingsRow.hidden = storedScheme != 2`，目标是五笔区块的 `draft.scheme === "wubi"` 门控。 |
| Bracket paging UI did not disable edge selection.（及其反向 Edge selection UI did not disable bracket paging.） | 已对齐，而且三条路径都堵住了：开翻页键关以词定字、开以词定字关对应翻页键、以及被占用的键组在单选里直接 `disabled`。所以 `Preferences::validate()` 的 `ConflictingKeyBindings` 在界面上走不到，只是存储层的兜底。 |

其余 36 条覆盖本地输入模式、皮肤卡片、候选窗预览、词库状态行、悬浮工具栏开关、学习数据清除确认、跟随光标与颜色覆盖、侧边栏导航项不可取消选中等，均有对应实现。两处是模型不同而非缺失：

- **标点**：参考用 `alwaysChinesePunctuation` / `alwaysEnglishPunctuation` 两个互斥的钉住标志加一个跟随态；目标用一个 `chinese_punctuation` 状态加独立的 `smart_punctuation` 开关。目标这侧更能表达（参考没有「钉成英文标点同时开智能标点」这种组合）。
- **翻译服务**：参考是单选 provider（账号 / 腾讯 / DeepLX），所以需要「DeepLX endpoint 行跟随选择」这条不变量；目标是三家各自独立的开关与凭据区块，各自的字段在各自区块里，等价保证。

## InputMenuTests.mm（16 条）

输入菜单。逐项一致：中文输入 / 英文输入 / 简体输出 / 繁体输出 / 表情与符号… / 检查更新… / 水杉输入法设置… / 开始或结束语音输入（⌃⌥V）/ 语音输入设置…，连分隔位置与 selector 都相同（`platforms/macos/src/input/InputMenu.h`），目标另有菜单主题处理。本地测试目标 `input-menu`。

## InputControllerKeyRoutingTests.mm（14 条）

11 条是组合输出（你 / 你们 / 爷 / 你好 / 日期），由引擎驱动；目标的等价覆盖是 `ShortcutTest.mm` 的 `TestRealSessionComposition()`（#3240），走真引擎 → 真控制器 → 文本客户端。

- `Wubi auto-commit fired before the fourth code.` — 共享的 `core/WubiCommitPolicy.h`，目标控制器直接引用。
- `IMKCandidates does not support moveUp:/pageUp:.` — 这两条是参考在**记录平台限制**，说明它为什么自绘候选窗。目标同样自绘（`candidate/CandidatePanel.mm`），结论已内化，没有要实现的东西。

## UninstallerTests.mm（12 条）

保留用户数据卸载、连用户数据一起删、重复卸载、bundle 已不在时清残留、报告去向、落入废纸篓。目标是 `crates/host-macos/native/uninstaller.mm`，本地测试目标 `shared-uninstaller`。

## UpdateControllerTests.mm（5 条）

Sparkle 驱动就绪状态、手动检查激活 accessory UI 并转发给 Sparkle、两处缓存不得过期。目标 `core/UpdateController.mm`，本地测试目标 `update-controller`。

## 其余三个文件（6 条）

| 文件 | 断言 | 状态 |
| --- | --- | --- |
| InputSourceRegistrationTests | 注册收到已安装 bundle 的 URL；父输入源找到之前不得启用输入模式 | 目标 `input/InputSourceRegistration.mm`，测试目标 `input-source-registration` |
| CandidateSelectionStateTests | 重置不得留下过期的引擎索引；分页夹具候选数够用 | 目标 `candidate-selection-state`、`candidate-pagination` |
| FloatingToolbarPanelTests | 关掉一个开关再打开要恢复按钮 | 已对齐 |
| FloatingToolbarPanelTests | **四个开关全关，齿轮还在** | **刻意分歧。** 参考的 `MetasequoiaFloatingToolbarItemKeys()` 只有四项，齿轮不可关；目标把齿轮也做成可开关，并多出表情与屏幕键盘两项。理由：目标的工具栏组件本来就更多，且关掉齿轮不困人——输入菜单里仍有「水杉输入法设置…」，手写与语音按钮恒常存在，工具栏不会变成空条。 |

## 这份清单不能证明什么

它证明的是「来源用测试钉住的行为，这边都有对应」，不是「所有行为都一致」——来源没写测试的行为不在这 93 条里。已知的、不打算跟的分歧只有上面那一条齿轮；两处模型差异（标点、翻译 provider）也写在上面，不是遗漏。
