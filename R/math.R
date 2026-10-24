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
