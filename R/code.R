# R parsing only: never source, eval, load packages, or invoke submitted calls.
code_positive_integer <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x < 1 || x != floor(x) || x > .Machine$integer.max)
    stop(paste(name, "must be a representable positive integer."))
  as.integer(x)
}
.code_key <- function(x) paste0(nchar(x, type = "chars"), ":", x, collapse = "|")
.empty_code_tokens <- function() data.frame(token_id = integer(), kind = character(),
  text = character(), start_offset = integer(), end_offset = integer(),
  start_line = integer(), start_column = integer(), end_line = integer(), end_column = integer(),
  stringsAsFactors = FALSE)

tokenize_r_code <- function(code, max_chars = 100000L, max_tokens = 20000L, max_nodes = 50000L, max_statements = 2000L) {
  if (!is.character(code) || length(code) != 1L || is.na(code))
    stop("code must be one non-missing character string.")
  max_chars <- code_positive_integer(max_chars, "max_chars")
  max_tokens <- code_positive_integer(max_tokens, "max_tokens")
  max_nodes <- code_positive_integer(max_nodes, "max_nodes")
  max_statements <- code_positive_integer(max_statements, "max_statements")
  code <- gsub("\r\n?", "\n", enc2utf8(code), perl = TRUE)
  chars <- strsplit(code, "", fixed = TRUE)[[1L]]; n <- length(chars)
  if (n > max_chars) stop("Code character limit exceeded.")
  result <- list(source = code, tokens = .empty_code_tokens(), token_count = 0L,
    normalized_key = NA_character_, renamed_key = NA_character_,
    variable_map = data.frame(name = character(), canonical = character()),
    status = "limited", parse_status = "error", rename_status = "unavailable", issues = character(),
    statements = list(), statement_status = "unavailable")
  # Do not interpret submitted source-location directives or follow their filenames.
  if (grepl("(?m)^[ \t]*#line[ \t]+", code, perl = TRUE)) {
    result$parse_status <- "limited"; result$issues <- "unsupported_line_directive"; return(result)
  }
  parsed <- tryCatch(parse(text = code, keep.source = TRUE, encoding = "UTF-8"), error = identity)
  if (inherits(parsed, "error")) {
    result$issues <- paste0("parse_error: ", conditionMessage(parsed)); return(result)
  }
  pd <- utils::getParseData(parsed, includeText = FALSE)
  result$parse_status <- "ok"
  if (is.null(pd) || !nrow(pd)) {
    result$status <- "empty"; result$rename_status <- "not_applicable"
    result$statement_status <- "not_applicable"; return(result)
  }
  if (nrow(pd) > max_nodes) stop("Code parse node limit exceeded.")
  terminal <- pd[pd$terminal, , drop = FALSE]
  if (nrow(terminal) > max_tokens) stop("Code token limit exceeded.")
  # includeText=FALSE avoids truncated text for long string literals.
  literal <- tryCatch(unname(utils::getParseText(pd, terminal$id)), error = function(e) NULL)
  cursor <- 1L; starts <- ends <- integer(nrow(terminal)); mapped <- !is.null(literal)
  whitespace <- c(" ", "\t", "\n", "\r", "\f", "\v")
  if (mapped) for (i in seq_len(nrow(terminal))) {
    while (cursor <= n && chars[cursor] %in% whitespace) cursor <- cursor + 1L
    if (is.na(literal[i]) || !nzchar(literal[i])) { mapped <- FALSE; break }
    width <- nchar(literal[i], type = "chars")
    finish <- cursor + width - 1L
    actual <- if (width > 0L && finish <= n) paste0(chars[seq.int(cursor, finish)], collapse = "") else ""
    if (!width || !identical(actual, literal[i])) { mapped <- FALSE; break }
    starts[i] <- cursor; ends[i] <- finish; cursor <- finish + 1L
  }
  while (cursor <= n && chars[cursor] %in% whitespace) cursor <- cursor + 1L
  if (!mapped || cursor <= n) {
    result$parse_status <- "limited"; result$issues <- "token_source_mapping_failed"; return(result)
  }
  line_starts <- c(1L, which(chars == "\n") + 1L)
  line_a <- findInterval(starts, line_starts); line_b <- findInterval(ends, line_starts)
  tokens <- data.frame(token_id = terminal$id, kind = terminal$token, text = literal,
    start_offset = starts, end_offset = ends, start_line = as.integer(line_a),
    start_column = as.integer(starts - line_starts[line_a] + 1L), end_line = as.integer(line_b),
    end_column = as.integer(ends - line_starts[line_b] + 1L), stringsAsFactors = FALSE)
  result$tokens <- tokens
  ignored <- terminal$token == "COMMENT" | literal == ";"
  included <- pd[!pd$terminal | !pd$id %in% terminal$id[ignored], , drop = FALSE]
  result$token_count <- as.integer(sum(!ignored))
  if (!result$token_count) {
    result$status <- "empty"; result$rename_status <- "not_applicable"
    result$statement_status <- "not_applicable"; return(result)
  }
  node_parent <- match(included$parent, included$id, nomatch = 0L)
  values <- rep("", nrow(included))
  leaves <- included$terminal
  values[leaves] <- literal[match(included$id[leaves], terminal$id)]
  graph_key <- function(v) .code_key(paste(included$token, node_parent, v, sep = "\001"))
  result$normalized_key <- graph_key(values)
  # Keep grammatical parent relationships: newline-sensitive expression boundaries matter.
  issues <- character()
  scope_tokens <- c("FUNCTION", "FOR", "WHILE", "REPEAT", "IF", "ELSE")
  if (any(terminal$token %in% scope_tokens) || any(literal %in% c("<<-", "->", "->>")) ||
      any(terminal$token == "EQ_ASSIGN") || any(literal == "~"))
    issues <- c(issues, "renaming_restricted_scope_or_assignment")
  allowed_calls <- c("c", "mean", "sum", "sd", "var", "median", "min", "max", "length", "sqrt",
    "abs", "log", "exp", "round", "seq", "rep", "sort", "order", "unique", "which", "is.na",
    "as.numeric", "as.integer", "as.character", "numeric", "integer", "character", "matrix", "array",
    "data.frame", "list", "print", "cat", "stop", "warning", "cor", "cov", "sample", "rnorm",
    "runif", "set.seed", "head", "tail", "nrow", "ncol")
  if (any(!literal[terminal$token == "SYMBOL_FUNCTION_CALL"] %in% allowed_calls))
    issues <- c(issues, "renaming_restricted_call")
  if (any(!literal[terminal$token == "SYMBOL_PACKAGE"] %in% c("base", "stats", "utils")))
    issues <- c(issues, "renaming_restricted_namespace")
  inside <- function(node) {
    terminal[(terminal$line1 > node$line1 | (terminal$line1 == node$line1 & terminal$col1 >= node$col1)) &
      (terminal$line2 < node$line2 | (terminal$line2 == node$line2 & terminal$col2 <= node$col2)), , drop = FALSE]
  }
  for (id in terminal$id[literal == "("]) {
    open <- pd[match(id, pd$id), , drop = FALSE]
    children <- pd[pd$parent == open$parent & pd$token != "COMMENT", , drop = FALSE]
    before <- children[children$line2 < open$line1 | (children$line2 == open$line1 & children$col2 < open$col1), , drop = FALSE]
    if (nrow(before) == 1L && before$token == "expr") {
      head_terms <- inside(before)
      if (!all(head_terms$token %in% c("SYMBOL_FUNCTION_CALL", "SYMBOL_PACKAGE", "NS_GET", "NS_GET_INT")) ||
          sum(head_terms$token == "SYMBOL_FUNCTION_CALL") != 1L)
        issues <- c(issues, "renaming_restricted_computed_call")
    }
  }
  candidates <- character(); defining_ids <- integer(); defining_parents <- integer()
  for (id in terminal$id[terminal$token == "LEFT_ASSIGN" & literal == "<-"]) {
    operator <- pd[match(id, pd$id), , drop = FALSE]
    children <- pd[pd$parent == operator$parent & pd$token != "COMMENT", , drop = FALSE]
    left <- children[children$line2 < operator$line1 | (children$line2 == operator$line1 & children$col2 < operator$col1), , drop = FALSE]
    if (nrow(left) != 1L || left$token != "expr") next
    symbol <- pd[pd$parent == left$id & pd$token != "COMMENT", , drop = FALSE]
    if (nrow(symbol) != 1L || symbol$token != "SYMBOL") next
    name <- literal[match(symbol$id, terminal$id)]
    if (!grepl("^[A-Za-z.][A-Za-z0-9._]*$", name) || name %in% candidates) next
    candidates <- c(candidates, name); defining_ids <- c(defining_ids, symbol$id)
    defining_parents <- c(defining_parents, operator$parent)
  }
  safe <- vapply(seq_along(candidates), function(i) {
    name <- candidates[i]; definition <- match(defining_ids[i], terminal$id)
    # A name used as a function is kept literally throughout the block.
    if (name %in% literal[terminal$token == "SYMBOL_FUNCTION_CALL"]) return(FALSE)
    uses <- which(terminal$token == "SYMBOL" & literal == name)
    if (any(uses < definition)) return(FALSE)
    assign <- pd[match(defining_parents[i], pd$id), , drop = FALSE]
    refs <- inside(assign)
    any_self_reference <- any(refs$id != defining_ids[i] & refs$token == "SYMBOL" &
      literal[match(refs$id, terminal$id)] == name)
    !any_self_reference
  }, logical(1))
  candidates <- candidates[safe]
  # Member names are literal even if they happen to equal a local variable name.
  member <- rep(FALSE, nrow(terminal))
  syntax <- which(terminal$token != "COMMENT")
  if (length(syntax) > 1L) member[syntax[-1L]] <- literal[head(syntax, -1L)] %in% c("$", "@")
  eligible <- rep(FALSE, nrow(included))
  if (!length(issues)) {
    replaced <- values
    eligible <- included$terminal & included$token == "SYMBOL"
    indices <- match(included$id, terminal$id)
    eligible[eligible] <- !member[indices[eligible]] & values[eligible] %in% candidates
    if (any(eligible)) replaced[eligible] <- paste0("@variable:", match(values[eligible], candidates))
    result$renamed_key <- graph_key(replaced)
    result$variable_map <- data.frame(name = candidates, canonical = if (length(candidates)) paste0("v", seq_along(candidates)) else character(), stringsAsFactors = FALSE)
    result$rename_status <- "ok"; result$status <- "ok"
  } else {
    result$rename_status <- "restricted"; result$status <- "limited"
  }
  result$issues <- unique(issues)
  roots <- included[!included$terminal & included$parent == 0L, , drop = FALSE]
  if (nrow(roots) > max_statements) stop("Code statement count limit exceeded.")
  covered <- integer(nrow(terminal)); statements <- list()
  for (i in seq_len(nrow(roots))) {
    root <- roots[i, , drop = FALSE]
    within <- function(rows) (rows$line1 > root$line1 | (rows$line1 == root$line1 & rows$col1 >= root$col1)) &
      (rows$line2 < root$line2 | (rows$line2 == root$line2 & rows$col2 <= root$col2))
    token_rows <- which(within(terminal) & !ignored)
    if (!length(token_rows)) next
    node_rows <- which(within(included))
    nodes <- included[node_rows, , drop = FALSE]
    parents <- match(nodes$parent, nodes$id, nomatch = 0L)
    key <- function(v) .code_key(paste(nodes$token, parents, v, sep = "\001"))
    shape <- values[node_rows]
    shape[eligible[node_rows]] <- "@renameable"
    covered[token_rows] <- covered[token_rows] + 1L
    statements[[length(statements) + 1L]] <- list(token_rows = as.integer(token_rows),
      content = substring(code, starts[token_rows[1L]], ends[tail(token_rows, 1L)]),
      normalized_key = key(values[node_rows]),
      shape_key = if (result$rename_status == "ok") key(shape) else NA_character_,
      rename_eligible = eligible[match(terminal$id[token_rows], included$id)])
  }
  if (!length(statements) || any(covered[!ignored] != 1L)) {
    result$status <- "limited"; result$statement_status <- "unavailable"
    result$issues <- unique(c(result$issues, "statement_extraction_failed"))
  } else {
    result$statements <- statements; result$statement_status <- "ok"
  }
  result
}

prepare_code_units <- function(doc, max_units = 500L, max_total_chars = 1000000L) {
  if (!inherits(doc, "rmd_document")) stop("doc must be an rmd_document.")
  max_units <- code_positive_integer(max_units, "max_units")
  max_total_chars <- code_positive_integer(max_total_chars, "max_total_chars")
  units <- doc$units[doc$units$type %in% c("code", "inline_r"), , drop = FALSE]
  if (nrow(units) > max_units) stop("Code unit limit exceeded.")
  if (sum(nchar(units$content, type = "chars")) > max_total_chars) stop("Total code character limit exceeded.")
  details <- lapply(seq_len(nrow(units)), function(i) {
    if (tolower(units$language[i]) != "r") {
      d <- list(source = units$content[i], tokens = .empty_code_tokens(), token_count = 0L,
        normalized_key = NA_character_, renamed_key = NA_character_,
        variable_map = data.frame(name = character(), canonical = character()), status = "limited",
        parse_status = "unsupported", rename_status = "unavailable", issues = "unsupported_code_language")
    } else d <- tokenize_r_code(units$content[i])
    if (units$status[i] != "ok") {
      d$status <- "limited"; d$parse_status <- "limited"; d$rename_status <- "unavailable"
      d$normalized_key <- d$renamed_key <- NA_character_; d$issues <- c(d$issues, "parser_limited")
    }
    if (nrow(d$tokens)) {
      d$tokens$start_offset <- as.integer(d$tokens$start_offset + units$content_start[i] - 1L)
      d$tokens$end_offset <- as.integer(d$tokens$end_offset + units$content_start[i] - 1L)
      source_chars <- strsplit(doc$source, "", fixed = TRUE)[[1L]]
      starts <- c(1L, which(source_chars == "\n") + 1L)
      d$tokens$start_line <- as.integer(findInterval(d$tokens$start_offset, starts))
      d$tokens$end_line <- as.integer(findInterval(d$tokens$end_offset, starts))
      d$tokens$start_column <- as.integer(d$tokens$start_offset - starts[d$tokens$start_line] + 1L)
      d$tokens$end_column <- as.integer(d$tokens$end_offset - starts[d$tokens$end_line] + 1L)
    }
    d
  })
  units$code_status <- vapply(details, function(d) d$status, character(1))
  units$token_count <- vapply(details, function(d) d$token_count, integer(1))
  units$details <- I(details)
  units
}

compare_code_pair <- function(doc_a, doc_b, max_pairs = 10000L, max_pair_chars = 5000000L) {
  max_pairs <- code_positive_integer(max_pairs, "max_pairs")
  max_pair_chars <- code_positive_integer(max_pair_chars, "max_pair_chars")
  a <- prepare_code_units(doc_a); b <- prepare_code_units(doc_b)
  na <- nrow(a); nb <- nrow(b)
  if (as.double(na) * nb > max_pairs) stop("Code pair limit exceeded.")
  if (sum(nchar(a$content)) * as.double(nb) + sum(nchar(b$content)) * as.double(na) > max_pair_chars)
    stop("Code pair character work limit exceeded.")
  matches <- data.frame(file_id_a = character(), file_id_b = character(), unit_id_a = character(),
    unit_id_b = character(), raw_equal = logical(), tokens_equal = logical(), renamed_equal = logical(),
    token_count = integer(), start_line_a = integer(), end_line_a = integer(),
    start_line_b = integer(), end_line_b = integer(), status = character(), stringsAsFactors = FALSE)
  matches$variable_map <- I(list())
  comments <- data.frame(unit_id_a = character(), unit_id_b = character(), comment_count = integer(), stringsAsFactors = FALSE)
  for (i in seq_len(na)) for (j in seq_len(nb)) {
    x <- a$details[[i]]; y <- b$details[[j]]
    cx <- x$tokens$text[x$tokens$kind == "COMMENT"]; cy <- y$tokens$text[y$tokens$kind == "COMMENT"]
    if (length(cx) && identical(cx, cy)) comments <- rbind(comments,
      data.frame(unit_id_a = a$unit_id[i], unit_id_b = b$unit_id[j], comment_count = length(cx)))
    raw <- x$status != "empty" && y$status != "empty" && nzchar(trimws(a$content[i])) && identical(a$content[i], b$content[j])
    lexical <- x$parse_status == "ok" && y$parse_status == "ok" && x$token_count > 0L && y$token_count > 0L &&
      identical(x$normalized_key, y$normalized_key)
    renamed <- x$rename_status == "ok" && y$rename_status == "ok" &&
      identical(x$renamed_key, y$renamed_key)
    if (!raw && !lexical && !renamed) next
    row <- data.frame(file_id_a = a$file_id[i], file_id_b = b$file_id[j], unit_id_a = a$unit_id[i], unit_id_b = b$unit_id[j],
      raw_equal = raw, tokens_equal = lexical, renamed_equal = renamed,
      token_count = as.integer(min(x$token_count, y$token_count)), start_line_a = a$start_line[i], end_line_a = a$end_line[i],
      start_line_b = b$start_line[j], end_line_b = b$end_line[j],
      status = if (x$status == "ok" && y$status == "ok") "ok" else "limited", stringsAsFactors = FALSE)
    row$variable_map <- I(list(if (renamed) data.frame(a = x$variable_map$name, b = y$variable_map$name)
      else data.frame(a = character(), b = character())))
    matches <- rbind(matches, row)
  }
  limited <- any(c(a$code_status, b$code_status) == "limited") ||
    any(c(doc_a$diagnostics$severity, doc_b$diagnostics$severity) %in% c("warning", "error"))
  status <- if (limited) "limited" else if (!na || !nb) "not_applicable" else
    if (any(c(a$code_status, b$code_status) == "empty")) "insufficient_content" else "ok"
  list(status = status, matches = matches, comment_matches = comments, code_a = a, code_b = b,
    parameters = list(max_pairs = max_pairs, max_pair_chars = max_pair_chars),
    diagnostics = list(a = doc_a$diagnostics, b = doc_b$diagnostics))
}
