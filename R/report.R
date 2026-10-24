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

analyze_rmd_pair <- function(input_a, input_b, text_options = list(), formula_options = list(), code_options = list(), exclusions = NULL) {
  for (options in list(text_options, formula_options, code_options)) {
    if (!is.list(options) || (length(options) && (is.null(names(options)) || any(!nzchar(names(options))) || anyDuplicated(names(options)))))
      stop("Module options must be named lists with unique names.")
  }
  if (any(c("doc_a", "doc_b") %in% c(names(text_options), names(formula_options), names(code_options))))
    stop("Input documents cannot be overridden through module options.")
  inputs <- list(A = input_a, B = input_b)
  docs <- lapply(names(inputs), function(id) tryCatch(read_rmd(inputs[[id]], file_id = id), error = identity))
  names(docs) <- names(inputs)
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
  info <- list(status = if (requested) "not_run" else "not_requested", error = "",
    records = exclusion_empty_records(), units = data.frame())
  baseline <- NULL; analysis_docs <- docs
  if (all(manifest$read_status == "ok")) {
    if (requested) {
      baseline <- .report_run_modules(docs, text_options, formula_options, code_options)
      plan <- tryCatch(prepare_document_exclusions(docs, exclusions), error = identity)
      if (inherits(plan, "error")) {
        info$status <- "error"; info$error <- conditionMessage(plan)
        modules <- lapply(modules, function(m) skip("公共来源排除配置无效，未运行排除后分析。"))
      } else {
        analysis_docs <- plan$documents; info <- plan; info$documents <- NULL
        modules <- .report_run_modules(analysis_docs, text_options, formula_options, code_options)
      }
    } else modules <- .report_run_modules(docs, text_options, formula_options, code_options)
  }
  statuses <- c(vapply(modules, function(m) m$status, character(1)),
    vapply(baseline, function(m) m$status, character(1)))
  overall <- if (any(manifest$read_status == "error")) "input_error" else if (info$status == "error") "exclusion_error" else
    if (any(statuses == "error")) "partial_failure" else if (any(statuses == "limited")) "limited" else "completed"
  list(engine_version = "0.6.0-dev", verdict = "not_enabled", overall_status = overall,
    manifest = manifest, documents = docs, analysis_documents = analysis_docs, exclusions = info,
    baseline_modules = baseline, modules = modules,
    requested_options = list(text = text_options, formula_sequence = formula_options, code_local = code_options),
    r_version = as.character(getRversion()))
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
    messages <- c(m$error, m$warnings); messages <- paste(messages[nzchar(messages)], collapse = "; ")
    coverage <- if (name %in% c("text", "code_local")) v$coverage else NULL
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

detector_report_html <- function(result, max_evidence = 10L) {
  max_evidence <- code_positive_integer(max_evidence, "max_evidence")
  if (max_evidence > 100L) stop("max_evidence must not exceed 100.")
  if (!is.list(result) || !identical(result$verdict, "not_enabled")) stop("Expected an analyze_rmd_pair result.")
  out <- character(); add <- function(...) out <<- c(out, paste0(...))
  section <- function(title) add("<h2>", report_escape(title), "</h2>")
  note <- function(text) add("<p>", report_escape(text), "</p>")
  module <- function(name) {
    m <- result$modules[[name]]
    note(paste("分析状态：", m$status))
    if (nzchar(m$error)) add("<div class='notice error'>", .report_pre(m$error), "</div>")
    if (length(m$warnings)) add(.report_pre(paste(m$warnings, collapse = "\n")))
    m$value
  }
  evidence_rows <- function(df, title, fun) {
    add("<h3>", report_escape(title), "</h3>")
    if (!nrow(df)) { note("没有达到当前规则的对应条目；这不是无抄袭结论。"); return(invisible(NULL)) }
    n <- min(nrow(df), max_evidence)
    note(paste0("共 ", nrow(df), " 条，展示前 ", n, " 条；可重叠，不作为独立证据累计。"))
    for (i in seq_len(n)) {
      add("<article class='evidence'><h4>", report_escape(paste(title, i)), "</h4>")
      fun(df[i, , drop = FALSE]); add("</article>")
    }
  }
  line_pair <- function(row, a, b) .report_pair(a, b,
    paste0("A：第", row$start_line_a, "—", row$end_line_a, "行"),
    paste0("B：第", row$start_line_b, "—", row$end_line_b, "行"))
  add("<div class='detector-report'>")
  add("<div class='notice'><strong>未启用最终判定</strong><p>本报告提供相似片段及定位，不能证明抄袭、复制方向或数学/程序语义等价。参数尚未标定，不输出抄袭概率，也不平均三类指标。</p></div>")
  note(paste("运行状态：", result$overall_status, "；引擎：", result$engine_version, "；R：", result$r_version))
  section("输入与分析概况"); add(.report_table(result$manifest))
  labels <- c(text = "文字", formula_single = "完整公式", formula_sequence = "公式步骤", code_whole = "完整代码", code_local = "局部代码")
  statuses <- data.frame(module = unname(labels), status = vapply(result$modules, function(m) m$status, character(1)), stringsAsFactors = FALSE)
  add(.report_table(statuses))
  note("error 表示模块未完成，不能按零相似度处理；limited 表示只分析了支持的范围。not_applicable、insufficient等状态需结合原文核查。")
  if (any(result$manifest$read_status != "ok")) {
    note("输入读取失败，本次未运行分项比较。请检查路径、Rmd扩展名及UTF-8编码后重新运行。")
    add("</div>"); return(paste(out, collapse = "\n"))
  }
  if (!is.null(result$exclusions) && result$exclusions$status != "not_requested") {
    section("公共来源：明确标注与排除前后")
    note(paste("排除状态：", result$exclusions$status))
    note("来源由操作者明确标注；本程序不验证来源真实性，不根据共有内容自动排除。以下正文证据属于排除后范围，原始输入概况和诊断仍保留。")
    if (nzchar(result$exclusions$error)) {
      add("<div class='notice error'>", .report_pre(result$exclusions$error), "</div>")
      note("配置未全部通过核对，没有应用任何一侧的排除；排除后分析未运行。排除前结果仅供核查。")
    }
    if (!is.null(result$baseline_modules)) add(.report_table(rbind(
      .report_scope_summary(result$baseline_modules, "排除前"),
      .report_scope_summary(result$modules, "排除后"))))
    records <- result$exclusions$records
    if (nrow(records)) {
      note(paste("排除记录共", nrow(records), "条；以下最多展示100条，quote最多展示4000字符，完整记录保留在分析结果中。"))
      shown <- utils::head(records, 100L); shown$quote <- substr(shown$quote, 1L, 4000L)
      add(.report_table(shown))
      note("已排除的解析单元（最多展示100行）：")
      add(.report_table(utils::head(result$exclusions$units, 100L)))
    }
    note("排除前后的分母不同，不能只比较覆盖率高低。被排除区域仍作匹配边界，未解析诊断不会因排除自动清空。")
  } else note("未启用公共来源排除；共同题干仍可能形成匹配。")
  da <- result$documents$A; db <- result$documents$B
  section("文字：字符覆盖与片段"); text <- module("text")
  if (!is.null(text)) {
    note(paste("字符片段 Jaccard：", if (is.na(text$jaccard$similarity)) "信息不足" else format(text$jaccard$similarity, digits = 5)))
    note("以下覆盖按实际相同源字符的并集计算；替换字符、插删空位和忽略的排版标记不计覆盖。行号区间不等于整段均匹配。")
    add(.report_table(text$coverage))
    evidence_rows(text$exact_matches, "精确文字片段", function(row) {
      add(.report_table(row[, c("matched_chars", "start_line_a", "end_line_a", "start_line_b", "end_line_b"), drop = FALSE]))
      add(line_pair(row, .report_source(da, row$source_positions_a[[1L]]), .report_source(db, row$source_positions_b[[1L]])))
    })
    evidence_rows(text$approximate_matches, "近似文字片段", function(row) {
      add(.report_table(row[, c("equal_chars", "alignment_columns", "similarity"), drop = FALSE]))
      add(line_pair(row, .report_source(da, row$aligned_positions_a[[1L]]), .report_source(db, row$aligned_positions_b[[1L]])))
    })
    note("精确和近似表可能展示同一处内容；上述覆盖已经去重。近似算法受种子、窗口及每窗口一个最佳对齐限制。")
  }
  section("公式：完整表达与多步对应"); single <- module("formula_single")
  if (!is.null(single)) evidence_rows(single$matches, "完整公式对应", function(row) {
    add(.report_table(row[, c("raw_equal", "normalized_equal", "renamed_equal", "token_count", "status"), drop = FALSE]))
    a <- single$formulas_a$content[match(row$unit_id_a, single$formulas_a$unit_id)]
    b <- single$formulas_b$content[match(row$unit_id_b, single$formulas_b$unit_id)]
    add(line_pair(row, a, b)); add(.report_table(row$variable_map[[1L]]))
  })
  sequence <- module("formula_sequence")
  if (!is.null(sequence)) evidence_rows(sequence$matches, "推导步骤对应", function(row) {
    add(.report_table(row[, c("matched_steps", "skipped_steps", "step_similarity", "token_count"), drop = FALSE]))
    add(.report_table(row$variable_map[[1L]]))
    pairs <- row$step_pairs[[1L]]
    for (j in seq_len(nrow(pairs))) add(line_pair(pairs[j, , drop = FALSE], pairs$content_a[j], pairs$content_b[j]))
    for (side in c("a", "b")) {
      ids <- row[[paste0("skipped_units_", side)]][[1L]]
      if (length(ids)) { table <- sequence[[paste0("formulas_", side)]]
        note(paste(toupper(side), "跳过且未计匹配的步骤：")); add(.report_pre(table$content[match(ids, table$unit_id)])) }
    }
  })
  note("公式以转义后的LaTeX源码展示，不加载在线排版资源。短标准公式不单独构成抄袭结论；未计算公式覆盖率。完整公式接口与步骤接口的支持范围不同。")
  section("代码：词法与一致改名"); whole <- module("code_whole")
  if (!is.null(whole)) {
    evidence_rows(whole$matches, "完整代码单元对应", function(row) {
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
    evidence_rows(local$matches, "局部代码对应", function(row) {
      add(.report_table(row[, c("method", "matched_statements", "matched_tokens", "skipped_statements", "skipped_tokens", "alignment_ratio"), drop = FALSE]))
      add(.report_table(row$variable_map[[1L]])); pairs <- row$statement_pairs[[1L]]
      for (j in seq_len(nrow(pairs))) add(line_pair(pairs[j, , drop = FALSE], pairs$content_a[j], pairs$content_b[j]))
      for (side in c("a", "b")) {
        ids <- row[[paste0("skipped_statements_", side)]][[1L]]
        if (length(ids)) { table <- local[[paste0("statements_", side)]]
          note(paste(toupper(side), "跳过且未计覆盖的语句：")); add(.report_pre(table$content[match(ids, table$statement_id)])) }
      }
    })
    note("只按顶层完整语句匹配，不进入函数/循环内部查找局部片段。完整单元与局部表可能重叠；覆盖按源token位置去重。")
  }
  section("解析诊断与未覆盖内容")
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
  note(paste("每类最多展示", max_evidence, "条；展示截断不改变分析或覆盖结果。参数只是当前开发默认值，尚未作检测能力标定。"))
  note("本版本尚未实现最终判断规则、自动公共来源识别、公式覆盖及开发/保留集效果评估。公共来源仅按有效人工标注排除。高覆盖可能来自共同来源或标准解法；低覆盖可能来自语法限制或改写。请结合原文核查。")
  add("</div>")
  paste(out, collapse = "\n")
}
