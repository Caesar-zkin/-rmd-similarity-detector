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

# 样例十：映射回整篇文档
mapped_doc <- parse_rmd_text(
  "# 标题\n\n统 计 $x$ 分 析。",
  file_id = "A"
)

prepared <- prepare_text_units(mapped_doc)

stopifnot(
  nrow(prepared) == 2L,

  identical(
    prepared$normalized_text,
    c("统计", "分析。")
  ),

  identical(
    prepared$source_positions[[1L]],
    c(7L, 9L)
  ),

  identical(
    prepared$source_positions[[2L]],
    c(15L, 17L, 18L)
  ),

  identical(
    prepared$unit_id,
    extract_text_units(mapped_doc)$unit_id
  )
)

# 样例十一：链接标签的内容起点不同于原文单元起点
link_doc <- parse_rmd_text(
  "[统 计](https://example.org)"
)

prepared_link <- prepare_text_units(link_doc)

stopifnot(
  identical(prepared_link$normalized_text, "统计"),

  identical(
    prepared_link$source_positions[[1L]],
    c(2L, 4L)
  )
)

# 样例十二：没有正文时仍保留输出结构
prepared_empty <- prepare_text_units(
  parse_rmd_text("$x$")
)

stopifnot(
  is.data.frame(prepared_empty),
  nrow(prepared_empty) == 0L,

  all(c("normalized_text", "source_positions") %in%
        names(prepared_empty))
)

# 根据映射从文档原文取回字符，应能重建规范化文字
for (i in seq_len(nrow(prepared))) {
  positions <- prepared$source_positions[[i]]

  recovered <- paste0(
    substring(
      mapped_doc$source,
      positions,
      positions
    ),
    collapse = ""
  )

  stopifnot(
    identical(recovered, prepared$normalized_text[i])
  )
}

# 样例十三：连续片段的内容与位置
grams <- make_character_ngrams("统计分析方法", k = 3L)

stopifnot(
  identical(
    grams$gram,
    c("统计分", "计分析", "分析方", "析方法")
  ),
  identical(grams$start, 1:4),
  identical(grams$end, 3:6)
)

# 样例十四：文本长度恰好等于k
exact <- make_character_ngrams("统计", k = 2L)

stopifnot(
  nrow(exact) == 1L,
  identical(exact$gram, "统计"),
  identical(exact$start, 1L),
  identical(exact$end, 2L)
)

# 样例十五：空文本和过短文本
for (input in c("", "统")) {
  short <- make_character_ngrams(input, k = 2L)

  stopifnot(
    nrow(short) == 0L,
    identical(names(short), c("gram", "start", "end")),
    is.character(short$gram),
    is.integer(short$start),
    is.integer(short$end)
  )
}

# 样例十六：相同片段在不同位置重复出现，应保留
repeated <- make_character_ngrams("哈哈哈哈", k = 2L)

stopifnot(
  identical(repeated$gram, rep("哈哈", 3L)),
  identical(repeated$start, 1:3),
  identical(repeated$end, 2:4)
)

# 样例十七：k为1时，每个字符形成一个片段
single <- make_character_ngrams("甲乙", k = 1L)

stopifnot(
  identical(single$gram, c("甲", "乙")),
  identical(single$start, 1:2),
  identical(single$end, 1:2)
)

# 样例十八：拒绝无效的k
for (bad_k in list(0, -1, 1.5, NA_real_, Inf, "3", c(2, 3))) {
  invalid_result <- try(
    make_character_ngrams("统计分析", k = bad_k),
    silent = TRUE
  )

  stopifnot(inherits(invalid_result, "try-error"))
}

# 样例十九：拒绝无效的文字输入
for (bad_text in list(NA_character_, 123, c("甲", "乙"))) {
  invalid_result <- try(
    make_character_ngrams(bad_text, k = 2L),
    silent = TRUE
  )

  stopifnot(inherits(invalid_result, "try-error"))
}

# 样例二十：文档片段与原文位置
gram_doc <- parse_rmd_text(
  "# 标题\n\n统 计 分 析",
  file_id = "A"
)

document_grams <- make_document_ngrams(gram_doc, k = 2L)

stopifnot(
  identical(
    document_grams$gram,
    c("统计", "计分", "分析")
  ),
  identical(document_grams$file_id, rep("A", 3L)),
  identical(document_grams$normalized_start, 1:3),
  identical(document_grams$normalized_end, 2:4),

  identical(
    document_grams$source_positions[[1L]],
    c(7L, 9L)
  ),
  identical(
    document_grams$source_positions[[2L]],
    c(9L, 11L)
  ),
  identical(
    document_grams$source_positions[[3L]],
    c(11L, 13L)
  )
)

# 根据原文位置取回字符，应得到对应片段
for (i in seq_len(nrow(document_grams))) {
  positions <- document_grams$source_positions[[i]]

  recovered <- paste0(
    substring(gram_doc$source, positions, positions),
    collapse = ""
  )

  stopifnot(
    identical(recovered, document_grams$gram[i])
  )
}

# 样例二十一：不跨公式拼接正文单元
split_doc <- parse_rmd_text("统计 $x$ 分析")

split_grams <- make_document_ngrams(split_doc, k = 2L)

stopifnot(
  identical(split_grams$gram, c("统计", "分析")),
  length(unique(split_grams$unit_id)) == 2L,
  nrow(make_document_ngrams(split_doc, k = 3L)) == 0L
)

# 样例二十二：没有正文，或正文太短
no_text <- make_document_ngrams(
  parse_rmd_text("$x$"),
  k = 2L
)

too_short <- make_document_ngrams(
  parse_rmd_text("统"),
  k = 2L
)

stopifnot(
  nrow(no_text) == 0L,
  nrow(too_short) == 0L,
  identical(names(no_text), names(document_grams)),
  identical(names(too_short), names(document_grams)),
  is.list(no_text$source_positions)
)

# 样例二十三：重复片段保留不同位置
repeated_doc <- make_document_ngrams(
  parse_rmd_text("哈哈哈哈"),
  k = 2L
)

stopifnot(
  nrow(repeated_doc) == 3L,
  identical(repeated_doc$source_positions[[1L]], c(1L, 2L)),
  identical(repeated_doc$source_positions[[3L]], c(3L, 4L))
)

# 样例二十四：即使文档没有正文，无效k也应报错
invalid_result <- try(
  make_document_ngrams(parse_rmd_text("$x$"), k = 0L),
  silent = TRUE
)

stopifnot(inherits(invalid_result, "try-error"))

# 样例二十五：可人工计算的相似度
doc_a <- parse_rmd_text("统计分析", file_id = "A")
doc_b <- parse_rmd_text("统计方法", file_id = "B")

comparison <- compare_text_jaccard(doc_a, doc_b, k = 2L)

stopifnot(
  identical(comparison$status, "ok"),
  comparison$unique_count_a == 3L,
  comparison$unique_count_b == 3L,
  comparison$shared_count == 1L,
  comparison$union_count == 5L,
  isTRUE(all.equal(comparison$similarity, 1 / 5))
)

# 样例二十六：交换输入顺序，不改变相似度
reverse_comparison <- compare_text_jaccard(
  doc_b, doc_a, k = 2L
)

stopifnot(
  identical(
    comparison$similarity,
    reverse_comparison$similarity
  )
)

# 样例二十七：相同正文相似度为1
same <- compare_text_jaccard(doc_a, doc_a, k = 2L)

stopifnot(same$similarity == 1)

# 样例二十八：两个非空集合没有共有片段
different <- compare_text_jaccard(
  parse_rmd_text("甲乙丙丁"),
  parse_rmd_text("天地玄黄"),
  k = 2L
)

stopifnot(
  identical(different$status, "ok"),
  different$similarity == 0
)

# 样例二十九：集合指标不考虑重复次数
repeated_comparison <- compare_text_jaccard(
  parse_rmd_text("哈哈哈哈"),
  parse_rmd_text("哈哈"),
  k = 2L
)

stopifnot(
  repeated_comparison$unique_count_a == 1L,
  repeated_comparison$unique_count_b == 1L,
  repeated_comparison$similarity == 1
)

# 样例三十：任意一边没有有效片段，都应返回信息不足
for (pair in list(
  list(parse_rmd_text("统"), doc_a),
  list(doc_a, parse_rmd_text("$x$")),
  list(parse_rmd_text(""), parse_rmd_text(""))
)) {
  insufficient <- compare_text_jaccard(
    pair[[1L]], pair[[2L]], k = 2L
  )

  stopifnot(
    is.na(insufficient$similarity),
    identical(insufficient$status, "insufficient_ngrams")
  )
}

# 样例三十一：共有片段及两侧位置
match_a <- parse_rmd_text("统计分析", file_id = "A")
match_b <- parse_rmd_text("统计方法", file_id = "B")

matches <- match_text_ngrams(match_a, match_b, k = 2L)

stopifnot(
  nrow(matches) == 1L,
  identical(matches$gram, "统计"),
  identical(matches$file_id_a, "A"),
  identical(matches$file_id_b, "B"),
  identical(matches$source_positions_a[[1L]], c(1L, 2L)),
  identical(matches$source_positions_b[[1L]], c(1L, 2L))
)

# 样例三十二：重复片段保留所有出现位置组合
repeated_matches <- match_text_ngrams(
  parse_rmd_text("哈哈哈", file_id = "A"),
  parse_rmd_text("哈哈哈", file_id = "B"),
  k = 2L
)

stopifnot(
  nrow(repeated_matches) == 4L,
  identical(
    repeated_matches$normalized_start_a,
    c(1L, 1L, 2L, 2L)
  ),
  identical(
    repeated_matches$normalized_start_b,
    c(1L, 2L, 1L, 2L)
  )
)

# 样例三十三：没有共有片段时，保留空表结构
no_matches <- match_text_ngrams(
  parse_rmd_text("甲乙"),
  parse_rmd_text("丙丁"),
  k = 2L
)

stopifnot(
  nrow(no_matches) == 0L,
  identical(names(no_matches), names(matches))
)

# 样例三十四：一侧没有片段，也应正常返回空表
missing_matches <- match_text_ngrams(
  parse_rmd_text("$x$"),
  match_b,
  k = 2L
)

stopifnot(
  nrow(missing_matches) == 0L,
  identical(names(missing_matches), names(matches))
)

# 样例三十五：超过匹配数量上限时明确报错
too_many <- try(
  match_text_ngrams(
    parse_rmd_text("哈哈哈"),
    parse_rmd_text("哈哈哈"),
    k = 2L,
    max_pairs = 3L
  ),
  silent = TRUE
)

stopifnot(inherits(too_many, "try-error"))

# 样例三十六：拒绝无效的数量上限
for (bad_limit in list(0, 1.5, NA_real_, Inf, "10")) {
  invalid_result <- try(
    match_text_ngrams(
      match_a, match_b,
      k = 2L,
      max_pairs = bad_limit
    ),
    silent = TRUE
  )

  stopifnot(inherits(invalid_result, "try-error"))
}

cat("Text module tests passed.\n")


