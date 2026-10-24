# 边界与误报风险观察

本组10对材料全部由项目自建，单独登记、单独运行，不加入36个核心名额、不使用保留材料，也不声称是人类独立作答。
当前没有最终分类器。role表示实验控制类型，不能当作抄袭真值；有匹配不等于误报，无匹配也不证明无抄袭。

| ID | 情形 | 要观察的行为 |
|---|---|---|
| B01 | 真正空文件 | 文字/代码无有效分母，指标NA |
| B02 | 仅YAML | 元数据不作为正文证据 |
| B03 | 共同题干、不同短回答 | 题干仍被匹配，暴露尚未实现公共来源排除的风险 |
| B04 | 同一条样本均值公式 | 单条公式可匹配，不能凭短标准公式单独判疑似 |
| B05 | 相同的短均值调用 | 完整代码词法可匹配；局部20token门槛不应被短调用绕过 |
| B06 | 不相关中英文自建段落 | 无共有片段；不是人类独立作答负例 |
| B07 | 不完整R语法 | 标受限；不能把无法解析写成零覆盖 |
| B08 | 未支持LaTeX命令 | 保留未知命令限制 |
| B09 | 非R代码 | 不执行，不假装得到R词法覆盖 |
| B10 | 长文中的一段复制，中文空格路径 | 全篇占比低仍能定位足够长局部片段 |

## 运行

在仓库根目录的PowerShell运行：

```powershell
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" tests/test-boundary.R
& "C:\Program Files\R\R-4.6.1\bin\Rscript.exe" scripts/run-boundary.R
```

输出仅进入已忽略的reports-local/boundary/，重复运行会覆盖该目录内同名实验文件：
- results.csv：每对内容类型、控制角色、预期关注点、实际分项状态/错误、双向指标和risk_observation。
- input-and-code-hashes.csv：显式登记的输入、清单与实际分析代码指纹。
- experiment.rds：完整分析结果、实际参数、清单快照、代码提交、R/sessionInfo与时间。

共同题干、短标准公式、短常规代码分别可能出现shared_prompt_is_matching_evidence、routine_formula_is_matching_evidence、routine_code_is_matching_evidence。
这些值只说明已观察到需谨慎解释的匹配，不是判定结果，也不代表已经实现公共来源识别或排除。
所有verdict仍为not_enabled；没有分类误报率、准确率或阈值标定结果。

脚本只接受validation/boundary/fixtures内的显式Rmd路径，支持中文和空格，拒绝目录穿越及核心、独立答案、保留材料路径。
只读取输入，不执行Rmd代码、YAML或非R代码。测试核对各类行为及结果快照；这些是功能/风险检查，不是泛化性能保证。

下一阶段应依据原文来源与用户明确标注处理公共题干，再整合非重复证据；不能简单把两份共有内容全部删掉，否则复制内容也会一并丢失。
