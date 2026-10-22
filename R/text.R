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

# 提取并规范化正文，将字符位置映射回文档
prepare_text_units <- function(doc) {

  units <- extract_text_units(doc)

  # 分别处理每个正文单元
  normalized <- lapply(units$content, normalize_text)

  # 每个单元对应一个规范化字符串
  units$normalized_text <- vapply(
    normalized,
    function(item) item$text,
    character(1)
  )

  # 单元内位置转换为文档位置
  positions <- lapply(seq_len(nrow(units)), function(i) {
    as.integer(
      units$content_start[i] +
        normalized[[i]]$source_positions - 1L
    )
  })

  # 每行保存长度可能不同的位置向量
  units$source_positions <- I(positions)

  units
}

# 将字符串切成固定长度的连续字符片段
make_character_ngrams <- function(text, k = 5L) {

  if (!is.character(text) ||
      length(text) != 1L ||
      is.na(text)) {
    stop("text must be one non-missing character string.")
  }

  # k必须是可表示的正整数
  if (!is.numeric(k) ||
      length(k) != 1L ||
      is.na(k) ||
      !is.finite(k) ||
      k < 1 ||
      k != floor(k) ||
      k > .Machine$integer.max) {
    stop("k must be a positive integer.")
  }

  k <- as.integer(k)
  text <- enc2utf8(text)
  n <- nchar(text, type = "chars")

  # 无法组成完整片段时，返回结构一致的空表
  if (n < k) {
    return(data.frame(
      gram = character(),
      start = integer(),
      end = integer(),
      stringsAsFactors = FALSE
    ))
  }

  starts <- seq_len(n - k + 1L)
  ends <- starts + k - 1L

  data.frame(
    gram = substring(text, starts, ends),
    start = starts,
    end = ends,
    stringsAsFactors = FALSE
  )
}