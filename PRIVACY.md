# 网络请求与数据流向

这份文档说明**本仓库的代码**在什么条件下发出什么网络请求、内容是什么、去哪里、默认是否开启，以及在哪一行代码里。

它不是隐私政策。产品的隐私政策在 <https://msime.app/privacy/>，设置页「关于」里也有入口（`packages/ui/src/index.tsx`）。两者冲突时以隐私政策为准；这里提供的是可以对着代码核对的技术细节，给审阅者和贡献者用。

输入法是能看到你输入的一切的软件，所以这个问题值得一个能逐条验证的答案，而不是一句「我们重视你的隐私」。

## 一句话结论

默认配置下，**只有一个功能会把你输入的内容发出设备：云联想**。它默认开启，把当前正在组的拼音串发给 Google 输入工具。其余所有联网功能——语音识别、语音润色、候选翻译、AI 联想、账号同步——默认凭据为空，你不填自己的密钥它们就不会发出任何请求。仓库里没有任何遥测、统计或崩溃上报 SDK。

## 逐项说明

### 云联想（默认开启）

| | |
| --- | --- |
| 偏好字段 | `cloud_candidates`，默认 `true` |
| 目的地 | `https://inputtools.google.com/request` |
| 发送内容 | 当前正在组的拼音串，作为 `text` 查询参数 |
| 需要凭据 | 否 |
| 代码 | `crates/client-core/src/cloud/candidates.rs` 的 `build_google_url`，经 `crates/input-runtime/src/providers.rs` 调用 |

URL 的完整形态可以在同文件的测试里看到，是断言过的字面量：

```
https://inputtools.google.com/request?text=ni%20hao&itc=zh-t-i0-pinyin&num=1&ie=utf-8&oe=utf-8
```

日文输入方案走 `ja-t-i0-und`，其余相同。这是仓库里唯一的云候选来源，没有第二个提供方。

发出前有几道硬性限制，定义在共享层（`candidates.rs` 顶部的常量）：输入为空、超过 256 字节、或含控制字符时不发；响应超过 256 KiB 或单条候选超过 512 字节即丢弃。请求按代次绑定，失焦和换代次会使迟到的结果作废，不会写进新会话。共享层的云候选代码路径不含任何日志调用，查询和响应不经由它落盘。

防抖间隔**由各宿主自己决定**，不是共享常量：共享层的 `spawn_with_debounce` 接受调用方给的时长，`spawn` 默认为零。已在代码中固定取值的是 Android（`OnlineCandidatePolicy.QUIET_INTERVAL_MILLIS = 350`）和 HarmonyOS（`OnlineCandidatePolicy.QUIET_INTERVAL_MS = 350`），两者都是组字停顿 350 ms 后才发一次，并用请求身份保证同一组合只问一次。其余宿主的取值请以各自代码为准。

**关掉它**：设置页「云联想」开关，或把配置里的 `cloud_candidates` 设为 `false`。关闭后宿主不再发起云候选请求，并拒绝任何返回的云来源候选。

保持默认开启是为了与已发布的平台输入法行为一致。这与常见中文输入法的云输入功能是同一类能力，但既然仓库公开，端点和发送内容就应当白纸黑字写在这里，而不是让人去读源码才能知道。

### 候选翻译（默认开启，但需要你自己的凭据）

`candidate_translations` 默认 `true`，支持腾讯机器翻译（`https://tmt.tencentcloudapi.com`）、小牛翻译（`https://api.niutrans.com/v2/text/translate`）和自定义端点。三者都要求你在设置里填入自己的 API 凭据，默认全为空字符串——**没有凭据就不会发出请求**，开关为真也一样。发送内容是待翻译的候选词。代码在 `crates/client-core/src/credential/translation.rs`。

### 语音输入（默认凭据为空）

`voice_input.enabled` 默认 `true`，但这只表示功能可用，录音要你主动触发。默认识别服务是豆包（`wss://openspeech.bytedance.com/...`），**`asr_token` 默认为空字符串**，不填就无法使用。可选的识别服务还有 SiliconFlow、OpenAI、Groq、EveryAPI、Mistral Voxtral，以及两种不出设备的选项：

- `local`：本地 Whisper（macOS），需要你指定 ggml 模型的绝对路径，音频不离开设备。
- `system`：调用操作系统自带的识别（macOS / HarmonyOS），数据流向由操作系统决定。

选择云端服务时，发送的是录制的音频。代码在 `crates/client-core/src/credential/asr.rs`，服务选择逻辑在 `crates/client-core/src/preferences.rs`。

### 语音润色（默认关闭）

`voice_input.polish_enabled` 默认 `false`。开启后把识别出的文本发给一个 Chat Completions 服务做整理，默认端点是 SiliconFlow，`polish_token` 默认为空。

### AI 联想（自带端点与密钥）

需要显式启用且配置完整才会发起请求，发送内容是当前查询。端点由你自己填写，代码对它做校验：必须是 http/https、不得内嵌用户名密码、长度不超过 2048、不含控制字符（`apps/desktop/src-tauri/src/ai.rs`）。常见的 DeepSeek、OpenAI、Groq、SiliconFlow、OpenRouter、EveryAPI 只是文档和测试里出现的示例，仓库不预置任何一家的密钥。

### 账号与同步（需要登录）

`https://api.msime.app`，定义在 `crates/client-core/src/account.rs` 的 `ACCOUNT_ORIGIN`。不登录不发生。凭据存放在系统密钥库：macOS/iOS 用 Keychain（`crates/host-macos/native/account.mm`、`crates/tauri-mobile-platform/ios/Sources/MobilePlatformPlugin.swift`），Android 用 Keystore 加密后落盘。

### 资源与更新下载

首次准备词库时从 GitHub Releases 拉取固定版本的资源，地址、长度和 SHA-256 全部写死在 `resources/desktop-dictionary.lock.json` 里，逐一校验，全部成功才发布到内容标识目录。下载的是公开发布物，不上传任何东西。更新检查读取 `https://msime.app/update.json`。

Android 的手写识别使用 ML Kit，**首次使用需要联网下载识别模型**，之后在设备上离线识别。Linux 与桌面端使用 Engine 随附的离线 Zinnia 模型，从安装路径读取，全程不联网。

## 留在本地的东西

- **输入历史与学习数据**由 C++ Engine 管理，写在宿主提供的用户目录里，不上传。
- **剪贴板历史默认关闭**（`clipboard_history` 默认 `false`）。开启后写入状态目录下的 `clipboard_history.json`，仅本地；关闭时会清空该文件。
- **设置**保存在应用数据目录的 `preferences.json`，可用绝对路径环境变量 `MSIME_CLIENT_STATE_DIR` 指向隔离目录。

## 没有的东西

仓库里不存在遥测、使用统计或崩溃上报：没有 Sentry、Mixpanel、Amplitude、Crashlytics、Google Analytics 或任何等价物的依赖与调用。代码侧可以自己核一遍，结果应当是零：

```sh
git grep -inE '\b(telemetry|analytics|sentry|mixpanel|crashlytics)\b' -- crates apps packages platforms shared
```

词边界是必须的：不加的话 `PROCESSENTRY32W` 会匹配上 `sentry`，触感振幅和波形振幅的 `amplitude` 会匹配上 `amplitude`，全是误报。

依赖侧再核一遍锁文件：

```sh
grep -niE 'opentelemetry|sentry|mixpanel|crashlytics|google-analytics' pnpm-lock.yaml Cargo.lock
```

唯一的命中是 `@opentelemetry/api`，它是测试框架 vitest 的**可选 peer 依赖**，没有被安装，也不进入任何产物。

## 自己核对

```sh
# 所有出现在代码里的外部地址
git grep -nIoE 'https?://[a-zA-Z0-9.-]+\.[a-z]{2,}' -- crates apps packages platforms | sort -u

# 云候选的完整 URL 构造与其边界检查
sed -n '/fn build_google_url/,/^}/p' crates/client-core/src/cloud/candidates.rs

# 所有默认开启的偏好
grep -n 'enabled_by_default' crates/client-core/src/preferences.rs
```

发现本文档与代码不符，请按[贡献指南](CONTRIBUTING.md)提 issue；若涉及数据泄露或凭据问题，走[安全策略](SECURITY.md)的私下报告入口，不要开公开 issue。
