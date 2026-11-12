# Evidence report integration. Submitted Rmd files are read only by read_rmd().
report_escape <- function(x) {
  x <- enc2utf8(as.character(x)); x[is.na(x)] <- "不适用"
  for (pair in list(c("&", "&amp;"), c("<", "&lt;"), c(">", "&gt;"),
      c("\"", "&quot;"), c("'", "&#39;"), c("`", "&#96;")))
    x <- gsub(pair[1L], pair[2L], x, fixed = TRUE)
  x
}

.report_module <- function(fun) {
  warnings <- character()
  value <- tryCatch(withCallingHandlers(fun(), warning = function(w) {
    warnings <<- c(warnings, conditionMessage(w)); invokeRestart("muffleWarning")
  }), error = identity)
  if (inherits(value, "error")) return(list(status = "error", error = conditionMessage(value), warnings = warnings, value = NULL))
  list(status = if (length(warnings) && value$status == "ok") "limited" else value$status,
    error = "", warnings = unique(warnings), value = value)
}

.report_run_modules <- function(docs, text_options, formula_options, code_options) {
  args <- list(doc_a = docs$A, doc_b = docs$B)
  list(
    text = .report_module(function() do.call(analyze_text_pair_approx, c(args, text_options))),
    formula_single = .report_module(function() do.call(compare_math_pair, args)),
    formula_sequence = .report_module(function() do.call(find_math_sequences, c(args, formula_options))),
    code_whole = .report_module(function() do.call(compare_code_pair, args)),
    code_local = .report_module(function() do.call(analyze_code_pair_local, c(args, code_options)))
  )
}

analyze_rmd_pair <- function(input_a, input_b, text_options = list(), formula_options = list(), code_options = list(),
    exclusions = NULL, public_reference = NULL) {
  for (options in list(text_options, formula_options, code_options)) {
    if (!is.list(options) || (length(options) && (is.null(names(options)) || any(!nzchar(names(options))) || anyDuplicated(names(options)))))
      stop("Module options must be named lists with unique names.")
  }
  if (any(c("doc_a", "doc_b") %in% c(names(text_options), names(formula_options), names(code_options))))
    stop("Input documents cannot be overridden through module options.")
  inputs <- list(A = input_a, B = input_b)
  docs <- lapply(names(inputs), function(id)
    tryCatch(read_rmd(inputs[[id]], file_id = id, keep_bytes = TRUE), error = identity))
  names(docs) <- names(inputs)
  files_identical <- if (all(vapply(docs, inherits, logical(1), "rmd_document")))
    identical(docs$A$input_bytes, docs$B$input_bytes) else NA
  for (id in names(docs)) {
    if (inherits(docs[[id]], "rmd_document")) docs[[id]]$input_bytes <- NULL
  }
  manifest <- do.call(rbind, lapply(names(inputs), function(id) {
    d <- docs[[id]]; ok <- inherits(d, "rmd_document"); path <- inputs[[id]]
    data.frame(file_id = id, filename = if (is.character(path) && length(path) == 1L && !is.na(path)) basename(path) else "无效路径",
      read_status = if (ok) "ok" else "error", characters = if (ok) d$summary$characters else NA_integer_,
      units = if (ok) nrow(d$units) else NA_integer_, diagnostics = if (ok) nrow(d$diagnostics) else NA_integer_,
      message = if (ok) "" else conditionMessage(d), stringsAsFactors = FALSE)
  }))
  skip <- function(message = "两份输入均成功读取后才运行分析。")
    list(status = "not_run", error = message, warnings = character(), value = NULL)
  modules <- setNames(lapply(seq_len(5L), function(i) skip()), c("text", "formula_single", "formula_sequence", "code_whole", "code_local"))
  requested <- !(is.null(exclusions) || identical(exclusions, ""))
  reference_requested <- !(is.null(public_reference) || identical(public_reference, ""))
  if (requested && reference_requested) stop("Use either a public Rmd reference or a CSV exclusion plan.")
  requested <- requested || reference_requested
  info <- list(status = if (requested) "not_run" else "not_requested", error = "",
    records = exclusion_empty_records(), units = data.frame())
  baseline <- NULL; analysis_docs <- docs
  if (all(manifest$read_status == "ok")) {
    if (requested) {
      baseline <- .report_run_modules(docs, text_options, formula_options, code_options)
      plan <- tryCatch(if (reference_requested) prepare_reference_exclusions(docs, public_reference) else
        prepare_document_exclusions(docs, exclusions), error = identity)
      if (inherits(plan, "error")) {
        info$status <- "error"; info$error <- conditionMessage(plan)
        modules <- lapply(modules, function(m) skip("公共来源排除配置无效，未运行排除后分析。"))
      } else {
        analysis_docs <- plan$documents; info <- plan; info$documents <- NULL
        modules <- if (info$status == "no_matches") baseline else
          .report_run_modules(analysis_docs, text_options, formula_options, code_options)
      }
    } else modules <- .report_run_modules(docs, text_options, formula_options, code_options)
  }
  statuses <- c(vapply(modules, function(m) m$status, character(1)),
    vapply(baseline, function(m) m$status, character(1)))
  overall <- if (any(manifest$read_status == "error")) "input_error" else if (info$status == "error") "exclusion_error" else
    if (any(statuses == "error")) "partial_failure" else if (any(statuses == "limited")) "limited" else "completed"
  result <- list(engine_version = "0.6.0-dev", verdict = "not_enabled", overall_status = overall,
    files_identical = files_identical,
    manifest = manifest, documents = docs, analysis_documents = analysis_docs, exclusions = info,
    baseline_modules = baseline, modules = modules,
    requested_options = list(text = text_options, formula_sequence = formula_options, code_local = code_options),
    r_version = as.character(getRversion()))
  result$evidence <- if (all(manifest$read_status == "ok") && info$status != "error")
    .report_module(function() summarize_pair_evidence(result)) else skip("输入或排除配置无效，未整理证据。")
  if (result$evidence$status == "error") result$overall_status <- "partial_failure"
  code_coverage <- supplement_short_code_coverage(modules$code_local$value, modules$code_whole$value,
    result$evidence$value$records)
  result$code_coverage_with_short <- code_coverage$coverage
  result$short_code_matches <- code_coverage$added
  result$decision <- tryCatch(evaluate_candidate_decision(result), error = function(e)
    list(status = "error", stage = "development_unvalidated", verdict = "insufficient_evidence", label = "证据不足",
      pathway = "decision_error", reasons = paste("开发规则评估失败：", conditionMessage(e)),
      limitations = "规则尚未完成效果标定；失败不视为零匹配。", rules = decision_rules_v1(),
      trigger_records = data.frame(), adequacy = data.frame()))
  if (result$decision$status == "error") result$overall_status <- "partial_failure"
  result
}

.report_table <- function(df) {
  if (!is.data.frame(df) || !nrow(df)) return("<p class='muted'>没有对应条目。</p>")
  rows <- vapply(seq_len(nrow(df)), function(i) paste0("<tr>", paste0("<td>", report_escape(vapply(df, function(col)
    if (is.na(col[i])) "不适用" else as.character(col[i]), character(1))), "</td>", collapse = ""), "</tr>"), character(1))
  paste0("<div class='table-wrap'><table><thead><tr>", paste0("<th>", report_escape(names(df)), "</th>", collapse = ""),
    "</tr></thead><tbody>", paste0(rows, collapse = ""), "</tbody></table></div>")
}
.report_pre <- function(text, max_chars = 4000L) {
  text <- paste0(text, collapse = "\n")
  clipped <- nchar(text, type = "chars") > max_chars
  paste0("<pre><code>", report_escape(substr(text, 1L, max_chars)), "</code></pre>",
    if (clipped) "<p class='muted'>展示已截断至4000字符；分析仍使用完整片段。</p>" else "")
}
.report_pair <- function(a, b, label_a = "A", label_b = "B") paste0("<div class='evidence-pair'><div><h4>",
  report_escape(label_a), "</h4>", .report_pre(a), "</div><div><h4>", report_escape(label_b), "</h4>", .report_pre(b), "</div></div>")
.report_source <- function(doc, positions) {
  positions <- positions[!is.na(positions)]
  if (!length(positions)) "" else substring(doc$source, min(positions), max(positions))
}
.report_params <- function(x, prefix = "") {
  if (!length(x)) return(data.frame(parameter = character(), value = character()))
  rows <- lapply(names(x), function(name) {
    key <- if (nzchar(prefix)) paste(prefix, name, sep = ".") else name
    if (is.list(x[[name]])) .report_params(x[[name]], key) else
      data.frame(parameter = key, value = paste(as.character(x[[name]]), collapse = ", "), stringsAsFactors = FALSE)
  })
  do.call(rbind, rows)
}


.report_scope_summary <- function(modules, stage) {
  rows <- list()
  for (name in names(modules)) {
    m <- modules[[name]]; v <- m$value
    messages <- c(m$error, m$warnings, v$approximate_error)
    messages <- paste(messages[nzchar(messages)], collapse = "; ")
    coverage <- if (name == "text" && !is.null(v$coverage_with_short)) v$coverage_with_short else
      if (name %in% c("text", "code_local")) v$coverage else NULL
    if (!is.null(coverage) && nrow(coverage)) {
      for (i in seq_len(nrow(coverage))) {
        c <- coverage[i, ]; text <- name == "text"
        rows[[length(rows) + 1L]] <- data.frame(stage = stage, method = name, side = c$side, status = m$status,
          unit = if (text) "character" else "token", comparable = c[[if (text) "comparable_chars" else "comparable_tokens"]],
          matched = c[[if (text) "matched_chars" else "matched_tokens"]], coverage = c$coverage, match_entries = NA_integer_, message = messages)
      }
    } else rows[[length(rows) + 1L]] <- data.frame(stage = stage, method = name, side = "-", status = m$status,
      unit = "match_entries", comparable = NA_integer_, matched = NA_integer_, coverage = NA_real_,
      match_entries = if (is.null(v)) NA_integer_ else nrow(v$matches), message = messages)
  }
  do.call(rbind, rows)
}

# Display existing decision data only; do not recompute or change the rules.
.report_analysis_overview <- function(result) {
  d <- result$decision
  modules <- result$modules
  reason <- if (is.null(d)) "本次没有生成候选结论。" else switch(d$pathway,
    single_text = "一处文字匹配达到复核条件。请对照下方原文，核查是否来自共同题干或引用。",
    single_math = "一处公式或推导匹配达到复核条件。请对照下方原文，核查是否属于常见解法。",
    single_code = "一处 R 代码匹配达到复核条件。请对照下方原文，核查是否使用了同一份模板或常见写法。",
    cumulative_text = "多处独立位置的文字匹配合计达到复核条件。下方列出了这些片段。",
    cumulative_code = "多处独立位置的 R 代码匹配合计达到复核条件。下方列出了这些片段。",
    cross_type_support = "不同类型的相似片段在两份作业中都出现在相近位置，值得放在一起复核。",
    input_unavailable = "至少有一份作业未能读取。请检查文件格式和编码后再试。",
    invalid_exclusion = "公共来源排除配置有误。请检查配置后再试。",
    evidence_unavailable = "本次未能整理匹配证据，请查看技术详情。",
    analysis_limited = "部分比较受限或未完成，现有证据不足以判断。",
    content_too_short = "两份作业中可用于比较的同类内容太少。",
    unresolved_matches = "发现了值得查看的相似片段，但证据不足以给出更明确的判断。",
    no_qualifying_evidence = "在本次可比较的内容中，未发现达到复核条件的相似片段。",
    decision_error = "本次未能生成候选结论，请查看技术详情。",
    "请结合下面的各项结果和原文片段复核。")
  coverage <- function(module, label, noun, matched, comparable, rows = NULL) {
    if (module$status == "not_run") return(paste0(label, "比较未运行。"))
    if (module$status == "error") return(paste0(label, "比较未完成。原因见对应分析详情。"))
    if (is.null(rows)) rows <- module$value$coverage
    if (module$status %in% c("not_applicable", "insufficient_ngrams", "insufficient_content") ||
        is.null(rows) || anyNA(rows$coverage)) {
      message <- paste0("至少有一份作业的", label, "内容不足，无法给出两侧覆盖比例。")
    } else {
      values <- sprintf("作业 %s %s%%（%d / %d）", rows$side,
        format(round(rows$coverage * 100, 1), trim = TRUE, drop0trailing = TRUE),
        rows[[matched]], rows[[comparable]])
      message <- paste0(noun, "的证据覆盖率为 ", paste(values, collapse = "，"), "。")
    }
    if (identical(module$value$approximate_status, "resource_limit")) {
      paste0(message, "近似比较超出资源上限，当前结果来自已完成的精确比较。")
    } else if (module$status == "limited") {
      paste0(message, "部分比较方式或内容受限。")
    } else message
  }
  formula <- function(module, label) switch(module$status,
    not_run = paste0(label, "未运行。"),
    error = paste0(label, "未完成。"),
    not_applicable = paste0(label, "缺少可比较的内容。"),
    insufficient_steps = "推导步骤不足，无法进行多步比较。",
    paste0(label, "找到 ", nrow(module$value$matches), " 条对应记录。",
      if (module$status == "limited") "部分比较方式或内容受限。"))
  rows <- data.frame(
    "比较内容" = c("文字", "公式", "R 代码"),
    "本次发现" = c(
      coverage(modules$text, "文字", "匹配字符", "matched_chars", "comparable_chars",
        modules$text$value$coverage_with_short),
      paste0(formula(modules$formula_single, "完整公式比较"),
        formula(modules$formula_sequence, "推导步骤比较")),
      paste0(coverage(modules$code_local, "代码", "匹配的代码元素（含变量一致改名）",
        "matched_tokens", "comparable_tokens", result$code_coverage_with_short),
        formula(modules$code_whole, "完整代码块比较"))),
    check.names = FALSE, stringsAsFactors = FALSE
  )
  exclusions <- if (identical(result$exclusions$status, "applied") && !is.null(result$exclusions$reference_name)) {
    paste0("已按公共参考排除 ", nrow(result$exclusions$units), " 个完整单元。上表仅统计剩余内容。")
  } else if (identical(result$exclusions$status, "applied")) {
    "已按提供的标注排除公共内容。上表统计排除后的结果。"
  } else if (identical(result$exclusions$status, "no_matches")) {
    "两份作业中均未找到与公共参考一致的完整单元，比较范围没有缩小。"
  } else if (identical(result$exclusions$status, "not_requested") && all(result$manifest$read_status == "ok")) {
    "本次没有排除共同题干或模板，这些内容也可能产生匹配。"
  } else ""
  files <- paste0("<div><dt>作业 ", report_escape(result$manifest$file_id),
    "</dt><dd>", report_escape(result$manifest$filename), "</dd></div>", collapse = "")
  identity_notice <- if (isTRUE(result$files_identical)) paste0(
    "<p class='notice'><strong>文件内容完全相同（100%）</strong>。已逐字节核对两份原始文件。</p>") else ""
  paste0("<dl class='report-files'>", files, "</dl>",
    identity_notice,
    "<div class='notice report-outcome'><strong>候选结论　",
    report_escape(if (is.null(d)) "未生成" else d$label), "</strong><p>", report_escape(reason),
    "</p><p class='muted'>未启用最终判定。当前规则尚未标定，结果供人工复核。</p></div>",
    .report_table(rows),
    "<p class='muted'>证据覆盖率以各自可比较的内容为分母。能唯一配对的短段落和短代码也可计入，重复片段按原文位置去重。</p>",
    if (nzchar(exclusions)) paste0("<p class='muted'>", report_escape(exclusions), "</p>"))
}

.report_conclusion_guide <- function() {
  rows <- data.frame(
    conclusion = c("疑似抄袭", "未检出明显证据", "证据不足"),
    meaning = c(
      "至少一项有效证据达到当前开发规则的较强证据条件，需要人工核查对应片段及共同来源；不能据此认定抄袭。其他模块仍可能受限。",
      "在当前支持范围内，比较内容量满足开发规则要求，且未发现达到规则条件或需要进一步复核的匹配；不代表证明无抄袭。",
      "尚无有效证据触发较强证据条件，同时存在分析受限或失败、内容量不足，或仍需复核的匹配，因此无法给出明确倾向；不等于无抄袭。"),
    stringsAsFactors = FALSE
  )
  names(rows) <- c("候选结论", "含义与使用方式")
  .report_table(rows)
}

detector_report_html <- function(result, max_evidence = 10L) {
  max_evidence <- code_positive_integer(max_evidence, "max_evidence")
  if (max_evidence > 100L) stop("max_evidence must not exceed 100.")
  if (!is.list(result) || !identical(result$verdict, "not_enabled")) stop("Expected an analyze_rmd_pair result.")
  out <- character(); add <- function(...) out <<- c(out, paste0(...))
  section <- function(title, id = NULL) {
    anchor <- if (is.null(id)) "" else paste0(" id='", report_escape(id), "'")
    add("<h2", anchor, ">", report_escape(title), "</h2>")
  }
  note <- function(text) add("<p>", report_escape(text), "</p>")
  module <- function(name) {
    m <- result$modules[[name]]
    note(paste("分析状态：", m$status))
    if (nzchar(m$error)) add("<div class='notice error'>", .report_pre(m$error), "</div>")
    if (length(m$warnings)) add(.report_pre(paste(m$warnings, collapse = "\n")))
    m$value
  }
  trigger_ids <- result$decision$trigger_records$record_id
  records <- result$evidence$value$records
  triggers <- if (length(trigger_ids)) records[match(trigger_ids, records$record_id, nomatch = 0L), , drop = FALSE] else
    empty_evidence_records()
  trigger_cards <- list()
  render_row <- function(row, title, fun) {
    parts <- c("<article class='evidence'><h4>", report_escape(title), "</h4>")
    fun(row, function(...) parts <<- c(parts, paste0(...)))
    paste0(c(parts, "</article>"), collapse = "")
  }
  evidence_rows <- function(module_name, table_name, title, fun) {
    df <- result$modules[[module_name]]$value[[table_name]]
    add("<h3>", report_escape(title), "</h3>")
    if (!nrow(df)) { note("没有达到当前规则的对应条目；这不是无抄袭结论。"); return(invisible(NULL)) }
    selected <- triggers[triggers$module == module_name & triggers$table == table_name, , drop = FALSE]
    for (j in seq_len(nrow(selected))) {
      i <- selected$source_row[j]
      id <- selected$record_id[j]
      trigger_cards[[id]] <<- render_row(df[i, , drop = FALSE], paste(id, title, i), fun)
    }
    ordinary <- setdiff(seq_len(nrow(df)), selected$source_row)
    shown <- head(ordinary, max_evidence)
    note(paste0("共 ", nrow(df), " 条，", nrow(selected), " 条触发片段在候选结论下展示；其余展示前 ",
      length(shown), " 条。条目可重叠，不作为独立证据累计。"))
    for (i in shown) add(render_row(df[i, , drop = FALSE], paste(title, i), fun))
  }
  line_pair <- function(row, a, b) .report_pair(a, b,
    paste0("A：第", row$start_line_a, "—", row$end_line_a, "行"),
    paste0("B：第", row$start_line_b, "—", row$end_line_b, "行"))
  add("<div class='detector-report'>")
  add("<section class='report-overview' aria-label='分析结果速览'>")
  section("分析结果速览")
  add(.report_analysis_overview(result))
  if (all(result$manifest$read_status == "ok")) {
    add("<nav class='report-navigation' aria-label='报告章节'>",
      "<a href='#report-text'>文字证据</a><a href='#report-formula'>公式证据</a>",
      "<a href='#report-code'>R 代码证据</a><a href='#report-diagnostics'>分析限制</a></nav>")
  }
  add("</section>")
  trigger_after <- length(out)
  if (!is.null(result$decision)) {
    d <- result$decision
    add("<details class='report-details'><summary>判定规则和技术详情</summary>")
    section("开发规则试判（未标定）")
    note(paste("规则版本：", d$rules$version, "；触发路径：", d$pathway))
    add(.report_pre(paste(d$reasons, collapse = "\n")))
    add(.report_table(d$trigger_records))
    note("以下为两侧当前可比较内容量；公式步骤和公式token只作开发规则的内容量检查，不是公式覆盖率。")
    add(.report_table(d$adequacy))
    add(.report_pre(paste(d$limitations, collapse = "\n")))
    add("<h3>开发规则参数</h3>", .report_table(.report_params(d$rules)), "</details>")
  }
  add("<details class='report-details'><summary>输入与分析概况</summary>")
  note(paste("运行状态：", result$overall_status, "；引擎：", result$engine_version, "；R：", result$r_version))
  add(.report_table(result$manifest))
  labels <- c(text = "文字", formula_single = "完整公式", formula_sequence = "公式步骤", code_whole = "完整代码", code_local = "局部代码")
  statuses <- data.frame(module = unname(labels), status = vapply(result$modules, function(m) m$status, character(1)), stringsAsFactors = FALSE)
  add(.report_table(statuses))
  note("error 表示模块未完成，不能按零相似度处理；limited 表示只分析了支持的范围。not_applicable、insufficient等状态需结合原文核查。")
  add("</details>")
  if (any(result$manifest$read_status != "ok")) {
    note("输入读取失败，本次未运行分项比较。请检查路径、Rmd扩展名及UTF-8编码后重新运行。")
    section("解析诊断与未覆盖内容")
    add("<h3>三种候选结论是什么意思</h3>", .report_conclusion_guide())
    add("</div>"); return(paste(out, collapse = "\n"))
  }
  if (!is.null(result$exclusions) && result$exclusions$status != "not_requested") {
    section("公共来源：明确标注与排除前后")
    note(paste("排除状态：", result$exclusions$status))
    if (!is.null(result$exclusions$reference_name)) {
      note(paste0("公共参考文件为 ", result$exclusions$reference_name,
        "。程序只排除规范化后与参考完全一致的完整单元。"))
    } else {
      note("来源由操作者明确标注。以下正文证据属于排除后范围，原始输入概况和诊断仍保留。")
    }
    if (nzchar(result$exclusions$error)) {
      add("<div class='notice error'>", .report_pre(result$exclusions$error), "</div>")
      note("配置未全部通过核对，没有应用任何一侧的排除；排除后分析未运行。排除前结果仅供核查。")
    }
    if (!is.null(result$baseline_modules)) add(.report_table(rbind(
      .report_scope_summary(result$baseline_modules, "排除前"),
      .report_scope_summary(result$modules, "排除后"))))
    note("排除前后的代码对照表使用局部匹配口径。报告速览另计入符合条件的短代码块。")
    records <- result$exclusions$records
    if (nrow(records)) {
      note(paste("排除记录共", nrow(records), "条；以下最多展示100条，quote最多展示4000字符，完整记录保留在分析结果中。"))
      shown <- utils::head(records, 100L); shown$quote <- substr(shown$quote, 1L, 4000L)
      add(.report_table(shown))
      note("已排除的解析单元（最多展示100行）：")
      add(.report_table(utils::head(result$exclusions$units, 100L)))
    }
    note("排除前后的分母不同，不能只比较覆盖率高低。被排除区域仍作匹配边界，未解析诊断不会因排除自动清空。")
  }
  da <- result$documents$A; db <- result$documents$B
  if (!is.null(result$evidence)) {
    add("<details class='report-details'><summary>查看匹配记录索引</summary>")
    section("证据整理：位置重叠与方法来源")
    note(paste("证据整理状态：", result$evidence$status))
    if (nzchar(result$evidence$error)) add(.report_pre(result$evidence$error))
    e <- result$evidence$value
    if (!is.null(e)) {
      note(paste("原始匹配记录", nrow(e$records), "条；位置分组", nrow(e$groups), "组；仅辅助原文比较", e$support_only_count, "条。以下表格各最多展示100行，完整记录保留在分析结果中。"))
      add(.report_table(utils::head(e$groups, 100L)))
      add(.report_table(utils::head(e$records[, c("record_id", "group_id", "kind", "module", "table", "source_row", "method", "level", "eligible", "matched_units"), drop = FALSE], 100L)))
      if (length(e$issues)) add(.report_pre(paste(e$issues, collapse = "\n")))
      note("同类记录只要在任一侧共享实际位置就归为一组。字符、token和公式步骤分开；分组不是独立性证明，也不产生综合分数。组内可能有不同对应或变量映射，不能将其拼成一个更长匹配；largest_match来自真实代表记录。unique_a/b只表示位置并集，行号范围只是外包范围。")
      note("证据仅来自当前分析范围；启用公共来源排除时，不混入排除前结果。未知语法等仅辅助原文比较不提供有效长度，不触发判定。")
    }
    add("</details>")
  }
  section("文字：字符覆盖与片段", "report-text"); text <- module("text")
  if (!is.null(text)) {
    note(paste("字符片段 Jaccard：", if (is.na(text$jaccard$similarity)) "信息不足" else format(text$jaccard$similarity, digits = 5)))
    note("以下覆盖按实际相同源字符的并集计算；替换字符、插删空位和忽略的排版标记不计覆盖。行号区间不等于整段均匹配。")
    add(.report_table(if (is.null(text$coverage_with_short)) text$coverage else text$coverage_with_short))
    evidence_rows("text", "exact_matches", "精确文字片段", function(row, add) {
      add(.report_table(row[, c("matched_chars", "start_line_a", "end_line_a", "start_line_b", "end_line_b"), drop = FALSE]))
      add(line_pair(row, .report_source(da, row$source_positions_a[[1L]]), .report_source(db, row$source_positions_b[[1L]])))
    })
    if (identical(text$approximate_status, "resource_limit")) {
      note("近似文字匹配超出资源上限，文字覆盖仅基于已完成的精确匹配。")
      add(.report_pre(text$approximate_error))
    } else {
      evidence_rows("text", "approximate_matches", "近似文字片段", function(row, add) {
        add(.report_table(row[, c("equal_chars", "alignment_columns", "similarity"), drop = FALSE]))
        add(line_pair(row, .report_source(da, row$aligned_positions_a[[1L]]), .report_source(db, row$aligned_positions_b[[1L]])))
      })
    }
    if (!is.null(text$short_matches)) evidence_rows("text", "short_matches", "短段落补充匹配", function(row, add) {
      add(.report_table(row[, c("equal_chars", "similarity"), drop = FALSE]))
      add(line_pair(row, row$text_a, row$text_b))
    })
    if (isTRUE(text$short_matching_limited)) note("短段落轻改比较超过工作量上限，已保留短段落精确匹配。")
    note("精确和近似表可能展示同一处内容；上述覆盖已经去重。近似算法受种子、窗口及每窗口一个最佳对齐限制。")
  }
  section("公式：完整表达与多步对应", "report-formula"); single <- module("formula_single")
  if (!is.null(single)) evidence_rows("formula_single", "matches", "完整公式对应", function(row, add) {
    add(.report_table(row[, c("raw_equal", "normalized_equal", "renamed_equal", "token_count", "status"), drop = FALSE]))
    a <- single$formulas_a$content[match(row$unit_id_a, single$formulas_a$unit_id)]
    b <- single$formulas_b$content[match(row$unit_id_b, single$formulas_b$unit_id)]
    add(line_pair(row, a, b)); add(.report_table(row$variable_map[[1L]]))
  })
  sequence <- module("formula_sequence")
  if (!is.null(sequence)) evidence_rows("formula_sequence", "matches", "推导步骤对应", function(row, add) {
    add(.report_table(row[, c("matched_steps", "skipped_steps", "step_similarity", "token_count"), drop = FALSE]))
    add(.report_table(row$variable_map[[1L]]))
    pairs <- row$step_pairs[[1L]]
    for (j in seq_len(nrow(pairs))) add(line_pair(pairs[j, , drop = FALSE], pairs$content_a[j], pairs$content_b[j]))
    for (side in c("a", "b")) {
      ids <- row[[paste0("skipped_units_", side)]][[1L]]
      if (length(ids)) { table <- sequence[[paste0("formulas_", side)]]
        add("<p>", report_escape(paste(toupper(side), "跳过且未计匹配的步骤：")), "</p>")
        add(.report_pre(table$content[match(ids, table$unit_id)])) }
    }
  })
  note("公式以转义后的LaTeX源码展示，不加载在线排版资源。短标准公式不单独构成抄袭结论；未计算公式覆盖率。完整公式接口与步骤接口的支持范围不同。")
  section("代码：词法与一致改名", "report-code"); whole <- module("code_whole")
  if (!is.null(whole)) {
    evidence_rows("code_whole", "matches", "完整代码单元对应", function(row, add) {
      add(.report_table(row[, c("raw_equal", "tokens_equal", "renamed_equal", "token_count", "status"), drop = FALSE]))
      add(line_pair(row, whole$code_a$content[match(row$unit_id_a, whole$code_a$unit_id)], whole$code_b$content[match(row$unit_id_b, whole$code_b$unit_id)]))
      add(.report_table(row$variable_map[[1L]]))
    })
    add("<h3>注释补充对应</h3>", .report_table(utils::head(whole$comment_matches, max_evidence)))
    note(paste("注释补充共", nrow(whole$comment_matches), "条；仅显示前", max_evidence, "条，不作为独立主要证据。"))
  }
  local <- module("code_local")
  if (!is.null(local)) {
    add("<h3>原词法 token 覆盖</h3>", .report_table(local$lexical_coverage))
    add("<h3>包含一致改名的对应 token 覆盖</h3>", .report_table(local$coverage))
    note("第二种覆盖允许变量字符不同，统计结构对应token；不是文字相同字符覆盖，不能与字符数或公式步骤数相加。")
    if (!is.null(result$short_code_matches) && result$short_code_matches > 0L) {
      add("<h3>加入短代码块后的覆盖</h3>", .report_table(result$code_coverage_with_short))
      note(paste("短代码补充来自", result$short_code_matches, "对唯一对应的完整代码块。可在上方核对原文。"))
    }
    evidence_rows("code_local", "matches", "局部代码对应", function(row, add) {
      add(.report_table(row[, c("method", "matched_statements", "matched_tokens", "skipped_statements", "skipped_tokens", "alignment_ratio"), drop = FALSE]))
      add(.report_table(row$variable_map[[1L]])); pairs <- row$statement_pairs[[1L]]
      for (j in seq_len(nrow(pairs))) add(line_pair(pairs[j, , drop = FALSE], pairs$content_a[j], pairs$content_b[j]))
      for (side in c("a", "b")) {
        ids <- row[[paste0("skipped_statements_", side)]][[1L]]
        if (length(ids)) { table <- local[[paste0("statements_", side)]]
          add("<p>", report_escape(paste(toupper(side), "跳过且未计覆盖的语句：")), "</p>")
          add(.report_pre(table$content[match(ids, table$statement_id)])) }
      }
    })
    note("只按顶层完整语句匹配，不进入函数/循环内部查找局部片段。完整单元与局部表可能重叠；覆盖按源token位置去重。")
  }
  section("解析诊断与未覆盖内容", "report-diagnostics")
  add("<h3>三种候选结论是什么意思</h3>", .report_conclusion_guide())
  note("候选结论与运行状态分别解释：limited 表示分析范围受限，并不直接决定结论；已有有效较强证据时仍可给出候选疑似。以下诊断说明具体限制。")
  for (id in c("A", "B")) { add("<h3>", id, " 的解析诊断</h3>", .report_table(utils::head(result$documents[[id]]$diagnostics, 100L))) }
  for (name in c("formula_single", "formula_sequence", "code_whole", "code_local")) {
    value <- result$modules[[name]]$value
    if (is.null(value)) next
    for (side in c("a", "b")) {
      units <- value[[paste0(if (startsWith(name, "formula")) "formulas_" else "code_", side)]]
      rows <- lapply(seq_len(nrow(units)), function(i) {
        issues <- units$details[[i]]$issues
        if (!length(issues)) return(NULL)
        data.frame(side = toupper(side), unit_id = units$unit_id[i], line = units$start_line[i], issue = paste(issues, collapse = "; "))
      })
      rows <- Filter(Negate(is.null), rows)
      if (length(rows)) { note(paste(labels[[name]], toupper(side), "的受限诊断共", length(rows), "条：")); add(.report_table(utils::head(do.call(rbind, rows), 100L))) }
    }
  }
  note("诊断表最多展示100条。图片内容、外部资源、复杂语法和未成功解析区域不视为已分析；标准解法仍需核查；共同题干仅在提供有效人工标注时排除。")
  section("本次参数与方法边界")
  add(.report_table(.report_params(result$requested_options)))
  for (name in names(result$modules)) {
    value <- result$modules[[name]]$value
    if (is.null(value)) next
    parameters <- value$parameters
    if (is.null(parameters) && name == "formula_single") parameters <- list(max_pairs = value$max_pairs)
    if (length(parameters)) { add("<h3>", report_escape(labels[[name]]), "</h3>", .report_table(.report_params(parameters))) }
  }
  note(paste("普通片段每类最多展示", max_evidence, "条；触发片段单独展示。展示截断不改变分析或覆盖结果。参数只是当前开发默认值，尚未作检测能力标定。"))
  note("本版本尚未实现最终判断规则、自动公共来源识别、公式覆盖及开发/保留集效果评估。公共来源仅按有效人工标注排除。高覆盖可能来自共同来源或标准解法；低覆盖可能来自语法限制或改写。请结合原文核查。")
  add("</div>")
  if (length(trigger_cards)) out <- append(out, c("<h3>触发结论的原文片段</h3>",
    unlist(trigger_cards[trigger_ids], use.names = FALSE)), after = trigger_after)
  paste(out, collapse = "\n")
}
