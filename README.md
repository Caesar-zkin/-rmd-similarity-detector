# Rmd 作业相似性检测工具

基于 R Markdown 的文字、数学公式与 R 代码相似性检测课程项目。

当前分支：v0.6.0证据报告开发中。已实现文字、受限公式与R代码分项比较，并生成可独立编译的detector.Rmd。最终判定、规则标定及开发/保留集效果评估尚未完成。

## 项目目标

输入两份 .Rmd 作业，纯本地读取与分析，生成包含综合判断、分项结果、相似片段和原始位置的 HTML 报告。均衡控制漏检与误报。相似度不解释为抄袭概率。

## 项目依据

- [项目草案 V3.0](docs/project-plan.md)：已确认的需求与方法基准。
- [决策记录](docs/decisions.md)：后续变更的原因和影响。
- [路线图](docs/roadmap.md)：阶段任务与验收要求。
- [维护说明](CONTRIBUTING.md)：分支、提交与验证流程。
- [更新日志](CHANGELOG.md)：项目版本进度。
- [使用与交付说明](docs/delivery-guide.md)：环境准备、独立运行及报告解读。
- [课程项目报告](docs/course-report.Rmd)：研究现状、系统设计、检测方法、验证结果与局限。
- [AI 样本检查记录](docs/ai-pair-review.md)：三组探索样本的结果及限制。

## 目录

| 路径 | 用途 |
|---|---|
| docs/ | 方案、决策与路线图 |
| R/ | 后续开发时使用的模块函数 |
| examples/ | 自建示例作业 |
| tests/ | 自动化与边界测试 |
| validation/ | 验证方案、样例清单与结果说明 |
| detector.Rmd | 生成的单文件证据报告入口 |
| templates/ | 报告模板 |
| scripts/ | 构建与编译助手 |

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

测试命令：`Rscript tests/test-parser.R`。详见[解析契约](docs/parser-spec.md)。本分支配置Linux/Windows结构测试；只有实际成功运行的结果才算验证通过。已有证据报告命令，尚无经过验证的最终判定阈值。

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
近似匹配超出计算上限时，报告标记分析受限，并保留精确匹配和相应覆盖率。参数未标定。

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
步骤包括单独公式和受支持多行环境的行；不输出公式覆盖率或抄袭结论。

## 多行公式演示

运行 `Rscript examples/run-math-multiline-demo.R`；可追加两份Rmd路径。
测试：`Rscript tests/test-math-multiline.R`。加载顺序仍为parser.R → math.R → math-sequences.R。
prepare_math_steps保留每行与原公式单元的关系，支持有限align/aligned、gather/gathered及equation包装。
多列、未知命令和复杂嵌套标受限；不是完整LaTeX或数学等价分析。

## R代码基础比较

运行 `Rscript examples/run-code-demo.R`；可追加两份Rmd路径。
测试：`Rscript tests/test-code.R`。加载parser.R后加载code.R。
使用R解析器只解析不执行；保留函数、参数、成员、数字和字符串，简单局部变量可一致改名。
未知调用和复杂作用域保留原名并标受限；该入口按完整单元比较。详见[代码规格](docs/code-spec.md)。

## 代码局部匹配

运行 `Rscript examples/run-code-local-demo.R`；可追加两份Rmd路径。
测试：`Rscript tests/test-code-local.R`。加载parser.R、code.R后加载code-local.R。
按完整顶层语句组成重叠窗口，允许预算内语句插删，整段共用变量映射；覆盖按原文token位置去重。
分别报告原词法覆盖与包含改名的结构对应覆盖，不解释为抄袭概率。
不切入单条表达式或函数/循环内部做局部匹配，不支持任意token修改；参数未标定。

## 在本地页面比较作业

Windows 可双击 `dist/RmdDetector.exe`。启动器内嵌 `detector.Rmd`，使用本机的 R、`rmarkdown`、`shiny` 和 Pandoc。使用期间保留启动窗口。

修改主文档后，先运行 `Rscript scripts/build-detector.R`，再从 PowerShell 运行 `& ./scripts/build-launcher.ps1` 更新 EXE。

提前安装 R、`rmarkdown`、`shiny` 和 Pandoc。在 RStudio 打开 `detector.Rmd`，点击 **Run Document**。也可以从项目目录在 R 控制台运行：

```r
rmarkdown::run("detector.Rmd", shiny_args = list(host = "127.0.0.1"))
```

页面打开后选择两份 UTF-8 编码的 `.Rmd` 作业，点击 **开始分析**。候选结论、相似片段和原文行号会显示在当前页面。R 会话需保持运行，文件由本地 Shiny 服务读取。

## 生成静态证据报告

环境需预装rmarkdown及Pandoc。运行 `Rscript scripts/render-detector.R`，默认使用两份综合示例，输出 `reports-local/detector-report.html`。
指定作业：`Rscript scripts/render-detector.R A.Rmd B.Rmd reports-local/my-report.html`。
在 R 中可用 `rmarkdown::render("detector.Rmd", runtime = "static")` 静态编译。报告明确显示未启用最终判定，不输出抄袭概率。

开发维护：修改R/或模板后运行 `Rscript scripts/build-detector.R`，CI用 `--check`验证生成文件未过期。
测试：`Rscript tests/test-report.R`；真实单文件编译测试：`Rscript tests/test-render-report.R`。
详见[报告规格与运行说明](docs/report-spec.md)。检测阶段不自动安装依赖，不执行待检测作业。

## 明确标注公共来源

默认不排除共有内容。可提供CSV，逐侧指定完整解析单元的行号、原文核对文本、理由和来源；任何记录无效则不应用排除。
运行 `Rscript examples/run-exclusion-demo.R` 查看B03共同题干的排除前后比较。
生成演示报告：`Rscript scripts/render-detector.R validation/boundary/fixtures/B03/a.Rmd validation/boundary/fixtures/B03/b.Rmd reports-local/prompt-excluded.html examples/prompt-exclusions.csv`。
报告保留前后分母/匹配量、排除记录及原始诊断。来源真实性由操作者确认，不自动识别公共题干或标准解法。
测试：`Rscript tests/test-exclusions.R`。详见[排除规格](docs/exclusion-spec.md)。

## 三状态开发试判

运行 `Rscript examples/run-decision-demo.R` 查看疑似抄袭、未检出明显证据和证据不足三个开发路径；测试为 `Rscript tests/test-decision.R`。
报告自动展示decision及原始触发记录，CLI打印Development candidate，批量CSV保存candidate_verdict和规则版本。
正式verdict仍为not_enabled。当前参数只是初始开发规则，没有独立答案或保留集准确率，不能按演示结果宣称已验证检测能力。详见[开发判定规格](docs/decision-spec.md)。
