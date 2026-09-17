# 整句转换评测集

在此之前仓库没有任何衡量拼音→中文转换质量的手段。词图、回退解码器、以及将来任何重排，做完都无法说明变好还是变坏——这个目录提供那个数字。

跑法：

```sh
cargo run --release -p msime-input-runtime --example convert_eval -- \
  --resources <已校验的词库目录> \
  --set resources/eval/sentences-v1.tsv \
  --baseline scripts/eval-baseline-sentences.json
```

`--update-baseline` 接受当前结果。`--limit N` 取等距子集（不是前 N 条，否则全是短词）。

## 两个集，测的不是一回事

### `quanpin-words-v1.tsv` — 25,119 条词级

由 `build_eval_set` 从 `vendor/MSIME-Engine/dictionary/source/SampleIMESimplifiedQuanPin.txt` 固化而来，来源是 microsoft/Windows-classic-samples，MIT 授权，没有任何构建脚本读它，也不进入 `msime.db`。之所以固化进仓库：`vendor/MSIME-Engine` 不受 git 跟踪，`scripts/fetch_engine.py` 在磁盘标记与 `engine-lock.json` 不一致时会整树删除。

生成时丢弃 27,561 条单字、1,955 条截断条目，无解析失败。截断过滤用 Engine 自己的 `normalize_full_pinyin` 判断「key 能否恰好切成 gold 字数个音节」，而不是长度阈值——该格式在 12 字符处截断，但 `chulufengma`、`shumenshul` 这类更短的 key 同样被砍，长度阈值漏得掉。

**它测的是词典命中与排序，不是整句能力。** 实测 `gold_source` 几乎全是 `database`，词图一次都没有贡献过正确答案。

**不要用 `msime.db` 自身出题。** 它就是解码器查的那张表，等于让系统考自己；而 1–2 音节的排序实现就是 `ORDER BY weight DESC`，拿 weight 当金标准是在考 SQLite。

### `sentences-v1.tsv` — 60 条整句，手写

整句语料在仓库里不存在，磁盘上也没有任何 bigram 计数，所以这部分只能手写。金标准是「母语者在该拼音串下唯一自然的写法」；拼音本身就有两种同样自然写法的句子一律不收——评测集不能既诚实又有歧义。

**n=60 的统计分辨率：单臂比例的 95% 置信半宽约 ±13 个百分点。** 聚合数字的小幅变动不构成证据。两次运行要逐条比对每个 gold 的 rank，而不是对着汇总值做减法。基线 JSON 因此保留了分标签、分音节数和失败样例。

标签分布：`function-word` 10、`seg-ambiguity` 12、`homophone` 12、`number-measure` 6、`name-place` 6、`long-sentence` 8、`short-phrase` 6。人名一律是常见姓 + 通用名，不含真实个人信息。

## 为什么报告要分 source

候选带 `source`，对应 `vendor/MSIME-Engine/core/word_item.h` 的 `CandidateSource`。3 音节以上时，Engine 只加一条词图路径（`nbest = 1`），随后**在 Google-Pinyin 回退产出了整句的前提下**把那条回退搬到 index 0（`quanpin/quanpin_dictionary.cpp`，注释原文：「The lattice is a secondary source」）。

所以位置 1 到底是谁，随输入而变——词图的改动能不能反映到 top-1 也随之而变。`top1_source` 和 `gold_source` 每次运行都记录实际情况，而不是假定其中一种。

## 已知测不到的东西

词表覆盖（词级集的金标准 99.94% 本来就在词典里）、用户学习与调频（harness 强制关闭，否则前一条会污染后一条）、双拼路径、九宫格、语言模型困惑度（没有语料）。
