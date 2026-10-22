source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")

# 样例一：正文中包含公式
doc <- parse_rmd_text("说明 $x$。", file_id = "A")
text_units <- extract_text_units(doc)

stopifnot(
  # 提取出公式前后两段文字
  nrow(text_units) == 2L,

  # 结果全部为正文
  all(text_units$type == "text"),

  # 内容与人工预期一致
  identical(text_units$content, c("说明 ", "。")),

  # 原始起点被保留：第一段从1开始，句号从7开始
  identical(text_units$start_offset, c(1L, 7L))
)

# 样例二：文档只有公式，没有正文
math_only <- parse_rmd_text("$x$")
empty_text <- extract_text_units(math_only)

stopifnot(
  is.data.frame(empty_text),
  nrow(empty_text) == 0L,
  identical(names(empty_text), names(math_only$units))
)

# 样例三：错误输入应被拒绝
invalid_result <- try(
  extract_text_units("这不是解析结果"),
  silent = TRUE
)

stopifnot(inherits(invalid_result, "try-error"))

# 样例四：去除普通空格，同时保留位置
normalized <- normalize_text("统 计 分 析")

stopifnot(
  identical(normalized$text, "统计分析"),
  identical(normalized$source_positions, c(1L, 3L, 5L, 7L))
)

# 样例五：制表符和换行
normalized <- normalize_text("A\tB\nC")

stopifnot(
  identical(normalized$text, "ABC"),
  identical(normalized$source_positions, c(1L, 3L, 5L))
)

# 样例六：不换行空格与全角空格
normalized <- normalize_text("统\u00a0计\u3000学")

stopifnot(
  identical(normalized$text, "统计学"),
  identical(normalized$source_positions, c(1L, 3L, 5L))
)

# 样例七：保留大小写和标点
normalized <- normalize_text("R 语言，A!")

stopifnot(
  identical(normalized$text, "R语言，A!"),
  identical(
    normalized$source_positions,
    c(1L, 3L, 4L, 5L, 6L, 7L)
  )
)

# 样例八：空字符串和全空白字符串
for (input in c("", " \t\n\u3000")) {
  normalized <- normalize_text(input)

  stopifnot(
    identical(normalized$text, ""),
    identical(normalized$source_positions, integer())
  )
}

# 样例九：错误输入
for (input in list(NA_character_, 123, c("甲", "乙"))) {
  invalid_result <- try(
    normalize_text(input),
    silent = TRUE
  )

  stopifnot(inherits(invalid_result, "try-error"))
}

cat("Text extraction and normalization tests passed.\n")