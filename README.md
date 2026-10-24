# Rmd 作业相似性检测工具

基于 R Markdown 的文字、数学公式与 R 代码相似性检测课程项目。

当前分支：文字模块与v0.4.0公式基础开发中。解析器已合入main；本分支已有正文Jaccard、精确匹配、候选窗口、近似局部对齐和双向覆盖率。新增单条公式原始/排版/一致改名比较。新增分别定界公式的多步一致映射与受限步骤插删。多行公式环境、深度语义改写、代码相似度、最终判定和detector.Rmd尚未实现。

## 项目目标

输入两份 .Rmd 作业，纯本地读取与分析，生成包含综合判断、分项结果、相似片段和原始位置的 HTML 报告。均衡控制漏检与误报。相似度不解释为抄袭概率。

## 项目依据

- [项目草案 V3.0](docs/project-plan.md)：已确认的需求与方法基准。
- [决策记录](docs/decisions.md)：后续变更的原因和影响。
- [路线图](docs/roadmap.md)：阶段任务与验收要求。
- [维护说明](CONTRIBUTING.md)：分支、提交与验证流程。
- [更新日志](CHANGELOG.md)：项目版本进度。

## 目录

| 路径 | 用途 |
|---|---|
| docs/ | 方案、决策与路线图 |
| R/ | 后续开发时使用的模块函数 |
| examples/ | 自建示例作业 |
| tests/ | 自动化与边界测试 |
| validation/ | 验证方案、样例清单与结果说明 |
| detector.Rmd | 计划中的最终单文件入口，尚未创建 |

开发时允许模块化维护，交付时生成包含所需函数的 detector.Rmd，避免手工维护两份算法。

## 运行约定

依赖提前安装；检测期间不自动安装、不联网、不执行待检测作业代码。最终报告需能离线查看；若使用数学排版资源，应本地提供或以转义源码展示，避免外部 CDN 依赖。

解析演示（从仓库根目录在R中运行）：

```r
source("R/parser.R", encoding = "UTF-8")
doc <- read_rmd("examples/parser-demo.Rmd", file_id = "A")
doc$units
doc$diagnostics
```

测试命令：`Rscript tests/test-parser.R`。详见[解析契约](docs/parser-spec.md)。本分支配置Linux/Windows结构测试；只有实际成功运行的结果才算验证通过。目前没有抄袭检测命令或经过验证的阈值。

## 数据管理

真实学生作业、私人报告和本地文件路径不提交。仅提交有权使用的匿名或自建材料。保留测试材料不得用于日常调参或自动化回归测试。


## 文件比较演示（开发分支）

从项目根目录执行 `Rscript examples/run-text-demo.R`。
指定文件：`Rscript examples/run-text-demo.R A.Rmd B.Rmd 5 30`，
最后两个参数分别为字符片段长度和合并后最低匹配长度，尚未标定。

加载顺序为parser.R → text.R → text-matches.R。
新增逻辑在R/text-matches.R，旧工具函数不改动。

测试：`Rscript tests/test-text-matches.R`；
同时保留 `tests/test-parser.R` 和 `tests/test-text.R`。
仅分析正文，不输出最终抄袭结论。详见[文字规格](docs/text-spec.md)。

## 少量文字编辑演示

`Rscript examples/run-text-approx-demo.R`

示例只有中间1字替换；相同9字/10列，近似相似度0.9，两侧覆盖率0.9。
关键代码在R/text-approx.R，加载时放在text-matches.R之后。
测试：`Rscript tests/test-text-approx.R`。

仅支持当前窗口和种子范围内的文字编辑，不保证找到全部局部复制，不进行语义理解。
输入较大超过上限会明确报错；参数未标定。

## 正文排版演示

支持有限的强调、删除线、引用/列表前缀和转义处理，保留原文字符映射；不是完整Markdown实现。
运行 `Rscript examples/run-text-markdown-demo.R`，示例的规范化正文一致，Jaccard和覆盖率均为1。
测试：`Rscript tests/test-text-markdown.R`。原文、公式和代码不会被此步骤修改。

## 单条公式比较

运行 `Rscript examples/run-math-demo.R`；也可追加两份Rmd路径。
测试：`Rscript tests/test-math.R`。加载R/parser.R后加载R/math.R。
支持有限LaTeX词法规范化与单条公式内的一一符号映射，未知命令标受限。
这是结构匹配，不能证明数学等价或抄袭。详见[公式规格](docs/math-spec.md)。

## 多步公式推导演示

运行 `Rscript examples/run-math-sequence-demo.R`；可追加两份Rmd路径。
新增R/math-sequences.R，加载在math.R之后；测试为 `Rscript tests/test-math-sequences.R`。
整段共用一一变量映射，允许预算内跳过内部步骤并记录位置。示例匹配3步、跳过1步，步骤比例0.75。
当前每个分别定界的公式算一步，尚不支持多行环境拆分；不输出公式覆盖率或抄袭结论。
