# iOS frontend

This directory contains the native iOS host app, custom keyboard extension, iOS-only shared UI, and their tests. `project.yml` is the reproducible XcodeGen source of truth; generated `.xcodeproj` files are build artifacts and are not committed.

The iOS frontend consumes `MetasequoiaImeEngine` through the Objective-C++ adapter in `shared/apple-bridge`. It must not import AppKit, InputMethodKit, Sparkle, macOS registration helpers, or macOS installer code. The keyboard operates locally without Open Access or network access. The host app and keyboard extension share the selected full-pinyin or Xiaohe double-pinyin scheme through the `group.app.msime.ios` App Group.

See [Apple platform architecture](../../docs/apple-platform-architecture.md) for ownership boundaries and the progressive pull-request sequence.

Generate and build the current shell for the Simulator from the repository root:

```sh
brew install boost fmt spdlog xcodegen cocoapods
python3 platforms/ios/scripts/prepare_dictionary.py
mkdir -p build/ios
xcodegen generate --spec platforms/ios/project.yml --project build/ios --project-root .
pod install --deployment --project-directory=platforms/ios
xcodebuild -workspace build/ios/MetasequoiaImeIOS.xcworkspace -scheme MetasequoiaImeIOS -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' -derivedDataPath build/ios-derived CODE_SIGNING_ALLOWED=NO build
bash platforms/ios/scripts/run_ui_tests.sh
```

The UI-test runner prefers an already booted iPhone Simulator, otherwise selects the newest available iPhone runtime, waits for its reported boot readiness, and runs the onboarding smoke test without fixed startup delays. Set `IOS_SIMULATOR_UDID` to target a specific device.

`CODE_SIGNING_ALLOWED=NO` above keeps the Simulator build reproducible without a signing identity, but it also means the installed app carries no entitlements and the operating system never provisions the App Group. The host app and the keyboard extension then each get their own `group.app.msime.ios` preferences file inside their own container, so a setting changed in the host app never reaches the keyboard and the sharing looks broken when it is not. Build and install with signing enabled when the shared settings themselves are what needs verifying; the two containers are under `~/Library/Developer/CoreSimulator/Devices/<udid>/data/Containers/Data/` and reading both plists tells the two cases apart immediately.

`BREW_PREFIX` defaults to `/opt/homebrew` in `project.yml`; override that build setting when dependencies are installed under another prefix.

The keyboard routes letter input, composition editing, raw/candidate commit, cancellation, numbered candidate selection, and Chinese punctuation through the shared engine. Its candidate bar also provides a local `中` / `英` switch; entering English mode first commits the leading Engine candidate, then passes letters and symbols directly to the host app. The native `123` / `ABC` layer owns only key layout; it does not duplicate the engine's composition or punctuation policy.

The host app exposes the same input-scheme setting as a native segmented control. A changed setting is picked up when the keyboard appears or before the next composition begins; an active composition keeps its original scheme until it is committed or cancelled.

The host app also exposes a simplified/traditional output setting, shared through the same App Group and defaulting to simplified. The engine and the packaged dictionary keep their original simplified strings; only the candidates shown in the keyboard and the text it commits are converted, through Core Foundation's `Simplified-Traditional` transform. Candidate selection continues to use engine indexes, and the preedit is left alone because it carries pinyin rather than Chinese output.

`prepare_dictionary.py` first builds the canonical database, then retains all single-syllable entries and common multi-syllable entries with weight 2000 or greater. The generated database and its SHA-256 sidecar are ignored build artifacts. At runtime the extension atomically installs a changed bundled database into its private writable Application Support directory, keeping dictionary access local without requesting Open Access.

## TestFlight publishing

The public release assets remain unsigned and reproducible. When the repository has all three
`IOS_APP_STORE_CONNECT_API_KEY_BASE64`, `IOS_APP_STORE_CONNECT_API_KEY_ID`, and
`IOS_APP_STORE_CONNECT_API_KEY_ISSUER_ID` plus the two distribution profile secrets
`IOS_APP_PROVISIONING_PROFILE_BASE64` and `IOS_KEYBOARD_PROVISIONING_PROFILE_BASE64`, `release.yml`
uses the matching distribution profiles on the macOS runner and uploads the build to TestFlight. The
API key must be a Team API key with permission to manage signing assets; the App ID records and the
profiles must exist for `app.msime.ios` and `app.msime.ios.keyboard`. If the signing permissions are
unavailable, the release keeps its unsigned iOS artifacts and records the skipped TestFlight upload
in the workflow summary.

To create the base64 secret without printing the private key:

```sh
openssl base64 -A -in AuthKey_<KEY_ID>.p8 | pbcopy
```

The issuer ID and key ID are entered as plain text in their respective secrets. The workflow uses
the existing `MACOS_NOTARY_TEAM_ID` secret for the Apple Developer team ID because both workflows
belong to the same team.

### 手写输入

在 App 的输入方案中启用「手写」，再从键盘方案卡片切换。首次点「下载中文手写模型」需要网络和键盘完全访问权限，下载完成后识别在设备上运行，可撤销、清空、选择候选上屏，支持简繁输出设置。没有下载模型时不会接受笔迹。

识别使用锁定的 ML Kit Digital Ink 4.0.0，保留 iOS 15.0 支持；SDK 和依赖通过 Podfile.lock 恢复。每次重新运行 XcodeGen 后都需要再运行 pod install，开发时打开生成的 xcworkspace。该 SDK 只提供 x86_64 模拟器库，因此测试需要 universal 模拟器运行时（ARM-only 运行时不能运行）；真机使用 arm64。

ML Kit 会发送性能与使用统计，应用的输入方案页和关于页提供相关说明。模型准备在键盘扩展自己的生命周期内完成；下载会话通过系统公开的 sharedContainerIdentifier 使用 App Group。适配器在 SDK 初始化之前为后台会话工厂补充默认共享目录，仅在扩展进程生效，保留显式指定的目录。
