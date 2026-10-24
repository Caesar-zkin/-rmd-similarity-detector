# Rmd 作业相似性检测工具

基于 R Markdown 的文字、数学公式与 R 代码相似性检测课程项目。

当前分支：v0.3.0文字模块开发中。解析器已合入main；本分支已有正文Jaccard、精确匹配定位和双向覆盖率。近似改写、公式/代码相似度、最终判定和detector.Rmd尚未实现。

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
