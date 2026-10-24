# 公式模块：第一批基础比较

## 范围与入口

加载R/parser.R与R/math.R，调用compare_math_pair(doc_a, doc_b, max_pairs=10000L)。
只比较解析器标记为math的单元，保留文件、单元标识、原文及行号；不执行输入。
当前是单条公式的词法比较，不是LaTeX完整语法分析或数学等价证明。

三层分别返回布尔结果：
- raw_equal：公式content完全相同；不包括解析器已去除的外层定界符。
- normalized_equal：支持范围内的规范化词法单元序列完全相同。
- renamed_equal：上述词法序列中的变量按首次出现次序规范化后完全相同。

返回所有至少一层匹配的单元对及显式variable_map。重复公式保留不同位置组合。
没有匹配仅表示当前比较方法未检出，不是无抄袭结论。
不计算公式覆盖率或最终判定，不把单个短公式当成主要证据。

## 规范化子集

去除公式外层的ASCII空白。统一dfrac/tfrac为frac。
忽略left/right、big系列定界大小命令和quad/qquad/enspace/thinspace及控制标点间距命令。
实际括号、花括号、正负号、数字、大小写、运算符和上下标标记保留。
x_i与x_{i}当前不合并，避免在未建立语法树前误删分组。

字母逐字符作为变量，支持清单中的希腊字母命令也作为变量。
sin、cos、log等已支持函数命令与运算命令保留。
text、mathrm、mathbf、mathbb等命令的整个花括号参数原样保留，
其中的词语、字符和空白不进行改名。支持命令清单以R/math.R为准。
同一公式内的重复变量必须对应同一变量，一一映射；x+x不能匹配a+b。
映射目前仅在单条公式内有效，不声称连续推导采用了统一映射。

词法key包含各token长度和分隔，避免不同命令序列因直接拼接碰撞。
normalized用于阅读，实际比较用token key。

## 位置与限制

prepare_math_units返回原单元字段、normalized、math_status、token_count及details。
details包括tokens、kinds、各token的source_positions、变量及issues。
位置为doc$source中的1基字符位置，不是磁盘字节。
忽略的命令/空白没有比较token；别名token保留原命令的位置，长度可与规范化值不同。
token_count只用于描述当前序列长度，尚不是标定过的有效证据长度。

未知命令、控制符、直接非ASCII数学符号、未平衡花括号、部分特殊TeX语法及解析器受限单元标limited。
受限内容不参加规范化或改名匹配；完全相同的非空原始表达仍记录raw_equal并标limited。
text/字体参数是保守的字面内容，不解释其中嵌套宏。
这里只做词法扫描及部分分组检查，不保证命令参数数量、表达式或TeX排版语法合法。
多行环境、宏定义、一般数学等价、相邻多步推导和步骤插删待后续实现。
不得把状态ok解释为数学正确或文档已完整分析。

整体status：解析诊断或公式受限优先为limited；任一侧没有公式则not_applicable；
有空公式则insufficient_content；否则ok。原始解析诊断和公式issues均保留。
空表维持列结构。任一公式超过20000字符或公式对数超过max_pairs明确报错，不静默截断。

## 复现

- Rscript tests/test-math.R
- Rscript examples/run-math-demo.R
- Rscript examples/run-math-demo.R A.Rmd B.Rmd

内置例子frac{x+x}{2}与dfrac{ a + a }{2}只在改名层匹配，映射x到a。
测试覆盖重复变量关系、函数/数字/符号保留、位置、缺失与受限内容、输入及资源上限。
这是自建功能测试，不是检测准确率评价。
