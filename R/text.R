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

# Identify removable Markdown characters without editing the source itself.
# Conservative subset: paired emphasis/strike, line prefixes and ASCII escapes.
markdown_drop_positions <- function(doc) {
  u <- extract_text_units(doc)
  chars <- strsplit(doc$source, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  if (!n || !nrow(u)) return(integer())
  eligible <- rep(FALSE, n)
  for (i in seq_len(nrow(u))) {
    if (u$content_start[i] <= u$content_end[i])
      eligible[seq.int(u$content_start[i], u$content_end[i])] <- TRUE
  }
  drop <- rep(FALSE, n)
  # Protected content occupies its original width, but cannot supply delimiters.
  masked <- chars
  masked[!eligible & chars != "\n"] <- "\ufffc"
  escaped <- function(at) {
    j <- at - 1L; count <- 0L
    while (j >= 1L && chars[j] == "\\") { count <- count + 1L; j <- j - 1L }
    count %% 2L == 1L
  }
  ascii_punctuation <- c("!", "\"", "#", "$", "%", "&", "'", "(", ")", "*", "+", ",",
    "-", ".", "/", ":", ";", "<", "=", ">", "?", "@", "[", "\\", "]", "^", "_", "`", "{", "|", "}", "~")
  for (p in seq_len(n)) {
    if (eligible[p] && chars[p] == "\\" && !escaped(p) && p < n &&
        eligible[p + 1L] && chars[p + 1L] %in% ascii_punctuation)
      drop[p] <- TRUE
  }
  # Recognise quote/list prefixes only at real source line starts.
  starts <- c(1L, which(chars == "\n") + 1L)
  for (li in seq_along(starts)) {
    s <- starts[li]
    e <- if (li < length(starts)) starts[li + 1L] - 2L else n
    if (s > e) next
    used <- 0L
    repeat {
      p <- s + used
      if (p > e) break
      line <- paste0(masked[seq.int(p, e)], collapse = "")
      found <- regexpr("^ {0,3}(?:>[ \t]?|(?:[-+*]|[0-9]{1,9}[.)])[ \t]+)", line, perl = TRUE)
      if (found[1L] < 0L) break
      width <- attr(found, "match.length")
      ids <- seq.int(p, p + width - 1L)
      if (!all(eligible[ids])) break
      drop[ids] <- TRUE
      used <- used + width
    }
  }
  whitespace <- function(ch) ch %in% c(" ", "\t", "\n", "\r", "\f", "\v", "\u00a0", "\u3000")
  word <- function(ch) grepl("^[\\p{L}\\p{N}]$", ch, perl = TRUE)
  # Pair delimiters within the same paragraph context, including around protected
  # inline math/code, but never use delimiters from inside that protected content.
  for (indices in split(seq_len(nrow(u)), u$context_id)) {
    valid <- indices[u$content_start[indices] <= u$content_end[indices]]
    if (!length(valid)) next
    lo <- min(u$content_start[valid]); hi <- max(u$content_end[valid])
    stack <- list(); p <- lo
    while (p <= hi) {
      marker <- masked[p]
      if (!eligible[p] || drop[p] || !marker %in% c("*", "_", "~")) {
        p <- p + 1L; next
      }
      j <- p
      while (j <= hi && masked[j] == marker) j <- j + 1L
      width <- j - p
      supported <- if (marker == "~") width == 2L else width %in% 1:3
      if (!supported || escaped(p)) { p <- j; next }
      key <- paste0(marker, width)
      can_open <- j <= hi && !whitespace(masked[j])
      can_close <- p > lo && !whitespace(masked[p - 1L])
      if (marker == "_") {
        if (p > lo && word(masked[p - 1L])) can_open <- FALSE
        if (j <= hi && word(masked[j])) can_close <- FALSE
      }
      top <- length(stack)
      if (can_close && top > 0L && identical(stack[[top]]$key, key)) {
        opening <- stack[[top]]$positions
        drop[c(opening, seq.int(p, j - 1L))] <- TRUE
        stack <- stack[-top]
      } else if (can_open) {
        stack[[top + 1L]] <- list(key = key, positions = seq.int(p, j - 1L))
      }
      p <- j
    }
  }
  which(drop)
}

# 提取并规范化正文，将字符位置映射回文档
prepare_text_units <- function(doc) {

  units <- extract_text_units(doc)

  # 先排除已识别的排版标记，再去空白；始终保留原字符位置。
  dropped <- markdown_drop_positions(doc)
  normalized <- lapply(seq_len(nrow(units)), function(i) {
    chars <- strsplit(units$content[i], "", fixed = TRUE)[[1L]]
    positions <- as.integer(units$content_start[i] + seq_along(chars) - 1L)
    keep <- !positions %in% dropped
    result <- normalize_text(paste0(chars[keep], collapse = ""))
    list(text = result$text,
      source_positions = positions[keep][result$source_positions])
  })

  # 每个单元对应一个规范化字符串
  units$normalized_text <- vapply(
    normalized,
    function(item) item$text,
    character(1)
  )

  # 此处已经是文档位置；不能再次添加content_start。
  positions <- lapply(normalized, function(item) item$source_positions)

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

# 找到两份文档中内容完全相同的字符片段
match_text_ngrams <- function(
    doc_a, doc_b, k = 5L, max_pairs = 50000L) {

  if (!is.numeric(max_pairs) ||
      length(max_pairs) != 1L ||
      is.na(max_pairs) ||
      !is.finite(max_pairs) ||
      max_pairs < 1 ||
      max_pairs != floor(max_pairs)) {
    stop("max_pairs must be a positive integer.")
  }

  grams_a <- make_document_ngrams(doc_a, k = k)
  grams_b <- make_document_ngrams(doc_b, k = k)

  # 计算重复片段展开后，会产生多少对匹配
  counts_a <- table(grams_a$gram)
  counts_b <- table(grams_b$gram)

  shared <- intersect(names(counts_a), names(counts_b))

  pair_count <- sum(
    as.double(counts_a[shared]) *
      as.double(counts_b[shared])
  )

  # 防止大量重复片段产生过大的结果，不静默丢弃匹配
  if (pair_count > max_pairs) {
    stop(
      "Matching pairs exceed max_pairs. ",
      "Use a larger k or explicitly increase max_pairs."
    )
  }

  matches <- merge(
    grams_a,
    grams_b,
    by = "gram",
    suffixes = c("_a", "_b"),
    sort = FALSE
  )

  # 按两侧出现位置排序，方便检查
  matches <- matches[
    order(
      matches$unit_id_a,
      matches$normalized_start_a,
      matches$unit_id_b,
      matches$normalized_start_b
    ),
    ,
    drop = FALSE
  ]

  rownames(matches) <- NULL

  matches
}
