# 验证管理

## 当前材料与范围

固定6个基础任务、每任务6种变体，共36个计划名额。tasks.csv固定4个开发任务、2个保留任务；同一任务全部变体只能留在同一组。
T01文字、T02推导、T03代码与说明、T04均值公式与实现进入开发；T05文字、T06代码与说明预留为保留任务。
任务按侧重点分为文字2、公式2、代码与说明2；基础样例不要求每份同时出现三类内容。
保留组没有独立的纯公式任务，后续评估不能声称覆盖所有任务类型。此处分组先于保留材料采集和查看结果。

当前20对开发材料可运行：4个开发任务各有直接复制、仅改变排版、轻度修改、局部复制和分散复制五种变体。
全部由项目自建，目标明确由源文件派生；短推导和常规均值代码是算法行为检查，不代表足以判断抄袭。
另外16个名额明确标记pending，包括4对开发组独立作答和12对保留材料。
尚无真正独立答案，也没有完成准确率、误报率、召回率或保留评估。

## 文件用途

| 文件 | 用途 |
|---|---|
| tasks.csv | 固定任务分组及内容类型 |
| pairs.csv | 36个名额、变体、来源、状态与输入路径 |
| annotations.csv | 已就绪材料两侧的原文范围和人工可核查原句 |
| dev/T01—T04/ | 可公开提交的自建Rmd材料 |
| ../scripts/validation-tools.R | 清单校验、标注核对、批量运行及实验快照 |
| ../scripts/validation-localization.R | 按侧、按方法评价复制来源位置；对重叠位置取并集 |
| ../scripts/validation-decisions.R | 开发候选三状态的分标签、分变体统计；缺失材料不进入分母 |
| ../scripts/run-validation.R | 从仓库根目录运行开发实验的入口 |
| ../tests/test-validation.R | 清单隔离、错误标注及基础行为回归检查 |

## 标注规则

annotations.csv每行记录pair_id、side(A/B)、kind(text/math/code)、start、end及quote。
start/end是解析器UTF-8、统一换行后的source的1基字符位置，含两端；不是字节或磁盘偏移。
quote必须与该位置的原文完全一致；脚本逐条核对，防止编辑材料后留下失效位置。
排版符号、公式定界符、代码围栏可以位于来源范围内。范围表达内容的复制来源，不表示其中每个字符都应计入相同字符覆盖。
文字覆盖、代码token覆盖及公式步骤的单位不同；后续定位评价必须先转换为对应可比较位置，不能直接把范围长度当作检测分母。
本批标注表达复制来源，轻改区域可以包含修改字符。相同字符匹配不会覆盖修改字符，因此文字定位召回可能低于1；这不能解释为所有来源字符都应相同。插入的额外公式、代码和干扰文字不列入复制来源。

## 运行

在仓库根目录的终端运行：

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" tests/test-validation.R
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" scripts/run-validation.R
```

实验输出到已忽略的reports-local/validation/：
- results.csv：每对的分项状态、错误、Jaccard、双向覆盖、公式序列数量；NA保留不适用或失败情况。
- localization.csv：两侧、三种方法各自的可比较数量、来源标注数量、预测数量、TP/FP/FN、定位precision/recall及状态。
- decision-summary.csv：开发候选三状态的数量、待补数量及描述性比例，详见下文；没有独立答案时误报率为NA。
- input-and-code-hashes.csv：清单、输入、运行脚本及引擎文件的MD5指纹，用于复现实验，不作为安全签名。
- experiment.rds：清单快照、完整分项结果、实际参数、R/sessionInfo、UTC时间及可取得的Git提交。

readRDS("reports-local/validation/experiment.rds")可在R中查看完整快照。
重复运行会覆盖上述五个文件，需保留某次实验时先复制整个输出目录。RDS的schema_version为3，新增decision_summary并保留完整逐对结果。
工作区未提交修改会改变文件指纹，因此不能仅凭commit判断实验代码完全一致。
运行不编译输入Rmd，不执行其代码，不联网安装包。配置CSV仅按数据读取。

## 隔离与补充原则

当前批量入口只允许validation/dev/内显式登记的文件，不扫描目录，也不接受保留集参数。
保留行只登记任务/变体名额，不填写路径；保留材料未来放在已忽略的validation/holdout-local/，不提交、不进入常规CI。
独立答案需记录实际作者或采集方式，并确保作答时没有查看源答案；不得将AI或人工改写冒充独立完成。
pending行不会运行。材料就绪时补齐来源、标签、两侧路径和必要标注，再将状态改为ready，并同步相应测试。

已完成既有证据去重、定位评价和未标定三状态开发试判。后续补更有代表性的开发材料与真正独立作答，检查误报、漏检与证据不足，再冻结规则并进行一次性保留评估。
当前20对短复制样例不能用于估计分类误报或均衡选择判定阈值。

## 三状态开发验证汇总

decision-summary.csv按scope=all（全部开发材料）及各variant分组；label分别为copied与independent。
planned、evaluated、pending依次是计划名额、实际运行对数和待补数量。pending中unassigned的名额仅按变体归入计划类别，不作为已审核真值，不进入任何比例分母。保留组和边界控制均不进入此表。
suspected、no_clear_evidence、insufficient_evidence三列的数量相加等于evaluated。decision_errors单列记录判定程序失败，是insufficient_evidence的子集，不能重复相加。

| 比例列 | 分子 / 分母 |
|---|---|
| detection_rate | 复制材料中候选疑似数 / 已运行复制对数 |
| clear_miss_rate | 复制材料中候选未检出数 / 已运行复制对数 |
| false_alarm_rate | 独立材料中候选疑似数 / 已运行独立对数 |
| abstention_rate | 当前标签中证据不足数 / 该标签已运行对数 |

证据不足保留在分母内，不能通过只计算有明确结论的样例来提高比例。clear_miss_rate只记录明确未检出；未被触发为疑似的复制材料还包括证据不足，两列必须同时查看。
分母为0或该比例不适用于当前标签时为NA。每对材料权重相同，同一任务的多个派生变体并非独立抽样，比例只描述当前登记材料，不能推断真实作业表现或置信区间。不输出总体accuracy、F1或抄袭概率。
统计拒绝漏行、重复ID、错配标签、混合规则版本以及将判定失败写成未检出。仍使用development_unvalidated阶段，正式verdict保持not_enabled。

初始development-v1在现有20对基础派生样例上的观察：疑似0、未检出0、证据不足20。复制触发比例0，证据不足比例1；独立材料0对，因此误报率NA。这暴露材料代表性及规则标定缺口，不证明具备可用检测能力，也不为提高命中率而直接降低门槛。

在PowerShell中可查看全部及分变体统计：

```powershell
Import-Csv .\reports-local\validation\decision-summary.csv | Format-Table scope,label,evaluated,pending,suspected,no_clear_evidence,insufficient_evidence
```

## 定位评价的单位与限制

定位precision=落在标注复制来源内的检测位置数/全部检测位置数；recall=被检出的标注来源位置数/全部可比较的标注来源位置数。
这是复制区域定位指标，不是疑似抄袭判定的分类精确率或召回率，也不证明两侧每个位置一一对应正确。
重叠标注、重复方法或重叠窗口的位置只计一次；不按最外层行号范围填满间隔。

- text：文字精确及近似匹配的相同字符位置并集。标注范围先与规范化后实际可比较字符取交集，排版与空白不计入。
- code_local：局部代码匹配（含一致改名）的token起点并集。只有完全落在标注范围内的完整词法token列为来源；注释和分号不计入。
- formula_sequence：仅评价多步公式序列接口的受支持步骤ID；一步的全部比较token都在来源标注内才计入。完整公式比较接口的结果不并入此项，也不把步数称为公式字符覆盖率。

预测为空且有来源标注时，recall=0、precision=NA；来源为空时recall=NA；没有可比较内容时标no_comparable_content。
模块失败或未运行时标analysis_unavailable，计数和指标为NA；解析受限时只评价成功比较的子集，保留analysis_status和annotated_regions，不能声称全文件都已评价。
各单位分开列出，不合并为一个总分。完整原文标注仍保留，未支持内容不会被宣布为已检测。

分散变体故意包含已知边界：T02把公式分放在不同标题下，序列不能跨标题；T03把短语句分进不同代码块，每块不足当前20token门槛。
这两种情形保留为观察到的漏定位，不调整默认参数来让自建样例全部通过。自动测试断言边界行为，后续若改进算法须同步更新说明和相关断言。

后续先采集真正独立答案和共同题干/标准解法等负例，再考虑比较候选参数；保留组仍未采集、未运行。

## 边界材料与独立作答采集

新增boundary/cases.csv及10对自建边界材料，使用scripts/run-boundary.R单独运行，结果写reports-local/boundary/，不并入36对核心名额或20对复制实验。详见boundary/README.md。
共同题干、短常规公式/代码匹配只是风险观察，不被自动标为抄袭或冒充独立答案；无最终分类时不计算误报率。

independent-tasks.md是可单独交给未见过源答案者的任务单，independent-collection.md说明匿名采集及来源审核，另有空白Rmd和登记CSV模板。
真实材料存放已忽略的validation/independent-local/；公开批量脚本不会读取它们，公开独立答案名额继续pending。尚未实际收集独立答案。
新增scripts/run-independent-validation.R作为单独本地入口：--audit核对来源字段与指纹，人工verified后才分析，基础与加长任务分开统计；详见independent-collection.md。
independent-extended-tasks.md是不含源答案的加长任务单。当前登记模板为七个pending记录，不代表已经采集。旧版私人登记表需补新字段，不能覆盖已收集信息。

## 加长开发补充材料

extended/单独登记3个源家族、12对派生控制，包含完整分析段落、五步推导及十二句R代码的原样、排版、轻改和局部版本。
沿用现有检测方法与默认规则，单独输出候选三状态、定位与完整实验记录；不修改原36个名额，不冒充人类独立答案或保留材料，不混算总体准确率。
运行scripts/run-extended-validation.R，详见extended/README.md。
