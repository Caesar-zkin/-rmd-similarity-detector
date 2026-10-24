source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")
source("R/text-matches.R", encoding = "UTF-8")

count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L
  cat("PASS", label, "\n")
}
cases <- list(
  c("**统 计**", "统计"),
  c("*统计*", "统计"),
  c("_统计_", "统计"),
  c("***统计***", "统计"),
  c("~~统计~~", "统计"),
  c("**统计 *分析* 方法**", "统计分析方法"),
  c("a_b_c", "a_b_c"),
  c("x * y * z", "x*y*z"),
  c("\\*统计\\*", "*统计*"),
  c("**统计", "**统计"),
  c("****统计****", "****统计****"),
  c("1. **统计**\n2. _分析_", "统计分析"),
  c("> 统计\n> 分析", "统计分析"),
  c("> - **统计**", "统计"),
  c("1.23 -x", "1.23-x"),
  c("[**统 计**](https://example.org)", "统计")
)
for (i in seq_along(cases)) {
  doc <- parse_rmd_text(cases[[i]][1L])
  original <- doc
  prepared <- prepare_text_units(doc)
  check(identical(paste0(prepared$normalized_text, collapse = ""),
    cases[[i]][2L]), paste("normalization", i))
  check(identical(doc, original), paste("input unchanged", i))
  for (j in seq_len(nrow(prepared))) {
    pos <- prepared$source_positions[[j]]
    recovered <- if (length(pos)) paste0(substring(doc$source, pos, pos), collapse = "") else ""
    check(identical(recovered, prepared$normalized_text[j]),
      paste("source reconstruction", i, j))
  }
}
bold <- prepare_text_units(parse_rmd_text("**统 计**"))
check(identical(bold$source_positions[[1L]], c(3L, 5L)), "bold positions")
link <- prepare_text_units(parse_rmd_text("[**统 计**](url)"))
check(identical(link$source_positions[[1L]], c(4L, 6L)), "link label positions")
for (input in c("**统计 $a*b$ 分析**", "**统计 `x_y` 分析**")) {
  prepared <- prepare_text_units(parse_rmd_text(input))
  check(identical(prepared$normalized_text, c("统计", "分析")), "protected inline content")
}
empty <- prepare_text_units(parse_rmd_text("```{r}\nx <- '**统计**'\n```"))
check(nrow(empty) == 0L, "fenced code excluded")
a <- parse_rmd_text("**统计分析**", file_id = "A")
b <- parse_rmd_text("统计分析", file_id = "B")
result <- analyze_text_pair(a, b, k = 2L, min_chars = 2L)
check(result$jaccard$similarity == 1, "formatting invariant Jaccard")
check(all(result$coverage$comparable_chars == 4L), "markers excluded from denominator")
check(all(result$coverage$coverage == 1), "formatting invariant coverage")
cat("All", count, "Markdown assertions passed.\n")
