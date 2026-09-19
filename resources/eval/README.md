# 整句转换评测集

在此之前仓库没有任何衡量拼音→中文转换质量的手段。词图、回退解码器、以及将来任何重排，做完都无法说明变好还是变坏——这个目录提供那个数字。

跑法：

```sh
cargo run --release -p msime-input-runtime --example convert_eval -- \
  --resources <已校验的词库目录> \
  --set resources/eval/sentences-v1.tsv \
  --baseline resources/eval/baseline-sentences.json
```

`--update-baseline` 接受当前结果。`--limit N` 取等距子集（不是前 N 条，否则全是短词）。

**基线是带重排的数字。** `sentence-model.safetensors` 已经在 `desktop-dictionary.lock.json` 里，所以按锁文件取到的资源目录一定带它，而 `convert_eval` 见到模型就会挂上重排器。想量引擎单独的表现，把模型从资源目录里拿掉再跑——它会打印 `no model at ...`，那一行是判断当前测的是哪个臂的唯一依据。

## 延迟基准

同一批输入还用来量重排的代价。`convert_eval` 回答「排得对不对」，`rerank_latency` 回答「一次按键为此多花多少毫秒」：

```sh
cargo run --release -p msime-input-runtime --example rerank_latency -- \
  --resources <已校验的词库目录> \
  --set resources/eval/sentences-v1.tsv
```

需要资源目录里有 `sentence-model.safetensors`——它量的就是重排的开销，没有模型就没有可量的东西。`--budget-ms` 默认 16（一帧），p95 超出即以非零码退出；`--warmup N` 丢弃前 N 条用例的样本（默认 5）。

同进程里开两个 runtime，一个挂重排一个不挂，逐条交替先后顺序，按键**配对**相减。配对是必须的：真正要问的不是一次按键多久，而是**因为重排**多了多久，两次独立运行的差值里混着散热状态和页缓存。

**要看超预算的按键占比，不要只看均值。** 多数按键根本不走重排（三音节以下词图不跑，只有一条读法时也无从选择），均值把少数按键的代价摊到了全部按键上。6.8M int8 在整句集上均值只多 7.9ms，看着在预算内，实际是 25.2% 的按键超过一帧。

## 两个集，测的不是一回事

### `quanpin-words-v1.tsv` — 25,119 条词级

由 `build_eval_set` 从 `vendor/MSIME-Engine/dictionary/source/SampleIMESimplifiedQuanPin.txt` 固化而来，来源是 microsoft/Windows-classic-samples，MIT 授权，没有任何构建脚本读它，也不进入 `msime.db`。之所以固化进仓库：`vendor/MSIME-Engine` 不受 git 跟踪，`scripts/fetch_engine.py` 在磁盘标记与 `engine-lock.json` 不一致时会整树删除。

生成时丢弃 27,561 条单字、1,955 条截断条目，无解析失败。截断过滤用 Engine 自己的 `normalize_full_pinyin` 判断「key 能否恰好切成 gold 字数个音节」，而不是长度阈值——该格式在 12 字符处截断，但 `chulufengma`、`shumenshul` 这类更短的 key 同样被砍，长度阈值漏得掉。

**它测的是词典命中与排序，不是整句能力。** 实测 `gold_source` 几乎全是 `database`，词图一次都没有贡献过正确答案。

**不要用 `msime.db` 自身出题。** 它就是解码器查的那张表，等于让系统考自己；而 1–2 音节的排序实现就是 `ORDER BY weight DESC`，拿 weight 当金标准是在考 SQLite。

### `sentences-v2.tsv` — 310 条收割，带上文

从 C4 中文部分（ODC-BY，保留标点的原文，不是 `corpus/fetch.py` 剥过标点的训练语料）收割：把句子用 Engine 的拼音表转成拼音再打回去，首选与原句不同的收下来，上文取同一篇的前一句。`harvest_eval_set` 做这件事，`scripts/review-harvested-cases.py` 用 Jev 过一道评审（选中原文且无强歧义否决），再按拼音+原文去重。500 条收割 → 345 条通过 → 310 条。

**它不是准确率基准，用错了会得出荒谬结论。** 用例是按「产品当前打错」筛出来的，所以 `top1` 天生接近零（0.123），拿它和 v1 的 0.850 相减没有任何意义。它回答的是另一个问题：**已经打错的那些里，有多少是排序够得着的**——`top5` 是 0.561，即五成六的正确答案就在前五名，剩下四成四要解码器出力。`found` 恒为 1.000，因为收割时就要求金标准必须出现在候选列表里（`hanzi_to_pinyin` 对多音字不总是对，键错了原句永远解不出来，那种用例是废的）。

想要有代表性的准确率集，得不筛成败地随机抽样，那是 `harvest_eval_set` 换一个判断条件的事，不是换一份语料。

**已知杂质**：网页文本按标点切句，少数用例是切出来的半句（「是一次意气风发」）。金标准仍是原文、拼音仍解得出来，所以测的东西没变，只是读起来不像完整句子。

**它和 v1 互补，不替代 v1。** v1 是手写的、干净的、无上文的，量的是「常见句子排得对不对」；v2 是收割的、带上文的、全是硬骨头，量的是「排错的还有多少救得回来」。两个都在 `verify-local.sh` 里。

### `sentences-v1.tsv` — 60 条整句，手写

整句语料在仓库里不存在，磁盘上也没有任何 bigram 计数，所以这部分只能手写。金标准是「母语者在该拼音串下唯一自然的写法」；拼音本身就有两种同样自然写法的句子一律不收——评测集不能既诚实又有歧义。

**n=60 的统计分辨率：单臂比例的 95% 置信半宽约 ±13 个百分点。** 聚合数字的小幅变动不构成证据。两次运行要逐条比对每个 gold 的 rank，而不是对着汇总值做减法。基线 JSON 因此保留了分标签、分音节数和失败样例。

标签分布：`function-word` 10、`seg-ambiguity` 12、`homophone` 12、`number-measure` 6、`name-place` 6、`long-sentence` 8、`short-phrase` 6。人名一律是常见姓 + 通用名，不含真实个人信息。

## 往整句集里加用例

手写不是唯一来源。真实行文自己就是金标准：把句子用 Engine 自己的拼音表转成拼音，再把拼音打回去，首选不是原句的就是一个带已知正确答案、并且带着真实上文的失败用例。三步，最后一步是人。

上文那一列是第 6 列，`sentences-v1.tsv` 的手写行没有它，读作空串，两个既有基线因此逐字节不变。它存在的理由和 `sentences-v1.tsv` 那节说的是同一件事：把 会议 排在 回忆 前面是关于前文的判断，一个没有前文的集合问不出这个问题。**上文是 seed 进已提交历史的，不是当按键重放的**——重放会让每条用例的成绩取决于上一句转得好不好，而那正是逐例测量要排除的混淆。

### 一、收割

```sh
cargo run --release -p msime-input-runtime --example harvest_eval_set -- \
  --resources <已校验的词库目录> \
  --corpus <一行一篇的纯文本> \
  --out target/harvest.tsv \
  --attribution "语料来源与授权"
```

`--limit N` 限收录条数，`--min-chars` / `--max-chars` 限句长。署名写进输出文件头：C4 中文部分是 ODC-BY，LCCC 是 MIT，两者都要求署名跟着文本走，而一份收割出来的句子就是那些文本。

**语料必须一行一篇、保留标点、句序不变。** 上文取自前一句，所以标点被剥掉或句子被打乱的语料只能永远产出空上文。`chinese-ime-lm` 的 `corpus/fetch.py` 输出不合格：它的 `segment()` 只保留汉字串并按固定宽度切断，那对训练字模型是对的，对这里是错的。解压与 JSON 拆包在这个 example 之外做——它只读纯文本，这是它不依赖任何语料格式的原因。

**资源目录里必须有 `sentence-model.safetensors`。** 没有模型时它打印 `no model at ...` 并去挖引擎单独会错的用例，而产品是带重排发货的：第一批这样挖到的 108 条，重排自己就修好了 80.6%，几乎整批都是产品不需要做的工。挂上模型后同一份语料 2578 句只留下 100 条失败，失败率从 8.5% 降到 3.9%。

输出 8 列，比评测集多「当前首选」和「金标准排名」供评审时看。它**不是评测集**：它只证明「解码器没还原出原文」，没有判断过原文是不是该拼音串唯一自然的写法。

### 二、机器初筛

评审要看真实候选，所以先让 `convert_eval` 把收割文件跑一遍并导出。它读第 6 列作上文，多出来的两列忽略：

```sh
cargo run --release -p msime-input-runtime --example convert_eval -- \
  --resources <已校验的词库目录> \
  --set target/harvest.tsv \
  --dump target/harvest.jsonl

TYPESAFE_API_KEY=... scripts/review-harvested-cases.py target/harvest.jsonl target/harvest
```

脚本对每条问两个互不依赖的问题：在解码器实际产出的那些写法之间做选择，以及「这串拼音是不是有不止一种同样自然的写法」——后者就是上面那条排除规则本身，直接问出来。选择落在原文、且歧义没有强烈否决的，写进 `target/harvest-accepted.tsv`，列与 `sentences-v1.tsv` 一致、可直接粘；其余连同理由写进 `target/harvest-flagged.tsv`。150 条一轮约 9 万 input token，$0.004。

**选择是主判据，歧义只作强否决。** 第一版在歧义 >0.40 就否决，砍掉 150 条里的 70 条，而这 70 条的选择全都落在原文上——0.5 附近意味着模型对「是」和「否」给出相近概率，不是「中等歧义」，那个阈值是在抛硬币的区间里下判断。改成 >0.65 才否决后通过 108 条。阈值是在这批数据上的起点，不是定论。

**它只提议，不决定，也不是门禁。**

### 三、人工确认，这一步才产生评测集

逐行读 `harvest-accepted.tsv`，只问一件事：这串拼音是不是只有原文这一种自然写法？是就把该行粘进 `sentences-v1.tsv`，拿不准就丢。少一条没关系，多一条两可的句子会让之后每一次比较都测不准。

`flagged` 里 `disagrees-with-original` 那一档通常直接丢：语料自带错别字——LCCC 里有 我说连累我**阿**（该是 啊）、没什么**拉**（该是 啦），这时「金标准」本身就是错的，150 条里有 23 条属于这一档。聊天记录对这件事是嘈杂的来源，带标点的连续行文才是这套流程想要的语料。

并入后重跑 `convert_eval` 并 `--update-baseline`，基线 JSON 才对得上新的集合。

**对话语料的「上文」不是这个意义上的上文。** LCCC 是对话轮次，前一句是对方说的话，而模型把上文当作「我刚提交的内容」。150 条带上文重跑，top-1 从 0.687 掉到 0.667——3 条，噪声内，方向还不对。这说明机制通了，不说明有收益；要上文真正起作用，语料得是保留标点的连续行文。

## 为什么报告要分 source

候选带 `source`，对应 `vendor/MSIME-Engine/core/word_item.h` 的 `CandidateSource`。3 音节以上时 Engine 加入词图路径（`sentence_alternatives` 打开时是多条，关闭时一条），随后**在 Google-Pinyin 回退产出了整句的前提下**把那条回退搬到 index 0（`quanpin/quanpin_dictionary.cpp`，注释原文：「The lattice is a secondary source」）。

所以位置 1 到底是谁，随输入而变——词图的改动能不能反映到 top-1 也随之而变。`top1_source` 和 `gold_source` 每次运行都记录实际情况，而不是假定其中一种。

## 已知测不到的东西

词表覆盖（词级集的金标准 99.94% 本来就在词典里）、用户学习与调频（harness 强制关闭，否则前一条会污染后一条）、双拼路径、九宫格、语言模型困惑度（没有语料）。
