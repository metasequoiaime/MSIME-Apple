# 第三方组件清单

这份清单回答「这个项目用了谁的代码和数据、各自什么许可」。它是仓库级的索引；各平台打包时实际生成的通知文件另有位置，见末尾的[通知文件在哪](#通知文件在哪)。

清单不替代许可证审计。它记录已知的来源与条款，并明确标出尚未记录的部分——后者同样重要，因为一份看起来完整、实则有空白的清单比承认空白更危险。

## 本项目

源码为 **GPL-3.0-only**，全文在根目录 [LICENSE](../LICENSE)。Rust workspace 的 `license` 字段、Linux 打包元数据和共享客户端都声明同一许可证。

## 固定上游（`engine-lock.json`）

锁文件记录每个归档的 commit 与 SHA-256，`scripts/fetch_engine.py` 校验后展开到被忽略的 `vendor/MSIME-Engine/`。下列 SPDX 标识取自各仓库在 GitHub 上的许可证声明，于 2026-09-20 核对：

| 组件 | 许可证 | 说明 |
| --- | --- | --- |
| `metasequoiaime/msime-engine` | GPL-3.0 | 输入算法与组合状态 |
| `metasequoiaime/Google-PinyinIME-Rev` | Apache-2.0 | Google Pinyin IME 的修订分支 |
| `nemtrif/utfcpp` | BSL-1.0 | UTF-8 处理 |
| `mackron/miniaudio` | 上游为公有领域 / MIT-0 双许可 | 音频采集；GitHub 分类器未给出单一标识，以归档内许可证文本为准 |
| `ggml-org/whisper.cpp` | MIT | 本地语音识别 |

五个归档均可匿名下载，不需要凭据，`fetch_engine.py` 使用 `urllib.request` 直接取回。

## 随包资源（`resources/desktop-dictionary.lock.json`）

锁文件固定十个产物的 URL、长度和 SHA-256，全部可匿名下载。其中八个来自 `metasequoiaime/msime-engine` 的 `dict-v2.0.0` 发布，`sentence-model.safetensors` 来自 `metasequoiaime/chinese-ime-lm` 的 `model-v1`——两者是不同的仓库和不同的发布，以锁文件里各自的 `url` 为准。**锁文件本身不记录许可证字段**，来源信息分散在别处：

| 产物 | 大小 | 已知来源 |
| --- | --- | --- |
| `msime.db` | 76.3 MB | Engine 发布的工作词库 |
| `english.db` | 1.7 MB | Engine 发布的英文词库 |
| `bigram.bin` | 12.0 MB | Engine 发布的二元语言模型表，整句词格仲裁按它加权 |
| `trigram.bin` | 12.0 MB | Engine 发布的三元语言模型表，同上 |
| `others.db` | 1.5 MB | Engine 发布的表情等数据 |
| `dict_japanese.dat` | 66.5 MB | Mozc 的开源版日文词库，构成见[下一节](#日文词库的分发义务) |
| `mozc_dictionary_oss_README.txt` | 5.8 KB | 上述词库的许可证全文。**分发时必须一同携带**，理由见下节 |
| `dictionary-manifest.json` | 1.9 KB | 资源清单 |
| `dict_pinyin.dat` | 1.1 MB | 拼音数据 |
| `sentence-model.safetensors` | 4.5 MB | 整句重排模型，权重为 Apache-2.0；训练语料与分发要求见[下下节](#整句重排模型的署名要求) |

`Artifact` 结构体带 `#[serde(deny_unknown_fields)]`，所以在锁文件里直接加 `license` 字段会让解析失败；要记录许可证需要同时修改 `crates/client-core/src/resources.rs`。在那之前，新增或更换随包资源时请把来源与授权写进本文件。

### 日文词库的分发义务

`dict_japanese.dat` 是 Mozc 的开源版词典，不是 Google 日本語入力所用的那一份。按随附 `mozc_dictionary_oss_README.txt` 的说明，它由四部分构成：

- **IPAdic**（`mecab-ipadic-2.7.0-20070801`），奈良先端科学技術大学院大学 2000–2003 年版权。允许使用、复制和分发，但要求任何副本——无论原样还是修改过——都必须同时包含其版权声明和紧随其后的两段免责声明。
- **ICOT Free Software**，词条中很大一部分源于此。其条款要求 `NO WARRANTY` 一节**始终**出现在随程序分发的材料中，或附加于其上。
- **冲绳辞書**（[o-dic](http://sourceforge.jp/projects/o-dic/)），明示为 Public Domain，使用、修改、分发均无限制。
- Google 手工增补的形容词／动词、片假名词和复合词，适用 Mozc 自身的条款；该 README 未复述这部分，GitHub 对 `google/mozc` 的许可证识别结果是 `NOASSERTION`，因此本文件不替它断定 SPDX 标识。

**实际后果：分发这份词库时必须一并携带 `mozc_dictionary_oss_README.txt`**，IPAdic 和 ICOT 两条都把"许可证文本随附"写成了硬性条件。锁文件把这个 5.8 KB 的文本和词库本身一起固定并校验，正是为此——它是许可证义务，不是文档习惯，重新打包资源时不要因为"只是个 README"而丢掉它。

开源版不含日本邮政编码词典；README 给出了自行生成的步骤，本仓库没有执行。

### 整句重排模型的署名要求

`sentence-model.safetensors` 来自 [`metasequoiaime/chinese-ime-lm`](https://github.com/metasequoiaime/chinese-ime-lm) 的 `model-v1` 发布。它的许可信息不在任何外部文档里，而是嵌在权重文件自身的 safetensors `__metadata__` 头中——上游这样做正是为了让署名无法与权重分离。以下内容读自本仓库锁定的那一份（SHA-256 与 `desktop-dictionary.lock.json` 逐位一致）：

| 字段 | 值 |
| --- | --- |
| `license` | `Apache-2.0` |
| `attribution` | Trained on the Chinese portion of C4 (ODC-BY) and LCCC (MIT) |
| `precision` | `int8` |
| `version` | `1` |

两份训练语料的许可都要求署名随衍生成果传播：[C4 中文部分](https://huggingface.co/datasets/allenai/c4)为 ODC-BY，[LCCC](https://github.com/thu-coai/CDial-GPT)为 MIT。**再分发权重时必须保留 `__metadata__` 中的 `attribution` 字段**；任何重新导出、量化或转换权重的流程，如果丢掉 safetensors 的元数据头，就切断了这条署名链。

可以随时自行核对：

```sh
python3 -c '
import json,struct,sys
f=open(sys.argv[1],"rb"); n=struct.unpack("<Q",f.read(8))[0]
print(json.loads(f.read(n))["__metadata__"]["attribution"])
' <资源目录>/sentence-model.safetensors
```

上游仓库还说明，`corpus/fetch.py` 支持的中文维基百科、MDN、Kubernetes 文档等来源带有 share-alike 义务，**本仓库分发的这份权重不使用它们**。

## 编译进共享库的数据

| 组件 | 许可证 | 位置与说明 |
| --- | --- | --- |
| [OpenCC](https://github.com/BYVoid/OpenCC) 词典，提交 `26753884f1984add422f3b0249ccee8613deaff6` | Apache-2.0 | `crates/client-core/data/opencc/`，许可证全文在同目录 `LICENSE`。`STPhrases.txt`、`STCharacters.txt`、`CJK_Compatibility_Ideographs.txt` 原样取自该提交的 `data/dictionary/`；`STPhrases_GeneratedFromRegionalPhrases.txt` 是该提交的 OpenCC 构建产物（`data/scripts/generate_st_phrases_from_regional_phrases.py` 用 `t2s.json` 生成），本仓不重新生成。提交号与来源 MSIME-Windows 的 `vendor/opencc` 子模块一致。只使用数据，不链接 OpenCC 的 C++ 库；`chinese_conversion.rs` 按 `s2t.json` 的规则实现转换。Windows 通知由 `Collect-Notices.ps1` 一并收集 |

## 各平台引入的第三方 SDK

| 平台 | 组件 | 许可 |
| --- | --- | --- |
| Android | `com.google.mlkit:digital-ink-recognition:19.0.0` | **Google 的 ML Kit 服务条款，不是开源许可证** |
| Android | AndroidX、`com.google.android.material` | Apache-2.0 |
| iOS | `MLKitDigitalInkRecognition` 8.0.0（CocoaPods，链接进键盘扩展 target） | **Google 的 ML Kit 服务条款，不是开源许可证** |
| macOS | Sparkle 2.9.6 | 以上游发布附带的许可证为准；框架不随仓库分发，由构建者按 `platforms/macos/README.md` 记录的 SHA-256 自行取得 |
| Windows | vcpkg 提供的 Boost、fmt、spdlog、SQLite3 | 各自上游许可证；通知由 `platforms/windows/Collect-Notices.ps1` 收集 |
| Linux | IBus / Fcitx5 与 GTK 栈 | 各自上游许可证，按发行版依赖引入 |
| 桌面 | Tauri、React、Vite 等 | 见 `pnpm-lock.yaml` 与各自上游 |

两个移动平台的 ML Kit 是识别手写笔迹用的。桌面与 Linux 不使用它，改用 Engine 随附的离线 Zinnia 识别器和模型；Android 的原生构建明确把 Zinnia 及其模型路径排除在外（`platforms/android/verify-native.sh`）。

仓库不捆绑任何字体文件；界面使用系统字体，`Noto Sans SC` 与 `Microsoft YaHei` 只是回退字体名。

## 语言生态依赖

逐个列出会立刻过时，以锁文件为准：

- Rust：`Cargo.lock`，559 个依赖。`cargo audit` 是 `scripts/verify-local.sh` 完整版的一个阶段，漏洞视为失败；被接受的 `unmaintained` / `unsound` 公告逐条记在 [`.cargo/audit.toml`](../.cargo/audit.toml) 里，每条都写明引入链和接受理由。
- Node：`pnpm-lock.yaml`。
- iOS：`platforms/ios/Podfile.lock`。

## 通知文件在哪

| 位置 | 覆盖范围 |
| --- | --- |
| `platforms/macos/resources/Licenses/THIRD_PARTY_NOTICES.txt` | macOS 客户端内嵌组件的完整通知 |
| `platforms/ios/SharedResources/MLKit-NOTICES.txt`、`MLKit-Dependencies.txt` | iOS 的 ML Kit 依赖通知 |
| `apps/desktop/src-tauri/gen/android/gradle/LICENSE-2.0.txt`、同目录 `NOTICE.md` | Android Gradle 模板的 Apache-2.0 文本与来源说明 |
| `platforms/windows/Notices.md` | Windows 通知生成器的用法与限制；产物由 `Collect-Notices.ps1` 生成 |

这些生成器和收集器都在各自文档里写明「不是完整性或再分发授权的评估」。发布二进制前的逐平台要求见[开源发布清单](open-source-release.md)。

## 新增依赖时

引入新的上游代码、字体、图标、模型或服务 SDK 时，同时提交来源提交、许可证文本、通知位置和分发限制，并在本文件登记——不要只在 README 留一个链接。资源锁文件只校验内容，不授予任何分发权利。
