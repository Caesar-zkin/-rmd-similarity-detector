# Formula comparison foundation. Never evaluate TeX, R or symbolic expressions.
math_one_string <- function(x) {
  if (!is.character(x) || length(x) != 1L || is.na(x))
    stop("formula must be one non-missing character string.")
}

normalize_math <- function(formula) {
  math_one_string(formula)
  chars <- strsplit(enc2utf8(formula), "", fixed = TRUE)[[1L]]
  n <- length(chars)
  if (n > 20000L) stop("Formula character limit exceeded (20000).")
  tokens <- character(); kinds <- character(); positions <- list()
  issues <- character(); depth <- 0L
  add <- function(value, kind, ids) {
    tokens <<- c(tokens, value); kinds <<- c(kinds, kind)
    positions[[length(positions) + 1L]] <<- as.integer(ids)
  }
  greek <- c("alpha", "beta", "gamma", "delta", "epsilon", "varepsilon",
    "zeta", "eta", "theta", "vartheta", "iota", "kappa", "lambda", "mu",
    "nu", "xi", "pi", "varpi", "rho", "varrho", "sigma", "varsigma",
    "tau", "upsilon", "phi", "varphi", "chi", "psi", "omega",
    "Gamma", "Delta", "Theta", "Lambda", "Xi", "Pi", "Sigma", "Upsilon", "Phi", "Psi", "Omega")
  layout <- c("left", "right", "big", "Big", "bigg", "Bigg", "bigl", "bigr",
    "Bigl", "Bigr", "biggl", "biggr", "Biggl", "Biggr", "quad", "qquad", "enspace", "thinspace")
  fixed <- c("frac", "sqrt", "sum", "prod", "int", "iint", "lim", "sin", "cos", "tan",
    "log", "ln", "exp", "min", "max", "sup", "inf", "det", "Pr", "bar", "hat",
    "widehat", "tilde", "widetilde", "overline", "underline", "vec", "dot", "ddot",
    "le", "leq", "ge", "geq", "ne", "neq", "approx", "sim", "equiv", "in", "notin",
    "subset", "subseteq", "cup", "cap", "cdot", "times", "div", "pm", "mp", "infty",
    "partial", "nabla", "forall", "exists", "to", "rightarrow", "Rightarrow", "langle",
    "rangle", "lvert", "rvert", "vert", "Vert", "ldots", "cdots", "dots")
  literal <- c("text", "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "mathcal", "mathbb", "operatorname")
  p <- 1L
  while (p <= n) {
    ch <- chars[p]
    if (ch %in% c(" ", "\t", "\n", "\r", "\f", "\v")) { p <- p + 1L; next }
    if (ch == "\\") {
      start <- p; p <- p + 1L
      if (p > n) { issues <- c(issues, "trailing_backslash"); add("\\", "fixed", start); next }
      if (grepl("^[A-Za-z]$", chars[p])) {
        j <- p
        while (p <= n && grepl("^[A-Za-z]$", chars[p])) p <- p + 1L
        name <- paste0(chars[seq.int(j, p - 1L)], collapse = "")
        if (name %in% layout) next
        if (name %in% c("dfrac", "tfrac")) name <- "frac"
        if (name %in% literal) {
          # Preserve text/font payload literally, including words and spaces.
          q <- p
          while (q <= n && chars[q] %in% c(" ", "\t", "\n", "\r")) q <- q + 1L
          if (q <= n && chars[q] == "{") {
            level <- 1L; j <- q + 1L
            while (j <= n && level > 0L) {
              if (chars[j] == "\\" && j < n) { j <- j + 2L; next }
              if (chars[j] == "{") level <- level + 1L
              if (chars[j] == "}") level <- level - 1L
              j <- j + 1L
            }
            if (level == 0L) {
              add(paste0("\\", name), "fixed", seq.int(start, p - 1L))
              add(paste0(chars[seq.int(q, j - 1L)], collapse = ""), "literal", seq.int(q, j - 1L))
              p <- j; next
            }
          }
          issues <- c(issues, "invalid_literal_group")
        } else if (!name %in% c(greek, fixed)) {
          issues <- c(issues, paste0("unsupported_command:", name))
        }
        add(paste0("\\", name), if (name %in% greek) "variable" else "fixed", seq.int(start, p - 1L))
      } else {
        symbol <- chars[p]; p <- p + 1L
        if (symbol %in% c(",", ";", ":", "!", " ")) next
        if (!symbol %in% c("{", "}", "_", "%", "#", "&", "$", "|"))
          issues <- c(issues, paste0("unsupported_control_symbol:", symbol))
        add(paste0("\\", symbol), "fixed", seq.int(start, p - 1L))
      }
      next
    }
    if (ch == "{") depth <- depth + 1L
    if (ch == "}") {
      depth <- depth - 1L
      if (depth < 0L) issues <- c(issues, "unbalanced_braces")
    }
    if (ch %in% c("%", "#", "&", "$")) issues <- c(issues, "unsupported_tex_syntax")
    if (!grepl("^[ -~]$", ch)) issues <- c(issues, "unsupported_non_ascii_symbol")
    add(ch, if (grepl("^[A-Za-z]$", ch)) "variable" else "fixed", p)
    p <- p + 1L
  }
  if (depth != 0L) issues <- c(issues, "unbalanced_braces")
  # Token keys use lengths: concatenation alone could merge distinct commands.
  key <- function(x) paste0(nchar(x, type = "chars"), ":", x, collapse = "|")
  vars <- unique(tokens[kinds == "variable"])
  structural <- tokens
  selected <- kinds == "variable"
  structural[selected] <- paste0("@v", match(tokens[selected], vars))
  issues <- unique(issues)
  list(raw = formula, normalized = paste0(tokens, collapse = ""), tokens = tokens,
    kinds = kinds, source_positions = positions, normalized_key = key(tokens),
    structure_key = if (!length(issues) && length(tokens)) key(structural) else NA_character_,
    variables = vars, token_count = length(tokens), issues = issues,
    status = if (length(issues)) "limited" else if (!length(tokens)) "empty" else "ok")
}

prepare_math_units <- function(doc) {
  if (!inherits(doc, "rmd_document")) stop("doc must be an rmd_document.")
  units <- doc$units[doc$units$type == "math", , drop = FALSE]
  parsed <- lapply(units$content, normalize_math)
  for (i in seq_along(parsed)) {
    parsed[[i]]$source_positions <- lapply(parsed[[i]]$source_positions,
      function(p) as.integer(units$content_start[i] + p - 1L))
    if (units$status[i] != "ok") {
      parsed[[i]]$status <- "limited"
      parsed[[i]]$issues <- unique(c(parsed[[i]]$issues, "parser_limited"))
      parsed[[i]]$structure_key <- NA_character_
    }
  }
  units$normalized <- vapply(parsed, function(x) x$normalized, character(1))
  units$math_status <- vapply(parsed, function(x) x$status, character(1))
  units$token_count <- vapply(parsed, function(x) as.integer(x$token_count), integer(1))
  units$details <- I(parsed)
  units
}

compare_math_pair <- function(doc_a, doc_b, max_pairs = 10000L) {
  if (!is.numeric(max_pairs) || length(max_pairs) != 1L || is.na(max_pairs) ||
      !is.finite(max_pairs) || max_pairs < 1 || max_pairs != floor(max_pairs))
    stop("max_pairs must be a positive integer.")
  a <- prepare_math_units(doc_a); b <- prepare_math_units(doc_b)
  pair_count <- as.double(nrow(a)) * nrow(b)
  if (pair_count > max_pairs) stop("Formula pair limit exceeded.")
  matches <- data.frame(file_id_a = character(), file_id_b = character(),
    unit_id_a = character(), unit_id_b = character(),
    raw_equal = logical(), normalized_equal = logical(), renamed_equal = logical(),
    token_count = integer(), start_line_a = integer(), end_line_a = integer(),
    start_line_b = integer(), end_line_b = integer(),
    status = character(), stringsAsFactors = FALSE)
  matches$variable_map <- I(list())
  for (i in seq_len(nrow(a))) for (j in seq_len(nrow(b))) {
    x <- a$details[[i]]; y <- b$details[[j]]
    supported <- x$status == "ok" && y$status == "ok"
    raw <- x$token_count > 0L && identical(x$raw, y$raw)
    normalized <- supported && identical(x$normalized_key, y$normalized_key)
    renamed <- supported && identical(x$structure_key, y$structure_key)
    if (!raw && !normalized && !renamed) next
    row <- data.frame(file_id_a = a$file_id[i], file_id_b = b$file_id[j],
      unit_id_a = a$unit_id[i], unit_id_b = b$unit_id[j],
      raw_equal = raw, normalized_equal = normalized, renamed_equal = renamed,
      token_count = as.integer(min(x$token_count, y$token_count)),
      start_line_a = a$start_line[i], end_line_a = a$end_line[i],
      start_line_b = b$start_line[j], end_line_b = b$end_line[j],
      status = if (supported) "ok" else "limited", stringsAsFactors = FALSE)
    row$variable_map <- I(list(if (renamed) data.frame(a = x$variables, b = y$variables,
      stringsAsFactors = FALSE) else data.frame(a = character(), b = character())))
    matches <- rbind(matches, row)
  }
  has_math_a <- nrow(a) > 0L; has_math_b <- nrow(b) > 0L
  limited <- any(c(a$math_status, b$math_status) == "limited") ||
    any(c(doc_a$diagnostics$severity, doc_b$diagnostics$severity) %in% c("warning", "error"))
  status <- if (limited) "limited" else if (!has_math_a || !has_math_b) "not_applicable" else
    if (any(c(a$math_status, b$math_status) == "empty")) "insufficient_content" else "ok"
  list(status = status, formulas_a = a, formulas_b = b, matches = matches,
    pair_count = pair_count, max_pairs = max_pairs,
    diagnostics = list(a = doc_a$diagnostics, b = doc_b$diagnostics))
}

# Return source-indexed rows. Unsupported structures remain a single barrier.
.math_step_plan <- function(unit) {
  chars <- strsplit(unit$content, "", fixed = TRUE)[[1L]]
  n <- length(chars)
  if (n > 20000L) stop("Formula character limit exceeded (20000).")
  cut <- function(a, b) if (a > b) "" else paste0(chars[seq.int(a, b)], collapse = "")
  ws <- c(" ", "\t", "\n", "\r", "\f", "\v")
  escaped <- function(at) {
    j <- at - 1L; count <- 0L
    while (j >= 1L && chars[j] == "\\") { count <- count + 1L; j <- j - 1L }
    count %% 2L == 1L
  }
  trim <- function(a, b) {
    while (a <= b && chars[a] %in% ws) a <- a + 1L
    while (b >= a && chars[b] %in% ws && !escaped(b)) b <- b - 1L
    c(a, b)
  }
  mode <- ""; issues <- character()
  fallback <- function(issue) list(environment = mode,
    rows = list(list(start = 1L, end = n, drop = integer())), issues = issue)
  supported <- c("align", "align*", "aligned", "gather", "gather*", "gathered", "equation", "equation*")
  opening <- regmatches(unit$raw, regexpr("^\\\\begin\\{[A-Za-z*]+\\}", unit$raw))
  if (length(opening) && nzchar(opening)) {
    mode <- sub("^\\\\begin\\{([^}]+)\\}$", "\\1", opening)
    if (!mode %in% supported) return(fallback("unsupported_step_environment"))
  }
  bounds <- trim(1L, n); lo <- bounds[1L]; hi <- bounds[2L]
  # Permit a single row environment inside an equation wrapper, or one display wrapper.
  repeat {
    body <- cut(lo, hi)
    opener <- regmatches(body, regexpr("^\\\\begin\\{[A-Za-z*]+\\}", body))
    if (!length(opener) || !nzchar(opener)) break
    name <- sub("^\\\\begin\\{([^}]+)\\}$", "\\1", opener)
    if (!name %in% supported || (nzchar(mode) &&
        !(mode %in% c("equation", "equation*") && name %in% c("aligned", "gathered"))))
      return(fallback("unsupported_nested_environment"))
    closer <- paste0("\\end{", name, "}")
    if (!endsWith(body, closer) || nchar(body) < nchar(opener) + nchar(closer))
      return(fallback("unclosed_step_environment"))
    mode <- name
    bounds <- trim(lo + nchar(opener), hi - nchar(closer))
    lo <- bounds[1L]; hi <- bounds[2L]
  }
  row_mode <- mode %in% c("align", "align*", "aligned", "gather", "gather*", "gathered")
  align_mode <- mode %in% c("align", "align*", "aligned")
  rows <- list(); start <- lo; dropped <- integer(); ampersands <- 0L; depth <- 0L; p <- lo
  emit <- function(end) {
    bounds <- trim(start, end)
    rows[[length(rows) + 1L]] <<- list(start = bounds[1L], end = bounds[2L], drop = dropped)
    if (ampersands > 1L) issues <<- c(issues, "multiple_alignment_columns")
  }
  while (p <= hi) {
    ch <- chars[p]
    if (ch == "\\") {
      if (p < hi && chars[p + 1L] == "\\") {
        if (depth == 0L) {
          if (!row_mode) return(fallback("row_break_outside_supported_environment"))
          emit(p - 1L)
          p <- p + 2L
          if (p <= hi && chars[p] == "*") p <- p + 1L
          if (p <= hi && chars[p] == "[") {
            q <- p + 1L
            while (q <= hi && chars[q] != "]") q <- q + 1L
            spacing <- trimws(cut(p + 1L, q - 1L))
            if (q > hi || !grepl("^[+-]?([0-9]+(\\.[0-9]*)?|\\.[0-9]+)(pt|pc|bp|dd|cc|sp|mm|cm|in|em|ex)$", spacing))
              return(fallback("unsupported_row_spacing"))
            p <- q + 1L
          }
          start <- p; dropped <- integer(); ampersands <- 0L
          next
        }
        p <- p + 2L; next
      }
      q <- p + 1L
      while (q <= hi && grepl("^[A-Za-z]$", chars[q])) q <- q + 1L
      command <- cut(p + 1L, q - 1L)
      if (command %in% c("begin", "end")) return(fallback("unsupported_nested_environment"))
      if (depth == 0L && command %in% c("notag", "nonumber"))
        dropped <- c(dropped, seq.int(p, q - 1L))
      p <- if (q == p + 1L) min(p + 2L, hi + 1L) else q
      next
    }
    if (ch == "{") depth <- depth + 1L
    if (ch == "}") depth <- depth - 1L
    if (depth < 0L) return(fallback("unbalanced_step_braces"))
    if (ch == "&" && depth == 0L) {
      if (!align_mode) return(fallback("alignment_outside_supported_environment"))
      ampersands <- ampersands + 1L; dropped <- c(dropped, p)
    }
    p <- p + 1L
  }
  if (depth != 0L) return(fallback("unbalanced_step_braces"))
  last <- trim(start, hi)
  # A trailing row break is allowed; empty internal rows are retained as barriers.
  if (last[1L] <= last[2L] || !length(rows)) emit(hi)
  if (any(vapply(rows, function(r) r$start > r$end, logical(1))) && length(rows) > 1L)
    issues <- c(issues, "empty_internal_math_row")
  list(environment = mode, rows = rows, issues = unique(issues))
}

prepare_math_steps <- function(doc, max_steps = 500L) {
  if (!inherits(doc, "rmd_document")) stop("doc must be an rmd_document.")
  if (!is.numeric(max_steps) || length(max_steps) != 1L || is.na(max_steps) ||
      !is.finite(max_steps) || max_steps < 1 || max_steps != floor(max_steps) || max_steps > .Machine$integer.max)
    stop("max_steps must be a representable positive integer.")
  units <- doc$units[doc$units$type == "math", , drop = FALSE]
  result <- units[FALSE, , drop = FALSE]
  for (name in c("parent_unit_id", "parent_raw", "environment", "comparison_content", "normalized", "math_status"))
    result[[name]] <- character()
  result$step_index <- integer(); result$token_count <- integer()
  result$comparison_positions <- I(list()); result$details <- I(list())
  source_chars <- strsplit(doc$source, "", fixed = TRUE)[[1L]]
  line_starts <- c(1L, which(source_chars == "\n") + 1L)
  for (i in seq_len(nrow(units))) {
    parent <- units[i, , drop = FALSE]
    chars <- strsplit(parent$content, "", fixed = TRUE)[[1L]]
    plan <- .math_step_plan(parent)
    if (nrow(result) + length(plan$rows) > max_steps) stop("Expanded formula step limit exceeded.")
    rows <- lapply(seq_along(plan$rows), function(j) {
      span <- plan$rows[[j]]
      ids <- if (span$start <= span$end) seq.int(span$start, span$end) else integer()
      keep <- ids[!ids %in% span$drop]
      raw <- paste0(chars[ids], collapse = "")
      comparison <- paste0(chars[keep], collapse = "")
      positions <- as.integer(parent$content_start + keep - 1L)
      details <- normalize_math(comparison)
      details$source_positions <- lapply(details$source_positions, function(p) positions[p])
      details$comparison_content <- comparison; details$raw <- raw
      row <- parent
      row$parent_unit_id <- parent$unit_id; row$parent_raw <- parent$raw
      row$environment <- plan$environment; row$step_index <- as.integer(j)
      if (nzchar(plan$environment) || length(plan$rows) > 1L)
        row$unit_id <- paste0(parent$unit_id, ":s", sprintf("%03d", j))
      row$content_start <- as.integer(parent$content_start + span$start - 1L)
      row$content_end <- as.integer(parent$content_start + span$end - 1L)
      row$start_offset <- row$content_start; row$end_offset <- row$content_end
      row$start_line <- as.integer(findInterval(row$start_offset, line_starts))
      row$end_line <- as.integer(findInterval(max(row$start_offset, row$end_offset), line_starts))
      row$start_column <- as.integer(row$start_offset - line_starts[row$start_line] + 1L)
      row$end_column <- as.integer(row$end_offset - line_starts[row$end_line] + 1L)
      row$raw <- raw; row$content <- raw; row$comparison_content <- comparison
      row$normalized <- details$normalized; row$math_status <- details$status
      row$token_count <- as.integer(details$token_count)
      row$comparison_positions <- I(list(positions)); row$details <- I(list(details))
      row[, names(result), drop = FALSE]
    })
    issues <- unique(c(plan$issues, if (parent$status != "ok") "parser_limited",
      unlist(lapply(rows, function(r) r$details[[1L]]$issues), use.names = FALSE)))
    if (length(rows) > 1L && any(vapply(rows, function(r) r$math_status == "empty", logical(1))))
      issues <- unique(c(issues, "empty_internal_math_row"))
    # Any unsupported row limits the whole parent; do not silently salvage it.
    if (length(issues)) rows <- lapply(rows, function(row) {
      row$math_status <- "limited"; row$details[[1L]]$status <- "limited"
      row$details[[1L]]$issues <- issues; row$details[[1L]]$structure_key <- NA_character_
      row
    })
    for (row in rows) result <- rbind(result, row)
  }
  rownames(result) <- NULL
  result
}
