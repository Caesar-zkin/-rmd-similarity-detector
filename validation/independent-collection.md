# 独立答案采集与登记（协调人使用）

## 采集前

1. 找未见过项目源答案的人。项目开发者或已浏览dev答案的人不能作为这些题的未暴露独立作答者。
2. 基础题只提供independent-tasks.md，加长题只提供independent-extended-tasks.md，可选提供空白independent-template.Rmd；不要提供仓库、base.Rmd或派生样例。
3. 不提示希望得到怎样的相似度，不按检测结果选择、筛除或返工答案。
4. 给匿名编号，例如I01；不要收集姓名、学号等与本实验无关的信息。不发送他人真实作业。

## 本地保存

在仓库根目录的PowerShell运行：

```powershell
New-Item -ItemType Directory -Force ".\validation\independent-local" | Out-Null
if (-not (Test-Path ".\validation\independent-local\metadata.csv")) {
    Copy-Item ".\validation\independent-metadata-template.csv" ".\validation\independent-local\metadata.csv"
}
```

把答案放在该目录，例如I01-T01.Rmd或I01-E01.Rmd，并在metadata.csv填写路径及来源。模板有T01—T04及E01—E03七个pending记录，后三个是开发补充任务，不能算作原36个名额或保留任务。
此目录已经被Git忽略，不把真人答案、来源信息或含答案的报告提交到仓库。Git忽略只防止新文件被普通git add纳入，不会删除已跟踪内容。
不要覆盖已有metadata.csv；上述复制命令仅在首次建立登记表时使用。

## 字段与审核

- pair_id/task_id：task_id只允许T01—T04及E01—E03。pair_id每行唯一；增加另一人的答案时可使用I02_T01等新编号。公开核心清单继续pending，不写入真人私有路径。
- status：pending→received→verified或excluded；审核与判定结果无关。
- participant_code：匿名编号。同一人的多题答案不是多个独立参与者，应保留这种关联。
- completed_on：实际完成日期，YYYY-MM-DD。未确认日期的记录先保留received，不能转verified。
- prior_answer_access：no、yes或unknown。只有能确认no的材料才进入未暴露独立组。
- authorship：human_self_report、ai_generated、mixed或unknown；如实记录，不把AI改写记为人类独立完成。
- assistance_kind：none、reference_only、ai_or_human_help或unknown。仅前两种可进入当前独立组。
- assistance：具体使用的资料、工具或帮助；无则写none，不能留空。
- consent_to_local_use：yes、no或unknown；没有同意的材料不进入分析。
- file_path：例如validation/independent-local/I01-E01.Rmd，必须位于该私有目录，不编译输入答案。
- source_md5/answer_md5：审核的固定源文件和交回答案指纹；运行--audit取得observed列后，经人工核对再填入。MD5用于版本核对，不证明独立性，也不是安全签名。
- reviewed_by/reviewed_on：匿名审核人编号（如R01）及YYYY-MM-DD审核日期。
- notes：采集方式、暴露情况、排除理由等；verified必须有采集说明。

作答者自述无法证明绝对独立，最终报告需说明采集方法及其限制。已暴露或来源不明的答案可另作探索材料，不能悄悄计入独立负例。

## 审核与本地运行

先把已交回答案登记为received，填完匿名编号、完成日期、暴露情况、作者自述、帮助类型、帮助说明、同意情况、路径和采集说明。不要先改成verified。

```powershell
$projectRscript = "C:\Program Files\R\R-4.6.1\bin\Rscript.exe"
& $projectRscript scripts/run-independent-validation.R --audit
code .\validation\independent-local\audit.csv
code .\validation\independent-local\metadata.csv
```

audit.csv中needs_human_review只表示基础字段和路径检查通过，绝不自动批准独立性；blocked行说明缺失或冲突原因。pending/excluded行不会打开答案，缺同意或来源条件不满足的received/verified行也不会打开答案。
协调人核对交回内容、题号和来源记录。符合条件时，将observed_source_md5、observed_answer_md5分别填入metadata.csv的source_md5、answer_md5，填写reviewed_by/reviewed_on，再把status改为verified。
无法核实、已看过答案或不符合当前独立组条件的材料可保留received或改excluded，不因检测结果高低选择性排除。
审核不会改写metadata.csv。答案或源文件修改后，旧指纹失效，需要重新核对，而不是只机械替换指纹。

```powershell
& $projectRscript scripts/run-independent-validation.R
Import-Csv .\reports-local\independent\results.csv |
    Format-Table pair_id,task_id,candidate_label,candidate_pathway
Import-Csv .\reports-local\independent\summary.csv |
    Format-Table scope,cohort,task_id,evaluated,participants,suspected,insufficient_evidence,false_alarm_rate
```

若本地metadata.csv不存在，脚本只使用公开pending模板，不创建或覆盖登记表，不打开任何答案，显示Verified answers evaluated: 0，误报比例为NA。输出仍会记录缺口。
若存在verified记录但审核失败，则整次验证停止，不默默略过该记录或覆盖上次实验。received记录即使审核字段完备，也不会自动运行。
同一个人同一题最多一份有效答案，同一个文件不能以多个编号重复计数；不同题来自同一人时保留参与者关联。最多100条登记，单个答案和登记CSV均限制1 MB。

如果之前复制了旧版登记表，请根据当前模板补充assistance_kind、source_md5、answer_md5、reviewed_by、reviewed_on列，再添加E01—E03的pending行。保留已有信息，不直接覆盖旧表。

## 统计和输出的边界

结果仅写入已忽略的reports-local/independent/，重复运行覆盖同名文件：results.csv、summary.csv、input-and-code-hashes.csv、experiment.rds。
RDS保存审核记录、完整分析、实际参数、原文、R/sessionInfo和文件指纹，含私有材料，不提交仓库或上传CI artifact。audit.csv也位于已忽略的independent-local。
core与extended分组统计，各题另有一行；不把基础短题与加长题合并成一个误报估计。表中参与者数量与答案对数分开，一人多题不能当作多个独立参与者。
false_alarm_rate=本组已审核独立作答自述中候选疑似数/本组已运行答案对数；abstention_rate=证据不足数/本组已运行答案对数。证据不足保留在分母，判定失败是证据不足的子集，不重复相加。无样本则比例NA。
这些比例只描述收到并通过来源审核的材料，标签依赖作答者自述及协调人核查，不能证明绝对独立，不是总体误报率、准确率或置信区间。正式判定仍为not_enabled，规则仍未标定。

## 与自动实验的关系

当前scripts/run-validation.R仅运行公开、可重现的20对自建复制材料；scripts/run-boundary.R仅运行10对边界材料。
两者及run-extended-validation.R都不会扫描independent-local，不自动把收到的文件改为ready，也不读取保留材料。
仅新入口run-independent-validation.R允许读取metadata中显式登记且审核合格的本地答案，不接受T05/T06或保留路径，不扫描目录；源答案按题号固定，不能由登记表指定其他路径。
CI只运行test-independent-validation.R中的临时自建契约文件，不运行真实本地入口，不读取实际independent-local，也不发布其结果。临时测试的human_self_report字段只是测试输入，不表示采集过真人数据。
当前实际真人答案仍为零，没有完成真实误报评估或阈值标定，也没有使用保留材料。
