# 示例材料

parser-demo.Rmd用于read_rmd读取与分类演示，含中文、公式、代码、行内R及未读取的图片引用。代码块带eval=FALSE，行内表达式是用于识别的内容；请通过解析接口读取，不以编译示例作为检测。

后续补充用于两份作业比较的自建示例。当前未提供相似度检测入口。

## 两份Rmd的正文比较演示

text-a.Rmd与text-b.Rmd分别包含正文“统计分析”和“统计方法”，
同时包含不参与当前文字评分的公式与代码。

从项目根目录，在R中运行：

```r
source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")

doc_a <- read_rmd("examples/text-a.Rmd", file_id = "A")
doc_b <- read_rmd("examples/text-b.Rmd", file_id = "B")

compare_text_jaccard(doc_a, doc_b, k = 2L)
```

预期：两侧片段集合各有3种，共有1种，并集5种，
Jaccard相似度为0.2。

k=2仅用于演示，不是经过验证的最终参数。
该分数只描述正文片段重合，不是抄袭概率。


## 一条命令运行文字分析

`Rscript examples/run-text-demo.R`

可选：`Rscript examples/run-text-demo.R A.Rmd B.Rmd 5 30`。
输出整体Jaccard、双向覆盖、连续精确匹配文字和行号，不写输出文件。
默认示例Jaccard=0.2、覆盖率两侧均为0.5，匹配文字为“统计”。
只比较正文；小参数仅为示范，不是检测阈值或抄袭判定。

## 少量编辑的局部对齐演示

`Rscript examples/run-text-approx-demo.R`
读取text-edits-a.Rmd和text-edits-b.Rmd（人工符号序列，中间1字替换），
输出对齐、精确覆盖和合并覆盖；预期近似相似度0.9、覆盖率0.9。
不写输出文件，不执行作业代码。不是自然语言性能评估。

可指定文件：`Rscript examples/run-text-approx-demo.R A.Rmd B.Rmd 30 0.8`，
最后两个参数为最低相同字符数与最低对齐相似度；其他演示参数见脚本，不是推荐阈值。
