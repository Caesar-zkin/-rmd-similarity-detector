# Requires parser.R and math.R. A step is one separately delimited math unit.
math_sequence_integer <- function(x, name, zero = FALSE) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x != floor(x) || x < (if (zero) 0 else 1) || x > .Machine$integer.max)
    stop(paste(name, "must be a representable", if (zero) "nonnegative" else "positive", "integer."))
  as.integer(x)
}

.extend_math_mapping <- function(x, y, mapping) {
  if (x$status != "ok" || y$status != "ok" ||
      !identical(x$structure_key, y$structure_key)) return(NULL)
  for (k in seq_along(x$tokens)) {
    if (x$kinds[k] != "variable") next
    a <- x$tokens[k]; b <- y$tokens[k]
    existing <- match(a, mapping$a)
    if (!is.na(existing)) {
      if (mapping$b[existing] != b) return(NULL)
    } else {
      if (b %in% mapping$b) return(NULL)
      mapping <- rbind(mapping, data.frame(a = a, b = b, stringsAsFactors = FALSE))
    }
  }
  mapping
}

.math_sequence_links <- function(doc, units, max_source_gap) {
  n <- nrow(units)
  if (n < 2L) return(logical())
  vapply(seq_len(n - 1L), function(i) {
    between <- doc$units$start_offset > units$end_offset[i] &
      doc$units$end_offset < units$start_offset[i + 1L]
    blocked <- any(doc$units$type[between] %in% c("heading", "code", "inline_r", "inline_code")) ||
      any(doc$units$status[between] != "ok")
    units$math_status[i] == "ok" && units$math_status[i + 1L] == "ok" &&
      identical(units$section[i], units$section[i + 1L]) && !blocked &&
      units$start_offset[i + 1L] - units$end_offset[i] - 1L <= max_source_gap
  }, logical(1))
}

find_math_sequences <- function(doc_a, doc_b, min_steps = 2L, max_steps = 5L,
    max_skips = 1L, max_source_gap = 2000L, max_pairs = 10000L,
    max_states = 20000L, max_results = 1000L, max_token_work = 5000000L,
    max_formulas = 500L) {
  min_steps <- math_sequence_integer(min_steps, "min_steps")
  max_steps <- math_sequence_integer(max_steps, "max_steps")
  max_skips <- math_sequence_integer(max_skips, "max_skips", TRUE)
  max_source_gap <- math_sequence_integer(max_source_gap, "max_source_gap", TRUE)
  max_pairs <- math_sequence_integer(max_pairs, "max_pairs")
  max_states <- math_sequence_integer(max_states, "max_states")
  max_results <- math_sequence_integer(max_results, "max_results")
  max_token_work <- math_sequence_integer(max_token_work, "max_token_work")
  max_formulas <- math_sequence_integer(max_formulas, "max_formulas")
  if (min_steps < 2L || min_steps > max_steps || max_steps > 20L)
    stop("Require 2 <= min_steps <= max_steps <= 20.")
  if (!inherits(doc_a, "rmd_document") || !inherits(doc_b, "rmd_document"))
    stop("Both inputs must be rmd_document objects.")
  na <- sum(doc_a$units$type == "math"); nb <- sum(doc_b$units$type == "math")
  if (max(na, nb) > max_formulas) stop("Formula unit limit exceeded.")
  if (as.double(na) * nb > max_pairs) stop("Formula pair limit exceeded.")
  a <- prepare_math_units(doc_a); b <- prepare_math_units(doc_b)
  links_a <- .math_sequence_links(doc_a, a, max_source_gap)
  links_b <- .math_sequence_links(doc_b, b, max_source_gap)
  states <- 0; token_work <- 0; paths <- list()
  attempt <- function(i, j, mapping) {
    states <<- states + 1
    token_work <<- token_work + max(a$token_count[i], b$token_count[j])
    if (states > max_states) stop("Formula search state limit exceeded.")
    if (token_work > max_token_work) stop("Formula token work limit exceeded.")
    .extend_math_mapping(a$details[[i]], b$details[[j]], mapping)
  }
  walk <- function(ia, ib, mapping, skipped) {
    i <- tail(ia, 1L); j <- tail(ib, 1L)
    extended <- FALSE
    if (length(ia) < max_steps && i < na && j < nb) {
      remaining <- max_skips - skipped
      for (di in seq_len(min(as.double(remaining) + 1, na - i))) {
        if (!all(links_a[seq.int(i, i + di - 1L)])) next
        for (dj in seq_len(min(as.double(remaining) - di + 2, nb - j))) {
          if (!all(links_b[seq.int(j, j + dj - 1L)])) next
          next_map <- attempt(i + di, j + dj, mapping)
          if (is.null(next_map)) next
          extended <- TRUE
          walk(c(ia, i + di), c(ib, j + dj), next_map, skipped + di + dj - 2L)
        }
      }
    }
    if (!extended && length(ia) >= min_steps) {
      if (length(paths) >= max_results) stop("Formula result limit exceeded.")
      paths[[length(paths) + 1L]] <<- list(a = ia, b = ib, mapping = mapping,
        skipped = skipped, keys = paste(ia, ib, sep = ":"))
    }
  }
  empty_map <- data.frame(a = character(), b = character(), stringsAsFactors = FALSE)
  for (i in seq_len(na)) for (j in seq_len(nb)) {
    mapping <- attempt(i, j, empty_map)
    if (!is.null(mapping)) walk(i, j, mapping, 0L)
  }
  # Remove contained paths, preserving distinct positional alignments.
  keep <- vapply(seq_along(paths), function(i) {
    !any(vapply(seq_along(paths), function(j) length(paths[[j]]$a) > length(paths[[i]]$a) &&
      all(paths[[i]]$keys %in% paths[[j]]$keys), logical(1)))
  }, logical(1))
  paths <- paths[keep]
  matches <- data.frame(file_id_a = character(), file_id_b = character(),
    matched_steps = integer(), skipped_steps = integer(), step_similarity = numeric(),
    token_count = integer(), raw_equal = logical(), normalized_equal = logical(),
    start_line_a = integer(), end_line_a = integer(), start_line_b = integer(), end_line_b = integer(),
    stringsAsFactors = FALSE)
  for (name in c("step_pairs", "variable_map", "skipped_units_a", "skipped_units_b")) matches[[name]] <- I(list())
  for (path in paths) {
    ia <- path$a; ib <- path$b
    pairs <- data.frame(unit_id_a = a$unit_id[ia], unit_id_b = b$unit_id[ib],
      content_a = a$content[ia], content_b = b$content[ib],
      start_line_a = a$start_line[ia], end_line_a = a$end_line[ia],
      start_line_b = b$start_line[ib], end_line_b = b$end_line[ib], stringsAsFactors = FALSE)
    pairs$token_positions_a <- I(lapply(a$details[ia], function(x) x$source_positions))
    pairs$token_positions_b <- I(lapply(b$details[ib], function(x) x$source_positions))
    raw <- all(vapply(seq_along(ia), function(k) identical(a$content[ia[k]], b$content[ib[k]]), logical(1)))
    normalized <- all(vapply(seq_along(ia), function(k)
      identical(a$details[[ia[k]]]$normalized_key, b$details[[ib[k]]]$normalized_key), logical(1)))
    row <- data.frame(file_id_a = doc_a$file_id, file_id_b = doc_b$file_id,
      matched_steps = length(ia), skipped_steps = path$skipped,
      step_similarity = length(ia) / (length(ia) + path$skipped),
      token_count = as.integer(sum(a$token_count[ia])), raw_equal = raw, normalized_equal = normalized,
      start_line_a = a$start_line[ia[1L]], end_line_a = a$end_line[tail(ia, 1L)],
      start_line_b = b$start_line[ib[1L]], end_line_b = b$end_line[tail(ib, 1L)], stringsAsFactors = FALSE)
    row$step_pairs <- I(list(pairs)); row$variable_map <- I(list(path$mapping))
    row$skipped_units_a <- I(list(a$unit_id[setdiff(seq.int(ia[1L], tail(ia, 1L)), ia)]))
    row$skipped_units_b <- I(list(b$unit_id[setdiff(seq.int(ib[1L], tail(ib, 1L)), ib)]))
    matches <- rbind(matches, row)
  }
  if (nrow(matches)) {
    matches <- matches[order(-matches$matched_steps, matches$skipped_steps,
      matches$start_line_a, matches$start_line_b), , drop = FALSE]
    rownames(matches) <- NULL
  }
  limited <- any(c(a$math_status, b$math_status) == "limited") ||
    any(c(doc_a$diagnostics$severity, doc_b$diagnostics$severity) %in% c("warning", "error"))
  status <- if (limited) "limited" else if (!na || !nb) "not_applicable" else
    if (min(sum(a$math_status == "ok"), sum(b$math_status == "ok")) < min_steps)
      "insufficient_steps" else "ok"
  list(status = status, matches = matches, formulas_a = a, formulas_b = b,
    state_count = states, token_work = token_work,
    parameters = list(min_steps = min_steps, max_steps = max_steps, max_skips = max_skips,
      max_source_gap = max_source_gap, max_pairs = max_pairs, max_states = max_states,
      max_results = max_results, max_token_work = max_token_work, max_formulas = max_formulas),
    diagnostics = list(a = doc_a$diagnostics, b = doc_b$diagnostics))
}
