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

compare_code_pair仍按完整单元比较；新增analyze_code_pair_local支持单元内顶层语句窗口、受限语句插删及token覆盖。不跨代码块建立映射，最终判定待实现。

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

默认每段最多100000字符、20000终结token、50000语法节点和2000顶层语句；
每侧最多500单元及1000000代码字符；最多10000单元对。
max_pair_chars=5000000限制两侧代码字符数乘对侧单元数之和，控制整个比较规模。
超限报错，不静默截断；解析器自身语法/深度错误标受限并保留诊断。
getParseData依赖R解析器实现，升级R版本后必须运行回归测试。

## 复现

Rscript tests/test-code.R
Rscript examples/run-code-demo.R
Rscript examples/run-code-demo.R A.Rmd B.Rmd

默认例子仅改名values→nums、center→avg并调整空白，原始/词法层不同，改名层相同。
仅为功能验证；完整单元接口不提供代码覆盖率或最终抄袭结论。

## 顶层语句与局部接口

加载顺序parser.R → code.R → code-local.R。
prepare_code_statements(doc, max_statements=2000L)从成功解析且位置已验证的代码单元中提取顶层语句。
tokenize_r_code额外返回statements及statement_status。每个根语法节点覆盖其完整终结token集合，要求所有有效token恰好归属一个语句。
提取失败标受限，不把平铺token串当作语句。函数、循环和条件内部不独立拆步；复杂整体语句仍可作词法比较。

语句表保留文件、单元、statement_id、原文、token数、行号、tokens及允许改名的位置。
语句key保留自身语法父节点关系，重新编号后不受前面无关语句的节点编号影响。
改名候选仍由整个原代码单元的保守规则决定，但局部匹配只对实际对齐部分建立映射，不沿用全文的变量编号。

analyze_code_pair_local(doc_a, doc_b)返回语句、窗口、候选、局部结果、两种覆盖、诊断及参数。
原完整单元接口和注释补充接口不改变；局部结果本身不新增独立注释证据。

## 窗口、种子和有序匹配

默认window_tokens=100、window_statements=20。窗口不切断语句，不跨代码单元。
逐个装入完整语句，下一条会超过token目标或语句上限时结束；按当前窗口语句数的一半（向下取整，至少1）前进，尾部覆盖。
这是约一半语句重叠，不保证恰好一半token重叠。
单个语句超过token目标时仍完整保留并标oversize；受原解析规模及局部token工作量上限约束。

候选分lexical与renamed两种模式，以至少共享一个完整语句key筛选窗口对。
lexical要求语法词法key相同；renamed要求固定词法结构相同、可改名位置一致，再逐token验证一一映射。
函数、参数、成员、外部输入、数字和字符串沿用基础接口的保留规则。

对候选窗口内任意起点进行顺序扩展，映射贯穿整个路径，不能逐句重置。
默认max_skips=1约束两侧合计的内部跳过语句数。只跳过完整语句，不在单个语句内作任意编辑。
替换一条语句可在max_skips>=2时表现为两侧各跳过一条，改动语句的全部token不计匹配。
路径至少满足min_tokens=20及min_statements=1，均为未标定的候选参数，不是抄袭阈值。
开头结尾的未匹配语句不算内部跳步。

只输出当前窗口内不能继续扩展的达标路径；相同位置对路径去重，再移除同一方法下被更长路径包含的结果。
全程原词法相同的改名路径不重复输出为renamed。
不同位置对齐保留；lexical短片段可以同时落在更长renamed片段中，覆盖阶段再次去重。
超过窗口范围的长复制可能拆成重叠证据，不保证枚举所有局部复制。

## 局部证据与token覆盖

matches包括method、matched_statements、matched_tokens、skipped_statements、skipped_tokens、alignment_ratio及行号。
alignment_ratio = 匹配token对数 / (匹配token对数 + 两侧跳过语句的token总数)。
未匹配前后缀不在该局部比例分母内；比例不表示整篇覆盖或抄袭概率。
statement_pairs列出逐句原文、ID及行号；variable_map为整段实际匹配的变量对应。
token_starts_a/b与token_ends_a/b是每个被匹配token的实际全局起止字符位置；
skipped_statements_a/b列出跳过语句ID，可在statements_a/b查原文。

lexical_coverage只汇总原词法相同的结果；coverage还包括通过一致改名建立的token对应。
两侧分别以token起点集合去重；分母是成功完整解析单元的全部有效token，包括短单元和未匹配语句。
COMMENT、分号和空白不计分母。语法失败/边界受限区域不能算成已成功比较，整体诊断保留。
重复窗口、重复对齐及两种方法的同一源token都只计一次，不填补跳过语句或整行范围。
分母为0返回NA；有可比较token但无达标结果为0，不是无抄袭结论。

包含改名的coverage统计结构对应token：变量字符可不同、长度可不同。
它不是文字模块的相同字符覆盖，也不是语义等价比例；不能与文字字符数或公式步骤数直接相加。

默认演示A有27个可比较token，B有23个；匹配3句共20token，B内部跳过3token：
lexical覆盖均0；包含改名覆盖分别20/27与20/23，局部alignment_ratio=20/23。
映射values→nums、center→avg。前后缀、插入语句都不计入匹配。

## 局部规模与边界

每侧总语句max_statements=2000、max_windows=500，window_statements最多20以限制搜索深度。
候选max_candidates=500、共享key展开前max_seed_pairs=100000。
max_states=50000限制所有已有映射下的语句配对尝试；
max_token_work=5000000按每次尝试两侧token数较大者累加。
max_results=1000限制去重后的终止路径数（移除包含结果前）。
所有超限明确报错，不截断成低覆盖或部分完成。
基础解析器每单元上限继续生效，增大全局参数不取消单元上限。

未知调用/复杂作用域可作lexical匹配，整体状态limited；语法失败或非R单元不进入局部步骤。
缺少代码为not_applicable，缺少可用语句为insufficient_content，其余ok（limited优先）。
ok不保证覆盖整个文件；短于门槛的结果可能被过滤。
单条长表达式、函数/循环内部的局部复制、任意token替换、跨代码块映射及算法重构不在本批保证范围。
测试为自建功能验证，性能与阈值尚未标定。

运行Rscript tests/test-code-local.R和Rscript examples/run-code-local-demo.R。
演示也接受两份Rmd路径；不执行待检测代码、不输出最终抄袭结论。
