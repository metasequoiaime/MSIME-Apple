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
