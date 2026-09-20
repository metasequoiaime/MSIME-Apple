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
| `TranslationClient.h/.mm` | 19 / 144 | `platforms/macos/src/cloud/TranslationCache.{h,mm}`、`cloud/CustomTranslationBatch.{h,mm}` |
| `ShuangpinKeymap.h/.cpp` | 14 / 96 | `platforms/macos/src/settings/ShuangpinKeymapPanel.{h,mm}` |
| `Uninstaller.h/.mm` | 15 / 127 | `crates/host-macos/native/uninstaller.mm`（仅大小写不同，有 `shared-uninstaller` CTest） |

## 四、目标有而来源没有

屏幕键盘、手写识别板、AI 辅助与 AI 对话、社区资源与皮肤、打字统计、悬浮工具栏皮肤编辑、双拼键位提示面板、输入模式 HUD。差集不是单向的。

## 这份清单不能证明什么

它证明的是「来源的每个源文件都有去处」，不是「每个函数的行为都一致」。行为层的证据在 `docs/macos-parity.md`：截图比对、23 个控制项标识、27 个运行时偏好键、以及来源自己测试里的 93 条断言——最后这条轴找出了唯一一个真缺口（恢复默认设置，#3280），其余三条都没有新发现。
