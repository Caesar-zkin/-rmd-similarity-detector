source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL ", label)
  checks <<- checks + 1L; cat("PASS", label, "\n")
}
fails <- function(fun) inherits(tryCatch(fun(), error = identity), "error")

# Contract fixtures exercise rule logic, not detection accuracy. Real files follow below.
fixture_doc <- parse_rmd_text(paste(rep(strrep("x", 200L), 200L), collapse = "\n"))
record <- function(id, kind, n, line_a = 1L, line_b = 1L, level = "exact", tokens = n, similarity = 1) {
  pos <- function(side, line) if (kind == "math") paste0(id, ":", side, ":s", seq_len(n)) else
    as.integer((line - 1L) * 201L + seq_len(n))
  a <- pos("a", line_a); b <- pos("b", line_b)
  r <- data.frame(record_id = id, kind = kind, unit = switch(kind, text = "character", code = "token", math = "step"),
    module = "fixture", table = "matches", source_row = 1L, method = "fixture", level = level, eligible = TRUE,
    matched_units = n, content_tokens = if (kind == "text") NA_integer_ else tokens, similarity = similarity,
    start_line_a = line_a, end_line_a = line_a + if (kind == "math") n - 1L else 0L,
    start_line_b = line_b, end_line_b = line_b + if (kind == "math") n - 1L else 0L,
    group_id = NA_character_, stringsAsFactors = FALSE)
  r$positions_a <- I(list(a)); r$positions_b <- I(list(b)); r
}
fixture <- function(records = empty_evidence_records(), text_n = 500L, code_n = 500L) {
  grouped <- group_position_evidence(records)
  math_units <- function(side) {
    rows <- list()
    for (i in which(records$kind == "math")) {
      r <- records[i, ]; n <- r$matched_units; counts <- rep(as.integer(r$content_tokens %/% n), n)
      if (r$content_tokens %% n) counts[seq_len(r$content_tokens %% n)] <- counts[seq_len(r$content_tokens %% n)] + 1L
      rows[[length(rows) + 1L]] <- data.frame(unit_id = r[[paste0("positions_", side)]][[1L]],
        math_status = "ok", token_count = counts,
        start_line = r[[paste0("start_line_", side)]] + seq_len(n) - 1L,
        end_line = r[[paste0("start_line_", side)]] + seq_len(n) - 1L)
    }
    if (length(rows)) do.call(rbind, rows) else data.frame(unit_id = character(), math_status = character(), token_count = integer(), start_line = integer(), end_line = integer())
  }
  module <- function(value) list(status = "ok", value = value, error = "", warnings = character())
  modules <- list(text = module(list(coverage = data.frame(side = c("A", "B"), comparable_chars = text_n))),
    code_local = module(list(coverage = data.frame(side = c("A", "B"), comparable_tokens = code_n))),
    formula_sequence = module(list(formulas_a = math_units("a"), formulas_b = math_units("b"))),
    formula_single = module(list()), code_whole = module(list()))
  list(manifest = data.frame(read_status = c("ok", "ok")), exclusions = list(status = "not_requested"),
    overall_status = "completed", modules = modules, analysis_documents = list(A = fixture_doc, B = fixture_doc),
    evidence = module(list(records = grouped$records, groups = grouped$groups)))
}
decide <- function(...) evaluate_candidate_decision(fixture(...))
check(decide()$verdict == "no_clear_evidence", "adequate complete input without evidence")
check(decide(text_n = 30L, code_n = 20L)$verdict == "insufficient_evidence", "short input cannot become a negative conclusion")
check(decide(record("t", "text", 100L))$pathway == "single_text", "text single threshold inclusive")
check(decide(record("t", "text", 99L))$verdict == "insufficient_evidence", "text below single threshold remains unresolved")
check(decide(record("t", "text", 55L))$verdict == "insufficient_evidence", "detected shorter local fragment is not a clean negative")
check(decide(record("t", "text", 100L, similarity = 0.899))$verdict != "suspected", "similarity below threshold excluded")
check(decide(record("t", "text", 100L, similarity = 0.899))$verdict == "insufficient_evidence", "lower-quality matched evidence is not silently discarded for a negative")
check(decide(record("t", "text", 100L, similarity = 0.9))$verdict == "suspected", "similarity threshold inclusive")
check(decide(record("c", "code", 60L, level = "lexical"))$pathway == "single_code", "lexical code single threshold")
check(decide(record("c", "code", 60L, level = "renamed"))$verdict != "suspected", "renamed code requires more tokens")
check(decide(record("c", "code", 80L, level = "renamed"))$verdict == "suspected", "long consistent renamed code")
check(decide(record("m", "math", 4L, level = "normalized", tokens = 40L))$pathway == "single_math", "long supported formula sequence")
check(decide(record("m", "math", 4L, level = "normalized", tokens = 40L, similarity = 0.8))$pathway == "single_math", "formula skip ratio uses its own threshold")
check(decide(record("m", "math", 4L, level = "normalized", tokens = 40L, similarity = 0.74))$verdict == "insufficient_evidence", "low-ratio formula evidence remains unresolved")
check(decide(record("m", "math", 4L, level = "normalized", tokens = 39L))$verdict != "suspected", "formula step count alone insufficient")
check(decide(record("m", "math", 4L, level = "renamed", tokens = 60L))$verdict != "suspected", "renamed formula requires longer sequence")
check(decide(record("m", "math", 5L, level = "renamed", tokens = 60L))$verdict == "suspected", "long consistently renamed formula sequence")
check(decide(record("m", "math", 1L, level = "normalized", tokens = 80L))$verdict != "suspected", "one formula is not a multi-step derivation")
two_text <- rbind(record("a", "text", 60L, 1L, 1L), record("b", "text", 60L, 30L, 30L))
check(decide(two_text, text_n = 400L)$pathway == "cumulative_text", "two nonoverlapping text records reach cumulative threshold")
check(decide(two_text, text_n = 1000L)$verdict != "suspected", "cumulative text needs coverage support")
repeated <- two_text; repeated$positions_a[[2L]] <- repeated$positions_a[[1L]]
check(decide(repeated, text_n = 400L)$verdict != "suspected", "one-sided duplicate evidence cannot accumulate")
two_code <- rbind(record("a", "code", 50L, 1L, 1L, "lexical"), record("b", "code", 50L, 30L, 30L, "lexical"))
check(decide(two_code, code_n = 300L)$pathway == "cumulative_code", "nonoverlapping code accumulates within token units")
two_code$level <- "renamed"
check(decide(two_code, code_n = 300L)$verdict != "suspected", "short renamed code does not bypass medium requirement")
rename_code <- rbind(record("a", "code", 60L, 1L, 1L, "renamed"), record("b", "code", 60L, 30L, 30L, "renamed"), record("c", "code", 60L, 60L, 60L, "renamed"))
check(decide(rename_code, code_n = 500L)$pathway == "cumulative_code", "renamed cumulative route uses stricter total")
mixed <- rbind(record("t", "text", 60L, 1L, 1L), record("c", "code", 40L, 5L, 5L, "lexical"))
check(decide(mixed)$pathway == "cross_type_support", "two types support each other locally")
far <- rbind(record("t", "text", 60L, 1L, 1L), record("c", "code", 40L, 5L, 40L, "lexical"))
check(decide(far)$verdict != "suspected", "support must be nearby on both sides")
weak <- mixed; weak$matched_units[2L] <- 39L; weak$content_tokens[2L] <- 39L
weak$positions_a[[2L]] <- head(weak$positions_a[[2L]], 39L); weak$positions_b[[2L]] <- head(weak$positions_b[[2L]], 39L)
check(decide(weak)$verdict != "suspected", "short second type does not satisfy support condition")
check(fails(function() evaluate_candidate_decision(fixture(mixed), max_support_checks = 1L)), "support work cap fails explicitly")

# Large line envelopes must not invent context around skipped or mismatched positions.
gap_text <- record("t", "text", 60L, 1L, 1L)
gap_text$positions_a[[1L]] <- c(1:30, as.integer(99L * 201L + 1:30))
gap_text$positions_b[[1L]] <- gap_text$positions_a[[1L]]
gap_text$end_line_a <- gap_text$end_line_b <- 100L
gap_case <- rbind(gap_text, record("c", "code", 40L, 50L, 50L, "lexical"))
check(decide(gap_case)$verdict != "suspected", "line envelopes cannot fill unmatched context gaps")
crossed <- gap_text
crossed$positions_a[[1L]] <- c(1:30, as.integer(49L * 201L + 1:30))
crossed$positions_b[[1L]] <- c(as.integer(49L * 201L + 1:30), 1:30)
crossed$end_line_a <- crossed$end_line_b <- 50L
check(decide(rbind(crossed, record("c", "code", 40L, 1L, 1L, "lexical")))$verdict != "suspected", "context must refer to corresponding matched line pairs")
limited <- fixture(); limited$modules$code_whole$status <- "limited"
check(evaluate_candidate_decision(limited)$verdict == "insufficient_evidence", "analysis limitation blocks a negative conclusion")
limited_strong <- fixture(record("t", "text", 100L)); limited_strong$modules$code_whole$status <- "error"
check(evaluate_candidate_decision(limited_strong)$verdict == "suspected", "supported strong evidence survives unrelated module failure")
check(any(grepl("受限或未完成", evaluate_candidate_decision(limited_strong)$limitations, fixed = TRUE)), "partial analysis remains disclosed")
rules <- decision_rules_v1(); rules$text_min_similarity <- NA_real_
check(fails(function() evaluate_candidate_decision(fixture(), rules)), "missing similarity threshold rejected")
rules <- decision_rules_v1(); rules$code_strong_tokens <- 1L
check(fails(function() evaluate_candidate_decision(fixture(), rules)), "invalid threshold hierarchy rejected")
rules <- decision_rules_v1(); rules$context_max_line_gap <- -1L
check(fails(function() evaluate_candidate_decision(fixture(), rules)), "negative context gap rejected")
check(fails(function() evaluate_candidate_decision(fixture(), list())), "incomplete rule schema rejected")

tmp <- tempfile("decision-tests-"); dir.create(tmp)
pa <- file.path(tmp, "a.Rmd"); pb <- file.path(tmp, "b.Rmd")
long_text <- paste0("分析开始前逐项核对观测记录的来源与单位，检查缺失值和可能的录入错误，并记录处理依据。",
  "随后同时报告中心位置、离散程度以及分布图形，避免用一个统计量代替全部特征。",
  "对异常观测先回查原始记录，再说明保留或剔除的理由，并比较不同处理下结论是否稳定。",
  "所有描述只针对当前样本，若要推广到总体，还需要明确抽样方式、适用条件以及不确定性的来源。")
writeLines(enc2utf8(long_text), pa, useBytes = TRUE); writeLines(enc2utf8(long_text), pb, useBytes = TRUE)
real <- analyze_rmd_pair(pa, pb)
check(real$decision$status == "ok" && real$decision$verdict == "suspected", "real long copied text produces draft suspected verdict")
check(real$verdict == "not_enabled" && real$decision$stage == "development_unvalidated", "final verdict remains separate from draft")
check(nrow(real$decision$trigger_records) == 1L, "single path identifies a real trigger record")
check(real$decision$trigger_records$record_id %in% real$evidence$value$records$record_id, "trigger record resolves to consolidated evidence")
check(identical(evaluate_candidate_decision(real), real$decision), "draft decision deterministic")
html <- detector_report_html(real)
check(grepl("开发规则试判（未标定）", html, fixed = TRUE) && grepl("疑似抄袭", html, fixed = TRUE), "draft verdict displayed with calibration status")
check(grepl("未启用最终判定", html, fixed = TRUE), "report separates draft and final status")
unrelated <- analyze_rmd_pair("validation/boundary/fixtures/B06/a.Rmd", "validation/boundary/fixtures/B06/b.Rmd")
check(unrelated$decision$verdict == "no_clear_evidence", "real unrelated supported text produces draft no-clear-evidence")
short <- analyze_rmd_pair("validation/boundary/fixtures/B05/a.Rmd", "validation/boundary/fixtures/B05/b.Rmd")
check(short$decision$verdict == "insufficient_evidence", "real short routine call cannot trigger suspected")
unknown <- analyze_rmd_pair("validation/boundary/fixtures/B08/a.Rmd", "validation/boundary/fixtures/B08/b.Rmd")
check(unknown$decision$verdict == "insufficient_evidence", "raw unsupported math cannot trigger suspected")
missing <- analyze_rmd_pair("__missing__.Rmd", pb)
check(missing$decision$verdict == "insufficient_evidence", "input failure is not no-clear-evidence")
bad_plan <- analyze_rmd_pair(pa, pb, exclusions = "__missing__.csv")
check(bad_plan$decision$verdict == "insufficient_evidence", "invalid exclusion plan blocks a suspected result")
shared <- analyze_rmd_pair("validation/boundary/fixtures/B03/a.Rmd", "validation/boundary/fixtures/B03/b.Rmd")
filtered <- analyze_rmd_pair("validation/boundary/fixtures/B03/a.Rmd", "validation/boundary/fixtures/B03/b.Rmd", exclusions = "examples/prompt-exclusions.csv")
check(shared$decision$verdict == "suspected", "known shared prompt exposes unexcluded draft-rule risk")
check(filtered$decision$verdict == "insufficient_evidence", "excluded prompt never re-enters draft decision")
check(any(grepl("共同题干", shared$decision$limitations, fixed = TRUE)), "common-source uncertainty disclosed")
check(!any(c("probability", "accuracy", "confidence") %in% names(real$decision)), "no fabricated probability or performance score")
unlink(tmp, recursive = TRUE)
cat("All", checks, "draft-decision assertions passed.\n")
