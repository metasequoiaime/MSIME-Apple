# HarmonyOS 迁移：来源文件逐个对照

这份清单回答一个问题：**来源（MSIME-Apple）的每一个源文件，在这个仓库里落到了哪里。** 它不是又一轮比对的结论，而是把结论摊开成可逐行核对的表——[harmony-parity.md](harmony-parity.md) 记的是「用什么方法比过、发现了什么」，这里记的是「一个不漏地列出来」。macOS 的同类清单是 [macos-feature-inventory.md](macos-feature-inventory.md)。

范围是来源的 `platforms/ios/App`、`platforms/ios/SharedUI`、`platforms/ios/KeyboardExtension`、`platforms/ios/KeyboardTestHost` 与 `shared`（含 `apple-bridge`、`backend`、`backend-ui`），共 **145 个** `.swift/.m/.mm/.h/.cpp` 文件，测试与 `Pods/` 的第三方依赖除外。

**与 macOS 那份清单最大的不同：这里几乎没有同名文件。** macOS 的 111 个里 85 个保持了原名，因为两边都是 Swift/ObjC；鸿蒙这边 145 个里只有 6 个撞名。宿主是 ArkTS 并按自己的命名重写，Swift/ObjC 的桥接与后端层整体由 Rust crate 取代，所以按文件名查会得出「几乎全部缺失」这个毫无意义的结论。下面因此逐个写去处，而不是只写改了名的那些。

核对方式（可重跑）：

```sh
ref=/path/to/MSIME-Apple
find "$ref"/platforms/ios/App "$ref"/platforms/ios/SharedUI "$ref"/platforms/ios/KeyboardExtension \
     "$ref"/platforms/ios/KeyboardTestHost "$ref"/shared -type f \
     \( -name '*.swift' -o -name '*.m' -o -name '*.mm' -o -name '*.h' -o -name '*.cpp' \) \
  | grep -viE 'Tests?/|Tests\.swift' | xargs -n1 basename | sort -u
```

## `shared/apple-bridge`（18）——由 `crates/host-api` 的 C ABI 取代

这一层是 Swift 与 C++ Engine 之间的 ObjC/C++ 桥。本仓库不保留它：同样的职责由 `crates/host-api` 的版本化 C ABI 承担，鸿蒙经 `platforms/harmony/native/client_napi.cpp` 的 NAPI 转发到达。

| 来源 | 去处 |
| --- | --- |
| `InputSessionAdapter.cpp/.h` | `crates/input-runtime` 的会话编排 + `crates/host-api/src/ffi/session.rs` |
| `MetasequoiaInputSessionBridge.mm/.h` | 同上；ArkTS 侧的对应物是 `KeyboardSession.ets` |
| `CandidateTranslation.cpp/.h` | `crates/client-core/src/translation.rs` + `ffi/translation.rs` |
| `DictionaryInstallation.mm/.h` | `crates/client-core/src/resources.rs`（暂存与校验），鸿蒙由 `StagedResources.ets` 调用 |
| `DictionarySessionLease.mm/.h` | `crates/client-core/src/dictionary/access.rs` 的 `DictionaryAccess` |
| `DictionarySnapshotBridge.mm/.h` | `crates/host-api/src/dictionary_snapshot.rs` |
| `PersonalDictionaryBridge.mm/.h` | `crates/client-core/src/dictionary/personal.rs` + `msime_client_personal_dictionary_request`（#3411） |
| `MSIMEBackendClient.m/.h` | `crates/client-core/src/account`；鸿蒙的传输在 `AccountCloudBridge.ts` |
| `ShuangpinKeymap.cpp/.h` | `msime_client_shuangpin_key_hints`，由 `ShuangpinKeyHintPolicy.ts` 消费 |

## `shared/backend`（14）——由 `crates/client-core` 取代

Swift 后端客户端。鸿蒙不跑 Swift，这些的契约都在 client-core，传输由 ArkTS 用系统 HTTPS 栈完成。

| 来源 | 去处 |
| --- | --- |
| `BackendAccountClient.swift` | `crates/client-core/src/account/client.rs`；ArkTS 侧 `AccountCloudBridge.ts` |
| `BackendAccountSession.swift` | `crates/client-core/src/account/session.rs`；ArkTS 侧同上的会话与 generation |
| `BackendAnonymousAccount.swift` | `crates/client-core/src/account`（匿名态）；鸿蒙默认离线，无需登录即可输入 |
| `BackendCandidateClient.swift` | `crates/client-core/src/cloud`；`OnlineCandidatePolicy.ts` |
| `BackendChatClient.swift` | `AccountCloudBridge.chat`（#3327） |
| `BackendClipboardClient.swift` | `AccountCloudBridge.clipboard` + `CloudClipboardPanel` |
| `BackendCommunityResourceClient.swift` | `AccountCloudBridge.communityResource`（#3338） |
| `BackendDictionaryClient.swift` | `AccountCloudBridge.dictionary` + 云词库面板 |
| `BackendLocalStore.swift` | `FileSessionStore`（`HarmonyAccountCloudBridge.ets`） |
| `BackendPreferencesClient.swift` | `AccountPreferencePlan.ts` + `preferencesSync`（#3331） |
| `BackendSkinArtworkClient.swift` | `HarmonyAiSkins.ets` + `msime_client_ai_skin_plan`（#3341） |
| `BackendSnapshotClient.swift` | `HarmonyAccountCloudBridge.snapshot` |
| `IOSPreferencePlan.swift` | `AccountPreferencePlan.ts`，键名用 `platform.harmony.*`（#3331） |
| `Package.swift` | SwiftPM 清单，无对应物 |

## `shared/backend-ui`（6）——共享 React 面板

| 来源 | 去处 |
| --- | --- |
| `BackendCommunityResourcesView.swift` | `packages/ui/src/community/community-resources.tsx` |
| `CloudCandidatesView.swift` | `packages/ui/src/keyboard/panels.tsx` 的 `CloudCandidatesPanel` |
| `CloudDictionaryCatalogView.swift` | 同上的 `CloudDictionaryCatalogPanel` |
| `CloudDictionaryEditor.swift` | 同上的 `CloudDictionaryPanel` |
| `BackendInputModifiers.swift`、`SettingsRows.swift` | SwiftUI 修饰器与行样式，由 `packages/ui` 自己的样式层取代 |

## `platforms/ios/App/Services`（9）

| 来源 | 去处 |
| --- | --- |
| `AISkinService.swift` | `crates/client-core/src/skin/ai.rs` + `HarmonyAiSkins.ets`（#3341） |
| `SkinCommunityAPI.swift` | `crates/client-core/src/skin/community.rs` + `AccountCloudBridge.community`（#3336） |
| `CloudDictionaryTransfer.swift` | 云词库面板与 `cloudDictionarySnapshot` |
| `CommunityPreviewFixtures.swift` | `packages/ui/src/community`（离线预览数据，模拟器上已确认渲染） |
| `CustomService.swift` | 共享 `ai_assistant` / `voice_input` 偏好；鸿蒙不另存一份服务配置 |
| `KeyboardAIService.swift` | **不迁移**：iOS 用钥匙串把凭据共享给键盘扩展；鸿蒙键盘直接读同一份偏好文件，没有跨进程共享凭据这一步 |
| `VoiceRecorder.swift` | **不迁移**：iOS 键盘扩展不能录音，所以 App 录完交接；鸿蒙键盘自己录（`HarmonyVoiceRecognizer.ets`） |
| `AppServicesBridge.mm/.h` | ObjC 桥，由 C ABI 取代 |

## `platforms/ios/App/Sources`（36）——共享 React 设置页

除下面标注的以外，全部落在 `packages/ui/src`，由鸿蒙的 WebView 承载。模拟器上已逐页确认渲染。

| 来源 | 去处 |
| --- | --- |
| `AppNavigation.swift`、`MetasequoiaImeApp.swift` | `packages/ui/src/index.tsx` 的页面路由与 `apps/harmony/src/main.tsx` |
| `KeyboardHomeView.swift` | `packages/ui/src/keyboard/home-page.tsx`（#3343，按平台裁剪为两个动作） |
| `WelcomeFlowView.swift`、`OnboardingView.swift` | `WelcomeFlowPage` + `OnboardingStatePolicy.ts` |
| `AccountSettingsView.swift`、`AccountCodeLoginView.swift` | `packages/ui/src/account/account-page.tsx` |
| `SettingsSyncView.swift` | 同上的 `SettingsSyncCard`（#3331） |
| `KeyboardChatView.swift` | `packages/ui/src/chat/chat-page.tsx`（#3327） |
| `SkinCommunityView.swift`、`CommunitySkinTrialView.swift`、`CommunityGalleryStyle.swift` | `packages/ui/src/community/community-skins.tsx`（#3336） |
| `CommunityResourcesView.swift` | `packages/ui/src/community/community-resources.tsx`（#3338） |
| `AISkinGenerationView.swift`、`SkinGenerationView.swift`、`SkinGenerationModel.swift` | AI 皮肤页 + `AiSkinRunPolicy.ts`（#3341） |
| `CustomSkinEditorView.swift` | `packages/ui/src/keyboard/touch-keyboard-skin-editor.tsx` + `customSkinLibrary`（#3334） |
| `KeyboardSkinPreview.swift`、`KeyboardPreviewCanvas.swift` | `packages/ui/src/keyboard/screen-keyboard-preview.tsx` |
| `CloudClipboardView.swift` | `CloudClipboardPanel` |
| `CloudDictionaryView.swift`、`CloudDictionaryApplyView.swift`、`CloudDictionaryFilesView.swift` | `CloudDictionaryPanel`、`CloudDictionaryApplyPanel`、`CloudDictionaryFilesPanel` |
| `PersonalDictionaryView.swift` | 词库页的本地词库管理 |
| `PersonalDictionaryImportView.swift` | `PersonalDictionaryImportCard`（#3411） |
| `FeatureSettingsViews.swift` | 输入页与词库页；其中「词库信息」一节本轮补齐（#3418） |
| `FuzzyPinyinSettingsView.swift`、`KeyboardLayoutSettingsView.swift` | 输入页的模糊拼音与触摸布局 |
| `TypingStatisticsView.swift`、`StatisticsCharts.swift` | `packages/ui/src/settings/typing-statistics.tsx` |
| `HelpAndFeedbackViews.swift` | 帮助页与反馈页；反馈报告的系统版本本轮补齐（#3432） |
| `AboutAndDownloadViews.swift` | 关于页与桌面版下载入口 |
| `ProviderPickerView.swift` | AI 页的 provider 选择器 |
| `AppIconSettingsView.swift` | **不迁移**：本平台无公开 API，依据记在 `platforms/harmony/README.md`（#3345） |
| `App-Bridging-Header.h`、`Backend-Bridging-Header.h` | ObjC 桥接头，无对应物 |

## `platforms/ios/SharedUI`（35）

偏好类整体由共享 `Preferences` 文档取代（`crates/client-core/src/preferences.rs`），键盘一侧读同一份文档。

| 来源 | 去处 |
| --- | --- |
| `CandidateGlossPreference`、`CandidateTranslationPreference` | `CandidateAnnotationPreferencePolicy.ts`、`TranslationPolicy.ts` |
| `ChineseOutputPreference`、`ChineseTextConversion` | `ChineseOutputPolicy.ts`（简繁转换由 Engine 完成） |
| `DictionaryLearningPreference`、`FrequencyAdjustmentPreference` | 共享 `learning` / `frequency` 偏好 |
| `EnglishMixedCandidatesPreference`、`EnglishSuggestionsPreference` | 共享 `mixed_input` / `english_suggestions`；`EnglishSuggestionPolicy.ts` |
| `FuzzyPinyinPreference`、`InputSchemePreference` | 共享 `fuzzy_pinyin` / `scheme`；`KeyboardScheme.ts` |
| `KeyboardFeedbackPreference` | `KeyboardFeedback.ts` + `KeyboardFeedbackBridge.ts` |
| `KeyboardLayoutPreference`、`KeyboardSkinPreference`、`KeyboardSkinCollection` | `touch_keyboard_layout` / `touch_keyboard_skin`；`skin/KeyboardSkin.ts` |
| `WubiCodeHintPreference`、`WubiMixedPinyinPreference` | `WubiCodeHintPolicy.ts`；共享 `wubi_mixed_pinyin` |
| `CustomKeyboardSkin`、`GeneratedKeyboardSkin` | `skin/CustomKeyboardSkin.ts`（含 photo/shade/position） |
| `KeyboardSkinTrial` | `msime_client_keyboard_skin_trial`（#3336） |
| `ClipboardHistoryStore` | `clipboard/ClipboardHistoryStore.ts` |
| `CommunityResource` | `CommunityReplyLibraryPolicy.ts` + `msime_client_community_resource_library`（#3338） |
| `PersonalDictionaryStore`、`PersonalDictionaryImport`、`PersonalWordBridge` | `crates/client-core/src/dictionary/personal.rs`（#3411） |
| `DictionarySnapshotQueue` | `HarmonyAccountCloudBridge.snapshot` + `snapshotPrepare/Activate` |
| `TypingStatistics` | `TypingStatisticsPolicy.ts` + `msime_client_typing_statistics` |
| `ReplyKeyboardView` | `ReplyKeyboardPolicy.ts` + `KeyboardView.replyFace` |
| `KeyboardAIView` | `AiPolishPolicy.ts` + `KeyboardView.polishFace`（#3414） |
| `KeyboardVoiceView` | **不迁移**：iOS 的语音交接面（App 录音→键盘插入）；鸿蒙键盘自己录音 |
| `VoiceTextHandoffStore` | **不迁移**：同上，交接机制本身不存在 |
| `MetasequoiaTheme`、`KeyboardPanelButtonStyle`、`SkinKeySurfaceView`、`KeyboardSkinBackgroundView`、`ScrollEdgeEffects` | SwiftUI 样式层，由 ArkUI 的皮肤绘制与 `packages/ui` 的样式取代 |

## `platforms/ios/KeyboardExtension/Sources`（26）

| 来源 | 去处 |
| --- | --- |
| `KeyboardViewController.swift` | `KeyboardExtensionAbility.ets` + `KeyboardView.ets` |
| `KeyboardInputView.swift`、`KeyboardKeyButton.swift` | `KeyboardView.ets` 的 `keyFace` / `flexibleKey` / `fixedKey` |
| `KeyboardCandidatePanelView.swift` | `KeyboardView.candidateStrip` / `candidateCell` |
| `KeyboardToolSection.swift`、`KeyboardMorePickerView.swift` | `SURFACE_TOOLS` / `SURFACE_MODES` 面 |
| `KeyboardSchemePickerView`、`KeyboardSkinPickerView`、`KeyboardLayoutPickerView` | `SURFACE_SCHEME` / `SURFACE_SKIN`（布局并入方案选择器，与共享 `touch_keyboard_schemes` 一致） |
| `KeyboardEmojiPickerView.swift`、`EmojiCatalog.swift` | `emoji/EmojiCatalogModel.ts` + `SURFACE_EMOJI` |
| `KeyboardSymbolPanelView.swift` | `KeyboardView` 的 `symbols` 键面 |
| `KeyboardClipboardView.swift` | `SURFACE_CLIPBOARD` + `clipboard/` 三个策略 |
| `HandwritingInputView.swift` | `HandwritingStrokePolicy.ts` + 手写面（识别改用系统 Core Vision Kit，无模型下载流程） |
| `JapaneseNineKeyView.swift` | `JapaneseNineKeyLayout.ts` / `JapaneseNineKeyActions.ts` |
| `CandidateTranslationStore.swift` | `candidate/TranslationPolicy.ts` |
| `DictionarySnapshotWorker.swift` | `KeyboardSession.snapshotActivate` + `drainPersonalDictionary`（#3411） |
| `EnglishCapitalizationPolicy.swift`、`EnglishSuggestionPolicy.swift` | 同名 ArkTS 策略（本仓 6 个撞名文件中的 2 个） |
| `SpaceCursorMovement.swift` | 同名 ArkTS 策略 |
| `KeyboardInputContext.swift`、`KeyboardHostContext.m/.h` | `KeyboardSession` 的 `editorGeneration` 与 `ReplyContextPolicy.ts` |
| `HandwritingDownloadSession.m/.h` | **不迁移**：ML Kit 模型下载；鸿蒙用系统 OCR |
| `MetasequoiaKeyboard-Bridging-Header.h` | ObjC 桥接头，无对应物 |

## `platforms/ios/KeyboardTestHost`（1）

`AppDelegate.swift` 是 iOS UI 测试的宿主应用，不是产品代码，无对应物。

## 这份清单证明什么、不证明什么

它证明的是「来源的每个产品源文件都有去处，且去处是写明的」，**不是**「每个函数的行为都逐字一致」。行为层的证据在 [harmony-parity.md](harmony-parity.md)：三条比对轴各自的方法与产出、四个查实并补齐的缺口、以及模拟器上从按键到候选上屏的完整验收。

三处「不迁移」都不是欠账，理由各自写在表里：应用图标本平台没有公开 API；语音交接和手写模型下载是 iOS 平台限制的变通，而鸿蒙没有那两个限制。
