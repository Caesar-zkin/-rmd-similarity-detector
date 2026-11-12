source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL ", label)
  checks <<- checks + 1L; cat("PASS", label, "\n")
}
fails <- function(fun) inherits(tryCatch(fun(), error = identity), "error")
pa <- "validation/boundary/fixtures/B03/a.Rmd"; pb <- "validation/boundary/fixtures/B03/b.Rmd"
docs <- list(A = read_rmd(pa, "A"), B = read_rmd(pb, "B"))
records <- rbind(make_exclusion_record(docs$A, "A", 3L, 3L, "共同题干", "自建B03题目"),
  make_exclusion_record(docs$B, "B", 3L, 3L, "共同题干", "自建B03题目"))
before <- analyze_rmd_pair(pa, pb)
after <- analyze_rmd_pair(pa, pb, exclusions = records)
check(before$exclusions$status == "not_requested", "default does not exclude shared content")
check(before$modules$text$value$coverage$matched_chars[1L] >= 60, "shared prompt matches before exclusion")
check(after$exclusions$status == "applied", "both explicit records applied")
check(all(after$baseline_modules$text$value$coverage$matched_chars >= 60), "pre-exclusion comparison retained")
check(all(after$modules$text$value$coverage$matched_chars == 0), "only prompt match removed")
check(all(after$modules$text$value$coverage$comparable_chars < before$modules$text$value$coverage$comparable_chars), "remaining denominator recomputed")
check(identical(after$documents, docs), "original documents unchanged")
for (side in c("A", "B")) {
  v <- after$analysis_documents[[side]]; d <- docs[[side]]
  check(identical(v$source, d$source), paste(side, "source unchanged"))
  check(identical(v$units$start_offset, d$units$start_offset), paste(side, "offsets unchanged"))
  check(identical(paste0(v$units$raw, collapse = ""), d$source), paste(side, "raw spans still reconstruct source"))
  check(any(v$units$type == "excluded" & v$units$status == "excluded"), paste(side, "excluded unit remains a boundary"))
}
html <- detector_report_html(after)
check(grepl("公共来源：明确标注与排除前后", html, fixed = TRUE), "report explains scope")
check(grepl("排除前", html, fixed = TRUE) && grepl("排除后", html, fixed = TRUE), "report shows both stages")
check(grepl("自建B03题目", html, fixed = TRUE), "source reference retained")
check(after$verdict == "not_enabled", "exclusion is not a verdict")
baseline_error <- analyze_rmd_pair(pa, pb, text_options = list(max_pairs = 1L), exclusions = records)
check(baseline_error$baseline_modules$text$status == "error" && baseline_error$modules$text$status != "error", "baseline resource failure does not block filtered analysis")
check(baseline_error$overall_status == "partial_failure" && grepl("max_pairs", detector_report_html(baseline_error), fixed = TRUE), "baseline failure remains visible in report")
bad <- records; bad$quote[2L] <- "changed source"
failed <- analyze_rmd_pair(pa, pb, exclusions = bad)
check(failed$overall_status == "exclusion_error", "stale quote causes explicit error")
check(all(vapply(failed$modules, function(m) m$status == "not_run", logical(1))), "invalid plan runs no filtered module")
check(identical(failed$analysis_documents, docs), "invalid second record does not partially apply first")
check(!is.null(failed$baseline_modules$text$value), "baseline retained when plan invalid")
check(grepl("没有应用任何一侧", detector_report_html(failed), fixed = TRUE), "invalid plan reported without fake results")
check(fails(function() prepare_document_exclusions(docs, rbind(records, records[1L, ]))), "overlapping ranges rejected")
for (field in c("side", "reason", "reference")) {
  bad <- records; bad[[field]][1L] <- ""
  check(fails(function() prepare_document_exclusions(docs, bad)), paste("invalid", field, "rejected"))
}
for (value in c("0", "1.5", "-1", "99999", "NA")) {
  bad <- records; bad$start_line <- as.character(bad$start_line); bad$start_line[1L] <- value
  check(fails(function() prepare_document_exclusions(docs, bad)), "invalid line rejected")
}
bad <- records; bad$quote[1L] <- NA_character_
check(fails(function() prepare_document_exclusions(docs, bad)), "missing quote rejected")
check(fails(function() prepare_document_exclusions(docs, records[, -1L])), "missing required column rejected")
check(fails(function() prepare_document_exclusions(docs, records[FALSE, ])), "explicit empty plan rejected")
check(fails(function() prepare_document_exclusions(docs, "__missing_exclusion__.csv")), "missing CSV rejected")
check(fails(function() prepare_document_exclusions(docs, records[rep(1L, 1001L), ])), "exclusion record resource limit")

tmp <- tempfile("exclusions-"); dir.create(tmp)
reference <- file.path(tmp, "共同模板.Rmd")
ra <- file.path(tmp, "reference-a.Rmd"); rb <- file.path(tmp, "reference-b.Rmd")
writeLines(c("Follow the supplied instructions.", "", "```{r}", "set.seed(12)", "```"), reference)
writeLines(c("**Follow the supplied instructions.**", "", "Unique answer from A.", "", "```{r}", "set.seed( 12 )", "```"), ra)
writeLines(c("Follow the supplied instructions.", "", "Different answer from B.", "", "```{r}", "set.seed(12)", "```"), rb)
reference_result <- analyze_rmd_pair(ra, rb, public_reference = reference)
check(reference_result$exclusions$status == "applied" &&
  nrow(reference_result$exclusions$units) == 4L, "reference excludes formatted prompt and starter code on both sides")
check(all(reference_result$modules$text$value$coverage$matched_chars == 0L) &&
  all(reference_result$modules$text$value$coverage_with_short$coverage == 0) &&
  all(reference_result$modules$text$value$coverage$comparable_chars > 0),
  "reference removes shared prompt from evidence and retains distinct answer text")
check(grepl("共同模板.Rmd", detector_report_html(reference_result), fixed = TRUE),
  "reference name is retained for audit")
unmatched_reference <- analyze_rmd_pair(pa, pb, public_reference = reference)
check(unmatched_reference$exclusions$status == "no_matches" &&
  identical(unmatched_reference$modules$text$value$coverage, before$modules$text$value$coverage),
  "reference with no matching units preserves original comparison")
csv <- file.path(tmp, "排除 标注.csv")
utils::write.csv(records, csv, row.names = FALSE, fileEncoding = "UTF-8")
from_csv <- analyze_rmd_pair(pa, pb, exclusions = csv)
check(from_csv$exclusions$status == "applied", "CSV in Chinese space path supported")
check(identical(from_csv$modules$text$value$coverage, after$modules$text$value$coverage), "CSV and dataframe agree")
poison <- records; poison$reason[1L] <- "<script id='exclude-poison'>bad()</script>"
poison$reference[1L] <- "<img src='https://example.invalid/x'>"
escaped <- detector_report_html(analyze_rmd_pair(pa, pb, exclusions = poison))
check(grepl("&lt;script id=", escaped, fixed = TRUE) && !grepl("<script id='exclude-poison'", escaped, fixed = TRUE), "exclusion reason HTML escaped")
check(!grepl("<img src='https://example.invalid/x'", escaped, fixed = TRUE), "exclusion source cannot load resources")

text_doc <- parse_rmd_text("甲乙丙丁", "A")
all_records <- rbind(make_exclusion_record(text_doc, "A", 1L, 1L, "题干", "演示"),
  make_exclusion_record(text_doc, "B", 1L, 1L, "题干", "演示"))
all_view <- prepare_document_exclusions(list(A = text_doc, B = text_doc), all_records)$documents
all_result <- analyze_text_pair_approx(all_view$A, all_view$B)
check(all(is.na(all_result$coverage$coverage)), "all comparable text excluded means NA denominator")
code_doc <- parse_rmd_text("```{r}\nvalues <- c(1,2,3)\nprint(values)\n```", "A")
partial <- make_exclusion_record(code_doc, "A", 2L, 2L, "片段", "演示")
check(fails(function() prepare_document_exclusions(list(A = code_doc, B = code_doc), partial)), "partial code block exclusion rejected")
whole_code <- make_exclusion_record(code_doc, "A", 1L, 4L, "题干代码", "演示")
code_view <- prepare_document_exclusions(list(A = code_doc, B = code_doc), whole_code)$documents$A
check(nrow(prepare_code_units(code_view)) == 0L, "whole code unit excluded from R comparison")
formula_doc <- parse_rmd_text("$$\nx=y\n$$", "A")
partial <- make_exclusion_record(formula_doc, "A", 2L, 2L, "片段", "演示")
check(fails(function() prepare_document_exclusions(list(A = formula_doc, B = formula_doc), partial)), "partial formula exclusion rejected")
whole_math <- make_exclusion_record(formula_doc, "A", 1L, 3L, "题干公式", "演示")
math_view <- prepare_document_exclusions(list(A = formula_doc, B = formula_doc), whole_math)$documents$A
check(nrow(prepare_math_units(math_view)) == 0L, "whole formula excluded from comparison")
bridge_doc <- parse_rmd_text("$x=y$\n\n公共说明。\n\n$y=z$", "A")
bridge_record <- make_exclusion_record(bridge_doc, "A", 3L, 3L, "题干", "演示")
bridge_view <- prepare_document_exclusions(list(A = bridge_doc, B = bridge_doc), bridge_record)$documents$A
check(nrow(find_math_sequences(bridge_doc, bridge_doc)$matches) > 0L, "ordinary prose permits baseline formula sequence")
check(nrow(find_math_sequences(bridge_view, bridge_doc)$matches) == 0L, "excluded region prevents formula stitching")
heading_doc <- parse_rmd_text("# 标题\n\n正文", "A")
heading_record <- make_exclusion_record(heading_doc, "A", 1L, 1L, "标题", "演示")
check(fails(function() prepare_document_exclusions(list(A = heading_doc, B = heading_doc), heading_record)), "non-comparable-only range rejected")
one_side <- analyze_rmd_pair(pa, pb, exclusions = records[1L, , drop = FALSE])
check(one_side$exclusions$status == "applied" && !any(one_side$analysis_documents$B$units$type == "excluded"), "explicit one-sided exclusion supported")
missing <- analyze_rmd_pair("__missing__.Rmd", pb, exclusions = csv)
check(missing$overall_status == "input_error" && missing$exclusions$status == "not_run", "input failure skips exclusion")
demo <- analyze_rmd_pair(pa, pb, exclusions = "examples/prompt-exclusions.csv")
check(demo$exclusions$status == "applied", "tracked public-prompt demo plan matches sources")
unlink(tmp, recursive = TRUE)
cat("All", checks, "exclusion assertions passed.\n")
