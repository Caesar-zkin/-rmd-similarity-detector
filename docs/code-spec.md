# R代码模块：第一批基础比较

## 入口和范围

加载R/parser.R与R/code.R，使用compare_code_pair(doc_a, doc_b)。
选择代码块及inline_r单元，普通inline_code不视为可执行R。
R语言用parse(text=..., keep.source=TRUE)及utils::getParseData/getParseText读取语法信息，
不执行输入、不加载提交代码提及的软件包、不调用其函数或读取其数据。
srcfile来自内存text，不使用作业里的路径。

参考R官方文档：
- https://stat.ethz.ch/R-manual/R-devel/library/base/html/parse.html
- https://stat.ethz.ch/R-manual/R-devel/library/utils/html/getParseData.html

当前按完整单元比较，不跨代码块建立映射；长块窗口、局部编辑对齐、代码覆盖率和最终判定待实现。

## 词法与位置

tokenize_r_code(code)返回source、tokens、比较key、变量映射及状态。
source统一UTF-8和LF。tokens包括终结词法单元及COMMENT，保留类型、原始字面文本和字符/行列范围。
从内存源获取完整token文本，并按源顺序验证每个token及其间只有空白。
位置不用R的tab显示列直接换算；通过逐字符验证建立，列号是字符列。
完整源匹配失败时明确标limited，不输出未经核对的token位置。
行首#line源位置指令不交给解析器解释，直接作受限原文处理；类似指令的普通字符串保留。
这项保守预检查也可能限制包含行首#line文本的多行字面字符串。
长字符串使用includeText=FALSE后从源取回，避免把解析表中可能被截断的文本当成真实token。

规范化key使用语法节点类型、重新编号的父节点关系及终结token原文。
忽略COMMENT和可替代语句换行的分号，保留表达式边界；
例如x<-1换行-y与x<-1-y不能因词法串相同而误配。
函数、参数标签、成员、命名空间、数字、字符串、运算符与控制结构保持区别。
不同引号或数字写法仍可能不同；此接口不尝试证明语义等价。

## 受限变量改名

只选简单左侧SYMBOL通过<-引入的ASCII名称，按首次赋值顺序编号。
成员/索引目标不作为简单变量定义。
首次定义前已经读取、首次赋值依赖自身、或同时作为被调用函数的名字保留。
仅对应普通SYMBOL引用改名；参数标签、函数名、$和@后的成员名保持字面原样。
整块保持重复引用关系及一一映射；外部未在块中定义的输入名称保留。

代码有函数定义、循环、条件分支、公式、非局部/右赋值或=赋值时，禁用整块改名。
只有明确清单的调用支持改名；未知调用、动态求名/NSE调用、计算得到的函数头及未知命名空间禁用改名。
清单以R/code.R中的allowed_calls为准，不代表完整R语义分析。
这些情况仍保留完整词法比较，rename_status=restricted，整体标limited。
复杂作用域、反射、隐式列名和函数副作用不进行语义推断；结构相同不表示运行结果相同。

## 三层与注释

raw_equal：非空、非纯注释单元的content完全相同；语法失败或非R语言的相同原文也可作受限记录。
tokens_equal：两侧完整解析及位置验证成功，忽略注释和排版后的语法词法key相同。
renamed_equal：两侧允许改名，改名后的key相同，显式返回变量对。
只有至少一层相同的单元对进入matches；空表保留字段。
保留所有跨位置的单元对，同一代码匹配的三层结果不应视为三份独立证据。

注释以完整原始COMMENT序列相同作为补充，放在comment_matches。
注释不混入代码key或token_count，不把相同短注释当成主要证据。
注释源范围可在code_a/b的details$tokens中查到。
纯注释块不产生代码匹配；文本说明重复是否应去重仍待证据整合阶段处理。

prepare_code_units(doc)保留原解析单元字段，追加code_status、token_count和details。
details中token坐标转换为doc$source的全局字符位置；doc本身不修改。
matches返回两侧文件/单元、三层标记、token_count、行号、status及variable_map。
token_count为两侧当前词法单元数的较小值，是描述量，尚不是标定后的证据阈值。

## 异常与规模

语法失败返回parse_error及原文，禁用词法和改名key；不把不完整前缀冒充完整分析。
非R语言仅进行受限原文比较。解析器已标limited的边界也禁用高层key。
整体状态limited优先；任一侧没有代码为not_applicable；存在空/纯注释单元为insufficient_content；其余ok。
ok或零匹配都不是抄袭结论。

默认每段最多100000字符、20000终结token、50000语法节点；
每侧最多500单元及1000000代码字符；最多10000单元对。
max_pair_chars=5000000限制两侧代码字符数乘对侧单元数之和，控制整个比较规模。
超限报错，不静默截断；解析器自身语法/深度错误标受限并保留诊断。
getParseData依赖R解析器实现，升级R版本后必须运行回归测试。

## 复现

Rscript tests/test-code.R
Rscript examples/run-code-demo.R
Rscript examples/run-code-demo.R A.Rmd B.Rmd

默认例子仅改名values→nums、center→avg并调整空白，原始/词法层不同，改名层相同。
仅为功能验证；没有检测准确率、代码覆盖率或最终抄袭结论。
