source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")
source("R/text-matches.R", encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAILED: ", label, call. = FALSE)
  checks <<- checks + 1L
  cat("PASS ", label, "\n", sep = "")
}
doc <- function(x, id = "document") parse_rmd_text(x, id)

# Adjacent overlapping seeds should become one longer match.
a <- doc("统计分析方法", "A"); b <- doc("前统计分析方法后", "B")
r <- analyze_text_pair(a, b, k = 2L, min_chars = 4L)
m <- r$exact_matches
check(nrow(m) == 1L && m$text == "统计分析方法", "merge overlapping seeds")
check(m$matched_chars == 6L, "merged length")
check(identical(m$source_positions_a[[1L]], 1:6), "positions on A")
check(identical(m$source_positions_b[[1L]], 2:7), "positions on B")
check(isTRUE(all.equal(r$coverage$coverage, c(1, 6/8))), "asymmetric coverage")
check(r$status == "ok", "analysis status")

# Whitespace is ignored, and its source positions are not counted as matched.
spaced <- analyze_text_pair(doc("统 计 分 析"), doc("统计分析"), 2L, 4L)
check(nrow(spaced$exact_matches) == 1L, "normalized exact match")
check(identical(spaced$exact_matches$source_positions_a[[1L]], c(1L, 3L, 5L, 7L)), "whitespace excluded from positions")
check(all(spaced$coverage$matched_chars == 4L) && all(spaced$coverage$coverage == 1), "whitespace excluded from coverage")

# Repetition yields alternative alignments; union counting prevents >100%.
repeat_result <- analyze_text_pair(doc("哈哈哈"), doc("哈哈哈"), 2L, 2L)
check(nrow(repeat_result$exact_matches) == 3L, "alternative repetition alignments")
check(sum(repeat_result$exact_matches$matched_chars) > 3L, "overlapping evidence retained")
check(all(repeat_result$coverage$matched_chars == 3L) && all(repeat_result$coverage$coverage == 1), "overlap coverage counted once")

# Same alignment offset must not bridge a mismatching character.
gap <- analyze_text_pair(doc("甲乙丙丁戊己"), doc("甲乙天丁戊己"), 2L, 2L)
check(setequal(gap$exact_matches$text, c("甲乙", "丁戊己")), "mismatch splits exact runs")
check(isTRUE(all.equal(gap$coverage$coverage, c(5/6, 5/6))), "mismatch not covered")

# Unit boundaries are preserved even when prose on both sides is identical.
boundary <- analyze_text_pair(doc("甲乙$x$丙丁"), doc("甲乙丙丁"), 2L, 3L)
check(nrow(boundary$exact_matches) == 0L, "no merging across formula boundaries")
check(all(boundary$coverage$coverage == 0), "below minimum not covered")

none <- analyze_text_pair(doc("甲乙"), doc("天地"), 2L, 2L)
check(nrow(none$exact_matches) == 0L && all(none$coverage$coverage == 0), "nonempty disjoint text")
check(identical(names(none$exact_matches), names(m)), "stable empty block schema")
check(nrow(merge_exact_text_matches(a, b, 2L, 7L)) == 0L, "minimum length filter")

empty <- analyze_text_pair(doc("$x$"), doc("甲乙"), 2L, 2L)
check(empty$status == "insufficient_ngrams", "missing grams is not a negative verdict")
check(is.na(empty$coverage$coverage[1L]) && empty$coverage$coverage[2L] == 0, "no-text side has NA coverage")
short <- analyze_text_pair(doc("甲"), doc("乙"), 2L, 2L)
check(short$status == "insufficient_ngrams", "short text marked insufficient")

# Link labels begin after '[', not at the raw unit start.
linked <- analyze_text_pair(doc("[统 计](x)"), doc("统计"), 2L, 2L)
check(identical(linked$exact_matches$source_positions_a[[1L]], c(2L, 4L)), "link content offset")

multiline <- analyze_text_pair(doc("甲\n乙丙"), doc("甲乙丙"), 2L, 3L)
check(multiline$exact_matches$start_line_a == 1L && multiline$exact_matches$end_line_a == 2L, "match line numbers")

warning_result <- analyze_text_pair(doc("统计\n\n![图](absent.png)"), doc("统计"), 2L, 2L)
check(warning_result$status == "limited" && nrow(warning_result$diagnostics$a) > 0L, "parser warnings propagated")

# All matched positions must reconstruct the stored normalized text.
fixtures <- list(
  list(r, a, b),
  list(spaced, doc("统 计 分 析"), doc("统计分析")),
  list(repeat_result, doc("哈哈哈"), doc("哈哈哈")),
  list(gap, doc("甲乙丙丁戊己"), doc("甲乙天丁戊己")),
  list(linked, doc("[统 计](x)"), doc("统计")),
  list(multiline, doc("甲\n乙丙"), doc("甲乙丙"))
)
for (fixture in fixtures) {
  blocks <- fixture[[1L]]$exact_matches
  check(all(lengths(blocks$source_positions_a) == blocks$matched_chars) &&
    all(lengths(blocks$source_positions_b) == blocks$matched_chars), "position vector lengths")
  for (j in seq_len(nrow(blocks))) {
    pa <- blocks$source_positions_a[[j]]
    pb <- blocks$source_positions_b[[j]]
    recovered_a <- paste0(substring(fixture[[2L]]$source, pa, pa), collapse = "")
    recovered_b <- paste0(substring(fixture[[3L]]$source, pb, pb), collapse = "")
    check(identical(recovered_a, blocks$text[j]) && identical(recovered_b, blocks$text[j]), "source reconstruction on both sides")
  }
}
for (bad in list(0, 1.5, NA_real_, Inf, "2")) {
  check(inherits(try(merge_exact_text_matches(a, b, min_chars = bad), silent = TRUE), "try-error"), "invalid min_chars rejected")
}
check(inherits(try(analyze_text_pair(doc("哈哈哈"), doc("哈哈哈"), 2L, 2L, 3L), silent = TRUE), "try-error"), "pair limit still enforced")

cat(sprintf("All %d exact-match assertions passed.\n", checks))
