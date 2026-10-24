source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")
source("R/text-matches.R", encoding = "UTF-8")
source("R/text-approx.R", encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAILED: ", label, call. = FALSE)
  checks <<- checks + 1L
  cat("PASS ", label, "\n", sep = "")
}
doc <- function(x, id = "document") parse_rmd_text(x, id)

same <- align_text_local("甲乙丙丁", "甲乙丙丁")
check(same$similarity == 1 && same$equal_chars == 4L, "exact local alignment")
check(identical(same$indices_a, 1:4) && identical(same$indices_b, 1:4), "local indices")
replacement <- align_text_local("甲乙丙丁戊己庚辛壬癸", "甲乙丙天戊己庚辛壬癸")
check(isTRUE(all.equal(replacement$similarity, 0.9)), "replacement identity")
check(sum(replacement$operations == "replace") == 1L && replacement$equal_chars == 9L, "replacement traceback")
inserted <- align_text_local("甲乙丙丁戊己", "甲乙丙天丁戊己")
check(isTRUE(all.equal(inserted$similarity, 6/7)), "insertion identity includes gap")
check(sum(inserted$operations == "consume_b") == 1L && inserted$equal_chars == 6L, "insertion traceback")
deleted <- align_text_local("甲乙丙天丁戊己", "甲乙丙丁戊己")
check(sum(deleted$operations == "consume_a") == 1L && deleted$equal_chars == 6L, "deletion traceback")
local <- align_text_local("天地甲乙丙丁戊己玄黄", "宇宙甲乙丙丁戊己洪荒")
check(identical(local$indices_a, 3:8) && identical(local$indices_b, 3:8), "unrelated flanks excluded")
check(local$aligned_a == "甲乙丙丁戊己" && local$aligned_b == local$aligned_a, "local span text")
check(align_text_local("甲乙", "天地")$equal_chars == 0L, "unrelated alignment empty")
check(align_text_local("", "甲")$columns == 0L, "empty alignment")

w <- make_text_windows(doc("甲乙丙丁戊己庚辛"), window_size = 4L)
check(identical(w$start, c(1L, 3L, 5L)), "half-overlap windows")
check(identical(sort(unique(as.integer(unlist(w$source_positions)))), 1:8), "windows cover all text characters")
boundary_windows <- make_text_windows(doc("甲乙$x$丙丁"), 10L)
check(identical(boundary_windows$text, c("甲乙", "丙丁")), "windows respect unit boundaries")
seed_a <- make_text_windows(doc("甲乙丙丁"), 10L)
seed_b <- make_text_windows(doc("甲天丙地"), 10L)
check(nrow(select_text_candidates(seed_a, seed_b, seed_k = 2L)) == 0L, "seed absence documented")
check(nrow(select_text_candidates(seed_a, seed_b, seed_k = 1L)) == 1L, "smaller seeds recover candidate")

a <- doc("甲乙丙丁戊己庚辛壬癸", "A")
b <- doc("甲乙丙天戊己庚辛壬癸", "B")
r <- analyze_text_pair_approx(a, b, k = 3L, min_chars = 8L,
  min_similarity = 0.8, seed_k = 2L, window_size = 100L)
check(nrow(r$exact_matches) == 0L && nrow(r$approximate_matches) == 1L, "approximate match where exact runs are too short")
check(isTRUE(all.equal(r$coverage$coverage, c(0.9, 0.9))), "replacement excluded from coverage")
check(all(r$exact_coverage$coverage == 0), "exact coverage kept separately")
check(r$candidate_count == 1L && r$status == "ok", "candidate and analysis status")
check(!4L %in% r$approximate_matches$source_positions_a[[1L]], "replaced A character not covered")
check(!4L %in% r$approximate_matches$source_positions_b[[1L]], "replaced B character not covered")

ia <- doc("甲乙丙丁戊己", "A"); ib <- doc("甲乙丙天丁戊己", "B")
ins <- analyze_text_pair_approx(ia, ib, k = 2L, min_chars = 5L, seed_k = 2L)
check(isTRUE(all.equal(ins$coverage$coverage, c(1, 6/7))), "inserted character not covered")
check(!4L %in% ins$approximate_matches$source_positions_b[[1L]], "insertion source position excluded")

strict <- find_approximate_text_matches(a, b, seed_k = 2L, min_chars = 8L, min_similarity = 0.95)
check(nrow(strict$matches) == 0L, "identity threshold enforced")
too_short <- find_approximate_text_matches(a, b, seed_k = 2L, min_chars = 10L)
check(nrow(too_short$matches) == 0L, "minimum equal-character count enforced")

dup_a <- doc("甲乙丙丁戊己", "A")
dup <- analyze_text_pair_approx(dup_a, dup_a, k = 2L, min_chars = 3L, seed_k = 2L)
check(all(dup$coverage$coverage == 1) && all(dup$coverage$matched_chars == 6L), "exact and approximate overlap counted once")

overlap_doc <- doc("甲乙丙丁戊己庚辛")
overlap <- find_approximate_text_matches(overlap_doc, overlap_doc,
  seed_k = 2L, window_size = 6L, min_chars = 4L)
overlap_coverage <- summarize_text_coverage(overlap_doc, overlap_doc, overlap$matches)
check(nrow(overlap$candidates) == 4L && nrow(overlap$matches) == 3L, "duplicate alignment from overlapping windows removed")
check(all(overlap_coverage$coverage == 1) && all(overlap_coverage$matched_chars == 8L), "overlapping approximate windows cover characters once")

unrelated <- analyze_text_pair_approx(doc("甲乙丙丁"), doc("天地玄黄"), k = 2L, min_chars = 2L, seed_k = 2L)
check(unrelated$candidate_count == 0L && all(unrelated$coverage$coverage == 0), "no candidates yields zero supported coverage")
empty <- analyze_text_pair_approx(doc("$x$"), doc("甲乙丙丁"), k = 2L, min_chars = 2L, seed_k = 2L)
check(empty$status == "insufficient_ngrams" && is.na(empty$coverage$coverage[1L]), "missing prose status")
check(identical(names(empty$approximate_matches), names(r$approximate_matches)), "stable empty approximate schema")
boundary <- analyze_text_pair_approx(doc("甲乙$x$丙丁"), doc("甲乙丙丁"), k = 2L, min_chars = 3L, seed_k = 1L)
check(nrow(boundary$approximate_matches) == 0L, "alignment does not cross formula")
warned <- analyze_text_pair_approx(doc("甲乙丙丁\n\n![图](x)"), doc("甲乙丙丁"), k = 2L, min_chars = 3L, seed_k = 2L)
check(warned$status == "limited", "parser warnings propagated")

# Traceback positions preserve both consumed spans and equal-character pairs.
for (fixture in list(list(r, a, b), list(ins, ia, ib), list(dup, dup_a, dup_a),
    list(list(approximate_matches = overlap$matches), overlap_doc, overlap_doc))) {
  matches <- fixture[[1L]]$approximate_matches
  for (i in seq_len(nrow(matches))) {
    pa <- matches$source_positions_a[[i]]; pb <- matches$source_positions_b[[i]]
    equal_a <- substring(fixture[[2L]]$source, pa, pa)
    equal_b <- substring(fixture[[3L]]$source, pb, pb)
    check(identical(equal_a, equal_b), "covered source characters truly equal")
    check(length(pa) == matches$equal_chars[i] && length(pb) == length(pa), "covered character counts")
    check(length(matches$operations[[i]]) == matches$alignment_columns[i], "operation columns")
    check(all(diff(pa) > 0L) && all(diff(pb) > 0L), "source alignment order")
  }
}

fails <- function(expr, label) check(inherits(try(expr, silent = TRUE), "try-error"), label)
fails(make_text_windows(doc("甲乙丙丁戊己庚辛"), 4L, max_windows = 1L), "window limit")
two <- make_text_windows(doc("甲乙\n\n丙丁"), 10L)
fails(select_text_candidates(two, two, seed_k = 1L, max_candidates = 1L), "candidate limit")
fails(select_text_candidates(two, two, seed_k = 1L, max_seed_pairs = 1L), "seed-pair limit")
fails(align_text_local("甲乙", "甲乙", max_cells = 4L), "matrix cell limit")
fails(find_approximate_text_matches(doc("甲乙\n\n丙丁"), doc("甲乙\n\n丙丁"), seed_k = 1L, min_chars = 2L, max_total_cells = 10L), "total alignment work limit")
for (bad in list(0, -1, 1.5, NA_real_, Inf, "3")) {
  fails(make_text_windows(a, window_size = bad), "invalid window size")
  fails(find_approximate_text_matches(a, b, seed_k = bad), "invalid seed length")
}
for (bad in list(-0.1, 1.1, NA_real_, Inf, "0.8"))
  fails(find_approximate_text_matches(a, b, min_similarity = bad), "invalid similarity threshold")
fails(align_text_local(NA_character_, "甲"), "invalid alignment text")

cat(sprintf("All %d approximate-match assertions passed.\n", checks))
