# 回退整句：一个被缺失文件掩盖了的排序缺陷

## 定位

整句评测第一次跑出 top-1 51.7% 时，有个数字比它更反常：`top1`、`top5`、`top9`、`found` 四个值完全相等。整句答错时，正确答案不是排在后面，而是**根本不在候选列表里**。

顺着候选来源查下去：60 条里 58 条位置 1 的 `source` 是 `Generated`（词图），`Fallback` 一条都没有。而 `quanpin/quanpin_dictionary.cpp` 的注释把回退称作「the primary whole-sentence suggestion」，词图只是「a secondary source」。主路径在生产里一次都没跑过。

原因在 `quanpin_dictionary.cpp:133`：

```cpp
decoder_(paths_.resource(metasequoia::assets::pinyin_model),
         paths_.user(metasequoia::assets::pinyin_user_dictionary)),
```

`assets::pinyin_model` 是 `dict_pinyin.dat`（`contracts/assets/assets.h:13`）。**该文件不在锁定的词库发布里**——发布只有 `msime.db`、`english.db`、`others.db`、`dict_japanese.dat` 和两个说明文件。

`core/pinyin_decoder.cpp:70` 的 `im_open_decoder` 失败时静默 `return {}`，所以没有任何征兆。文件只有 1.1 MB，一直躺在 Engine 仓库的 `googlepinyinime-rev/data/` 下。

## 补上文件之后

把 `dict_pinyin.dat` 加进资源集后，两个评测集朝相反方向走：

| | 无模型 | 有模型 |
|---|---|---|
| 整句 top-1 | 0.517 | **0.717** |
| 整句 found | 0.517 | 0.783 |
| 词级 top-1 | 0.767 | **0.633** |
| 词级 3 音节 top-1 | 0.926 | **0.605** |
| 词级 4 音节 top-1 | 0.905 | **0.451** |
| 词级 5 音节 top-1 | 0.300 | **0.000** |

词级失败的形状高度一致：正确答案是词典里的整词，却被回退拼出来的串顶掉。

| 输入 | 期望 | 补文件后的 top-1 | 正确答案落到 |
|---|---|---|---|
| `baiyibaishun` | 百依百顺 | 白一百顺 | 第 3 |
| `banbushishi` | 颁布实施 | 版不是是 | 第 3 |
| `anquanbaowei` | 安全保卫 | 安全包围 | 第 2 |
| `anli` | 按理 | 案例 | 第 8 |

`gold_source` 里 2765 条正确答案**全部**来自 `Database`，而位置 1 有 444 条被 `Fallback` 占据。

## 真正的缺陷

`quanpin_dictionary.cpp:389-400`：只要回退产出了整句，就无条件把它搬到 `result.begin()`。

```cpp
if (google != result.end() && google != result.begin())
{
    WordItem preferred = std::move(*google);
    result.erase(google);
    result.insert(result.begin(), std::move(preferred));
}
```

而 `quanpin/word_lattice.h:22-26` 写明的合并顺序是：

> 1. Exact SQLite full-key hits (CandidateSource::Database / UserDatabase)
> 2. Lattice full-cover sentences (CandidateSource::Generated)
> 3. Google-pinyin Fallback, prefixes, and other remaining items
>
> Lattice never displaces a leading exact Database/UserDatabase full-cover

代码与它自己的文档相反：回退被放在了第 1 位，而文档说它属于第 3 类，且第 2 类都不许挤掉第 1 类。

文件缺失把这条规则一直遮住了——回退从不产出，那段搬运代码从未执行。

## 经验

**不要单独补这个文件。** 单独补上是整句 +20 分、常用词 −13 分的交换，3–5 音节词退化尤其严重。补文件和修排序规则必须同时做。

**一个静默失败的可选数据源，会让依赖它的整条代码路径变成死代码，而所有测试照常通过。** `im_open_decoder` 失败时只是 `return {}`；没有日志、没有降级提示。这类可选资源缺失应当留下诊断。

**证伪步骤**：把 `dict_pinyin.dat` 从资源目录删掉再跑 `convert_eval`，整句 top-1 会掉回 0.517，且 `top1_source` 里 `fallback` 归零。

## 复现

```sh
cargo run --release -p msime-input-runtime --example convert_eval -- \
  --resources <资源目录> --set resources/eval/sentences-v1.tsv
cargo run --release -p msime-input-runtime --example convert_eval -- \
  --resources <资源目录> --set resources/eval/quanpin-words-v1.tsv --limit 3000
```

两个集必须一起看：任何只动整句排序的改动，都要用词级集确认没有把词典命中挤下去。
