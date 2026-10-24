source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL ", label)
  checks <<- checks + 1L; cat("PASS", label, "\n")
}
fails <- function(fun) inherits(tryCatch(fun(), error = identity), "error")
record <- function(id, a, b, kind = "text", method = "text_exact", eligible = TRUE) {
  d <- empty_evidence_records()
  row <- data.frame(record_id = id, kind = kind, unit = switch(kind, text = "character", code = "token", math = "step"),
    module = "fixture", table = "matches", source_row = 1L, method = method, level = "exact", eligible = eligible,
    matched_units = length(a), content_tokens = if (kind == "text") NA_integer_ else length(a), similarity = 1,
    start_line_a = 1L, end_line_a = 1L, start_line_b = 1L, end_line_b = 1L, group_id = NA_character_, stringsAsFactors = FALSE)
  row$positions_a <- I(list(a)); row$positions_b <- I(list(b)); rbind(d, row)
}
base <- record("one", 1:4, 10:13)
duplicate <- record("two", 1:4, 10:13, method = "text_approximate")
group <- group_position_evidence(rbind(base, duplicate))
check(nrow(group$groups) == 1L, "exact and approximate duplicates form one position group")
check(group$groups$unique_a == 4L && group$groups$unique_b == 4L, "positions counted once")
check(group$groups$largest_match == 4L && group$groups$records == 2L, "match length is not sum of methods")
left <- record("left", 1:3, 20:22); right <- record("right", 8:10, 21:23)
one_side <- group_position_evidence(rbind(left, right))
check(nrow(one_side$groups) == 1L, "overlap on B alone prevents independent accumulation")
left <- record("left", 1:3, 20:22); right <- record("right", 2:4, 30:32)
check(nrow(group_position_evidence(rbind(left, right))$groups) == 1L, "overlap on A alone prevents independent accumulation")
disjoint <- record("disjoint", 10:12, 30:32)
check(nrow(group_position_evidence(rbind(base, disjoint))$groups) == 2L, "disjoint positions remain separate")
middle <- record("middle", 3:6, 12:15); tail <- record("tail", 6:8, 15:17)
chain <- group_position_evidence(rbind(base, middle, tail))
check(nrow(chain$groups) == 1L && chain$groups$unique_a == 8L, "overlap chains are grouped conservatively")
check(chain$groups$largest_match == 4L, "overlap union never becomes an invented long alignment")
code <- record("code", 1:4, 10:13, kind = "code")
check(nrow(group_position_evidence(rbind(base, code))$groups) == 2L, "characters and tokens never mix")
formula <- record("formula", c("u1:s1", "u1:s2"), c("u2:s1", "u2:s2"), "math")
check(group_position_evidence(formula)$groups$largest_match == 2L, "formula step IDs stay in step units")
auxiliary <- record("raw", integer(), integer(), kind = "code", eligible = FALSE)
aux <- group_position_evidence(rbind(code, auxiliary))
check(nrow(aux$groups) == 1L && is.na(aux$records$group_id[2L]), "unsupported raw comparison supplies no effective group")
empty <- group_position_evidence(empty_evidence_records())
check(nrow(empty$groups) == 0L && nrow(empty$records) == 0L, "stable empty evidence schema")
check(fails(function() group_position_evidence(rbind(base, base))), "duplicate record IDs rejected")
bad <- base; bad$positions_a[[1L]] <- c(1L, 1L, 2L, 3L)
check(fails(function() group_position_evidence(bad)), "duplicate atoms rejected")
bad <- base; bad$positions_a[[1L]][1L] <- NA_integer_
check(fails(function() group_position_evidence(bad)), "missing atoms rejected")
bad <- base; bad$positions_b[[1L]] <- 10:12
check(fails(function() group_position_evidence(bad)), "noncorresponding footprint lengths rejected")
bad <- base; bad$positions_a[[1L]][1L] <- 0L
check(fails(function() group_position_evidence(bad)), "invalid source position rejected")
check(fails(function() group_position_evidence(rbind(base, duplicate), max_records = 1L)), "record resource limit")
check(fails(function() group_position_evidence(base, max_atoms = 1L)), "atom resource limit")

result <- analyze_rmd_pair("examples/report-a.Rmd", "examples/report-b.Rmd")
check(result$evidence$status != "error", "three-type evidence integration succeeds")
e <- result$evidence$value
check(all(c("text", "math", "code") %in% e$groups$kind), "all three content types retained")
check(any(e$groups$records > 1L), "existing methods overlap and are consolidated")
check(all(e$records$source_row >= 1L), "every record references its source match row")
for (i in seq_len(nrow(e$records))) {
  r <- e$records[i, ]; original <- result$modules[[r$module]]$value[[r$table]]
  check(r$source_row <= nrow(original), "source match reference resolves")
}
for (kind in c("text", "math", "code")) {
  r <- e$records[e$records$kind == kind & e$records$eligible, , drop = FALSE]
  g <- e$groups[e$groups$kind == kind, , drop = FALSE]
  check(sum(g$unique_a) == length(unique(unlist(r$positions_a, use.names = FALSE))), paste(kind, "A grouping union reconciles"))
  check(sum(g$unique_b) == length(unique(unlist(r$positions_b, use.names = FALSE))), paste(kind, "B grouping union reconciles"))
}
check(sum(e$groups$unique_a[e$groups$kind == "text"]) == result$modules$text$value$coverage$matched_chars[1L], "text grouping reconciles existing coverage")
check(identical(summarize_pair_evidence(result)$records, e$records), "deterministic source ordering")
check(fails(function() summarize_pair_evidence(result, max_atoms = 1L)), "collector resource failure is explicit")
html <- detector_report_html(result)
check(grepl("证据整理：位置重叠与方法来源", html, fixed = TRUE), "report shows consolidated evidence")
check(grepl("不能将其拼成一个更长匹配", html, fixed = TRUE), "report discloses mapping and union limitations")
check(result$verdict == "not_enabled", "consolidation does not invent a verdict")
excluded <- analyze_rmd_pair("validation/boundary/fixtures/B03/a.Rmd", "validation/boundary/fixtures/B03/b.Rmd",
  exclusions = "examples/prompt-exclusions.csv")
check(excluded$evidence$status != "error" && !any(excluded$evidence$value$records$kind == "text"), "excluded baseline evidence never re-enters consolidation")
check(excluded$baseline_modules$text$value$coverage$matched_chars[1L] > 0L, "baseline remains separately available")
invalid <- analyze_rmd_pair("validation/boundary/fixtures/B03/a.Rmd", "validation/boundary/fixtures/B03/b.Rmd", exclusions = "__missing__.csv")
check(invalid$evidence$status == "not_run", "invalid exclusion plan skips consolidation")
missing <- analyze_rmd_pair("__missing__.Rmd", "examples/report-b.Rmd")
check(missing$evidence$status == "not_run", "invalid input skips consolidation")
raw <- analyze_rmd_pair("validation/boundary/fixtures/B07/a.Rmd", "validation/boundary/fixtures/B07/b.Rmd")
check(raw$evidence$status != "error" && nrow(raw$evidence$value$groups) == 0L, "unparsed raw code cannot form effective token evidence")
unknown <- analyze_rmd_pair("validation/boundary/fixtures/B08/a.Rmd", "validation/boundary/fixtures/B08/b.Rmd")
check(unknown$evidence$status != "error" && nrow(unknown$evidence$value$groups) == 0L, "unknown formula raw comparison cannot form supported steps")
standard <- analyze_rmd_pair("validation/boundary/fixtures/B05/a.Rmd", "validation/boundary/fixtures/B05/b.Rmd")
check(standard$evidence$status != "error" && any(standard$evidence$value$records$module == "code_whole"), "short supported whole-unit evidence retained without changing thresholds")

# Full code plus local lexical comparison should describe the same token positions.
tmp <- tempfile("evidence-"); dir.create(tmp)
pa <- file.path(tmp, "a.Rmd"); pb <- file.path(tmp, "b.Rmd")
code_source <- "```{r}\nvalues <- c(1,2,3)\ncenter <- mean(values)\nprint(center)\n```"
writeLines(code_source, pa); writeLines(code_source, pb)
same <- analyze_rmd_pair(pa, pb)
cg <- same$evidence$value$groups; cg <- cg[cg$kind == "code", ]
check(nrow(cg) == 1L && cg$largest_match == 20L && cg$unique_a == 20L, "whole and local code do not double-count twenty tokens")
check(grepl("code_whole", cg$methods, fixed = TRUE) && grepl("code_local", cg$methods, fixed = TRUE), "code method provenance retained")
math_source <- readLines("validation/dev/T02/base.Rmd", encoding = "UTF-8", warn = FALSE)
writeLines(math_source, pa); writeLines(math_source, pb)
same_math <- analyze_rmd_pair(pa, pb)
mg <- same_math$evidence$value$groups; mg <- mg[mg$kind == "math", ]
check(same_math$evidence$status != "error" && nrow(mg) == 1L && mg$largest_match == 3L, "whole multiline formula and sequence use same step IDs")
check(grepl("formula_whole", mg$methods, fixed = TRUE) && grepl("formula_sequence", mg$methods, fixed = TRUE), "formula method provenance retained")
unlink(tmp, recursive = TRUE)
cat("All", checks, "evidence assertions passed.\n")
