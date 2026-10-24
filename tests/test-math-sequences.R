source("R/parser.R", encoding = "UTF-8")
source("R/math.R", encoding = "UTF-8")
source("R/math-sequences.R", encoding = "UTF-8")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L; cat("PASS", label, "\n")
}
doc <- function(steps, id = "document") {
  parse_rmd_text(paste0("$", steps, "$", collapse = "\n\n"), file_id = id)
}
fails <- function(expr, label) check(inherits(try(force(expr), silent = TRUE), "try-error"), label)
a <- doc(c("x=y", "y=z", "z=1"), "A")
b <- doc(c("a=b", "b=c", "c=1"), "B")
r <- find_math_sequences(a, b)
check(r$status == "ok" && nrow(r$matches) == 1L, "maximal consistent sequence")
check(r$matches$matched_steps == 3L && r$matches$skipped_steps == 0L, "three matched steps")
check(r$matches$step_similarity == 1, "step ratio without gaps")
check(identical(r$matches$variable_map[[1L]], data.frame(a = c("x", "y", "z"), b = c("a", "b", "c"))), "global mapping")
check(!r$matches$raw_equal && !r$matches$normalized_equal, "renamed sequence differs literally")
same <- find_math_sequences(a, a)
check(same$matches$raw_equal && same$matches$normalized_equal, "identical sequence layers")
inconsistent <- find_math_sequences(doc(c("x+x", "x^2")), doc(c("a+a", "b^2")))
check(nrow(inconsistent$matches) == 0L, "same source variable cannot change target between steps")
collision <- find_math_sequences(doc(c("x+x", "y^2")), doc(c("a+a", "a^2")))
check(nrow(collision$matches) == 0L, "distinct source variables cannot merge between steps")
number <- find_math_sequences(doc(c("x=1", "y=2")), doc(c("a=1", "b=3")))
check(nrow(number$matches) == 0L, "numeric change is not variable renaming")
inserted <- doc(c("a=b", "7=8", "b=c", "c=1"), "B")
ins <- find_math_sequences(a, inserted, min_steps = 3L)
check(nrow(ins$matches) == 1L && ins$matches$matched_steps == 3L, "insertion accepted")
check(ins$matches$skipped_steps == 1L && ins$matches$step_similarity == 0.75, "gap counts in step ratio")
check(identical(ins$matches$skipped_units_b[[1L]], ins$formulas_b$unit_id[2L]), "inserted formula explicitly recorded")
check(length(ins$matches$skipped_units_a[[1L]]) == 0L, "no gap on A side")
check(!"7=8" %in% ins$matches$step_pairs[[1L]]$content_b, "inserted formula excluded from matched pairs")
check(nrow(find_math_sequences(a, inserted, min_steps = 3L, max_skips = 0L)$matches) == 0L, "zero gap budget")
deleted <- find_math_sequences(inserted, a, min_steps = 3L)
check(deleted$matches$skipped_steps == 1L && deleted$matches$step_similarity == 0.75, "deletion accepted")
check(identical(deleted$matches$variable_map[[1L]]$a, ins$matches$variable_map[[1L]]$b), "reverse mapping")
two_gaps <- doc(c("a=b", "7=8", "9=0", "b=c", "c=1"))
check(nrow(find_math_sequences(a, two_gaps, min_steps = 3L)$matches) == 0L, "total gap budget enforced")
check(find_math_sequences(a, two_gaps, min_steps = 3L, max_skips = 2L)$matches$skipped_steps == 2L, "two gaps with explicit budget")
reordered <- find_math_sequences(doc(c("x=1", "y=2")), doc(c("b=2", "a=1")))
check(nrow(reordered$matches) == 0L, "step order preserved")
prefix <- doc(c("\\sin t", "a=b", "b=c", "c=1"))
shifted <- find_math_sequences(a, prefix, min_steps = 3L)
check(shifted$matches$start_line_b == 3L, "cross-position start")
check(identical(shifted$matches$step_pairs[[1L]]$start_line_b, c(3L, 5L, 7L)), "per-step line positions")
for (barrier in c("\n\n# 新题\n\n", "\n\n```{r}\nstop('must not run')\n```\n\n")) {
  blocked <- parse_rmd_text(paste0("$x=1$", barrier, "$y=2$"))
  check(nrow(find_math_sequences(blocked, doc(c("a=1", "b=2")))$matches) == 0L, "heading or code breaks derivation")
}
unknown <- doc(c("a=b", "\\mystery{t}", "b=c", "c=1"))
limited <- find_math_sequences(a, unknown, min_steps = 3L, max_skips = 2L)
check(limited$status == "limited" && nrow(limited$matches) == 0L, "unsupported formula cannot be skipped silently")
check(nrow(find_math_sequences(a, b, min_steps = 3L, max_source_gap = 0L)$matches) == 0L, "source distance barrier")
check(nrow(find_math_sequences(a, b, min_steps = 3L, max_source_gap = 10L)$matches) == 1L, "source distance explicit allowance")
repeat_a <- doc(c("x=1", "y=2", "x=1", "y=2"))
repeated <- find_math_sequences(repeat_a, doc(c("a=1", "b=2")), max_steps = 2L, max_skips = 0L)
check(nrow(repeated$matches) == 2L, "repeated derivations retain distinct positions")
check(identical(repeated$matches$start_line_a, c(1L, 5L)), "repeated derivation locations")
short_windows <- find_math_sequences(a, b, max_steps = 2L, max_skips = 0L)
check(all(short_windows$matches$matched_steps == 2L), "maximum matched-step window enforced")
check(find_math_sequences(doc("x=1"), b)$status == "insufficient_steps", "too few steps")
empty <- find_math_sequences(parse_rmd_text("正文"), b)
check(empty$status == "not_applicable" && nrow(empty$matches) == 0L, "no formulas")
check(identical(names(empty$matches), names(r$matches)), "stable empty result schema")
check(find_math_sequences(parse_rmd_text("$x"), b)$status == "limited", "parser limitation propagated")
original_a <- a; original_b <- b
invisible(find_math_sequences(a, b))
check(identical(a, original_a) && identical(b, original_b), "inputs unchanged")
for (side in c("a", "b")) {
  source_doc <- if (side == "a") a else b
  pairs <- r$matches$step_pairs[[1L]]
  for (i in seq_len(nrow(pairs))) {
    tokens <- normalize_math(pairs[[paste0("content_", side)]][i])$tokens
    positions <- pairs[[paste0("token_positions_", side)]][[i]]
    recovered <- vapply(positions, function(p) paste0(substring(source_doc$source, p, p), collapse = ""), character(1))
    check(identical(recovered, tokens), "per-step token source reconstruction")
  }
}
for (name in c("min_steps", "max_steps", "max_skips", "max_source_gap", "max_pairs", "max_states", "max_results", "max_token_work", "max_formulas")) {
  for (bad in list(-1, 1.5, Inf, NA_real_, "2")) {
    params <- list(doc_a = a, doc_b = b); params[[name]] <- bad
    fails(do.call(find_math_sequences, params), paste("invalid", name))
  }
}
fails(find_math_sequences(a, b, min_steps = 1L), "minimum at least two")
fails(find_math_sequences(a, b, max_steps = 21L), "bounded recursion depth")
fails(find_math_sequences(a, b, min_steps = 4L, max_steps = 3L), "ordered step bounds")
fails(find_math_sequences("bad", b), "invalid document input")
fails(find_math_sequences(a, b, max_pairs = 1L), "pair resource limit")
fails(find_math_sequences(a, b, max_states = 1L), "state resource limit")
fails(find_math_sequences(a, b, max_token_work = 1L), "token work resource limit")
fails(find_math_sequences(a, b, max_formulas = 1L), "formula count resource limit")
fails(find_math_sequences(a, b, max_steps = 2L, max_results = 1L), "result resource limit")
cat("All", count, "formula-sequence assertions passed.\n")
