# HarmonyOS 功能迁移对照

iOS 与 macOS 的同类文档是 [ios-parity.md](ios-parity.md) 和 [macos-parity.md](macos-parity.md)。方法沿用那两份：先做存在性比对定位可疑区域，再按行为逐条下钻。本文记录用什么方法比过、发现了什么，不计算完成百分比，也不把比对通过当成完成证明。

这份文档此前不存在，而另外三个平台都有。缺的代价是具体的：每一轮审计都得从头重建方法，上一轮排除过的区域下一轮还要再排除一遍，而"这里查过，结论是 X"这件事没有地方记。

逐文件的落点清单在 [harmony-feature-inventory.md](harmony-feature-inventory.md)：来源的 145 个产品源文件，一个不漏地写明在这个仓库里落到了哪里。那份记「列全」，这份记「怎么比的、发现了什么」。

## 范围与固定基线

目标是迁移 MSIME-Apple 的完整功能，而不是只移植能编译的子集。公共业务放共享层、公共管理界面放 Tauri；输入算法与组合状态仍归 C++ Engine；平台特性按 HarmonyOS 自身的机制适配，不照搬来源的实现形态。每部分本地验证后提交合并。

2026-09-21 本轮对照使用以下不可变对象：

- 来源：`metasequoiaime/MSIME-Apple`，本机检出 `58608929fa7f39b9aaed93b9ed3ed706212821c0`。`git status --porcelain -- platforms shared` 只有四个未跟踪的 `bigram.bin` / `trigram.bin` 构建产物，未读取未提交内容。
- 目标：`metasequoiaime/msime` 的 `develop`，固定提交 `8011f6dda`。

来源入口是该检出的 `platforms/ios/` 与 `shared/`。HarmonyOS 的对照面是 `platforms/harmony/entry/src/main/ets`、`apps/harmony/src` 与它渲染的 `packages/ui/src`——鸿蒙的设置界面就是那份共享 React 页，所以对照面必须把它算进来，只比 ArkTS 会把一整层功能误判成缺失。

## 第一次比对：客户端能力面（2026-09-21）

最有信号的一条轴不是文件也不是符号，而是 `SettingsClient`：共享设置页按宿主声明的能力决定画什么，所以"Android/iOS 提供而 Harmony 不提供的成员"就是"同一份页面在鸿蒙上少的那几块"。

把 `packages/ui/src/index.tsx` 的 `SettingsClient` 成员、`apps/desktop/src/core/mobile-host-services.ts`（Android 与 iOS 两个移动宿主共用）与 `apps/harmony/src/main.tsx` 做三方差集，本轮开始时缺八项：`chat`、`account.settingsSync`、`customSkinLibrary`、`communitySkins`、`communityResources`、`aiSkins`、`home`、`appIcon`。

前七项本轮全部接上（PR #3327、#3331、#3334、#3336、#3338、#3341、#3343）。`appIcon` 不接，原因见下。

这条轴的好处是它不会因为措辞不同而误报，坏处是它只看得见"页面级"的缺失：一整块没有会被抓到，一个区块里少一节不会。本轮后面两个缺口都是后者。

### 更正：这条轴的基线一度取错了

第一次写这一节时，差集是拿 `apps/desktop/src/core/mobile-host-services.ts`（Android 与 iOS 共用）做的，于是结论写成"只剩 `appIcon`"。那个基线漏掉了**桌面宿主提供而移动宿主不提供**的 20 个成员。把三方都算进来之后，鸿蒙没有提供的是 21 个：

| 成员 | 判定 |
| --- | --- |
| `appIcon` | 本平台无公开 API，见下文「不迁移的」 |
| `windowControl`、`beginWindowDrag`、`resizeWindow`、`onWindowStateChanged` | 共享页自绘标题栏与缩放把手，由 `window_chrome` 能力门控，仅桌面 |
| `restartInputMethod`、`installInputSource`、`uninstallInputSource` | 重启输入法与安装输入源；`restart_input_method` 能力对鸿蒙为 false，后两个是 macOS 的 IMK bundle |
| `loadMacosShuangpinKeymap`/`save…`、`loadMacosWubiAutoCommitUnique`/`save…` | macOS 存在原生 defaults 域里的四个开关 |
| `openScreenKeyboard`、`openHandwriting`、`openVoice` | 桌面把这三个开成独立面板窗口；本宿主它们是键盘自己的面（`SURFACE_*`） |
| `pickVoiceModelPath` | 按路径加载本地语音模型；本宿主用系统识别器或 HTTP provider |
| `resetLearnedData` | 共享 C ABI 对移动端明确返回 `learned-data reset is unavailable on mobile` |
| `clipboard` | 设置页里的剪贴板历史列表。**iOS 与 Android 也都不提供**——Apple 的剪贴板管理在键盘的 `KeyboardClipboardView` 里，对应本宿主的 `SURFACE_CLIPBOARD` |
| `resolveFontFamilies` | 候选字体预览的字族解析。iOS 的 `candidate_font_controls` 为 false，根本不显示候选字体控件；本宿主与 Android 一致 |
| `loadDefaultPreferences`、`openThirdPartyLicenses` | 「恢复默认设置」与第三方许可。**MSIME-Apple 的 iOS 上都不存在**（iOS 的「恢复默认」只作用于皮肤设计和键盘布局），属桌面功能 |

**逐条核过之后，21 个里没有一个是 MSIME-Apple iOS 有而鸿蒙缺的功能。** 但原先那句"只剩 `appIcon`"是拿错基线量出来的，读者无从发现，所以把完整分类写在这里而不是改掉那句话。

## 第二次比对：中文文案（2026-09-21）

抽取来源全部非测试源文件里含汉字的字符串字面量，逐条在鸿蒙宿主与共享 UI 的语料中精确检索。

| | 数量 |
| --- | --- |
| 来源产品文案（已排除仅出现在测试文件中的 281 条） | 1373 |
| 精确未命中 | 729 |
| 其中含 Swift 插值 `\(…)`，按构造不可能命中 TypeScript 语料 | 108 |
| 其余纯字面量 | 621 |
| 纯字面量中只出现在键盘侧（`KeyboardExtension` / `SharedUI`） | 125 |

**这个数字本身没有意义，得说清楚为什么。** iOS 那一轮的未命中是 161/1666，因为 iOS 直接复用同一份 Tauri 页，文案是同一批字符串；鸿蒙的键盘界面是自己的 ArkTS，设置页虽然共用但历史上由不同的人分别写过说明文字，所以措辞不同是常态而不是异常。抽样 30 条应用侧未命中逐条核对，全部是已实现功能的不同措辞（云词库、社区、皮肤编辑器、AI 皮肤、对话、个人词库）。

这条轴的价值不在比率，而在于**它会指出哪些"节"在目标里完全没有对应概念**。本轮它指出了一处：

### 查实的缺口一：词库页缺「词库信息」

来源 `FeatureSettingsViews` 在词库页写明装的是哪套词库——规格、上游提交、以及它随应用更新而不单独下载。共享设置页没有这一节，所以任何宿主都没有，鸿蒙也没有。

数据本来就在设备上：随应用安装的词库带着一份清单，鸿蒙已经把它作为引擎资源暂存了。缺的只是一条读出来的路。已补（PR #3418），那一节加在共享页而不是鸿蒙自己的界面里——每个能回答这个问题的宿主都该显示它。

## 第三次比对：键盘侧逐面板（2026-09-21）

按面板把来源的键盘扩展与鸿蒙的 `KeyboardView` 对起来。名称匹配在这条轴上没用——鸿蒙几乎每个都改了名（`CandidateTranslationStore` → `TranslationPolicy`、`EmojiCatalog` → `EmojiCatalogModel`、`HandwritingInputView` → `HandwritingStrokePolicy`），所以是按功能对。

| 来源面板 | 鸿蒙 | 结论 |
| --- | --- | --- |
| Symbol / Emoji / Clipboard / Scheme / Skin / More / Tool | `SURFACE_*` 十余个面与 `symbols` 切换 | 已覆盖；布局选择并入方案选择器，与共享 `touch_keyboard_schemes` 模型一致 |
| `JapaneseNineKeyView`、`HandwritingInputView` | 日语面与手写面 | 已覆盖 |
| `KeyboardVoiceView` | 语音面 | 来源那一套是 iOS 的变通：键盘扩展不能录音，所以 App 录完把文字交接给键盘（`VoiceTextHandoffStore`、「发送到键盘」「等待键盘插入」整组文案）。鸿蒙键盘自己能录音，这一整个交接面**不该有**，缺失是正确的 |
| `HandwritingInputView` 的模型下载流程 | 无 | 同上：来源要联网下载 Google 手写模型，鸿蒙用系统 Core Vision Kit OCR，没有模型可下 |
| `KeyboardAIView`（AI 润色） | 无 | **真实缺口**，见下 |

### 查实的缺口二：键盘没有 AI 润色

来源和 Android 的键盘都有 AI 润色，鸿蒙只有语音结果的润色——`HarmonyVoicePolisher` 写好了，调用方只有识别器一个。已补（PR #3414）。

来源润色的是**选区**。HarmonyOS 不给输入法读取选区的能力（`InputClient` 只有光标前后的文本，选区只以下标通知），所以照抄手势等于画一个不知道自己在操作什么的按钮；改为润色光标前的文字。这是本轮"按平台特性适配"最典型的一处。

### 查实的缺口三：键盘一个字也不念

来源 `KeyboardViewController` 有 55 处 `accessibilityLabel`。鸿蒙 `KeyboardView.ets` 里 `.accessibilityText()` 出现 **0 次**。

而 `LetterKeyFacePolicy.accessibilityLabel`、`EnglishLetterCaseState.accessibilityLabel/accessibilityValue`、`JapaneseVariantPolicy.accessibilityLabel`、`CandidateGlossPolicy.accessibilitySuffix` 四份标签策略**都已经移植过来、都有单测，调用方只有它们自己的测试**。标签算出来了，从没挂到任何控件上。已补（PR #3419）。

这一条值得单独记：它正是 iOS 那份文档说"存在性比对抓不到"的那一类——两边符号都在，行为不同。抓到它靠的是从渲染那一端反过来数：不是问"标签在不在"，而是问"有没有人把标签挂上去"。四组绿色断言让它看起来是有覆盖的。

## 不迁移的：应用图标切换

来源 `AppIconSettingsView` / 共享页的 `SettingsClient.appIcon`。**本平台没有公开 API**，详细核查记录在 [platforms/harmony/README.md](../platforms/harmony/README.md)：API 24 的 `@ohos.bundle.bundleManager` 对自身只读，`@ohos.bundle.shortcutManager` 只管快捷方式可见性，`api/` 与 `kits/` 下没有 `setAbilityEnabled`，也没有任何形式的 alternate/dynamic icon。

按能力模型处理：宿主不声明，页面不画那个控件。这是裁剪，不是欠账。

## 存在性比对看不见什么

与 iOS、macOS 两轮的结论相同，本轮又添了一个更尖锐的例子。三条轴里：

- 能力面比对只看得见页面级的缺失，看不见区块里少一节（缺口一是这么漏过去的）。
- 文案比对会被措辞差异淹没，在鸿蒙这种"键盘界面各写各的"的平台上尤其严重；它的产出是线索而不是清单。
- 逐面板比对能找到整块缺失（缺口二），但对"挂上了没有"无能为力（缺口三）。

缺口三只有一种方法能抓到：**去数渲染侧的调用点，而不是数定义**。移植一份策略、给它写好单测、然后忘记接线，三道检查都会是绿的。

这一条后来机械化了。`scripts/test-harmony-unwired-policies.py` 从导入方向问一个测试套件结构上问不出的问题——*除了测试之外，有没有东西到得了这个文件*——因为套件自己 import 那个模块，所以无论应用是否调用它，断言都会通过。它在本轮抓到两次：#3419 的原始缺陷（四份策略没接线），以及 #3435 那次合并把同一状态放回去（文件和它的测试一起消失，断言数从 1293 掉到 1289，全绿）。写好当天它还立刻抓到一处既有的：`6a865d6e8` 那次拆分把 `PreferenceStore.ts` 移进 `settings/` 却留下了旧副本，两份都没有调用方。那两条按 `known-failures.txt` 的先例记成债务而不是豁免——名字重新可达时这道检查会失败，所以名单不会烂成一串谎话。

本轮之后新增的 `scripts/test-harmony-bridge-parity.py`（PR #3343）是同一类问题的机械防线——它比的是"页面会调用的桥方法"与"真正注册出去的名字"，而不是两边都有没有这个符号。它当初就是这么抓到 `customSkinLibrary` 的。

## 第四次比对：来源自己的测试断言（2026-09-21）

前三条轴比的都是"有没有这个东西"——页面、文案、面板、调用点。全都通过之后仍然剩下一类东西看不见：**同一个东西在两边行为不同**。文件在、接线在、测试绿，但做的事不一样。

这一轮的轴是 MSIME-Apple 自己的测试套件。`platforms/ios/{KeyboardTests,ServiceTests,tests}` 与 `shared/backend/Tests` 共 232 个 `func test*`、1276 条断言，函数名本身就是行为规格。做法是把这 232 个名字读一遍，挑出属于键盘宿主（而非共享设置 UI、而非 Engine）的那些，逐个去鸿蒙侧找对应实现。

`NineKeyKeyboardTests.swift` 一个文件占了 48 条，是最大的一块，所以从它查起。绝大多数能对上：`CandidateChipsNeverWrapToASecondLine` 对 `CandidateWrapPolicy`、`SpaceCursorMovementAccumulatesDistanceAndReverses` 对 `SpaceCursorMovement`、`WubiCandidatesCarryAndShowTheCodeLeftToType` 对 `WubiCodeHintPolicy`、`SchemeGridHasFourColumnsAtNarrowAndWideSizes` 在模拟器截图里就是四列，等等。

对不上的是 `testLatinFieldsUseFullKeyboardAndRestoreNineKeyHeight`。鸿蒙侧 `EditorPolicy.prefersLatin` 有、也接了线，attach 时会把 Engine 切到英文；但它只改语言不改键面，`KeyboardView.onEditorChanged` 里只有 `this.english = ...` 一行。于是一个九宫格用户点进邮箱或网址框，得到的是**在 3×3 的 T9 网格上打英文**——恰恰是 Apple 那条断言刻意避免的情形。三道机械门禁都抓不到：文件在、接线在、单测绿，缺的是一个本该发生却没发生的赋值。

这条轴的成本高于前三条（要读来源的测试体，不只是名字），但它是唯一能看见"行为不同"的。修法与实测记在 `platforms/harmony/README.md` 的「地址栏与密码框拿到的是整块字母键面」。

同一条轴接着找到了更大的一处：`NineKeyInputAndLayoutSwitches`、`ShiftIsDiscoverableAndSwitchesToEnglishCapitalization`、`SymbolKeyOpensAPanelInsteadOfAMenu` 这些断言都默认九宫格上有一行动作键，而鸿蒙侧那一行写在 26 键分支内部，三块自绘键面全都没有它——九宫格和日语假名格没有空格、没有回车、退不出英文。`NineKeyDigitLayerKeepsTheGridInsteadOfTheTwentySixKeyRows` 和日语的 `DigitLayerKeepsTheSameThreeColumnGrid` 则对应另一处：按 `123` 会掉进十列符号排。两处一并修了，同样记在 README。

## 文件可达不等于符号可达

`test-harmony-unwired-policies.py` 问的是"除了测试之外有没有东西到得了这个文件"。修九宫格时发现同一个问题在方法这一层还在：`JapaneseNineKeyLayout.digitKeys()` 和 `digitBrackets()` 定义好、测试写好、产品从不调用，而因为 `JapaneseNineKeyLayout.ts` 本身被大量 import，那道门禁是绿的。

扫描做成了 `scripts/test-harmony-unwired-symbols.py`，判据与文件级那道一致：除声明处和测试之外，没有东西按 `类名.方法(` 的形式引用它。写这个脚本本身踩了两次坑，都会让数字偏低：

- 按裸方法名 `.method(` 匹配会撞名。`CandidateGlossPolicy.isCurrent` 一直显示为已接线，只因为 `HarmonyDoubaoRecognizer` 有个同名私有方法。第一版报 14，实际 21。
- 按"文件里第一个导出类"归属方法是错的，一个文件可以导出多个类（`ClipboardHistoryStore.ts` 导出六个），于是报出六个根本不存在的 `ClipboardHistoryError` 方法。现在按类体范围归属。

脚本有两张名单，区别就是全部意义所在。`ALLOWED` 是本平台永远不会调用的——它回答的那个问题 HarmonyOS 不问，每条写明是什么差异。`PENDING` 是应该接而尚未接的，写明背后的缺口**具体是什么**；诊断清楚才能进，写"还没做"不算条目。两张都是棘轮：名单上的名字一旦变得可达就报错，没上名单的新符号直接报错。`PENDING` 应当归零，`ALLOWED` 不必。

当前：250 个宿主静态方法，8 条平台差异，6 条已诊断待接。

## 第三次静默回退，和这次能抓住它的东西

`#3457`（自动大写）合进 develop 之后又整片消失了。`1d4864685 Merge branch 'develop' into feat/android-splash-screen` 把 `KeyboardSession.ets` 的冲突解成了该分支的旧侧，`#3459` 再把这个结果带回 develop。提交还在历史里（`4982e3f2f`），文件里的东西没了：`shouldShiftNextLetter`、`applyAutomaticCase`、`capitalizationFor` 全部为零，而同期的 `#3449`、`#3452` 完好。

这是同一类事故的第三次（`#3419` → `#3435` → `#3457`），三次都是绿的：回退之后的树自洽，断言数只是变小一点，所有门禁照过。

**这次有东西能抓住它。** 把本片新增的符号门禁拿到回退后的 develop 树上跑，它红了，点名的正是 `#3457` 接线的那两个：

```
EditorPolicy.capitalizationMode
EnglishCapitalizationPolicy.shouldShift
```

道理很简单：一次回退把接线去掉之后，被移植的策略重新变成"有测试、没有调用方"，而这正是这道门禁问的问题。`verify-local.sh --quick` 里已经加上，所以下一次同样的合并会在推之前就红。

## 来源断言会给出假阳性，只有设备能判

`ReturnKeyAction.shouldPerformEditorAction` 本来在 PENDING 里，理由看着很硬：键面对不可执行的动作已经显示"换行"，而 `submit()` 无条件 `sendKeyFunction(enterKey)`，那不就是键上写着换行、按下去不换行吗。

接上去之后在模拟器上一测，文本框里两个字符挤在同一行——`insertText("\n")` 被 WebView 忽略了。把改动退回原样再测同一个框（`enter=8`，即 `ENTER_KEY_TYPE_NEW_LINE`），换行**正常出现**。也就是说 `sendKeyFunction` 拿到 enter key type 之后框架自己就把换行做了，Android 需要宿主二选一的那个分叉在这里不存在。

这条移到了 `ALLOWED`，理由里写的是实测而不是推断。教训是这条轴的性质：来源的断言说明**存在这样一条规则**，但不说明**这条规则该由谁实现**。平台已经实现了的，照搬过来就是回归。判据只能是设备。

## 本轮合并的切片

| PR | 内容 |
| --- | --- |
| #3327 | 账号 AI 对话 |
| #3331 | 账号设置同步 |
| #3334 | 具名自定义皮肤库（新增 C ABI，复用 `CustomSkinLibraryStore`） |
| #3336 | 社区皮肤画廊、下载与试用 |
| #3338 | 社区词库与回复模板 |
| #3341 | AI 生成皮肤 |
| #3343 | 桥注册缺陷修复 + `test-harmony-bridge-parity.py` + 首页 |
| #3345 | 应用图标：记录本平台无公开 API |
| #3411 | 个人词库文件导入（走同步队列） |
| #3414 | 键盘 AI 润色 |
| #3418 | 词库页「词库信息」 |
| #3419 | 键盘无障碍标签接线 |

## 2026-09-21 补：模拟器验收

上面那份「证据边界」写完之后，在 API 21 的 `Mate 70 Pro` arm64 模拟器上实际跑了一遍，结论需要改写——不是因为结论错了，而是因为它们本来就只是没去跑。

**先撞上的是构建。** `hvigorw assembleHap` 报 13 个 ArkTS 错误，全部来自本轮合并的几片：`develop` 处在打不出 HAP 的状态，而 `tsc`、单测、设置包构建和 `verify-local.sh --quick` 全是绿的——没有一道门禁编译 ArkTS。修复与新增的 `scripts/test-harmony-arkts-subset.py` 见 #3426。这一条比本文档记录的任何一个功能缺口都更值得记：**这一整轮的机械比对，三条轴全都不会发现目标根本构建不出来。**

装机之后确认（详见 [platforms/harmony/README.md](../platforms/harmony/README.md)）：系统接受本输入法并拉起扩展进程；共享 React 界面在设备上渲染（欢迎流程、首页、词库页、账号页、社区页）；本轮新增的 C ABI 链路端到端可用（词库页显示的规格与提交号与锁文件一致）；**键盘作为系统输入法完整可用**——`nihao` → 候选 `你好` → 上屏，在本应用和第三方应用（华为浏览器的搜索框）里各验证过一次；回车键分别读作「前往」和「搜索」，都取自各自编辑器声明的动作，组合进行中变为「选定」。

也记下一个只有真机会告诉你的操作事实：`ime -e <bundle>` 默认进 `BASIC_MODE`，而那个模式下框架不会创建面板、扩展的 ArkTS 完全不运行，且没有任何错误提示；必须 `-f`。

## 证据边界

以上功能切片全部处在 [ARCHITECTURE.md](../ARCHITECTURE.md) 证据分级的第 1–2 级：源码、单元测试、`verify-local.sh --quick`、设置包构建。模拟器那一轮把其中几项推到了第 3–4 级：NAPI 边界、共享界面渲染、系统输入法注册与真实编辑器里的按键和候选，现在都有证据。

仍然没有证据的：

- 账号、社区、AI 服务的真实往返。模拟器本身是联网的（浏览器能拉到实时内容与搜索联想），社区页显示离线预览数据是因为没有登录账号，不是因为没有网络——先前这里写成「没有网络」是错的。
- `deleteBackwardSync(length)` 的单位（码点还是 UTF-16 单元）。AI 润色按码点计算，依据是本宿主退格路径的注释；替换前的重读是它的兜底，但单位错了仍然会表现为一次拒绝。
- 读屏实际念出什么，以及 `accessibilityText` 挂在键容器上是否会被读到（而不是被里面的 `Text` 盖过）。
- 个人词库队列是否真的在键盘下一次建立会话时被排空。
- 真机签名与麦克风授权流程。
