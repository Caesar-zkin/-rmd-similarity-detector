# 显式公共来源排除（开发版）

## 用途与默认行为

操作者可将已确认来自公共题干、教材给定内容或其他共同来源的区域排除，再比较剩余作答。
默认不启用；没有来源标注时所有原有行为保持不变。不把共有内容自动删掉，不自动判断标准解法或来源真实性。
本功能不替代最终抄袭规则，不能通过排除后高/低覆盖直接作结论。

## 标注契约

CSV或数据框必须包含side、start_line、end_line、quote、reason、reference。
side只允许A/B；起止行号是解析器UTF-8、统一为LF后的source中的1基行号，包含两端。
quote是所选行的完整原文，行间保留换行，但不包含最后一行的换行终止符。空白、排版、定界符和围栏都需保持一致。
reason和reference必须非空，分别说明为何排除及来源依据；网址仅当普通说明文本，不访问或加载。
原文变化、缺字段、非整数/越界行号、重叠区间、空计划或超过1000条均拒绝；CSV上限1MB。

当前只接受完整解析单元。不能在一个段落、公式、代码块或链接单元中间切开；报错会给出应覆盖的单元行号。
整行包含文字和行内公式/代码时，将一起排除，不能只按列排除其中一部分。纯标题/YAML/空白等原已不参与比较的范围会拒绝。
多行公式必须覆盖完整原公式单元，暂不支持只排除其中某一推导步骤。全部排除时对应指标为信息不足/NA。
允许只标注一侧，报告明确保留两侧的不同分母；来源依据由操作者负责确认。

## 生成标注

加载构建脚本中的模块列表后，可用make_exclusion_record生成quote，避免手工计算多行字符串：

```r
source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
a <- read_rmd("validation/boundary/fixtures/B03/a.Rmd", "A")
b <- read_rmd("validation/boundary/fixtures/B03/b.Rmd", "B")
records <- rbind(
  make_exclusion_record(a, "A", 3L, 3L, "共同题干", "B03自建题目说明"),
  make_exclusion_record(b, "B", 3L, 3L, "共同题干", "B03自建题目说明")
)
dir.create("reports-local", showWarnings = FALSE)
write.csv(records, "reports-local/exclusions.csv", row.names = FALSE,
          fileEncoding = "UTF-8")
```

生成quote只能核对位置，并不能证明来源。请先核查原文和来源后再登记。真实作业的quote及本地路径放已忽略目录，不提交。

## 调用

analyze_rmd_pair的exclusions参数接收数据框或CSV路径，NULL/空字符串表示关闭。
Rmd参数exclusion_file默认空字符串；单文件复制到其他目录后也可使用有效CSV路径。

CLI最后一个可选参数为CSV，需要同时提供HTML输出路径：

```text
Rscript scripts/render-detector.R A.Rmd B.Rmd reports-local/result.html reports-local/exclusions.csv
```

自建演示：Rscript examples/run-exclusion-demo.R；预置计划为examples/prompt-exclusions.csv，输入为B03两份边界材料。

## 处理与报告

先保留完整输入的baseline_modules，再验证全部排除记录；验证成功后用独立分析视图运行相同五个接口。
视图把选中的type/status标为excluded，保留raw、source、unit_id、字符偏移和行号。原documents不变；analysis_documents为视图。
视图summary更新剩余内容类型数量与excluded_units，字符数和总单元数仍指原始source和完整分段。
排除单元作为边界，公式序列不能跨其拼接；文字和代码本身也不跨原单元合并。原有诊断保留，受限内容不会因排除被宣布已分析。

报告主证据表属于排除后范围。另列前后状态、可比较数量、匹配数量、覆盖、公式/完整代码的匹配条目数；不同单位分开，不把条目数当独立证据数。
排除前的完整模块结果保留于返回对象；HTML展示前后概要及原文排除记录，记录/单元表最多100行，quote展示最多4000字符，完整标注不截断。
前后分母不同，覆盖升高或降低都需结合内容量解释。来源说明和原文经HTML转义，不作为代码或资源执行。

若任一记录无效，overall_status为exclusion_error，没有应用任一侧排除，当前modules为not_run；baseline_modules仍供核查。
若排除前某模块因资源限制失败，排除后其他分析可继续，但整体保留partial_failure，前后错误信息明确展示，不能冒充完整前后对照。
输入读取失败则不读取排除计划。verdict始终not_enabled。

## 验证与限制

tests/test-exclusions.R核查默认行为、位置不变、前后分母、失效计划原子性、完整公式/代码、公式边界、转义、CSV、资源限制及错误保留。
tests/test-render-report.R增加无R目录下的CSV排除真实编译；CI同时运行原有20对复制与10对边界材料，默认结果不受可选功能改变。
这不是自动公共来源检测，不处理部分单元/列区间或未知来源，也没有解决跨方法综合去重、最终判定和阈值标定。
