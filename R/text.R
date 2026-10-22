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

# 为整份文档生成正文片段，并保留原文字符位置
make_document_ngrams <- function(doc, k = 5L) {

  units <- prepare_text_units(doc)

  # 即使没有正文，也要验证k，并建立稳定的空表结构
  empty_grams <- make_character_ngrams("", k = k)

  empty_result <- data.frame(
    file_id = character(),
    unit_id = character(),
    context_id = character(),
    gram = empty_grams$gram,
    normalized_start = empty_grams$start,
    normalized_end = empty_grams$end,
    stringsAsFactors = FALSE
  )

  empty_result$source_positions <- I(vector("list", 0L))

  parts <- list()

  for (i in seq_len(nrow(units))) {

    grams <- make_character_ngrams(
      units$normalized_text[i],
      k = k
    )

    # 当前单元太短时，不生成片段
    if (nrow(grams) == 0L) {
      next
    }

    part <- data.frame(
      file_id = units$file_id[i],
      unit_id = units$unit_id[i],
      context_id = units$context_id[i],
      gram = grams$gram,
      normalized_start = grams$start,
      normalized_end = grams$end,
      stringsAsFactors = FALSE
    )

    # 从已有映射中取出每个片段对应的文档字符位置
    positions <- lapply(seq_len(nrow(grams)), function(j) {
      indices <- seq.int(
        grams$start[j],
        grams$end[j]
      )

      units$source_positions[[i]][indices]
    })

    part$source_positions <- I(positions)

    parts[[length(parts) + 1L]] <- part
  }

  if (length(parts) == 0L) {
    return(empty_result)
  }

  result <- do.call(rbind, parts)
  rownames(result) <- NULL

  result
}

# 比较两份文档的正文字符片段集合
compare_text_jaccard <- function(doc_a, doc_b, k = 5L) {

  grams_a <- make_document_ngrams(doc_a, k = k)
  grams_b <- make_document_ngrams(doc_b, k = k)

  # 集合比较：相同片段只保留一次
  set_a <- unique(grams_a$gram)
  set_b <- unique(grams_b$gram)

  shared <- intersect(set_a, set_b)
  combined <- union(set_a, set_b)

  enough <- length(set_a) > 0L && length(set_b) > 0L

  similarity <- if (enough) {
    length(shared) / length(combined)
  } else {
    NA_real_
  }

  list(
    similarity = similarity,
    status = if (enough) "ok" else "insufficient_ngrams",
    k = as.integer(k),
    unique_count_a = length(set_a),
    unique_count_b = length(set_b),
    shared_count = length(shared),
    union_count = length(combined)
  )
}
