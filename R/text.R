# 从解析结果中提取可比较的正文单元
extract_text_units <- function(doc) {

  # 检查输入是否来自项目解析器
  if (!inherits(doc, "rmd_document")) {
    stop("doc must be an rmd_document returned by the parser.")
  }

  # 只选择已正常解析的正文
  selected <- doc$units$type == "text" &
    doc$units$status == "ok"

  # 保留全部字段，包括原文、位置和上下文
  doc$units[selected, , drop = FALSE]
}
# 去除空白，并记录每个保留字符在输入字符串中的位置
normalize_text <- function(text) {

  # 只接受一个非缺失字符串
  if (!is.character(text) ||
      length(text) != 1L ||
      is.na(text)) {
    stop("text must be one non-missing character string.")
  }

  # 拆成字符向量
  chars <- strsplit(
    enc2utf8(text),
    split = "",
    fixed = TRUE
  )[[1L]]

  # 本版本明确处理的空白字符
  whitespace <- c(
    " ", "\t", "\n", "\r", "\f", "\v",
    "\u00a0",  # 不换行空格
    "\u3000"   # 全角空格
  )

  # 哪些字符需要保留
  keep <- !(chars %in% whitespace)

  # 保留字符原本的位置
  source_positions <- seq_along(chars)[keep]

  list(
    text = paste0(chars[keep], collapse = ""),
    source_positions = source_positions
  )
}