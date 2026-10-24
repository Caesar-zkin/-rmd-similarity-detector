# Draft tri-state rules over existing evidence. Not calibrated or enabled as final verdict.
decision_rules_v1 <- function() list(version = "development-v1",
  text_min_similarity = 0.9, code_min_similarity = 0.8, formula_min_step_similarity = 0.75,
  text_strong_chars = 100L, text_medium_chars = 60L, text_review_chars = 30L,
  text_cumulative_chars = 120L, code_strong_tokens = 60L, code_renamed_strong_tokens = 80L,
  code_medium_tokens = 40L, code_renamed_medium_tokens = 60L, code_review_tokens = 20L,
  code_cumulative_tokens = 100L, code_renamed_cumulative_tokens = 160L,
  formula_strong_steps = 4L, formula_strong_tokens = 40L,
  formula_renamed_strong_steps = 5L, formula_renamed_strong_tokens = 60L,
  formula_medium_steps = 2L, formula_medium_tokens = 20L, formula_renamed_medium_tokens = 30L,
  cumulative_min_groups = 2L, cumulative_min_coverage = 0.3, context_max_line_gap = 10L)

validate_decision_rules <- function(rules) {
  expected <- names(decision_rules_v1())
  if (!is.list(rules) || is.null(names(rules)) || anyDuplicated(names(rules)) ||
      !setequal(names(rules), expected)) stop("Decision rules need the complete, uniquely named draft schema.")
  if (!is.character(rules$version) || length(rules$version) != 1L || is.na(rules$version) || !nzchar(rules$version))
    stop("Decision rule version must be a nonempty string.")
  rates <- c("text_min_similarity", "code_min_similarity", "formula_min_step_similarity", "cumulative_min_coverage")
  for (name in setdiff(expected, c("version", rates, "context_max_line_gap")))
    rules[[name]] <- code_positive_integer(rules[[name]], name)
  for (name in rates) {
    x <- rules[[name]]
    if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) || x < 0 || x > 1)
      stop(name, " must lie in [0,1].")
  }
  gap <- rules$context_max_line_gap
  if (!is.numeric(gap) || length(gap) != 1L || is.na(gap) || !is.finite(gap) ||
      gap < 0 || gap != floor(gap) || gap > .Machine$integer.max) stop("Invalid context line gap.")
  if (rules$cumulative_min_groups < 2L || rules$text_strong_chars < rules$text_medium_chars ||
      rules$text_medium_chars < rules$text_review_chars || rules$code_medium_tokens < rules$code_review_tokens ||
      rules$code_strong_tokens < rules$code_medium_tokens ||
      rules$code_renamed_strong_tokens < rules$code_strong_tokens ||
      rules$code_renamed_medium_tokens < rules$code_medium_tokens ||
      rules$code_renamed_strong_tokens < rules$code_renamed_medium_tokens ||
      rules$formula_strong_steps < rules$formula_medium_steps ||
      rules$formula_strong_tokens < rules$formula_medium_tokens ||
      rules$formula_renamed_strong_steps < rules$formula_strong_steps ||
      rules$formula_renamed_strong_tokens < rules$formula_strong_tokens ||
      rules$formula_renamed_medium_tokens < rules$formula_medium_tokens ||
      rules$formula_renamed_strong_tokens < rules$formula_renamed_medium_tokens ||
      rules$text_cumulative_chars < rules$text_medium_chars * rules$cumulative_min_groups ||
      rules$code_cumulative_tokens < rules$code_medium_tokens * rules$cumulative_min_groups ||
      rules$code_renamed_cumulative_tokens < rules$code_renamed_medium_tokens * rules$cumulative_min_groups)
    stop("Decision threshold hierarchy is inconsistent.")
  rules
}

evaluate_candidate_decision <- function(result, rules = decision_rules_v1(), max_support_checks = 100000L) {
  rules <- validate_decision_rules(rules)
  max_support_checks <- code_positive_integer(max_support_checks, "max_support_checks")
  limitations <- c("开发规则未经独立答案及保留集效果标定，不是已验证的最终判定。",
    "相似内容可能来自共同题干、标准解法或其他公共来源；不能证明抄袭或复制方向。")
  if (result$exclusions$status == "applied") limitations <- c(limitations, "已按操作者标注排除公共来源；程序不验证其来源真实性。") else
    limitations <- c(limitations, "未应用公共来源排除，共同内容仍可能触发开发试判。")
  empty_triggers <- data.frame(record_id = character(), group_id = character(), kind = character(),
    method = character(), level = character(), matched_units = integer(), content_tokens = integer(),
    similarity = numeric(), stringsAsFactors = FALSE)
  adequacy <- data.frame(kind = character(), unit = character(), comparable_a = numeric(),
    comparable_b = numeric(), required = numeric(), sufficient = logical(), stringsAsFactors = FALSE)
  finish <- function(verdict, pathway, reasons, trigger = NULL) {
    labels <- c(suspected = "疑似抄袭", no_clear_evidence = "未检出明显证据", insufficient_evidence = "证据不足")
    if (is.null(trigger)) trigger <- empty_triggers else
      trigger <- trigger[, names(empty_triggers), drop = FALSE]
    list(status = "ok", stage = "development_unvalidated", verdict = verdict, label = unname(labels[verdict]),
      pathway = pathway, reasons = reasons, limitations = limitations, rules = rules,
      trigger_records = trigger, adequacy = adequacy, max_support_checks = max_support_checks)
  }
  if (any(result$manifest$read_status != "ok"))
    return(finish("insufficient_evidence", "input_unavailable", "至少一份输入未成功读取，没有可用于比较的两份完整输入。"))
  if (result$exclusions$status == "error")
    return(finish("insufficient_evidence", "invalid_exclusion", "公共来源排除标注未通过，排除后分析没有运行。"))
  if (is.null(result$evidence$value) || result$evidence$status %in% c("error", "not_run"))
    return(finish("insufficient_evidence", "evidence_unavailable", "证据整理未完成，不能用缺失结果替代零匹配。"))
  evidence <- result$evidence$value; records <- evidence$records
  flags <- vapply(result$modules, function(m) m$status, character(1))
  incomplete <- any(flags %in% c("limited", "error", "not_run")) || result$evidence$status == "limited" ||
    result$overall_status %in% c("limited", "partial_failure")
  if (incomplete) limitations <- c(limitations, paste("存在受限或未完成分析；当前模块状态：", paste(names(flags), flags, collapse = "; ")))
  denominator <- function(kind) {
    value <- result$modules[[if (kind == "text") "text" else "code_local"]]$value
    column <- if (kind == "text") "comparable_chars" else "comparable_tokens"
    if (is.null(value) || !is.data.frame(value$coverage)) return(c(A = NA_real_, B = NA_real_))
    setNames(vapply(c("A", "B"), function(side) {
      x <- value$coverage[[column]][value$coverage$side == side]
      if (length(x) == 1L) as.numeric(x) else NA_real_
    }, numeric(1)), c("A", "B"))
  }
  text_denominator <- denominator("text"); code_denominator <- denominator("code")
  math <- result$modules$formula_sequence$value
  math_count <- function(tokens = FALSE) setNames(vapply(c("a", "b"), function(side) {
    if (is.null(math)) return(NA_real_)
    u <- math[[paste0("formulas_", side)]]; ok <- u$math_status == "ok" & u$token_count > 0L
    if (tokens) as.numeric(sum(u$token_count[ok])) else as.numeric(sum(ok))
  }, numeric(1)), c("A", "B"))
  math_steps <- math_count(); math_tokens <- math_count(TRUE)
  add_adequacy <- function(kind, unit, values, required) data.frame(kind = kind, unit = unit,
    comparable_a = values[1L], comparable_b = values[2L], required = required,
    sufficient = isTRUE(all(values >= required)), row.names = NULL)
  adequacy <- rbind(add_adequacy("text", "character", text_denominator, rules$text_medium_chars),
    add_adequacy("code", "token", code_denominator, rules$code_medium_tokens),
    add_adequacy("math", "step", math_steps, rules$formula_strong_steps),
    add_adequacy("math", "token", math_tokens, rules$formula_strong_tokens))
  sufficient <- adequacy$sufficient[1L] || adequacy$sufficient[2L] || all(adequacy$sufficient[3:4])
  quality_required <- ifelse(records$kind == "text", rules$text_min_similarity,
    ifelse(records$kind == "code", rules$code_min_similarity, rules$formula_min_step_similarity))
  r <- records[records$eligible & records$similarity >= quality_required, , drop = FALSE]
  if (anyNA(r$group_id)) stop("Eligible evidence lacks position groups.")
  if (nrow(r)) r <- r[order(-r$matched_units, r$record_id), , drop = FALSE]
  renamed <- r$level == "renamed"
  strong <- (r$kind == "text" & r$matched_units >= rules$text_strong_chars) |
    (r$kind == "code" & r$matched_units >= ifelse(renamed, rules$code_renamed_strong_tokens, rules$code_strong_tokens)) |
    (r$kind == "math" & r$matched_units >= ifelse(renamed, rules$formula_renamed_strong_steps, rules$formula_strong_steps) &
      !is.na(r$content_tokens) & r$content_tokens >= ifelse(renamed, rules$formula_renamed_strong_tokens, rules$formula_strong_tokens))
  if (any(strong)) {
    chosen <- r[which(strong)[1L], , drop = FALSE]
    return(finish("suspected", paste0("single_", chosen$kind),
      paste("单处匹配达到当前开发长度及相似条件；核查原始记录", chosen$record_id, "，内容类型", chosen$kind, "。"), chosen))
  }
  medium <- (r$kind == "text" & r$matched_units >= rules$text_medium_chars) |
    (r$kind == "code" & r$matched_units >= ifelse(renamed, rules$code_renamed_medium_tokens, rules$code_medium_tokens)) |
    (r$kind == "math" & r$matched_units >= rules$formula_medium_steps & !is.na(r$content_tokens) &
      r$content_tokens >= ifelse(renamed, rules$formula_renamed_medium_tokens, rules$formula_medium_tokens))
  medium <- r[medium, , drop = FALSE]
  # Select real records from distinct position groups. Never use group unions as a single match.
  for (kind in c("text", "code")) {
    available <- medium[medium$kind == kind, , drop = FALSE]
    selections <- if (kind == "code") list(available[available$level != "renamed", , drop = FALSE], available) else list(available)
    for (candidates in selections) {
    candidates <- candidates[!duplicated(candidates$group_id), , drop = FALSE]
    if (nrow(candidates) < rules$cumulative_min_groups) next
    d <- if (kind == "text") text_denominator else code_denominator
    if (anyNA(d) || any(d <= 0)) next
    n <- vapply(c("a", "b"), function(side)
      length(unique(unlist(candidates[[paste0("positions_", side)]], use.names = FALSE))), integer(1))
    coverage <- n / d
    if (any(coverage > 1)) stop("Candidate coverage exceeds its comparable denominator.")
    minimum <- if (kind == "text") rules$text_cumulative_chars else
      if (any(candidates$level == "renamed")) rules$code_renamed_cumulative_tokens else rules$code_cumulative_tokens
    if (all(n >= minimum) && any(coverage >= rules$cumulative_min_coverage))
      return(finish("suspected", paste0("cumulative_", kind),
        paste("多个非重叠位置组达到开发累计条件；实际对应数量A/B：", paste(n, collapse = "/"),
          "；当前范围覆盖A/B：", paste(format(coverage, digits = 3), collapse = "/"), "。"), candidates))
    }
  }
  # Cross-type support is a conjunction of two methods, never an average or unit sum.
  gap <- function(a_start, a_end, b_start, b_end) max(0L, b_start - a_end - 1L, a_start - b_end - 1L)
  line_starts <- lapply(result$analysis_documents, function(doc) {
    c(1L, which(strsplit(doc$source, "", fixed = TRUE)[[1L]] == "\n") + 1L)
  })
  line_cache <- new.env(parent = emptyenv()); step_cache <- list()
  matched_lines <- function(row) {
    id <- row$record_id
    if (exists(id, line_cache, inherits = FALSE)) return(line_cache[[id]])
    positions <- list(a = row$positions_a[[1L]], b = row$positions_b[[1L]])
    bounds <- list()
    for (side in c("a", "b")) {
      if (row$kind == "math") {
        if (is.null(step_cache[[side]])) step_cache[[side]] <<- if (!is.null(math)) math[[paste0("formulas_", side)]] else
          prepare_math_steps(result$analysis_documents[[toupper(side)]])
        u <- step_cache[[side]]; index <- match(positions[[side]], u$unit_id)
        if (anyNA(index)) stop("Decision context references unknown formula steps.")
        bounds[[side]] <- data.frame(start = u$start_line[index], end = u$end_line[index])
      } else {
        lines <- findInterval(positions[[side]], line_starts[[toupper(side)]])
        bounds[[side]] <- data.frame(start = lines, end = lines)
      }
    }
    out <- unique(data.frame(start_a = bounds$a$start, end_a = bounds$a$end,
      start_b = bounds$b$start, end_b = bounds$b$end))
    line_cache[[id]] <- out; out
  }
  work <- 0
  near <- function(i, j) {
    a <- matched_lines(medium[i, , drop = FALSE]); b <- matched_lines(medium[j, , drop = FALSE])
    for (k in seq_len(nrow(a))) {
      work <<- work + nrow(b)
      if (work > max_support_checks) stop("Decision context work resource limit exceeded; no negative conclusion produced.")
      close_a <- b$start_a <= as.double(a$end_a[k]) + rules$context_max_line_gap + 1 &
        b$end_a >= as.double(a$start_a[k]) - rules$context_max_line_gap - 1
      close_b <- b$start_b <= as.double(a$end_b[k]) + rules$context_max_line_gap + 1 &
        b$end_b >= as.double(a$start_b[k]) - rules$context_max_line_gap - 1
      if (any(close_a & close_b)) return(TRUE)
    }
    FALSE
  }
  by_kind <- split(seq_len(nrow(medium)), medium$kind)
  kinds <- names(by_kind)
  if (length(kinds) >= 2L) for (ka in seq_len(length(kinds) - 1L)) for (kb in seq.int(ka + 1L, length(kinds))) {
    # Bound prefix scans and actual paired-line checks; never materialize an unbounded Cartesian join.
    ia <- by_kind[[kinds[ka]]]; ib <- by_kind[[kinds[kb]]]
    ib <- ib[order(medium$start_line_a[ib], medium$record_id[ib])]
    starts <- medium$start_line_a[ib]
    for (i in ia) {
      hi <- findInterval(as.double(medium$end_line_a[i]) + rules$context_max_line_gap + 1, starts)
      if (!hi) next
      work <- work + hi
      if (work > max_support_checks) stop("Decision context work resource limit exceeded; no negative conclusion produced.")
      js <- ib[seq_len(hi)]
      js <- js[medium$end_line_a[js] >= medium$start_line_a[i] - rules$context_max_line_gap - 1]
      for (j in js) if (gap(medium$start_line_b[i], medium$end_line_b[i], medium$start_line_b[j], medium$end_line_b[j]) <= rules$context_max_line_gap && near(i, j))
        return(finish("suspected", "cross_type_support",
          "两类达标片段在两份作业中均位于邻近范围，形成开发规则的联合支持；单位没有相加，映射没有合并。", medium[c(i, j), , drop = FALSE]))
    }
  }
  if (incomplete) return(finish("insufficient_evidence", "analysis_limited", "未触发较强证据路径，且存在分析受限或失败，不能据此给出未检出结论。"))
  if (!sufficient) return(finish("insufficient_evidence", "content_too_short", "两侧同类可比较内容不足当前开发要求；高覆盖或原文相同不能替代有效内容量。"))
  review <- records[records$eligible, , drop = FALSE]
  unresolved <- nrow(medium) > 0L || any(review$kind == "text" & review$matched_units >= rules$text_review_chars) ||
    any(review$kind == "code" & review$matched_units >= rules$code_review_tokens) ||
    any(review$kind == "math" & review$matched_units >= rules$formula_medium_steps & !is.na(review$content_tokens) & review$content_tokens >= rules$formula_medium_tokens)
  if (unresolved) return(finish("insufficient_evidence", "unresolved_matches", "存在值得核查的匹配，但未满足单处、累计或跨类型支持条件；未达候选相似门槛的局部片段也不冒充零匹配。"))
  finish("no_clear_evidence", "no_qualifying_evidence", "当前可比较内容达到开发最低要求，已完成范围内未检出满足候选规则的明显证据；不代表证明无抄袭。")
}
