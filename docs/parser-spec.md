# v0.2.0 解析契约

这是结构解析层，不计算相似度或抄袭判断。仅使用base R，不调用knitr、rmarkdown、eval或source执行待检测文件。开发者在自己的环境source的是本项目parser.R。

## 接口

```r
source("R/parser.R", encoding = "UTF-8")
doc <- read_rmd("examples/parser-demo.Rmd", file_id = "A")
doc$units
doc$diagnostics
```

parse_rmd_text(text, file_id)用于单个字符串；read_rmd(path, file_id, encoding)读取本地文件。默认UTF-8，UTF-8 BOM及CRLF/CR统一；不猜测编码。可显式提供平台支持的其他编码，解码失败或含NUL报错。文件后缀必须为.Rmd（忽略大小写）。

## 返回结构

返回rmd_document列表：file_id、source、units、diagnostics、summary；文件接口另带encoding。source是规范换行并去BOM后的UTF-8正文。

units为有序、互不重叠、无遗漏的原文分段表，拼接raw可以精确重建source。每行字段：

| 字段 | 含义 |
|---|---|
| unit_id / file_id | 文档内单元ID / 调用者提供的文件ID；跨文件以二者联合标识 |
| type | yaml、heading、blank、text、math、code、inline_r、inline_code、unsupported |
| context_id | 段落上下文；行内文字/公式/代码共享，空行、标题和代码块形成边界 |
| section | 最近的ATX标题文本，不推断题号对应关系 |
| language | 代码围栏标签的首个语言名称；未声明为空 |
| start_offset / end_offset | raw在source中的1基字符闭区间 |
| start_line / start_column | 起始行/列，1基Unicode字符位置 |
| end_line / end_column | 结束行/列，闭区间；换行符位于上一行末尾 |
| content_start / content_end | 去除外层定界符后的连续内容范围；空内容用start > end表示 |
| raw / content | 原文分段 / 供后续处理的内容，尚未进行检测规范化 |
| status | ok或limited，后者需结合diagnostics |

坐标不对应磁盘字节。正文内的普通Markdown排版符号在此层保留；后续文字规范化必须继续维护位置映射。内联链接原文保留完整raw，content仅含标签，因此不能用content长度替代原始跨度。空白也有单元但不参与相似度。

diagnostics列：code、severity（warning/info）、line、column、message。summary只描述数量，不声称“解析覆盖率”等于检测覆盖率。code_units含代码块和inline_r，不含普通inline_code。

## 支持范围与降级

- 文件开头的--- YAML到---或...，仅隔离，不解释标签或执行表达式。
- 0—3空格缩进的反引号/波浪围栏，长度至少3；关闭围栏同字符且长度不小于开头，允许尾空白。代码内部美元符号不解析。
- ATX标题；Setext标题与嵌套blockquote/list中的围栏未支持，会保留为正文。缩进至少4空格或tab提示歧义。
- 单行任意长度的反引号行内代码；r后接空白识别为inline_r。跨行行内代码暂不支持，未闭合标limited。
- 单美元行内公式限同一行，开头后、结尾前不能是空白；双美元、反斜杠圆括号/方括号，以及裸equation/align/gather/multline及其星号环境。反斜杠圆括号也限单行。
- display公式可跨空行；当前保留整个多行环境，公式步骤拆分留给公式模块。
- 公式内部LaTeX命令/宏原样保留，不验证数学正确性，不展开宏；同名嵌套环境未支持。
- 转义美元保留为文字。货币美元、复杂嵌套与非标准定界可能歧义，需要核查警告和原文。
- 支持同一行的简单内联链接/图片目的地址，包括平衡圆括号；不解析嵌套标签。图片不读取。引用式图片提示未支持，引用式链接按正文保留。
- HTML注释、script/style块隔离；其他HTML所在行标unsupported，复杂HTML块正文分类不保证。
- 代码注释在此阶段随代码保留，后续代码词法模块提取；不在解析层用正则错误拆分字符串中的#。
- 题干不自动删除；本版本尚未实现手工排除接口，题目等仍按普通文本保留。

未闭合YAML、代码围栏或display公式保守地保留至文件末尾，并发出警告，不能把剩余内容当作已成功分类。未闭合行内标记仅保留到行末。语法有歧义时不宣称完整CommonMark/Pandoc解析能力。

## 本阶段验收

运行Rscript tests/test-parser.R。检查原文重建、无重叠区间、行号、内容类别、上下文、代码不执行、中文路径、BOM/换行、缺失文件、解码失败与未闭合标记。测试只使用自建材料，与保留性能测试集无关。

R运行环境缺失时不得将静态审阅写成测试通过。v0.2.0可接受合入前的GitHub Actions执行结果作为验证记录。
