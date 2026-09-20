# iOS 功能迁移对照

macOS 的同类文档是 [macos-parity.md](macos-parity.md)。方法沿用那一份：先做存在性比对定位可疑区域，再按行为逐条下钻。本文记录用什么方法比过、发现了什么，不计算完成百分比，也不把比对通过当成完成证明。

## 范围与固定基线

目标是迁移 MSIME-Apple 的 iOS 完整功能，而不是只移植能编译的子集。公共业务放共享层、公共管理界面放 Tauri；输入算法与组合状态仍归 C++ Engine；平台特性按 iOS 自身的机制适配，不照搬来源的实现形态。每部分本地验证后提交合并。

2026-09-21 本轮对照使用以下不可变对象：

- 来源：`metasequoiaime/MSIME-Apple`，`git ls-remote --symref origin HEAD` 确认默认分支 `develop`，远端 HEAD `b93f169839c442cfa7034f3130c3dfaac11b9467`；本机检出与该提交一致。`git status --porcelain -- platforms/ios shared` 只有四个未跟踪的 `bigram.bin` / `trigram.bin` 构建产物，未读取未提交内容。
- 目标：`metasequoiaime/msime` 的 `develop`，固定提交 `10fba7d75`。

来源入口以该检出的 `platforms/ios/`（687 个文件）与 `shared/apple-bridge/`、`shared/backend/` 交叉核对。

## 第一次比对：文件与符号（2026-09-21）

| 维度 | 方法 | 结果 |
| --- | --- | --- |
| 源文件 | 来源 `platforms/ios` 与 `shared` 下 192 个 Swift/ObjC/C++ 文件按文件名在目标检索 | 未命中 66 个，逐个核实后集中在 `shared/apple-bridge/` 与 `shared/backend/`：前者是 ObjC 桥接层，目标以 `crates/host-api` 的 C ABI 取代；后者是 Swift 后端客户端，目标以 `crates/client-core` 取代。属架构差异，逐项确认能力均有归宿 |
| 用户可见文案 | 抽取来源全部源文件的中文字面量，逐条在目标检索 | 1666 条，精确未命中 163 条。其中 119 条是测试断言文案，不构成功能。余下逐条直查，全部已实现，仅措辞不同或已由 Tauri 页以不同表述覆盖 |
| 符号 | 抽取来源 ObjC 方法、C/C++ 函数与 Swift 函数名，按名与按 snake_case 改名在目标全文检索 | 619 个，未命中 84 个。按定义文件归属后逐簇核实：`InputSessionAdapter.cpp`（26）、`MetasequoiaInputSessionBridge.mm/.h`（28）、`CandidateTranslation.cpp`（10）、`MSIMEBackendClient.m/.h`（10）均为下沉到共享 Rust 的桥接层；余下逐个直查，**只有 `ShuangpinKeymap.cpp` 的两个是真实缺口**（见下） |

### 存在性比对看不见什么

与 macOS 那一轮的结论相同，而且这次更明显：**符号在两边都有、行为却不同**的那一类，三次存在性比对一个都抓不到。本轮唯一的真实缺口恰恰是这样被找到的——不是因为符号缺失，而是因为去读了来源在该处写下的「为什么这样做」。

`shared/apple-bridge/ShuangpinKeymap.h` 的注释写着：

> Per-key double-pinyin hint text derived from the engine's own profile, so a frontend never hardcodes a keymap that can drift from the scheme the session actually runs.

目标这边 `shuangpinKeyHints()` 的符号在、调用链在、`KeyboardViewController.updateSchemeButton()` 上方的注释甚至也写着「来自引擎自己的 profile……不会与按键实际产出漂移」——但实现是 `MetasequoiaInputSessionBridge.swift` 里一张手写的四方案 Swift 静态表。注释描述的是来源的做法，代码做的是它警告过的那件事。

把引擎的 `ShuangpinProfile` 逐键展开与那张表对比，确认了两处偏差：

- **内容**：小鹤双拼的 `K` 同时承载 `ing` 与 `uai`，手写表只列了 `ing`。于是打 `guai`（`g`+`k`）的那个键上没有任何 `uai` 的提示。其余三个方案内容一致——但一致是这次的运气，不是机制。
- **格式**：来源的 `" / "` 表示「声母 / 韵母」的分界，同一侧的多个单位用空格分隔；手写表把 `" / "` 当成通用分隔符，于是 `V` 读作 `ui / zh / ü`（三个并列项），而来源读作 `zh / ui ü`（声母 `zh`，韵母 `ui` 和 `ü`）。手道方案的 `E` 甚至排成 `e / sh`，把韵母排到了声母前面。

修复方式是按目标的分层把它接回引擎，而不是修那张表：`engine-bridge` 新增 `shuangpin_key_hints(profile)` 从 `GetShuangpinProfile` 展开，`host-api` 以 `msime_client_shuangpin_key_hints` 发布，iOS 键盘改为读这个 ABI。未知方案名返回空表而不是回落到默认方案——给键盘贴上一套它没在跑的方案，比不贴更糟。这条路径同时对 Android 与 HarmonyOS 的触摸键面可用。

来源的 `uses_shuangpin` 门控在目标侧由 `View.scheme` 承担：引擎无论什么方案都带着一个 profile 被构建，所以 `View.shuangpin_profile` 任何时候都非空，只有 scheme 才说明键面是不是在跑它。

## 第二次比对：成员与断言（2026-09-21）

存在性比对之后补两轮更细的机械核对。

| 维度 | 方法 | 结果 |
| --- | --- | --- |
| 可达控件 | 抽取来源全部 `accessibilityIdentifier` 字面量（254 个），逐个在目标检索 | 未命中 7 个，逐个直查后全部已实现：4 个是目标改了命名或改由参数传入（`emojiCategory-` 用连字符、关闭与删除键走 `headerButton(id:)`），3 个已由 Tauri 页覆盖（社区资源的范围筛选与分享、自定义皮肤重置） |
| 同名文件的成员 | 116 对同名 Swift 文件，逐对抽取 `func` / `var` / `let` 名做差集 | 16 个文件有差集。逐个核实后，只有 `JapaneseNineKeyView` 的一项是真实差异（见下）；其余是目标重构后的等价物（候选注解并成 `KeyboardCandidateAnnotation`、「更多」面板从布尔 `showsLocalModeTools` 换成显式页枚举、表情面板从内存目录换成分页 ABI） |
| 测试断言 | 来源 232 个 `test*` 函数逐个在目标检索 | 按名未命中 33 个。逐簇核对后 26 个已由目标改名或拆分的用例覆盖（目标该区域共 280 个用例，整体是超集），7 个是真正没有强制检查的行为 |

按本仓的证据分级，第三行那 7 条是「有调用链」而没有「有强制检查」——实现都在，只是没有任何东西拦着它们退化。本轮把它们补齐：候选释义预留行的三条契约（总开关关着不留行、取不到的语言不留行、键盘高度按预留行长出来）、释义到达前后格子高度与同页高度一致、释义独占一行、语言表越界回落，以及九键数字键给出英文补全（`65` → `ok`，来自一条用户反馈）。

### 唯一的实现差异：日语模式列的约束写法

来源在 `JapaneseNineKeyView` 里花了一整段注释解释它**换掉**了哪种写法：把每个模式键写成 `modes.heightAnchor × span/4` 加常数，算出来的数是对的，但它是个环——子键的高度引用父 stack，而 `.fill` 的 stack 高度又由子键决定。iOS 26 的求解器凑出了那个唯一解，iOS 27 没有：123 比 ^_^ 高 2.33pt，三个键加缝隙把列撑出 2pt。来源改成只在兄弟键之间表达：单格键彼此等高，跨两格的等于两格加中间那道缝，总高交给 stack 自己的 fill。

目标这边正是被换掉的那种写法。本轮按来源改过来。

**证据边界要说清楚：这条缺陷在本机没有复现。** 把加强后的断言放回旧实现，在 iPhone 18 Pro Max / iOS 27 模拟器上照样通过——它是求解器相关的环，不是算术错误，来源自己的注释也写着「算出来是对的」。所以这一项记为「按来源的证据移植来源的修复」，不是「复现并修好了一个失败」。加强后的断言（单格键彼此严格等高、三个键加两道缝正好等于列高）留在目标里，真溢出时拦得住。

## 套件基线（2026-09-21）

`platforms/ios/README.md` 一直写着该套件「210 通过、1 跳过、0 失败」。在 `origin/develop`（`e45a7f072`）上实测不成立：165 个用例里有 3 个失败（`xcodebuild` 计 8 次断言失败）。逐条查过，三条都是检查本身陈旧，不是产品坏了：

- `testBrandOpensCompactToolsAndUpdatesFeedbackState` 仍在根页找「键盘设置」卡。那一层已被有意删掉——实现里的注释写明了理由（六张一样的入口卡，要再点一次才知道按键音开没开），而同一个用例后面又直接从根页读 `moreCard-按键振动`，自相矛盾。README 的对应句子也停在旧结构，一并更新。
- `testSchemePickerUsesCurrentSkinPalette` 期望选中卡片的填充是 `accent` 的 0.10 透明度，实现是 0.12。0.12 来自来源，是 `f901ea494` 有意对齐的，测试没跟上。
- `testAdditionalEngineSchemesAndLocalProviders` 要求临时英文模式下 `hello` 给出多于一条候选。固定词库发布的 `english.db` 里以 `hello` 开头的词现在正好只有一个，所以它断的是词库内容而不是产品行为。改成断言补全确实以输入开头。

修掉第一条表层的 `XCTUnwrap` 之后，同一个用例往下跑露出了被它挡住的第二层：「设置」分组的开关卡 `maxY` 到 332 / 386，而面板高度是 306。原断言要求每张卡都在折线以上。

这一条没有按字面修，因为它和它所针对的设计相矛盾：面板是滚动视图，实现的注释写明这些开关是**有意**从「键盘设置」二级页搬到根页的，理由是那一层把状态藏了起来，而「面板本来就会滚动，分组标题也已经能区分两类」。所以改成断言设计真正保证的事——每个开关都落在可滚动内容之内（落在内容之外的卡片是滚不到的），而上面五张工具入口卡仍然必须在第一屏。

**这里有一个取舍要你来定，我没有替你决定。** 来源在 `KeyboardViewController` 里写过相反的一条理由：八个本地模式和一份设置列表曾经和工具挤在同一个滚动里，最后一项落在 292pt 面板下方 360pt 处，「没有任何东西说它们在那儿」，于是模式被移进了二级页。现在根页的最后一行开关同样在折线以下约 80pt，区别只在于它上面有一个「设置」分组标题。两种说法都成立：一种说多一层会把状态藏起来，一种说折线以下等于没有。折中的做法是把开关分组改成三列（五个开关两行），根页总高就压回一屏。要改的话说一声。

这三条不进 `scripts/known-failures.txt`：那份文件记的是债务，而这些是检查本身写错了，修掉就没有了。该套件仍不接入 `verify-local.sh`（需要模拟器和已暂存词库，单次约十分钟），所以它没有自动基线，这也是这三条能悄悄红着的原因。
