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

锁文件固定十个产物的长度和 SHA-256。其中九个带可匿名下载的 URL：八个来自 `metasequoiaime/msime-engine` 的 `dict-v2.0.1` 发布，`sentence-model.safetensors` 来自 `metasequoiaime/chinese-ime-lm` 的 `model-v1`——两者是不同的仓库和不同的发布，以锁文件里各自的 `url` 为准。第十个 `dict_pinyin.dat` 没有下载地址，改用 `engine_path` 从 `engine-lock.json` 固定的那份 `googlepinyinime-rev` 归档里只取这一个文件。**锁文件本身不记录许可证字段**，来源信息分散在别处：

| 产物 | 大小 | 已知来源 |
| --- | --- | --- |
| `msime.db` | 76.3 MB | Engine 发布的工作词库 |
| `english.db` | 1.7 MB | Engine 发布的英文词库 |
| `bigram.bin` | 12.0 MB | Engine 发布的二元语言模型表，整句词格仲裁按它加权 |
| `trigram.bin` | 12.0 MB | Engine 发布的三元语言模型表，同上 |
| `others.db` | 1.5 MB | Engine 发布的表情等数据 |
| `dict_japanese.dat` | 66.5 MB | Mozc 的开源版日文词库，构成见[下一节](#日文词库的分发义务) |
| `mozc_dictionary_oss_README.txt` | 5.8 KB | 上述词库的许可证全文。**分发时必须一同携带**，理由见下节 |
| `dictionary-manifest.json` | 2.5 KB | 资源清单 |
| `dict_pinyin.dat` | 1.1 MB | 拼音数据，取自 `Google-PinyinIME-Rev` 归档的 `data/dict_pinyin.dat`，许可证见上一节 |
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

## 自带辅助码表（`resources/helpcodes/`）

这是全仓唯一一项**带着明确再分发限制**的随包数据，不在上面两个锁文件的覆盖范围里，所以单列一节。完整说明在 [`resources/helpcodes/NOTICE.md`](../resources/helpcodes/NOTICE.md)，这里只做索引。

| 项 | 值 |
| --- | --- |
| 文件 | `resources/helpcodes/jiajia_helpcode.txt`（方案标识 `jiajia`，加加辅助码） |
| 来源仓库 | [metasequoiaime/MSIME-Windows](https://github.com/metasequoiaime/MSIME-Windows) 的 `engine/helpcode/helpcodes/jiajia_helpcode.txt` |
| 来源提交 | `566ff8b8320e7f56256544b2b1f0da8c8e7f037e` |
| 内容摘要 | `sha256:6538d744547b590630e93160198ac16bf76112a51ec78b4dbae505b914761879`，7968 行 |
| 注入方式 | `engine-lock.json` 列出的 `scripts/apply_engine_jiajia_helpcode.py`，在准备 Engine 时写入 `vendor/MSIME-Engine/helpcode/helpcodes/` |
| 许可状态 | **本仓库的 GPL-3.0 不覆盖这张表的内容** |

按 NOTICE.md 的记录，本表的一部分条目直接来自拼音加加 5.x 安装包内的数据表 `fzm.bin`，而拼音加加是商业软件；来源仓库的 `engine/helpcode/NOTICE.md` 写明六张辅助码表没有任何一项拿到明确的再分发授权，并指出 `jiajia` 一行与其余五张性质不同（其余各表只是复现已发表的输入方案）。**在权利澄清之前不要假定这张表可以自由再分发**，打包发布前需确认它在目标渠道是否可接受。退出方式也记在 NOTICE.md 里：去掉 `engine-lock.json` 中的 `scripts/apply_engine_jiajia_helpcode.py` 即可让整套方案不进入产物，设置页随之少一个选项，Engine 自带的另外五套不受影响。

构成这张表所用的部件拆分与笔顺数据另有来源（rime-radical-pinyin，GPL-3.0，上游含 chaizi/CC-BY-3.0、CHISE/GPL-2+、yi-bai/ids/MIT；笔顺来自 cnchar，MIT），逐条同样见 NOTICE.md。Engine 自带的五套辅助码表随 `engine-lock.json` 锁定的归档一起来，来源说明在 `vendor/MSIME-Engine/helpcode/NOTICE.md`。

## 背单词词书（`resources/wordbook.lock.json`）

背单词模式的八本内置词书来自 ECDICT，不在 `desktop-dictionary.lock.json` 的覆盖范围里，所以单列一节。

| 项 | 值 |
| --- | --- |
| 来源仓库 | [skywind3000/ECDICT](https://github.com/skywind3000/ECDICT) |
| 来源提交 | `82c9872576b23118d7c42e920c11beb77f510ae2` |
| 文件 | `ecdict.csv` |
| 内容摘要 | `sha256:1a6947e04785db63613a92e14903cdae7954f7e84860b10e68e5c7cbb3f9c3cf`，65,933,428 字节 |
| 许可 | MIT，`Copyright (c) 2025 Linwei` |
| 取用方式 | `scripts/fetch_wordbooks.py` 按锁校验后展开到被忽略的 `target/wordbooks/` |
| 分发限制 | MIT，保留版权声明与许可全文即可；与本仓库的 GPL-3.0 分发兼容 |

**源文件不进版本库，也不整份随包**。脚本只取 `word`、`phonetic` 和 `translation` 的首行释义——卡片要显示的就这三样——按 `tag` 列（`zk`/`gk`/`cet4`/`cet6`/`ky`/`ielts`/`toefl`/`gre`）分成八本，写成 `client-core::vocabulary::wordbook::Wordbook` 直接能反序列化的 JSON。八本合计约 3 MB，宿主用 serde_json 读，不需要 CSV 解析器或 SQLite 驱动。

考纲归属是 ECDICT 提供的：仓库自带的 `english.db` 有中英释义和语料频次，够做「最常用的一千词」，但不足以断言某个词在四级大纲里。那是已发布的考纲，凭频次给它安一个名字就是编的。

词书**放在 `EngineResources/` 的兄弟目录 `wordbooks/`**，不放进去：`ResourceStore::verify` 要求固定资源目录与词库锁逐字节一致，多一个文件就会破坏那道「证明随包词库完整」的检查。`settled-model` 出于同样理由也是兄弟目录。

退出方式：不运行 `scripts/fetch_wordbooks.py` 即可。设置页随之只提供用户自行导入的词表，不影响其余功能。

## 非英语离线释义（`resources/offline-glosses.lock.json`）

候选词释义的目标语言是法语、日语、西班牙语、俄语、德语或韩语时，离线来源是从英文维基词典译文表生成的六个 SQLite 文件。`english.db` 只有中英释义，这几种语言原来只能走在线翻译。

| 项 | 值 |
| --- | --- |
| 来源 | [英文维基词典](https://en.wiktionary.org/)（Wiktionary contributors），经 [Wiktextract](https://github.com/tatuylonen/wiktextract) 抽取，由 [kaikki.org](https://kaikki.org/dictionary/English/) 发布 |
| 许可 | CC BY-SA 4.0（维基词典按 CC BY-SA 4.0 与 GFDL 双许可，这里取前者）。CC BY-SA 4.0 可单向兼容到 GPL-3.0 |
| 生成器 | `scripts/build_offline_glosses.py`，只用 Python 标准库；离线测试 `scripts/test-offline-glosses.py` 用真实结构的夹具 `scripts/offline-glosses-fixture.jsonl` |
| 产物 | `offline-glosses/zh-<lang>.db`，每种语言一个文件，外加 `offline-glosses-NOTICE.txt` |
| 取词范围 | 同一张译文表（同一个英文义项）里的 Mandarin 行与目标语言行配对；只读顶层 `translations`；键为简体，用 `msime.db` 的词表校验；每个中文词最多两个义项、每个义项最多两个词 |
| 锁 | `resources/offline-glosses.lock.json`。发布前 `artifacts` 为空，`input` 各项为 `null` |

**产物尚未发布，也还没有任何宿主读取它。** 共享层已经能用：`msime_client_candidate_gloss_request` 接受 `target_language`，翻译查询里的 `offline_gloss_languages` 列出已安装的语言。发布前还需要做三件事：一是用固定的 kaikki dump 生成六个文件和过滤后的 jsonl；二是把它们连同 NOTICE 发到不被应用内更新检查读取的 release（不要发到 `metasequoiaime/msime/releases`）；三是把 url、sha256、size、dump 日期、Wiktextract 版本和生成时的 SQLite 版本回填到锁里。kaikki 每周覆盖同一个 URL，所以能复现构建的是过滤后的 jsonl，它也要作为 artifact 锁定。上游已把 postprocessed 的 English jsonl 标为 deprecated，将来可能只剩约 2.9 GB 的 raw dump；生成器两种格式都接受。

**放在 resources 的兄弟目录 `offline-glosses/`**，不放进去，理由与 `settled-model`、`wordbooks` 相同：资源目录必须和词库锁逐字节一致，而且各平台只想带自己需要的语言。

**分发义务**：这些文件是维基词典文本的改编作品，发布时必须随附 `offline-glosses-NOTICE.txt`，并保持 CC BY-SA 4.0。App Store 这类带 DRM 的渠道与 CC BY-SA 4.0 第 2(a)(5) 条「不得附加有效技术措施」之间的关系，和已随包分发的 bigram/trigram 是同一个问题，需要维护者判断。

退出方式：不安装 `offline-glosses/` 即可。释义退回只用 `english.db` 和在线翻译，其余功能不受影响。

## 编译进共享库的数据

| 组件 | 许可证 | 位置与说明 |
| --- | --- | --- |
| [OpenCC](https://github.com/BYVoid/OpenCC) 词典，提交 `26753884f1984add422f3b0249ccee8613deaff6` | Apache-2.0 | `crates/client-core/data/opencc/`，许可证全文在同目录 `LICENSE`。`STPhrases.txt`、`STCharacters.txt`、`CJK_Compatibility_Ideographs.txt` 原样取自该提交的 `data/dictionary/`；`STPhrases_GeneratedFromRegionalPhrases.txt` 是该提交的 OpenCC 构建产物（`data/scripts/generate_st_phrases_from_regional_phrases.py` 用 `t2s.json` 生成），本仓不重新生成。提交号与来源 MSIME-Windows 的 `vendor/opencc` 子模块一致。只使用数据，不链接 OpenCC 的 C++ 库；`chinese_conversion.rs` 按 `s2t.json` 的规则实现转换。Windows 通知由 `Collect-Notices.ps1` 一并收集 |

## 各平台引入的第三方 SDK

| 平台 | 组件 | 许可 |
| --- | --- | --- |
| Android | `com.google.mlkit:digital-ink-recognition:19.0.0` | **Google 的 ML Kit 服务条款，不是开源许可证** |
| Android | AndroidX、`com.google.android.material` | Apache-2.0 |
| Android | vcpkg 提供的 Boost、fmt、spdlog、SQLite3（原生库，清单在 `platforms/android/vcpkg.json`） | 各自上游许可证 |
| iOS | `MLKitDigitalInkRecognition` 8.0.0（CocoaPods，链接进键盘扩展 target） | **Google 的 ML Kit 服务条款，不是开源许可证** |
| macOS | Sparkle 2.9.6 | 以上游发布附带的许可证为准；框架不随仓库分发，由构建者按 `platforms/macos/README.md` 记录的 SHA-256 自行取得 |
| Windows | vcpkg 提供的 Boost、libcurl、fmt、spdlog、SQLite3、nlohmann/json、utfcpp（清单与 baseline 在 `platforms/windows/vcpkg.json`） | 各自上游许可证；通知由 `platforms/windows/Collect-Notices.ps1` 收集 |
| Linux | IBus / Fcitx5、GTK 栈、libcurl、ICU、xkbcommon、nlohmann/json、X11 与 Wayland 客户端库 | 各自上游许可证，按发行版依赖引入 |
| 桌面 | Tauri、React、Vite 等 | 见 `pnpm-lock.yaml` 与各自上游 |

两个移动平台的 ML Kit 是识别手写笔迹用的。桌面与 Linux 不使用它，改用 Engine 随附的离线 Zinnia 识别器和模型；Android 的原生构建明确把 Zinnia 及其模型路径排除在外（`platforms/android/verify-native.sh`）。

仓库不捆绑任何字体文件；界面使用系统字体，`Noto Sans SC` 与 `Microsoft YaHei` 只是回退字体名。

## 语言生态依赖

逐个列出会立刻过时，以锁文件为准：

- Rust：`Cargo.lock`，当前 573 个 package 条目（含本 workspace 自身的成员）。`cargo audit` 是 `scripts/verify-local.sh` 完整版的一个阶段，漏洞视为失败；被接受的 `unmaintained` / `unsound` 公告逐条记在 [`.cargo/audit.toml`](../.cargo/audit.toml) 里，每条都写明引入链和接受理由。
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
