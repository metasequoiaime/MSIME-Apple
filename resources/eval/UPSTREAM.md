# 这两个评测集的上游

`quanpin-words-v1.tsv` 与 `sentences-v1.tsv` 同时存在于 [chinese-ime-lm](https://github.com/metasequoiaime/chinese-ime-lm/tree/main/eval)。

这里保留一份副本，因为 `convert_eval` 要用真实引擎和真实词库跑它们——那是本仓库特有的验收路径，不该依赖网络。上游那份是给其他输入法用的。

**新增用例请提到上游**，再同步回来。反向操作会让两份悄悄分叉，而分叉的评测集比没有评测集更糟：两边都报数字，却不再可比。
