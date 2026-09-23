# macOS 迁移：来源文件逐个对照

这份清单回答一个问题：**来源（MSIME-Apple）的每一个源文件，在这个仓库里落到了哪里。** 它不是又一轮比对的结论，而是把结论摊开成可逐行核对的表——`docs/macos-parity.md` 记的是「用什么方法比过、发现了什么」，这里记的是「一个不漏地列出来」。

范围是来源的 `platforms/macos/src` 与 `shared`（含 `apple-bridge`、`backend`、`backend-ui`），共 111 个 `.h/.mm/.cpp/.swift` 文件，测试除外。其中 85 个在本仓库有同名文件，下面只逐条写清楚**剩下 26 个改了名或换了形态的**去了哪儿，以及为什么。

核对方式（可重跑）：

```sh
ref=/path/to/MSIME-apple
find "$ref"/platforms/macos/src "$ref"/shared -type f \( -name '*.mm' -o -name '*.h' -o -name '*.cpp' -o -name '*.swift' \) \
  | grep -v Tests | xargs -n1 basename | sort -u > /tmp/ref.txt
find platforms/macos/src shared crates/host-macos -type f \( -name '*.mm' -o -name '*.h' -o -name '*.cpp' -o -name '*.swift' \) \
  | xargs -n1 basename | sort -u > /tmp/ours.txt
comm -23 /tmp/ref.txt /tmp/ours.txt   # 这 26 条，应与下表一致
```

## 一、输入会话与桥接：换成 Rust C ABI

来源用一层 Objective-C++ 桥接直接抱住引擎；本仓库把输入算法与词库下沉到 Engine，宿主经 `crates/host-api` 的 C ABI 接。所以这一组不是丢了，是换了形态。

| 来源 | 行数 | 目的地 | 说明 |
| --- | --- | --- | --- |
| `MetasequoiaInputSessionBridge.h/.mm` | 122 / 657 | `platforms/macos/src/core/DesktopInputSession.{h,mm}` | 控制器持有的会话对象由 `MSIMEDesktopInputSession` 承担（`InputController.mm:613`） |
| `InputSessionAdapter.h/.cpp` | 140 / 485 | `crates/host-api`（C ABI）+ `crates/input-runtime` | C++ 适配层换成 Rust 运行时，宿主不再自建适配 |
| `PersonalDictionaryBridge.h/.mm` | 20 / 99 | `crates/host-api/src/dictionary.rs`、`crates/host-macos/native/dictionary.mm` | 用户词条的读写走同一套 C ABI |
| `CandidateTranslation.h/.cpp` | 32 / 190 | `crates/host-api/src/ffi/translation.rs` | `msime_client_candidate_gloss_request` 是所有宿主共用的入口 |
| `CandidateGlossClient.swift` | 57 | 同上 | 释义请求不再各宿主各写一份 |
| `MSIMEBackendClient.h` | 15 | `shared/backend/`（Swift 包） | 后端客户端集中在共享包里，不留平台头文件 |

## 二、偏好：散落的头文件合并进共享文档

来源把偏好按面板拆成若干头文件各自读写 `NSUserDefaults`；本仓库只有一份共享的 `Preferences`（`crates/client-core/src/preferences.rs`），macOS 侧由 `settings/AppearancePreferences.mm` 与它对接。

| 来源 | 行数 | 目的地 |
| --- | --- | --- |
| `CandidateAppearancePreferences.h` | 81 | 共享 `Preferences` 的候选外观字段 + `settings/AppearancePreferences.mm` |
| `FloatingToolbarPreferences.h` | 48 | 共享 `FloatingToolbarPreferences` + 同上 |
| `InputBehaviorPreferences.h` | 75 | 共享 `NavigationPreferences` / `WordCharacterPreferences`；两者的互斥由 `Preferences::validate()` 保证 |
| `LocalInputModePreferences.h` | 54 | 共享 `local_modes` 字段 + 设置页「实用功能」 |
| `CandidateTranslationLanguage.h` | 54 | `packages/ui/src/index.tsx` 的语言表（目标 7 种，来源 6 种，多一个俄语） |

## 三、改名或换宿主的其余项

| 来源 | 行数 | 目的地 |
| --- | --- | --- |
| `main.mm` | 87 | `platforms/macos/src/input/input_method_main.mm` |
| `PersonalDictionaryStore.h/.mm` | 44 / 191 | `platforms/macos/src/dictionary/DictionaryWindowController.{h,mm}` 与共享词库页 |
| `PersonalDictionaryView.h/.mm` | 8 / 489 | Tauri 设置页「词库」（`packages/ui/src/index.tsx`），按「公共 UI 放 Tauri」重构 |
| `TranslationClient.h/.mm` | 19 / 144 | `platforms/macos/src/cloud/TranslationCache.{h,mm}`、`platforms/macos/src/core/CustomTranslationBatch.{h,mm}` |
| `ShuangpinKeymap.h/.cpp` | 14 / 96 | `platforms/macos/src/settings/ShuangpinKeymapPanel.{h,mm}` |
| `Uninstaller.h/.mm` | 15 / 127 | `crates/host-macos/native/uninstaller.mm`（仅大小写不同，有 `shared-uninstaller` CTest） |

## 四、目标有而来源没有

屏幕键盘、手写识别板、AI 辅助与 AI 对话、社区资源与皮肤、打字统计、悬浮工具栏皮肤编辑、双拼键位提示面板、输入模式 HUD。差集不是单向的。

## 五、符号层：来源的 518 个函数与方法

文件层回答「文件去了哪」，断言层回答「被测试钉住的行为是什么状态」。两者都漏掉同一块：**来源写了、但自己没写测试的行为**。这一节补上——把来源 `platforms/macos/src` 与 `shared/apple-bridge` 里所有 Objective-C 方法与 C/C++ 函数抽出来逐个找去处。

抽取与比对（可重跑）：

```sh
ref=/path/to/MSIME-apple
{ grep -rhoE '^[-+] \([^)]+\)[a-zA-Z_][A-Za-z0-9_]*' "$ref"/platforms/macos/src "$ref"/shared/apple-bridge --include='*.mm' --include='*.h' | sed -E 's/^[-+] \([^)]+\)//'
  grep -rhoE '^(inline |static |extern "C" )*[A-Za-z_][A-Za-z0-9_:<>* ]* ([A-Z][A-Za-z0-9_]*)\(' "$ref"/platforms/macos/src "$ref"/shared/apple-bridge --include='*.h' --include='*.cpp' | grep -oE '[A-Z][A-Za-z0-9_]*\($' | tr -d '('
} | sort -u | wc -l   # 518
```

结果分三层：

| | 数量 | 说明 |
| --- | ---: | --- |
| 同名即命中 | 315 | 直接在本仓库里存在同名符号 |
| 原生设置窗的 AppKit 管线 | 166 | `*Changed` 动作选择器、`refresh*` / `update*Controls*` 控件刷新、`set*` / `stored*` 的 NSUserDefaults 存取器。这些是来源 3323 行 `PreferencesWindowController.mm` 的骨架；按「公共 UI 放 Tauri」，对应物是 React 的 `onChange` 与一份共享 `Preferences`，不存在同名符号是设计结果 |
| 承载行为、需逐个定位 | 37 | 下表 |

37 个逐个都有去处：

| 来源符号 | 目的地 |
| --- | --- |
| `MetasequoiaRegisterInputSource`、`MetasequoiaRegisterAndEnableInputSources`、`MetasequoiaShouldRegisterInputSource` | `platforms/macos/src/input/InputSourceRegistration.h`、`platforms/macos/src/input/input_method_main.mm`（仅前缀 `Metasequoia`→`MSIME`） |
| `MetasequoiaInputModeHUDFrame`、`MetasequoiaIsUsableCaretRect` | `platforms/macos/src/input/InputModeHUDPanel.mm`（后者为 `MSIMEValidCaret`） |
| `MetasequoiaShuangpinKeymapPanelFrame` | `platforms/macos/src/settings/ShuangpinKeymapPanel.h` |
| `MetasequoiaFloatingToolbarWidth` | `platforms/macos/src/core/FloatingToolbarPanel.mm` |
| `ShouldAutoCommitUniqueWubiCandidate` | `platforms/macos/src/core/WubiCommitPolicy.h` 的 `MSIMEShouldAutoCommitWubi` |
| `ActionForSolitaryShift`、`handleSolitaryShiftFlags` | `platforms/macos/src/core/ModifierTap.h`，控制器用 `MSIMEModifierTap` 观察修饰键 |
| `ClassifyConfiguredControllerKey` | `platforms/macos/src/input/InputControllerPhysicalKeys.h` |
| `MetasequoiaCandidateKeyOptions`、`MetasequoiaCandidateFollowsCaret` | 共享 `NavigationPreferences` / `candidate_follow_cursor` |
| `candidatePinToggled` | `platforms/macos/src/input/InputController.mm` 的 `MSIMETogglePinnedCandidate` / `MSIMECandidatePinCode` |
| 释义与翻译共 12 个（`LookupCandidateGloss`、`FormatCandidateGloss`、`TakeLeadingSenses`、`FindSenseDelimiter`、`CollapseWhitespace`、`IsAsciiSpace`、`IsHanCodePoint`、`IsEnglishCandidateText`、`NextArmedGlossColumn`、`CandidateGlossRequestForModifiers`、`CandidateSupportsOnlineGloss`、`TranslationQueryForCandidate`、`CandidateTranslationProviderAt`） | `crates/host-api/src/ffi/translation.rs`（所有宿主共用的 C ABI） |
| `EncodePersonalWord`、`DecodePersonalWord`、`personalEntriesAtOffset`、`ResetMetasequoiaLearnedData(ForCurrentUser)` | `crates/host-api/src/dictionary.rs` |
| `InstallMetasequoiaDictionary`、`InstallMetasequoiaEnglishDictionary`、`InstallMetasequoiaHelpCodes`、`PrepareMetasequoiaDictionary` | `shared/apple-bridge/DictionaryInstallation.mm`、`platforms/macos/src/dictionary/DictionaryInstaller.mm` |
| `UninstallMetasequoia`、`UninstallMetasequoiaForCurrentUser` | `crates/host-macos/native/uninstaller.mm` 的 `msime_macos_uninstall_input_source` |

这一轮没有找到缺口。

## 这份清单覆盖的层与其余的层

这份清单覆盖的是文件与符号两层：来源的每个源文件、每个函数都有明确去处。行为层由另外两份文档覆盖：[macos-assertion-audit.md](macos-assertion-audit.md) 逐条核对来源测试里的 93 条断言（这条轴找出了唯一一个真缺口，恢复默认设置，#3280），[macos-parity.md](macos-parity.md) 记录截图比对、23 个控制项标识、27 个运行时偏好键，以及按来源注释里的理由逐条回验的行为层比对。四条轴各自可重跑，合起来没有剩余的已知缺口。
