source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L; cat("PASS", label, "\n")
}
fails <- function(expr, label) check(inherits(try(force(expr), silent = TRUE), "try-error"), label)
build_detector(check = TRUE)
check(TRUE, "single-file bundle matches module sources")
r <- analyze_rmd_pair("examples/report-a.Rmd", "examples/report-b.Rmd")
check(r$verdict == "not_enabled", "final verdict remains disabled")
check(all(r$manifest$read_status == "ok"), "both Rmd inputs read")
check(!any(vapply(r$modules, function(m) m$status == "error", logical(1))), "all analysis interfaces complete")
check(all(r$modules$text$value$coverage$coverage == 1), "integrated text coverage")
check(r$modules$formula_sequence$value$matches$matched_steps == 3L, "integrated multiline formula steps")
check(r$modules$formula_sequence$value$matches$skipped_steps == 1L, "formula inserted step retained")
check(all(r$modules$code_local$value$coverage$matched_tokens == 20L), "integrated code token coverage")
check(isTRUE(all.equal(r$modules$code_local$value$coverage$coverage, c(1, 20 / 23))), "code metrics keep token units")
html <- detector_report_html(r)
for (label in c("未启用最终判定", "文字：", "公式：", "代码：", "解析诊断", "本次参数", "共同题干"))
  check(grepl(label, html, fixed = TRUE), paste("report section", label))
check(!grepl("<script", html, fixed = TRUE), "report body has no executable scripts")
check(!grepl("<img", html, fixed = TRUE), "report body has no external images")
check(regexpr("分析结果速览", html, fixed = TRUE)[1L] > 0L &&
  regexpr("分析结果速览", html, fixed = TRUE)[1L] <
  regexpr("输入与分析概况", html, fixed = TRUE)[1L], "plain-language overview precedes detailed input sections")
check(grepl(.report_analysis_overview(r), html, fixed = TRUE), "overview includes current analysis values")
check(all(vapply(c("文字", "公式", "R 代码", "作业 A", "作业 B", "100%", "20 / 23", "推导步骤"),
  grepl, logical(1), x = .report_analysis_overview(r), fixed = TRUE)),
  "overview explains all three comparisons with real coverage and formula findings")
guide <- .report_conclusion_guide()
check(grepl(guide, substring(html, regexpr("解析诊断与未覆盖内容", html, fixed = TRUE)[1L]), fixed = TRUE),
  "three-state definitions appear in diagnostics")
for (label in c("疑似抄袭", "未检出明显证据", "证据不足"))
  check(grepl(label, guide, fixed = TRUE), paste("conclusion definition", label))
changed <- r
changed$decision$label <- "<script>unsafe</script>"
check(grepl("&lt;script&gt;unsafe&lt;/script&gt;", .report_analysis_overview(changed), fixed = TRUE) &&
  !grepl("<script>", .report_analysis_overview(changed), fixed = TRUE), "overview escapes dynamic conclusion text")
original <- r; invisible(detector_report_html(r, max_evidence = 1L))
check(identical(r, original), "display limit does not change analysis")
check(grepl("展示前 1 条", detector_report_html(r, 1L), fixed = TRUE), "display limits disclosed")
unconsolidated <- r
unconsolidated$evidence <- list(status = "error", error = "Evidence atom resource limit exceeded.", value = NULL)
unconsolidated$decision <- evaluate_candidate_decision(unconsolidated)
check(grepl("精确文字片段", detector_report_html(unconsolidated), fixed = TRUE),
  "ordinary matches render when evidence consolidation is unavailable")
partial <- analyze_rmd_pair("examples/report-a.Rmd", "examples/report-b.Rmd", text_options = list(max_pairs = 1L))
check(partial$overall_status == "partial_failure" && partial$modules$text$status == "error", "resource error remains failure")
check(is.null(partial$modules$text$value), "failed module has no fabricated zero metrics")
check(grepl("文字比较未完成", .report_analysis_overview(partial), fixed = TRUE),
  "overview flags an incomplete text comparison in plain language")
check(!is.null(partial$modules$code_local$value), "independent modules continue after error")
check(grepl("partial_failure", detector_report_html(partial), fixed = TRUE), "partial failure visible in HTML")
missing <- analyze_rmd_pair("__missing_report_test__.Rmd", "examples/report-b.Rmd")
check(missing$overall_status == "input_error" && missing$manifest$read_status[1L] == "error", "missing input diagnosed")
check(all(vapply(missing$modules, function(m) m$status == "not_run", logical(1))), "no analysis after input failure")
check(!grepl("matched_tokens", detector_report_html(missing), fixed = TRUE), "input failure not represented as zero matching")
check(grepl("输入读取失败", detector_report_html(missing), fixed = TRUE), "input guidance included")
check(grepl(guide, detector_report_html(missing), fixed = TRUE), "input error report retains conclusion definitions")
bad_path <- analyze_rmd_pair(2, "examples/report-b.Rmd")
check(bad_path$overall_status == "input_error", "invalid path type handled")
temp <- tempfile("rmd-report-tests-"); dir.create(temp)
copy_a <- file.path(temp, "copy-a.Rmd"); copy_b <- file.path(temp, "copy-b.Rmd")
copy_source <- paste(c("abcdefghijklmnopqrstuvwxABCDEFGHIJKLMNOP",
  "", "firstshort", "", "secondline", "", "thirdshort", "", "fourthline", "", "fifthshort"), collapse = "\n")
writeBin(charToRaw(copy_source), copy_a)
check(file.copy(copy_a, copy_b), "byte-identical fixture has a second filename")
copies <- analyze_rmd_pair(copy_a, copy_b)
check(all(copies$modules$text$value$coverage$matched_chars == 40L) &&
  all(copies$modules$text$value$coverage$comparable_chars == 90L), "identical fixture reproduces 44.4 percent evidence coverage")
check(isTRUE(copies$files_identical) &&
  grepl("文件内容完全相同（100%）", .report_analysis_overview(copies), fixed = TRUE),
  "byte-identical inputs display 100 percent file identity")
check(is.null(copies$documents$A$input_bytes) && is.null(copies$documents$B$input_bytes),
  "byte comparison does not retain extra input copies")
writeBin(charToRaw(gsub("\n", "\r\n", copy_source, fixed = TRUE)), copy_b)
line_endings <- analyze_rmd_pair(copy_a, copy_b)
check(identical(line_endings$files_identical, FALSE) &&
  !grepl("文件内容完全相同（100%）", .report_analysis_overview(line_endings), fixed = TRUE),
  "normalized text equality does not imply byte identity")
check(is.na(missing$files_identical), "unreadable input leaves file identity unavailable")

writeLines(c("**Observed values.**", "", "The sample mean was ten.", "",
  "```{r}", "average <- mean(c(1, 2))", "```"), copy_a)
writeLines(c("Observed values.", "", "The sample mean was six.", "",
  "```{r}", "estimate<-mean(c(1,2))", "```"), copy_b)
short <- analyze_rmd_pair(copy_a, copy_b)
check(nrow(short$modules$text$value$short_matches) == 2L &&
  all(short$modules$text$value$coverage_with_short$coverage > .85),
  "formatted and lightly edited short paragraphs add genuine coverage")
check(all(short$code_coverage_with_short$coverage == 1) &&
  all(short$modules$code_local$value$coverage$coverage == 0),
  "a uniquely matched short code block adds coverage below the local threshold")
check(short$decision$verdict != "suspected", "short matches alone do not imply suspected plagiarism")

trigger_a <- file.path(temp, "trigger-a.Rmd")
trigger_b <- file.path(temp, "trigger-b.Rmd")
set.seed(42)
random_fragment <- function(n) paste(sample(c(letters, LETTERS, 0:9), n, replace = TRUE), collapse = "")
short_matches <- substr(replicate(12L, random_fragment(100L)), 1L, 48L)
shared_lines <- as.vector(rbind(short_matches, ""))
trigger_text <- paste0("TRIGGER_ONLY_MARKER", random_fragment(150L))
edited_chars <- strsplit(trigger_text, "", fixed = TRUE)[[1L]]
edits <- seq.int(22L, length(edited_chars), by = 16L)
edited_chars[edits] <- ifelse(edited_chars[edits] == "z", "y", "z")
edited_text <- paste(edited_chars, collapse = "")
writeLines(c(shared_lines, trigger_text), trigger_a)
writeLines(c(shared_lines, edited_text), trigger_b)
trigger_result <- analyze_rmd_pair(trigger_a, trigger_b)
trigger_records <- trigger_result$evidence$value$records
trigger <- trigger_records[trigger_records$record_id %in% trigger_result$decision$trigger_records$record_id, ]
check(nrow(trigger) == 1L && trigger$table == "approximate_matches" && trigger$source_row == 13L,
  "regression fixture triggers on a match beyond the default display limit")
trigger_html <- detector_report_html(trigger_result)
ordinary_section <- regexpr("输入与分析概况", trigger_html, fixed = TRUE)[1L]
priority_html <- substr(trigger_html, 1L, ordinary_section - 1L)
check(all(vapply(c(trigger_text, edited_text, "A：第25—25行", "B：第25—25行"),
  grepl, logical(1), x = priority_html, fixed = TRUE)),
  "default HTML shows both triggering excerpts and their original lines before ordinary evidence")

medium_matches <- replicate(2L, random_fragment(65L))
writeLines(c(medium_matches[1L], "", medium_matches[2L]), trigger_a)
writeLines(c("", medium_matches[1L], "", medium_matches[2L]), trigger_b)
cumulative <- analyze_rmd_pair(trigger_a, trigger_b)
check(cumulative$decision$pathway == "cumulative_text" && nrow(cumulative$decision$trigger_records) == 2L,
  "two disjoint matches trigger the cumulative path")
cumulative_html <- detector_report_html(cumulative, max_evidence = 1L)
priority_html <- substr(cumulative_html, 1L, regexpr("输入与分析概况", cumulative_html, fixed = TRUE)[1L] - 1L)
check(all(vapply(c(medium_matches, "A：第1—1行", "B：第2—2行", "A：第3—3行", "B：第4—4行"),
  grepl, logical(1), x = priority_html, fixed = TRUE)),
  "every cumulative trigger appears with its own lines even when the ordinary limit is one")

long_text <- intToUtf8(seq.int(0x4e00, length.out = 6500L))
writeLines(long_text, trigger_a, useBytes = TRUE); writeLines(long_text, trigger_b, useBytes = TRUE)
long_result <- analyze_rmd_pair(trigger_a, trigger_b)
check(long_result$overall_status == "limited" && long_result$decision$pathway == "single_text" &&
  long_result$decision$trigger_records$matched_units == 6500L,
  "report analysis can use preserved exact evidence after the approximate budget is exceeded")
long_html <- detector_report_html(long_result)
check(grepl("近似比较超出资源上限，当前结果来自已完成的精确比较", .report_analysis_overview(long_result), fixed = TRUE),
  "overview explains the scope of exact-only coverage")
check(all(vapply(c("近似文字匹配超出资源上限", "精确文字片段", substr(long_text, 1L, 100L)),
  grepl, logical(1), x = long_html, fixed = TRUE)),
  "report discloses the approximate limit and shows the surviving exact excerpt")

sentinel <- file.path(temp, "never-created.txt")
poison <- paste0("---\nauthor: !expr stop('YAML must not execute')\n---\n\n```{r}\n",
  "danger <- \"<script id='rmd-poison'>alert(1)</script>\"\n",
  "# <img src='https://example.invalid/never-fetch' onerror='alert(1)'>\n",
  "stop('chunk must not execute')\nwriteLines('executed', ", encodeString(sentinel, quote = "\""), ")\n```\n")
pa <- file.path(temp, "输入 A.Rmd"); pb <- file.path(temp, "输入 B.Rmd")
writeLines(enc2utf8(poison), pa, useBytes = TRUE); writeLines(enc2utf8(poison), pb, useBytes = TRUE)
safe <- analyze_rmd_pair(pa, pb, code_options = list(min_tokens = 1L))
safe_html <- detector_report_html(safe)
check(!file.exists(sentinel), "input YAML chunks and file writes never execute")
check(grepl("&lt;script id=&#39;rmd-poison&#39;&gt;", safe_html, fixed = TRUE), "script payload displayed as text")
check(grepl("&lt;img", safe_html, fixed = TRUE), "image payload escaped")
check(!grepl("<script id=", safe_html, fixed = TRUE) && !grepl("<img", safe_html, fixed = TRUE), "no active payload tags")
check(identical(report_escape("<>&\"'`"), "&lt;&gt;&amp;&quot;&#39;&#96;"), "HTML delimiters quotes and backticks escaped")
table <- .report_table(data.frame(value = c("<svg onload='x'>", NA_character_)))
check(grepl("&lt;svg", table, fixed = TRUE) && grepl("不适用", table, fixed = TRUE), "table cells escaped and missing values explicit")
check(grepl("展示已截断", .report_pre(paste0(rep("x", 4001L), collapse = "")), fixed = TRUE), "snippet clipping disclosed")
warning <- .report_module(function() { warning("test warning"); list(status = "ok") })
check(warning$status == "limited" && length(warning$warnings) == 1L, "module warnings retained")
empty_a <- file.path(temp, "empty-a.Rmd"); empty_b <- file.path(temp, "empty-b.Rmd")
file.create(empty_a, empty_b)
empty <- analyze_rmd_pair(empty_a, empty_b)
check(!grepl("作业 [AB] 0%", .report_analysis_overview(empty)),
  "overview does not turn missing comparable content into zero coverage")
check(!any(vapply(empty$modules, function(m) m$status == "error", logical(1))), "empty documents render missing-content states")
check(grepl("not_applicable", detector_report_html(empty), fixed = TRUE), "missing content visible")
fails(analyze_rmd_pair(pa, pb, text_options = 1), "invalid option container")
fails(analyze_rmd_pair(pa, pb, text_options = list(doc_a = 1)), "cannot replace parsed documents through options")
for (bad in list(0, -1, 1.5, Inf, NA_real_, 101, "2")) fails(detector_report_html(r, bad), "invalid evidence display limit")
fails(detector_report_html(list()), "invalid report object")
candidate <- file.path(temp, "bundle.Rmd")
build_detector(output = candidate)
check(identical(readBin(candidate, "raw", n = file.info(candidate)$size), readBin("detector.Rmd", "raw", n = file.info("detector.Rmd")$size)), "bundle build reproducible")
writeLines("stale", candidate)
fails(build_detector(output = candidate, check = TRUE), "stale bundle rejected")
unlink(temp, recursive = TRUE)
cat("All", count, "report-integration assertions passed.\n")
