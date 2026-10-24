# 证据报告与单文件入口（开发版）

## 当前能力

detector.Rmd接收两份Rmd路径，读取后运行文字、完整公式、公式步骤、完整代码及局部代码五个接口，输出三类分项证据HTML。
当前verdict固定not_enabled（未启用最终判定），不生成抄袭概率或综合平均分。
模块失败保留error，不伪装为零相似度；其他独立模块继续。任一输入读取失败则不运行分项分析，输出输入错误报告。

报告顺序：运行/判定状态、文件概况、分项结果、原文对照与行号、解析/模块诊断、参数及限制。
文字覆盖按相同字符并集，代码覆盖按token对应并集；分别标注词法与包含改名的覆盖。
公式只给表达与步骤对应，不提供覆盖率。三类单位不相加。
相同片段可能出现在多个方法表中；不把条目数当成独立证据数或最终判断。证据整理表按实际位置保守归组，保留原模块索引及真实代表长度，详见evidence-spec.md。

## 生成与维护

- R/report.R：整合分析、捕获错误/警告、HTML转义及证据展示。
- templates/detector-template.Rmd：可信报告模板、样式、输入和分析参数。
- scripts/build-detector.R：按固定顺序内嵌11个R模块，生成detector.Rmd。
- detector.Rmd：已提交的生成文件，包含所需函数，不依赖运行目录的R/。
- scripts/render-detector.R：CLI编译助手。
- examples/report-a.Rmd和report-b.Rmd：自建文字/多行公式/代码综合示例。

修改模块或模板后运行Rscript scripts/build-detector.R，并一并提交生成文件。
Rscript scripts/build-detector.R --check拒绝过期生成文件。
构建按UTF-8/LF输出，不写入时间戳；.gitattributes保证仓库R/Rmd等文件采用LF。

## 本地运行

先安装R、rmarkdown（会带上knitr依赖）和Pandoc，运行期间不联网安装。
已安装RStudio时，CLI在Windows会尝试常见的RStudio Pandoc目录；其他布局可手动设置RSTUDIO_PANDOC。
不需要待检测代码引用的软件包或数据文件。

从仓库根目录：
Rscript tests/test-report.R
Rscript scripts/render-detector.R

默认写到reports-local/detector-report.html，该目录已被Git忽略。
指定输入：
Rscript scripts/render-detector.R A.Rmd B.Rmd reports-local/my-report.html

CLI相对路径基于当前工作目录，带空格路径应加引号。只允许html输出扩展名。
也可直接在RStudio Knit detector.Rmd，先修改顶部params.input_a/input_b。
复制单个detector.Rmd到其他目录仍可运行，但需把参数改成有效输入路径；默认示例路径仅在仓库内成立。
R中可用rmarkdown::render('detector.Rmd', params=list(input_a='A.Rmd', input_b='B.Rmd'))。

rmarkdown缺失时先单独运行install.packages('rmarkdown')，这属于环境准备，不发生在检测脚本内部。
Pandoc缺失时安装/配置后重试。模板仅为HTML，不要求LaTeX/TinyTeX。

## 内容与运行边界

只编译可信detector.Rmd，不编译输入作业；输入只交给read_rmd。
待检测YAML、R块、行内R、HTML及其引用路径不交给knitr执行。
所有动态文本先转义HTML分隔符、引号及反引号，再进入表格或pre/code文本区。
公式以转义源码展示，禁用MathJax、在线高亮及主题依赖，self_contained=true、template=null。
不把输入链接、图片或HTML作为报告资源；不执行输入代码或安装其依赖。
报告模板/参数设置是用户维护的可信程序，不属于待检测作业内容。

每类证据默认最多展示10条，可设1—100；单个片段最多展示4000字符。
这些仅限制展示，分析与覆盖仍使用完整结果，截断会提示。
诊断最多展示100条，概况保留总诊断数；模块问题保留issues、错误及警告。
行号区间可能含未匹配字符/步骤，不把范围全部计入覆盖。

本地报告包含作业内容，应保存在已忽略的reports-local/，不提交真实学生作业及报告。
CI只使用仓库自建材料；CI安装编译依赖可联网，和本机离线检测分开。
CI输出的示例HTML作为短期artifact，内容仅为自建综合示例及B03题干排除演示。

## 验证与未完成项

tests/test-report.R：五接口整合、输入错误、资源错误、转义、不执行输入、展示限制、空文件及可重复构建。
tests/test-render-report.R：将单个Rmd复制到无R/的临时目录，在中文/空格路径下真实编译；
检查关键证据、未启用判定状态、恶意输入不执行，最终HTML资源仅允许data:或页内引用。
这些是结构及运行测试，不等于实际检测效果评价。

最终判定、自动公共来源识别、公式覆盖、跨方法证据的最终支持规则及开发/保留集效果评估仍未完成。明确标注的完整解析单元现可排除，详见exclusion-spec.md。
未知语法、窗口/种子、保守改名及规模上限会限制召回；参数必须通过后续开发实验再冻结。

格式依据：
https://rmarkdown.rstudio.com/docs/reference/html_document.html
https://rmarkdown.rstudio.com/docs/reference/render.html
