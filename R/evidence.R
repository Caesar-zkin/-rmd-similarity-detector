# Normalize existing results and conservatively group overlaps. No new matching.
empty_evidence_records <- function() {
  d <- data.frame(record_id = character(), kind = character(), unit = character(), module = character(),
    table = character(), source_row = integer(), method = character(), level = character(),
    eligible = logical(), matched_units = integer(), content_tokens = integer(), similarity = numeric(),
    start_line_a = integer(), end_line_a = integer(), start_line_b = integer(), end_line_b = integer(),
    group_id = character(), stringsAsFactors = FALSE)
  d$positions_a <- I(list()); d$positions_b <- I(list()); d
}

group_position_evidence <- function(records, max_records = 100000L, max_atoms = 5000000L) {
  max_records <- code_positive_integer(max_records, "max_records")
  max_atoms <- code_positive_integer(max_atoms, "max_atoms")
  required <- names(empty_evidence_records())
  if (!is.data.frame(records) || !all(required %in% names(records)) || nrow(records) > max_records)
    stop("Invalid evidence schema or record resource limit exceeded.")
  n <- nrow(records); atoms <- 0
  if (!is.logical(records$eligible) || !is.list(records$positions_a) || !is.list(records$positions_b) ||
      anyDuplicated(records$record_id) || anyNA(records$eligible) ||
      !all(records$kind %in% c("text", "math", "code"))) stop("Invalid evidence identities or kinds.")
  for (i in seq_len(n)) {
    a <- records$positions_a[[i]]; b <- records$positions_b[[i]]
    expected <- switch(records$kind[i], text = "character", math = "step", code = "token")
    if (records$unit[i] != expected || anyNA(a) || anyNA(b) || anyDuplicated(a) || anyDuplicated(b))
      stop("Invalid evidence position units or duplicate/missing atoms.")
    if (records$eligible[i]) {
      if (!length(a) || length(a) != length(b) || records$matched_units[i] != length(a))
        stop("Eligible evidence needs one corresponding position per side.")
      if (records$kind[i] != "math" && (!is.numeric(a) || !is.numeric(b) ||
          any(!is.finite(c(a, b))) || any(c(a, b) < 1 | c(a, b) != floor(c(a, b)))))
        stop("Character/token positions must be positive integers.")
      if (records$kind[i] == "math" && (!is.character(a) || !is.character(b) || any(!nzchar(c(a, b)))))
        stop("Formula step IDs must be nonempty strings.")
    } else if (length(a) || length(b) || records$matched_units[i] != 0L)
      stop("Support-only raw comparisons cannot supply effective position counts.")
    atoms <- atoms + length(a) + length(b)
    if (atoms > max_atoms) stop("Evidence atom resource limit exceeded; no partial grouping.")
  }
  groups <- data.frame(group_id = character(), kind = character(), unit = character(), records = integer(),
    methods = character(), representative_id = character(), largest_match = integer(),
    representative_tokens = integer(), unique_a = integer(), unique_b = integer(),
    start_line_a = integer(), end_line_a = integer(), start_line_b = integer(), end_line_b = integer(), stringsAsFactors = FALSE)
  records$group_id <- rep(NA_character_, n)
  active <- which(records$eligible)
  if (!length(active)) return(list(records = records, groups = groups))
  parent <- seq_len(n); seen <- new.env(hash = TRUE, parent = emptyenv())
  root <- function(i) {
    while (parent[i] != i) { parent[i] <<- parent[parent[i]]; i <- parent[i] }
    i
  }
  join <- function(a, b) {
    a <- root(a); b <- root(b)
    if (a != b) parent[max(a, b)] <<- min(a, b)
  }
  for (i in active) for (side in c("a", "b")) {
    keys <- paste(records$kind[i], side, records[[paste0("positions_", side)]][[i]], sep = "|")
    for (key in keys) {
      if (exists(key, envir = seen, inherits = FALSE)) join(i, seen[[key]]) else seen[[key]] <- i
    }
  }
  roots <- vapply(active, root, integer(1)); out <- list()
  for (r in unique(roots)) {
    ids <- active[roots == r]; rows <- records[ids, , drop = FALSE]
    rank <- match(rows$level, c("exact", "raw", "normalized", "lexical", "approximate", "renamed"))
    best <- ids[order(-rows$matched_units, rank, -rows$similarity, ids, na.last = TRUE)[1L]]
    id <- sprintf("g%05d", length(out) + 1L); records$group_id[ids] <- id
    a <- unique(unlist(rows$positions_a, use.names = FALSE)); b <- unique(unlist(rows$positions_b, use.names = FALSE))
    out[[length(out) + 1L]] <- data.frame(group_id = id, kind = rows$kind[1L], unit = rows$unit[1L],
      records = length(ids), methods = paste(sort(unique(rows$method)), collapse = "; "),
      representative_id = records$record_id[best], largest_match = records$matched_units[best],
      representative_tokens = records$content_tokens[best], unique_a = length(a), unique_b = length(b),
      start_line_a = min(rows$start_line_a), end_line_a = max(rows$end_line_a),
      start_line_b = min(rows$start_line_b), end_line_b = max(rows$end_line_b), stringsAsFactors = FALSE)
  }
  list(records = records, groups = do.call(rbind, out))
}

summarize_pair_evidence <- function(result, max_records = 100000L, max_atoms = 5000000L) {
  max_records <- code_positive_integer(max_records, "max_records")
  max_atoms <- code_positive_integer(max_atoms, "max_atoms")
  modules <- result$modules; rows <- list(); issues <- character(); atoms <- 0
  docs <- result$analysis_documents
  add <- function(kind, module, table, source_row, method, level, row, a, b, eligible = TRUE,
      similarity = 1, content_tokens = NA_integer_) {
    if (length(rows) >= max_records) stop("Evidence record resource limit exceeded.")
    if (!eligible) a <- b <- integer()
    atoms <<- atoms + length(a) + length(b)
    if (atoms > max_atoms) stop("Evidence atom resource limit exceeded.")
    d <- data.frame(record_id = sprintf("e%06d", length(rows) + 1L), kind = kind,
      unit = switch(kind, text = "character", math = "step", code = "token"), module = module,
      table = table, source_row = source_row, method = method, level = level, eligible = eligible,
      matched_units = length(a), content_tokens = content_tokens, similarity = similarity,
      start_line_a = row$start_line_a, end_line_a = row$end_line_a,
      start_line_b = row$start_line_b, end_line_b = row$end_line_b, group_id = NA_character_, stringsAsFactors = FALSE)
    d$positions_a <- I(list(a)); d$positions_b <- I(list(b)); rows[[length(rows) + 1L]] <<- d
  }
  text <- modules$text$value
  if (!is.null(text)) for (table in c("exact_matches", "approximate_matches")) {
    matches <- text[[table]]
    for (i in seq_len(nrow(matches))) {
      row <- matches[i, ]; exact <- table == "exact_matches"
      add("text", "text", table, i, if (exact) "text_exact" else "text_approximate",
        if (exact) "exact" else "approximate", row, row$source_positions_a[[1L]], row$source_positions_b[[1L]],
        similarity = if (exact) 1 else row$similarity)
    }
  }
  sequence <- modules$formula_sequence$value
  steps <- list()
  for (side in c("a", "b")) {
    steps[[side]] <- if (!is.null(sequence)) sequence[[paste0("formulas_", side)]] else
      tryCatch(prepare_math_steps(docs[[toupper(side)]]), error = function(e) {
        issues <<- c(issues, paste("Formula step view unavailable:", conditionMessage(e))); NULL
      })
  }
  single <- modules$formula_single$value
  if (!is.null(single)) for (i in seq_len(nrow(single$matches))) {
    row <- single$matches[i, ]; selected <- lapply(c("a", "b"), function(side) {
      s <- steps[[side]]
      if (is.null(s)) return(NULL)
      s[s$parent_unit_id == row[[paste0("unit_id_", side)]], , drop = FALSE]
    })
    eligible <- all(vapply(selected, function(s) !is.null(s) && nrow(s) > 0L && all(s$math_status == "ok" & s$token_count > 0L), logical(1))) &&
      isTRUE(row$raw_equal || row$normalized_equal || row$renamed_equal)
    a <- if (eligible) selected[[1L]]$unit_id else character()
    b <- if (eligible) selected[[2L]]$unit_id else character()
    # A whole-unit row with a different number of derived steps remains auxiliary.
    eligible <- eligible && length(a) == length(b)
    level <- if (row$raw_equal) "raw" else if (row$normalized_equal) "normalized" else "renamed"
    add("math", "formula_single", "matches", i, "formula_whole", level, row, a, b, eligible,
      content_tokens = if (eligible) as.integer(sum(selected[[1L]]$token_count)) else 0L)
  }
  if (!is.null(sequence)) for (i in seq_len(nrow(sequence$matches))) {
    row <- sequence$matches[i, ]; pairs <- row$step_pairs[[1L]]
    add("math", "formula_sequence", "matches", i, "formula_sequence",
      if (row$raw_equal) "raw" else if (row$normalized_equal) "normalized" else "renamed", row,
      pairs$unit_id_a, pairs$unit_id_b, similarity = row$step_similarity, content_tokens = row$token_count)
  }
  whole <- modules$code_whole$value
  if (!is.null(whole)) for (i in seq_len(nrow(whole$matches))) {
    row <- whole$matches[i, ]; tokens <- lapply(c("a", "b"), function(side) {
      u <- whole[[paste0("code_", side)]]; d <- u$details[[match(row[[paste0("unit_id_", side)]], u$unit_id)]]
      if (d$parse_status != "ok") return(integer())
      t <- d$tokens; t$start_offset[t$kind != "COMMENT" & t$text != ";"]
    })
    eligible <- length(tokens[[1L]]) > 0L && length(tokens[[1L]]) == length(tokens[[2L]]) &&
      isTRUE(row$raw_equal || row$tokens_equal || row$renamed_equal)
    add("code", "code_whole", "matches", i, "code_whole",
      if (row$raw_equal) "raw" else if (row$tokens_equal) "lexical" else "renamed", row,
      tokens[[1L]], tokens[[2L]], eligible, content_tokens = if (eligible) length(tokens[[1L]]) else 0L)
  }
  local <- modules$code_local$value
  if (!is.null(local)) for (i in seq_len(nrow(local$matches))) {
    row <- local$matches[i, ]
    add("code", "code_local", "matches", i, "code_local", row$method, row,
      row$token_starts_a[[1L]], row$token_starts_b[[1L]], similarity = row$alignment_ratio,
      content_tokens = row$matched_tokens)
  }
  records <- if (length(rows)) do.call(rbind, rows) else empty_evidence_records()
  grouped <- group_position_evidence(records, max_records, max_atoms)
  statuses <- vapply(modules, function(m) m$status, character(1))
  list(status = if (length(issues) || any(statuses %in% c("error", "limited", "not_run"))) "limited" else "ok",
    records = grouped$records, groups = grouped$groups, issues = unique(issues),
    scope = "current_modules_only", support_only_count = sum(!records$eligible),
    note = "Groups share positions on at least one side. They do not prove statistical independence, one consistent mapping across records, or plagiarism. Use a real representative record for match length; never combine different records into an invented alignment.")
}
