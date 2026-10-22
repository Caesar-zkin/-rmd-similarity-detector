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

