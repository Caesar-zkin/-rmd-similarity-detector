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

cat("Text extraction tests passed.\n")