# 独立答案采集与登记（协调人使用）

## 采集前

1. 找未见过项目源答案的人。项目开发者或已浏览dev答案的人不能作为这些题的未暴露独立作答者。
2. 只提供independent-tasks.md，可选提供空白independent-template.Rmd；不要提供仓库、base.Rmd或派生样例。
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

把答案放在该目录，例如I01-T01.Rmd，并在metadata.csv填写路径及来源。
此目录已经被Git忽略，不把真人答案、来源信息或含答案的报告提交到仓库。Git忽略只防止新文件被普通git add纳入，不会删除已跟踪内容。
不要覆盖已有metadata.csv；上述复制命令仅在首次建立登记表时使用。

## 字段与审核

- pair_id/task_id：对应公开清单中的T01_independent至T04_independent；先保持公开清单pending。
- status：pending→received→verified或excluded；审核与判定结果无关。
- participant_code：匿名编号。同一人的多题答案不是多个独立参与者，应保留这种关联。
- completed_on：实际完成日期；没有日期则留空并说明。
- prior_answer_access：no、yes或unknown。只有能确认no的材料才进入未暴露独立组。
- authorship：human_self_report、ai_generated、mixed或unknown；如实记录，不把AI改写记为人类独立完成。
- assistance：使用的资料、工具或帮助；无则写none。
- consent_to_local_use：yes、no或unknown；没有同意的材料不进入分析。
- file_path：实际本地Rmd路径，不编译输入答案。
- notes：采集方式、暴露情况、排除理由等。

作答者自述无法证明绝对独立，最终报告需说明采集方法及其限制。已暴露或来源不明的答案可另作探索材料，不能悄悄计入独立负例。

## 与自动实验的关系

当前scripts/run-validation.R仅运行公开、可重现的20对自建复制材料；scripts/run-boundary.R仅运行10对边界材料。
两者都不会扫描independent-local，不自动把收到的文件改为ready，也不读取保留材料。
真实独立材料就绪后，下一阶段增加独立的本地载入与审核入口，再进行分开的负例实验；不要把私有路径写入常规CI使用的公开清单。
这批提供采集流程，没有实际收集到真人答案，也没有产生误报率或综合判定阈值。
