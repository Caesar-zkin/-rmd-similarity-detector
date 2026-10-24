# 公式模块：单条与多步比较

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
compare_math_pair的映射仅在单条公式内有效；find_math_sequences使用贯穿整个候选推导的一致映射。

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
已支持有限多行环境的步骤拆分；复杂嵌套环境、宏定义及一般数学等价待后续实现。
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

## 多步推导入口

依次加载parser.R、math.R、math-sequences.R，调用find_math_sequences(doc_a, doc_b)。
步骤来自prepare_math_steps：普通math单元或受支持多行环境中的一行。
旧的单条公式接口不改变，也不把逐条独立改名结果拼成连续证据。

默认min_steps=2、max_steps=5、max_skips=1、max_source_gap=2000。
所有这些是未标定的运行/候选参数，不是抄袭阈值。
至少2步、最多20步的可配置硬边界用于控制递归深度。

从任意公式位置对开始，按原顺序扩展；每一对步骤必须在已支持的规范化词法层面完全一致，允许变量一致改名。
变量映射贯穿全部已匹配步骤，一一对应；相同源变量不能中途改名到另一目标变量，不同源变量不能合并到同一目标变量。
固定词法单元（数字、符号、函数及字面内容）仍须相同。

允许在两侧合计跳过max_skips个内部公式单元。跳过公式不参与映射，不作为匹配步骤。
不支持单步公式内部的近似替换；改动步骤只能在预算内作为跳过步骤处理。
开头结尾未对齐内容不计作内部跳过。匹配可以从文档任意公式开始。
重复公式可能产生多个对齐，不保证找出唯一复制区间。

## 序列边界

只能经过同一侧文档内连续可连接的公式。相邻公式间最多允许max_source_gap个源字符。
出现标题（包括同名重复标题）、R代码块/行内代码、受限单元或章节变化时中断。
受限/空公式是屏障，不能当成普通可跳过步骤隐藏。
普通说明文字与空行可位于步骤之间，但不参与公式匹配或映射，也不成为文字支持证据。
相邻公式数量和距离并不能证明它们属于同一题，题目识别与证据整合仍待实现。

## 序列输出

matches记录文件、matched_steps、skipped_steps、step_similarity、token_count与行号范围。
step_similarity = 匹配步骤数 / (匹配步骤数 + 两侧内部跳过步骤总数)。
这是步骤对齐比例，不是公式字符覆盖率、数学等价程度或抄袭概率。
token_count是匹配步骤A侧规范化token数之和，仅作描述；不累加被跳过步骤。

每条结果还有list列：
- step_pairs：逐步两侧步骤ID、原公式单元ID、步骤序号、原始content、起止行及逐token源位置。
- variable_map：整段推导统一的一一变量映射。
- skipped_units_a/b：两侧被跳过单元ID，可在formulas_a/b中查原文。
- raw_equal、normalized_equal：所有已匹配步骤是否在该层相同；跳过步骤不影响这些标记。

只输出无法在当前界限内继续扩展的路径，再移除匹配位置对完全被更长路径包含的结果。
保留不同位置对齐。较长推导可能以多个重叠的max_steps窗口出现，这些结果不能累计为独立证据。
行号范围包含中间的文字与跳过公式，不能把整个范围当作被匹配内容。
改名后的对应源字符可能不同；位置映射用于复核，不直接作为“相同字符覆盖”。
目前不输出公式覆盖率或最终判断。

## 规模与状态

默认每侧max_formulas=500，同时限制原公式单元数及展开后的步骤数；展开后的初始位置对max_pairs=10000。
每次尝试在已有映射下配对公式计1个state；max_states=20000。
token_work按每次尝试两侧token数的较大值累计，max_token_work=5000000。
max_results=1000约束去除包含结果前的终止路径数。
任一超限明确报错，不截断成部分结果或低相似结论。

limited优先于其他状态；没有公式为not_applicable；任一侧支持的公式数不足min_steps为insufficient_steps；
其余为ok。ok但空结果仅表示在当前语法、边界、预算及改名规则下未找到序列。
原解析诊断、准备后的公式及issues、参数、state_count和token_work随结果返回。
资源上限与排版/结构子集均可能限制召回，实际效果待开发材料验证。

运行Rscript tests/test-math-sequences.R和Rscript examples/run-math-sequence-demo.R。
演示匹配x=y、y=z、z=1到a=b、b=c、c=1，B中间插入7=8：
匹配3步、跳过1步、步骤比例0.75，映射x→a、y→b、z→c。
插入公式并不要求数学正确；本演示只验证算法行为。

## 多行环境拆分

prepare_math_steps(doc, max_steps=500L)位于math.R，不新增加载依赖；find_math_sequences已改用该步骤表。
compare_math_pair仍比较完整公式单元，其输出不因步骤拆分而改变。
对整块align进行完整单条词法比较仍可能标limited；这不等于步骤接口也无法分析，两个接口的范围不同。

支持裸align/align*、gather/gather*、equation/equation*（需先被解析器识别为math）。
显示定界符内可有上述环境或aligned/gathered包装；
equation/equation*中允许一层aligned/gathered，其余嵌套明确标受限。
裸aligned/gathered不在解析器支持范围，应放在显示定界符内。

只在顶层花括号深度0的双反斜线处分行，支持可选星号和紧接的简单数值长度参数，例如[2pt]。
长度单位支持pt/pc/bp/dd/cc/sp/mm/cm/in/em/ex；未知或未闭合长度参数使整块受限。
允许尾部换行分隔符；内部空行步骤使整块受限。
同一物理源行中可以有多个步骤，定位使用字符位置，不假定每步占一源行。

align/aligned每行最多允许一个顶层&，仅作对齐标记去除；gather系列禁止顶层&。
文本/字体参数等花括号组内不拆行、不删除&；转义的&与花括号保留。
顶层notag/nonumber命令仅控制编号，步骤比较时忽略。
其余命令仍由单条规范化支持清单决定；label/tag/intertext等暂不支持。
不展开宏，不把多列并排方程强行拼成一个式子。

multline/split/matrix/cases/alignat及其他复杂环境尚未支持。
有未知命令、异常括号、内部空步骤或不支持的结构时，整个父公式所有步骤标limited，
保留原文和issues、禁用结构key；不静默只取其中好分析的行。受限步骤保持序列屏障。

## 步骤位置契约

步骤表保留与原解析单元兼容的字段，另有：
- parent_unit_id、parent_raw：原公式单元标识与完整原文，方便复核环境和元数据。
- unit_id：普通公式保持原ID；多行/环境步骤使用原ID:s001等唯一标识。
- step_index、environment：父单元内的行序号及实际处理环境。
- content/raw：去除环境包装与行分隔符后、保留对齐标记的连续原始行片段；两端ASCII空白被裁去。
- content_start/end及行列：上述原始片段在doc$source中的连续范围。
- comparison_content、comparison_positions：忽略受支持对齐/编号标记后的内容及各字符全局位置。
- details：规范化token及映射、状态和issues；token位置已映射到全局源字符。

doc$source和doc$units不修改；解析器原单元的raw重建契约保持不变。
步骤表是派生结构，行分隔符、环境包装及空白不归入某个步骤的raw；
不得用步骤raw拼接来重建整篇文档。
别名token的源范围仍指向原命令，例如规范化frac指向原dfrac。
源位置对应UTF-8/LF规范后的字符，不是磁盘字节。
步骤行号范围也不作为覆盖率，未新增公式覆盖指标。

运行Rscript tests/test-math-multiline.R和Rscript examples/run-math-multiline-demo.R。
演示裸align与显示区域内aligned之间的三步匹配、一步插入及统一改名。
