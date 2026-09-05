# 水杉输入法 Apple 平台版

本仓库包含水杉输入法（Metasequoia IME）的 Apple 平台原生前端。已发布的 macOS 前端基于 InputMethodKit 与 AppKit，iOS 宿主 App 与自定义键盘扩展正在逐步添加。两个平台共用同一套 C++ 组词引擎，各自的生命周期、输入路由、候选展示、设置界面与辅助功能 UI 则保持原生且相互独立。

目标模块边界与迁移顺序记录在 [Apple 平台架构文档](docs/apple-platform-architecture.md)。已发布的 macOS 实现位于 `platforms/macos/`，iOS 代码随开发进度放在 `platforms/ios/`。

## 平台状态

| 平台 | 状态 | 原生前端 |
|---|---|---|
| macOS 12+ | 已发布 | InputMethodKit 与 AppKit |
| iOS | 开发中 | 宿主 App 与 `UIInputViewController` 键盘扩展 |

iOS 版本不会移植 Windows 的 TSF 或 WebView2 宿主，而是复用 `MetasequoiaImeEngine`，并提供 iOS 专用的 UI 与文本文档适配层。

当前版本支持全拼输入、来自官方水杉词库的实时候选、拼音候选旁的辅助码提示、通过原生候选窗口或数字键 1–9 选择候选、空格上屏首选、回车上屏原始输入、退格、Esc、焦点切换时自动上屏、Shift+Space 在中文与直接英文输入之间切换，以及可选的全角模式（Option+Shift+H 切换）。原生的可拖动悬浮状态栏会持续显示中英文、标点、全角和简繁输出状态，并提供一键打开设置的入口；可在「外观」页中隐藏。启用全角模式后，未处于组词状态的 ASCII 字母、数字、标点和空格会转换为对应的 Unicode 全角形式，不影响拼音组词。默认输出简体；输入法菜单和悬浮状态栏可以把可见候选和上屏的中文切换为繁体字，不改变词库键值和学习数据。「词库与数据」页中的「启用本地输入模式」默认关闭；打开后，未处于组词状态时 Shift+U 输入 Unicode 码点、Shift+T 输入日期时间、Shift+K 输入快捷短语、Shift+J 使用超级简拼，关闭时这些组合照常输入大写字母。引擎另外几个本地模式（表情、颜文字、临时英文、临时日文）需要 others.db、english.db 与 dict_japanese.dat，本安装包不附带这些文件，因此始终关闭。

## 环境要求

- macOS 12 或更高版本
- Xcode 命令行工具
- CMake 3.25 或更高版本
- Homebrew 包：`boost`、`fmt`、`spdlog` 和 `nlohmann-json`
- Python 3

## 构建

```sh
git clone --recursive https://github.com/metasequoiaime/MSIME-Apple.git
cd MSIME-Apple
brew install cmake boost fmt spdlog nlohmann-json
./platforms/macos/scripts/build.sh
```

构建脚本会下载 `product-lock.json` 锁定的 MSIME-Engine 词库 release，逐个校验 SHA256，再放到 `vendor/MetasequoiaImeDict/out/msime.db`。该数据库文件有意不纳入版本库。Windows 和 Linux 取的是同一份产物，所以三个平台分发的 `msime.db` 逐字节一致。

换用新的词库版本：`python3 scripts/product_lock.py refresh --dictionary-tag dict-YYYY.MM.DD`，然后 review 产生的 diff。

公共词库源数据、构建器、辅助码与语音模块现在统一来自固定的 [MSIME-Engine](https://github.com/metasequoiaime/MSIME-Engine) submodule。桌面端继续下载锁定的已发布词库；iOS 打包通过同一 Engine 中的 `build_profile.py` 构建移动词库。现有 MSIME-Dict release 的来源和摘要保持不变，不能用新的构建器提交替代它们。

## 为当前用户安装

```sh
./platforms/macos/scripts/install.sh
```

安装脚本会把已签名的 bundle 复制到 `~/Library/Input Methods`，完成注册，并自动为当前用户启用水杉输入法；整个过程不需要管理员权限。如果 macOS 拦截了 ad-hoc 构建，请在「隐私与安全性」中放行，再到「系统设置 > 键盘 > 文本输入 > 编辑」中启用。

## 设置

在「系统设置 > 键盘 > 文本输入 > 编辑」中选择水杉输入法，再选择其设置项，即可打开原生的「水杉输入法设置」面板。面板中可以选择全拼、小鹤双拼或 86 五笔，在组词时显示可选的小鹤双拼键位提示，配置唯一四码五笔候选自动上屏，预览并切换原生候选窗口的横排与竖排形式，设置每页显示 5、7 或 9 个候选，选择小、标准或大号候选字体，指定 `- / =`、`[ / ]` 或 Page Up / Page Down 作为翻页键，启用全拼纠错与辅助码，为全拼和双拼分别选择 蓝天小雨点、自然码、首右2.0、首右plus 或小鹤 辅助码方案，切换中文标点转换，启用 Option+Shift+H 全角输入，以及控制选中候选是否更新词频学习。启用辅助码后，拼音候选会在括号中显示对应提示，与产品截图中的候选展示一致。初学者键位提示会跟随插入点，高亮最新输入的字母，并在上屏或取消后消失；键盘下方另有一行零声母对照（`a=aa`、`ang=ah`、`eng=eg` 等），这些编码无法从键位本身推出。这些选项按当前用户保存，在没有活动组词时于下一次按键前生效；正在进行的组词会沿用原有设置，直到上屏或取消。后续会继续增加更多输入与候选选项。

发布 ZIP 中还附带 `Open Settings.command` 作为直接入口。安装后打开它即可启动同一个原生面板，无需先切换到水杉；关闭面板只会退出这个独立的设置进程，输入法本身不受影响。

输入法使用 Sparkle 2 自动检查仓库的已签名更新源。可以直接在输入法菜单或设置面板中选择「检查更新…」手动检查。可用版本会在后台下载，解压前用项目的 Ed25519 更新密钥校验，并就地替换现有输入法 bundle 完成安装，用户无需自行解压或运行 ZIP 安装器。`-update.zip` 是 Sparkle 的更新载荷，不是供手动打开的安装包。appcast 本身同样经过签名，Sparkle 框架与发布工具在构建和发布配置中固定到已验证的版本。appcast 使用项目自己的 Ed25519 更新密钥签名，与 Apple 的 Developer ID 签名相互独立，因此即使产物未经 Apple 签名，appcast 依然会发布、Sparkle 自动更新照常工作；只有在仓库未配置该更新密钥时才会没有 `appcast.xml`，此时自动更新暂停，直到密钥配置完成。

文本输入菜单还会显示水杉当前处于「中文输入」还是「英文输入」模式，以及中文候选使用「简体输出」还是「繁体输出」，并提供 macOS「表情与符号」查看器入口，因此关闭悬浮状态栏后仍然可用。可以直接选择对应输入模式，也可以按 Shift+Space；切换到英文时会先把正在进行的中文组词上屏，之后的按键原样透传。Shift+Space 快捷键默认启用，与其他工作流冲突时可在设置中关闭。

紧凑的原生悬浮状态栏会反映当前的中英文、标点、全角和简繁状态。其齿轮按钮会打开原生工具菜单，提供 macOS「表情与符号」查看器、设置、检查更新、msime.app 和「隐藏悬浮状态栏」；隐藏后可在原有的设置项中重新启用。

## macOS 语音接入

输入法菜单中的「语音输入设置…」可配置兼容 OpenAI multipart 转写接口的 HTTPS 服务与模型，或选择本地 Whisper 模型文件。密钥按服务来源分别保存在系统钥匙串中；更换服务地址后需重新填写密钥。文本整理单独启用并配置，会将转写文本发送给指定的整理服务。

切换到水杉后，按 Control+Option+V 开始录音，再按一次结束并识别，也可使用输入法菜单的「语音输入」入口。首次使用会请求麦克风权限，录音最长 60 秒。Esc、继续键盘输入、移动光标或切换输入窗口会取消当前请求，取消后的结果不会上屏。本地模型推理已开始时可能继续计算，但结果仍会被丢弃。音频只在本次请求的内存中保存；云端识别会上传本次录音。详见 [隐私说明](PRIVACY.md)。

macOS 产品直接链接 Engine 的 `Voice`、`VoiceCapture` 和 `VoiceWhisper` 目标。平台层负责权限、钥匙串、录音提示和 IMK 上屏。iOS 目前只接入公共输入引擎与词库构建器，尚未提供语音入口。

## 开发测试

```sh
python3 platforms/macos/tests/create_fixture_dictionary.py /tmp/metasequoia-ime-test/msime.db
cmake -S . -B build-test -DCMAKE_BUILD_TYPE=Debug -DCMAKE_PREFIX_PATH="$(brew --prefix)" -DMETASEQUOIA_IME_DICTIONARY=/tmp/metasequoia-ime-test/msime.db
cmake --build build-test --parallel
ctest --test-dir build-test --output-on-failure --timeout 20
```

测试套件使用真实的 SQLite 表和生产环境的引擎路径，不会用伪造候选替代。

## 发布

合并到 `main` 会根据 conventional commit 历史更新 Release Please 的 pull request。合并该发布 PR 会更新 `version.txt`、`CMakeLists.txt` 和 `CHANGELOG.md`，创建对应的 `vX.Y.Z` 标签，构建并测试通用架构的输入法 bundle，然后发布带有以下产物的 GitHub Release：

- `MetasequoiaIME-vX.Y.Z-macos-universal.pkg`
- `MetasequoiaIME-vX.Y.Z-macos-universal.pkg.sha256`
- `MetasequoiaIME-vX.Y.Z-macos-universal.zip`
- `MetasequoiaIME-vX.Y.Z-macos-universal.zip.sha256`
- `MetasequoiaIME-vX.Y.Z-macos-universal-update.zip`
- `MetasequoiaIME-vX.Y.Z-macos-universal-update.zip.sha256`
- `appcast.xml`

当未配置 Apple 发布凭据时，工作流会发布同样的四份产物，但在扩展名前加上 `-unsigned`，并在 GitHub Release 中附加警告。未签名产物仅用于测试，可能需要在 macOS 隐私与安全性设置中显式放行。

常规安装请使用 ZIP 并运行其中的 `Install.command`，或使用 PKG 通过 macOS 原生安装器安装。两种方式都会安装当前用户的 bundle，并尝试自动注册并启用水杉，无需注销或重启 Mac。如果没有已登录的图形界面用户，或 macOS 拦截了未签名 App，可稍后在「系统设置 > 键盘 > 文本输入 > 编辑」中启用。

如果选择 PKG，请下载安装包及其校验和文件，校验通过后双击安装。它会把副本安装到当前用户的 `~/Library/Input Methods`；原生安装器可能会请求管理员授权。安装过程不会自动注销或重启 Mac。macOS 仍可能要求你在方便的时候注销并重新登录，新复制的输入法才会出现。

```sh
shasum -a 256 -c MetasequoiaIME-vX.Y.Z-macos-universal.pkg.sha256
```

当以下仓库 secret 全部配置完成时，发布构建会使用 Developer ID Application 身份签名、使用 Developer ID Installer 身份签名安装包，并在发布前完成公证。一个都未配置时，工作流会发布明确标注为未签名的产物。只配置了一部分时，工作流会在下载构建依赖前失败，以免产出标注含糊的产物。

- `MACOS_DEVELOPER_ID_CERTIFICATE_BASE64`
- `MACOS_DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `MACOS_SIGNING_KEYCHAIN_PASSWORD`
- `MACOS_NOTARY_APPLE_ID`
- `MACOS_NOTARY_TEAM_ID`
- `MACOS_NOTARY_APP_SPECIFIC_PASSWORD`
- `MACOS_DEVELOPER_ID_APPLICATION`
- `MACOS_DEVELOPER_ID_INSTALLER`

本地开发构建仍为 ad-hoc 签名。安装后脚本会自动注册并启用水杉输入法；如果 macOS 拦截了该 bundle，请在「隐私与安全性」中放行，再到「系统设置 > 键盘 > 文本输入 > 编辑」中启用。

ZIP 通过 `Install.command` 提供同样的当前用户安装位置，是希望立即用上水杉、又不想注销或使用管理员权限时的推荐方式。安装器在替换已有安装前始终校验 bundle 的代码签名，随后向 macOS 注册并启用该 bundle，使其无需注销即可出现在输入法菜单中。如果注册或启用失败，已校验的 App 仍会保留在安装位置，安装器会引导你到「系统设置」中手动启用。已签名的发布还必须通过 Gatekeeper；明确标注为未签名的构建则需要输入 `I UNDERSTAND`，并可能需要在「系统设置 > 隐私与安全性」中显式放行。

校验 ZIP 的校验和，解压后运行 `Install.command`：

```sh
shasum -a 256 -c MetasequoiaIME-vX.Y.Z-macos-universal.zip.sha256
./MetasequoiaIME-vX.Y.Z/Install.command
```

## 卸载

发布 ZIP 中同样附带 `Uninstall.command`。它只移除当前用户的输入法，并移入废纸篓以便恢复。默认保留偏好设置与学习数据：

```sh
./MetasequoiaIME-vX.Y.Z/Uninstall.command
```

如果要把应用、偏好设置和学习数据一并移到废纸篓中的同一个恢复文件夹，请使用显式的数据移除选项：

```sh
./MetasequoiaIME-vX.Y.Z/Uninstall.command --remove-user-data
```

两种模式在修改文件前都要求输入 `REMOVE METASEQUOIAIME`。完成后请注销，让 macOS 刷新输入源缓存。

通过 PKG 安装时，同一个卸载脚本会保留在已安装的应用 bundle 内，因此即使没有发布 ZIP 也可以使用：

```sh
"$HOME/Library/Input Methods/MetasequoiaIME.app/Contents/Resources/Uninstall.command"
```

## 许可证

水杉输入法 Apple 平台版依据 GNU General Public License version 3 分发。发布归档、安装包和应用 bundle 均包含适用的 GPL 与第三方许可声明，详见 `LICENSE` 与 `THIRD_PARTY_NOTICES.txt`。

## 隐私与安全

输入处理与候选学习全部在设备本地完成，数据处理细节见 [PRIVACY.md](PRIVACY.md)。发现疑似安全漏洞请按 [SECURITY.md](SECURITY.md) 的说明私下报告，不要提交公开 issue。

### 词库产品边界

macOS 使用固定发布词库；iOS 从同一已校验的数据库调用 `vendor/MetasequoiaImeEngine/build_profile.py --profile mobile --source ...`。初始化工具：`git submodule update --init --recursive`。工具 gitlink 与数据发布源 commit 分别记录，移动产物同时带格式、压缩规则、来源摘要和文件摘要清单。现代发布必须携带清单；已锁定的 `dict-2026.09.05` 是明确的无清单兼容入口。
