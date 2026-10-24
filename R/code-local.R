# Requires parser.R and code.R; all submitted code remains unevaluated.
.code_nonnegative_integer <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x < 0 || x != floor(x) || x > .Machine$integer.max)
    stop(paste(name, "must be a representable nonnegative integer."))
  as.integer(x)
}

.code_statements_from_units <- function(units, max_statements) {
  result <- data.frame(file_id = character(), unit_id = character(), statement_id = character(),
    statement_index = integer(), content = character(), token_count = integer(),
    normalized_key = character(), shape_key = character(), unit_status = character(),
    start_line = integer(), end_line = integer(), stringsAsFactors = FALSE)
  result$tokens <- I(list()); result$rename_eligible <- I(list())
  for (i in seq_len(nrow(units))) {
    d <- units$details[[i]]
    if (d$parse_status != "ok" || !identical(d$statement_status, "ok")) next
    if (nrow(result) + length(d$statements) > max_statements) stop("Total code statement limit exceeded.")
    for (j in seq_along(d$statements)) {
      s <- d$statements[[j]]; tokens <- d$tokens[s$token_rows, , drop = FALSE]
      row <- data.frame(file_id = units$file_id[i], unit_id = units$unit_id[i],
        statement_id = paste0(units$unit_id[i], ":e", sprintf("%04d", j)), statement_index = as.integer(j),
        content = s$content, token_count = as.integer(nrow(tokens)), normalized_key = s$normalized_key,
        shape_key = s$shape_key, unit_status = d$status, start_line = tokens$start_line[1L],
        end_line = tail(tokens$end_line, 1L), stringsAsFactors = FALSE)
      row$tokens <- I(list(tokens)); row$rename_eligible <- I(list(s$rename_eligible))
      result <- rbind(result, row)
    }
  }
  rownames(result) <- NULL
  result
}

prepare_code_statements <- function(doc, max_statements = 2000L) {
  max_statements <- code_positive_integer(max_statements, "max_statements")
  .code_statements_from_units(prepare_code_units(doc), max_statements)
}

make_code_windows <- function(statements, window_tokens = 100L, window_statements = 20L, max_windows = 500L) {
  window_tokens <- code_positive_integer(window_tokens, "window_tokens")
  window_statements <- code_positive_integer(window_statements, "window_statements")
  max_windows <- code_positive_integer(max_windows, "max_windows")
  if (window_statements > 20L) stop("window_statements must not exceed 20.")
  if (!is.data.frame(statements) || !all(c("unit_id", "statement_id", "token_count") %in% names(statements)))
    stop("statements must come from prepare_code_statements.")
  result <- data.frame(window_id = character(), unit_id = character(), token_count = integer(), oversize = logical())
  result$statement_indices <- I(list())
  for (unit in unique(statements$unit_id)) {
    indices <- which(statements$unit_id == unit); start <- 1L; n <- length(indices)
    while (start <= n) {
      end <- start; total <- statements$token_count[indices[start]]
      while (end < n && end - start + 1L < window_statements &&
          total + statements$token_count[indices[end + 1L]] <= window_tokens) {
        end <- end + 1L; total <- total + statements$token_count[indices[end]]
      }
      if (nrow(result) >= max_windows) stop("Code window limit exceeded.")
      row <- data.frame(window_id = paste0("w", sprintf("%05d", nrow(result) + 1L)),
        unit_id = unit, token_count = as.integer(total), oversize = total > window_tokens)
      row$statement_indices <- I(list(indices[seq.int(start, end)]))
      result <- rbind(result, row)
      if (end == n) break
      start <- start + max(1L, as.integer(floor((end - start + 1L) / 2)))
    }
  }
  result
}

.code_window_features <- function(statements, windows) {
  rows <- list()
  for (i in seq_len(nrow(windows))) for (mode in c("lexical", "renamed")) {
    indices <- windows$statement_indices[[i]]
    keys <- statements[[if (mode == "lexical") "normalized_key" else "shape_key"]][indices]
    keys <- unique(keys[!is.na(keys)])
    if (length(keys)) rows[[length(rows) + 1L]] <- data.frame(window_index = i, mode = mode, key = keys)
  }
  if (!length(rows)) return(data.frame(window_index = integer(), mode = character(), key = character()))
  do.call(rbind, rows)
}

select_code_candidates <- function(statements_a, statements_b, windows_a, windows_b,
    max_candidates = 500L, max_seed_pairs = 100000L) {
  max_candidates <- code_positive_integer(max_candidates, "max_candidates")
  max_seed_pairs <- code_positive_integer(max_seed_pairs, "max_seed_pairs")
  a <- .code_window_features(statements_a, windows_a); b <- .code_window_features(statements_b, windows_b)
  empty <- data.frame(window_index_a = integer(), window_index_b = integer(), mode = character())
  if (!nrow(a) || !nrow(b)) return(empty)
  ca <- table(paste(a$mode, a$key, sep = "\002")); cb <- table(paste(b$mode, b$key, sep = "\002"))
  common <- intersect(names(ca), names(cb))
  projected <- sum(as.double(ca[common]) * as.double(cb[common]))
  if (projected > max_seed_pairs) stop("Code seed-pair limit exceeded.")
  joined <- merge(a, b, by = c("mode", "key"), suffixes = c("_a", "_b"), sort = FALSE)
  if (!nrow(joined)) return(empty)
  result <- unique(joined[, names(empty), drop = FALSE])
  if (nrow(result) > max_candidates) stop("Code candidate limit exceeded.")
  result <- result[order(result$window_index_a, result$window_index_b, result$mode), , drop = FALSE]
  rownames(result) <- NULL
  result
}

.extend_code_mapping <- function(a, b, mode, mapping) {
  if (mode == "lexical") return(if (identical(a$normalized_key, b$normalized_key)) mapping else NULL)
  if (is.na(a$shape_key) || is.na(b$shape_key) || !identical(a$shape_key, b$shape_key)) return(NULL)
  ta <- a$tokens[[1L]]; tb <- b$tokens[[1L]]
  eligible <- a$rename_eligible[[1L]]
  for (k in which(eligible)) {
    x <- ta$text[k]; y <- tb$text[k]; existing <- match(x, mapping$a)
    if (!is.na(existing)) {
      if (mapping$b[existing] != y) return(NULL)
    } else {
      if (y %in% mapping$b) return(NULL)
      mapping <- rbind(mapping, data.frame(a = x, b = y, stringsAsFactors = FALSE))
    }
  }
  mapping
}

.code_local_matches <- function(a, b, wa, wb, candidates, min_tokens, min_statements,
    max_skips, max_states, max_results, max_token_work) {
  states <- 0; work <- 0; paths <- list(); seen <- new.env(parent = emptyenv())
  empty_map <- data.frame(a = character(), b = character(), stringsAsFactors = FALSE)
  for (ci in seq_len(nrow(candidates))) {
    ia <- wa$statement_indices[[candidates$window_index_a[ci]]]
    ib <- wb$statement_indices[[candidates$window_index_b[ci]]]
    mode <- candidates$mode[ci]
    attempt <- function(i, j, mapping) {
      states <<- states + 1; work <<- work + max(a$token_count[ia[i]], b$token_count[ib[j]])
      if (states > max_states) stop("Code local search state limit exceeded.")
      if (work > max_token_work) stop("Code local token work limit exceeded.")
      .extend_code_mapping(a[ia[i], , drop = FALSE], b[ib[j], , drop = FALSE], mode, mapping)
    }
    walk <- function(pa, pb, mapping, skipped) {
      i <- tail(pa, 1L); j <- tail(pb, 1L); extended <- FALSE
      if (i < length(ia) && j < length(ib)) {
        remaining <- max_skips - skipped
        for (di in seq_len(min(as.double(remaining) + 1, length(ia) - i)))
          for (dj in seq_len(min(as.double(remaining) - di + 2, length(ib) - j))) {
            next_map <- attempt(i + di, j + dj, mapping)
            if (is.null(next_map)) next
            extended <- TRUE
            walk(c(pa, i + di), c(pb, j + dj), next_map, skipped + di + dj - 2L)
          }
      }
      aa <- ia[pa]; bb <- ib[pb]
      count <- sum(a$token_count[aa])
      if (extended || length(aa) < min_statements || count < min_tokens) return(invisible(NULL))
      if (mode == "renamed" && all(a$normalized_key[aa] == b$normalized_key[bb])) return(invisible(NULL))
      keys <- paste(a$statement_id[aa], b$statement_id[bb], sep = "=")
      key <- paste(mode, paste(keys, collapse = "/"), sep = ":")
      if (exists(key, envir = seen, inherits = FALSE)) return(invisible(NULL))
      if (length(paths) >= max_results) stop("Code local result limit exceeded.")
      assign(key, TRUE, envir = seen)
      paths[[length(paths) + 1L]] <<- list(a = aa, b = bb, mapping = mapping, mode = mode, keys = keys)
    }
    for (i in seq_along(ia)) for (j in seq_along(ib)) {
      mapping <- attempt(i, j, empty_map)
      if (!is.null(mapping)) walk(i, j, mapping, 0L)
    }
  }
  keep <- vapply(seq_along(paths), function(i) !any(vapply(seq_along(paths), function(j)
    paths[[i]]$mode == paths[[j]]$mode && length(paths[[j]]$a) > length(paths[[i]]$a) &&
      all(paths[[i]]$keys %in% paths[[j]]$keys), logical(1))), logical(1))
  paths <- paths[keep]
  matches <- data.frame(file_id_a = character(), file_id_b = character(), unit_id_a = character(), unit_id_b = character(),
    method = character(), matched_statements = integer(), matched_tokens = integer(), skipped_statements = integer(),
    skipped_tokens = integer(), alignment_ratio = numeric(), start_line_a = integer(), end_line_a = integer(),
    start_line_b = integer(), end_line_b = integer(), stringsAsFactors = FALSE)
  list_cols <- c("statement_pairs", "variable_map", "token_starts_a", "token_ends_a", "token_starts_b", "token_ends_b",
    "skipped_statements_a", "skipped_statements_b")
  for (name in list_cols) matches[[name]] <- I(list())
  for (path in paths) {
    aa <- path$a; bb <- path$b
    skipped_a <- setdiff(seq.int(aa[1L], tail(aa, 1L)), aa)
    skipped_b <- setdiff(seq.int(bb[1L], tail(bb, 1L)), bb)
    skipped_tokens <- sum(a$token_count[skipped_a]) + sum(b$token_count[skipped_b])
    total <- sum(a$token_count[aa])
    row <- data.frame(file_id_a = a$file_id[aa[1L]], file_id_b = b$file_id[bb[1L]],
      unit_id_a = a$unit_id[aa[1L]], unit_id_b = b$unit_id[bb[1L]], method = path$mode,
      matched_statements = as.integer(length(aa)), matched_tokens = as.integer(total),
      skipped_statements = as.integer(length(skipped_a) + length(skipped_b)), skipped_tokens = as.integer(skipped_tokens),
      alignment_ratio = total / (total + skipped_tokens), start_line_a = a$start_line[aa[1L]],
      end_line_a = a$end_line[tail(aa, 1L)], start_line_b = b$start_line[bb[1L]], end_line_b = b$end_line[tail(bb, 1L)])
    row$statement_pairs <- I(list(data.frame(statement_id_a = a$statement_id[aa], statement_id_b = b$statement_id[bb],
      content_a = a$content[aa], content_b = b$content[bb], start_line_a = a$start_line[aa], end_line_a = a$end_line[aa],
      start_line_b = b$start_line[bb], end_line_b = b$end_line[bb], stringsAsFactors = FALSE)))
    row$variable_map <- I(list(path$mapping))
    for (side in c("a", "b")) for (edge in c("start", "end")) {
      table <- if (side == "a") a else b; indices <- if (side == "a") aa else bb
      positions <- as.integer(unlist(lapply(table$tokens[indices], function(t) t[[paste0(edge, "_offset")]]), use.names = FALSE))
      row[[paste0("token_", edge, "s_", side)]] <- I(list(positions))
    }
    row$skipped_statements_a <- I(list(a$statement_id[skipped_a]))
    row$skipped_statements_b <- I(list(b$statement_id[skipped_b]))
    matches <- rbind(matches, row[, names(matches), drop = FALSE])
  }
  if (nrow(matches)) {
    matches <- matches[order(-matches$matched_tokens, matches$skipped_tokens, matches$start_line_a, matches$start_line_b, matches$method), , drop = FALSE]
    rownames(matches) <- NULL
  }
  list(matches = matches, state_count = states, token_work = work)
}

.code_local_coverage <- function(doc, units, matches, side, lexical_only) {
  comparable <- as.integer(unlist(lapply(units$details, function(d) {
    if (d$parse_status != "ok") return(integer())
    d$tokens$start_offset[d$tokens$kind != "COMMENT" & d$tokens$text != ";"]
  }), use.names = FALSE))
  comparable <- unique(comparable)
  rows <- if (lexical_only) matches$method == "lexical" else rep(TRUE, nrow(matches))
  matched <- unique(as.integer(unlist(matches[[paste0("token_starts_", side)]][rows], use.names = FALSE)))
  if (!all(matched %in% comparable)) stop("Code coverage contains unknown token positions.")
  data.frame(side = toupper(side), file_id = doc$file_id, comparable_tokens = length(comparable),
    matched_tokens = length(matched), coverage = if (length(comparable)) length(matched) / length(comparable) else NA_real_,
    status = if (length(comparable)) "ok" else "insufficient_tokens", stringsAsFactors = FALSE)
}

analyze_code_pair_local <- function(doc_a, doc_b, window_tokens = 100L, window_statements = 20L,
    min_tokens = 20L, min_statements = 1L, max_skips = 1L, max_statements = 2000L,
    max_windows = 500L, max_candidates = 500L, max_seed_pairs = 100000L,
    max_states = 50000L, max_results = 1000L, max_token_work = 5000000L) {
  config <- list(window_tokens = window_tokens, window_statements = window_statements, min_tokens = min_tokens,
    min_statements = min_statements, max_statements = max_statements, max_windows = max_windows,
    max_candidates = max_candidates, max_seed_pairs = max_seed_pairs, max_states = max_states,
    max_results = max_results, max_token_work = max_token_work)
  config <- Map(code_positive_integer, config, names(config))
  max_skips <- .code_nonnegative_integer(max_skips, "max_skips"); config$max_skips <- max_skips
  if (config$window_statements > 20L || config$min_statements > config$window_statements)
    stop("Require min_statements <= window_statements <= 20.")
  ua <- prepare_code_units(doc_a); ub <- prepare_code_units(doc_b)
  a <- .code_statements_from_units(ua, config$max_statements)
  b <- .code_statements_from_units(ub, config$max_statements)
  wa <- make_code_windows(a, config$window_tokens, config$window_statements, config$max_windows)
  wb <- make_code_windows(b, config$window_tokens, config$window_statements, config$max_windows)
  candidates <- select_code_candidates(a, b, wa, wb, config$max_candidates, config$max_seed_pairs)
  local <- .code_local_matches(a, b, wa, wb, candidates, config$min_tokens, config$min_statements,
    config$max_skips, config$max_states, config$max_results, config$max_token_work)
  coverage <- rbind(.code_local_coverage(doc_a, ua, local$matches, "a", FALSE), .code_local_coverage(doc_b, ub, local$matches, "b", FALSE))
  lexical <- rbind(.code_local_coverage(doc_a, ua, local$matches, "a", TRUE), .code_local_coverage(doc_b, ub, local$matches, "b", TRUE))
  limited <- any(c(ua$code_status, ub$code_status) == "limited") ||
    any(c(doc_a$diagnostics$severity, doc_b$diagnostics$severity) %in% c("warning", "error"))
  status <- if (limited) "limited" else if (!nrow(ua) || !nrow(ub)) "not_applicable" else
    if (!nrow(a) || !nrow(b)) "insufficient_content" else "ok"
  list(status = status, matches = local$matches, coverage = coverage, lexical_coverage = lexical,
    code_a = ua, code_b = ub, statements_a = a, statements_b = b, windows_a = wa, windows_b = wb,
    candidates = candidates, state_count = local$state_count, token_work = local$token_work, parameters = config,
    diagnostics = list(a = doc_a$diagnostics, b = doc_b$diagnostics))
}
