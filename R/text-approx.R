# Seed/window candidates and local alignment. Base R, no network or evaluation.
# Load parser.R, text.R and text-matches.R first.

.text_approximation_limit <- function(message) {
  stop(errorCondition(message, class = "text_approximation_limit"))
}

text_positive_integer <- function(x, name) {
  if (!is.numeric(x) || length(x) != 1L || is.na(x) || !is.finite(x) ||
      x < 1 || x != floor(x) || x > .Machine$integer.max)
    stop(name, " must be a positive integer.")
  as.integer(x)
}

make_text_windows <- function(doc, window_size = 200L, max_windows = 2000L) {
  size <- text_positive_integer(window_size, "window_size")
  limit <- text_positive_integer(max_windows, "max_windows")
  u <- prepare_text_units(doc)
  out <- data.frame(window_id = character(), unit_id = character(),
    start = integer(), end = integer(), text = character(), stringsAsFactors = FALSE)
  out$source_positions <- I(vector("list", 0L))
  rows <- list(); step <- max(1L, size %/% 2L)
  for (i in seq_len(nrow(u))) {
    n <- nchar(u$normalized_text[i], type = "chars")
    if (!n) next
    last <- max(1L, n - size + 1L)
    starts <- unique(c(seq.int(1L, last, by = step), last))
    if (length(rows) + length(starts) > limit)
      .text_approximation_limit("Window count exceeds max_windows; no partial result produced.")
    for (s in starts) {
      e <- min(n, s + size - 1L)
      row <- data.frame(window_id = sprintf("w%05d", length(rows) + 1L),
        unit_id = u$unit_id[i], start = as.integer(s), end = as.integer(e),
        text = substr(u$normalized_text[i], s, e), stringsAsFactors = FALSE)
      row$source_positions <- I(list(u$source_positions[[i]][seq.int(s, e)]))
      rows[[length(rows) + 1L]] <- row
    }
  }
  if (!length(rows)) return(out)
  result <- do.call(rbind, rows); rownames(result) <- NULL
  result
}

select_text_candidates <- function(windows_a, windows_b, seed_k = 3L,
    max_candidates = 500L, max_seed_pairs = 100000L) {
  k <- text_positive_integer(seed_k, "seed_k")
  limit <- text_positive_integer(max_candidates, "max_candidates")
  seed_limit <- text_positive_integer(max_seed_pairs, "max_seed_pairs")
  index <- function(w) {
    rows <- lapply(seq_len(nrow(w)), function(i) {
      g <- unique(make_character_ngrams(w$text[i], k)$gram)
      data.frame(gram = g, window = rep.int(i, length(g)), stringsAsFactors = FALSE)
    })
    if (!length(rows)) return(data.frame(gram = character(), window = integer()))
    do.call(rbind, rows)
  }
  a <- index(windows_a); b <- index(windows_b)
  ca <- table(a$gram); cb <- table(b$gram)
  common <- intersect(names(ca), names(cb))
  seed_pairs <- sum(as.double(ca[common]) * as.double(cb[common]))
  if (seed_pairs > seed_limit)
    .text_approximation_limit("Shared-seed combinations exceed max_seed_pairs; no partial result produced.")
  if (!seed_pairs) return(data.frame(window_a = integer(), window_b = integer(), shared_seeds = integer()))
  hits <- merge(a, b, by = "gram", suffixes = c("_a", "_b"), sort = FALSE)
  pairs <- aggregate(rep.int(1L, nrow(hits)),
    by = list(window_a = hits$window_a, window_b = hits$window_b), FUN = sum)
  names(pairs)[3L] <- "shared_seeds"
  if (nrow(pairs) > limit)
    .text_approximation_limit("Candidate count exceeds max_candidates; no partial result produced.")
  pairs <- pairs[order(-pairs$shared_seeds, pairs$window_a, pairs$window_b), , drop = FALSE]
  rownames(pairs) <- NULL
  pairs
}

# One best local alignment per pair. Fixed scores: equal +2, replace -1, gap -2.
# Equal-score ties prefer reset, diagonal, consume A, then consume B; earliest maximum wins.
align_text_local <- function(text_a, text_b, max_cells = 250000L) {
  validate <- function(x) {
    if (!is.character(x) || length(x) != 1L || is.na(x))
      stop("Alignment inputs must be single non-missing strings.")
    strsplit(enc2utf8(x), "", fixed = TRUE)[[1L]]
  }
  a <- validate(text_a); b <- validate(text_b)
  limit <- text_positive_integer(max_cells, "max_cells")
  n <- length(a); m <- length(b)
  empty <- list(score = 0, similarity = NA_real_, equal_chars = 0L,
    columns = 0L, indices_a = integer(), indices_b = integer(),
    operations = character(), aligned_a = "", aligned_b = "")
  if (!n || !m) return(empty)
  if ((as.double(n) + 1) * (as.double(m) + 1) > limit)
    stop("Alignment matrix exceeds max_cells.")
  h <- matrix(0, n + 1L, m + 1L)
  trace <- matrix(0L, n + 1L, m + 1L)
  best <- 0; best_i <- 0L; best_j <- 0L
  for (i in seq_len(n)) for (j in seq_len(m)) {
    values <- c(0, h[i, j] + if (a[i] == b[j]) 2 else -1,
      h[i, j + 1L] - 2, h[i + 1L, j] - 2)
    choice <- which.max(values)
    h[i + 1L, j + 1L] <- values[choice]
    trace[i + 1L, j + 1L] <- choice - 1L
    if (values[choice] > best) {
      best <- values[choice]; best_i <- i; best_j <- j
    }
  }
  if (!best) return(empty)
  i <- best_i; j <- best_j; ia <- integer(); ib <- integer(); ops <- character()
  while (i > 0L && j > 0L && h[i + 1L, j + 1L] > 0) {
    move <- trace[i + 1L, j + 1L]
    if (move == 1L) {
      ia <- c(ia, i); ib <- c(ib, j)
      ops <- c(ops, if (a[i] == b[j]) "equal" else "replace")
      i <- i - 1L; j <- j - 1L
    } else if (move == 2L) {
      ia <- c(ia, i); ib <- c(ib, NA_integer_); ops <- c(ops, "consume_a")
      i <- i - 1L
    } else if (move == 3L) {
      ia <- c(ia, NA_integer_); ib <- c(ib, j); ops <- c(ops, "consume_b")
      j <- j - 1L
    } else break
  }
  ia <- rev(ia); ib <- rev(ib); ops <- rev(ops)
  shown_a <- rep("-", length(ia)); shown_b <- rep("-", length(ib))
  shown_a[!is.na(ia)] <- a[ia[!is.na(ia)]]
  shown_b[!is.na(ib)] <- b[ib[!is.na(ib)]]
  list(score = best, similarity = sum(ops == "equal") / length(ops),
    equal_chars = as.integer(sum(ops == "equal")), columns = length(ops),
    indices_a = ia, indices_b = ib, operations = ops,
    aligned_a = paste0(shown_a, collapse = ""), aligned_b = paste0(shown_b, collapse = ""))
}

empty_approximate_matches <- function() {
  out <- data.frame(match_id = character(), unit_id_a = character(),
    unit_id_b = character(), text_a = character(), text_b = character(),
    aligned_a = character(), aligned_b = character(), equal_chars = integer(),
    alignment_columns = integer(), similarity = numeric(), score = numeric(),
    start_line_a = integer(), end_line_a = integer(), start_line_b = integer(),
    end_line_b = integer(), stringsAsFactors = FALSE)
  for (name in c("source_positions_a", "source_positions_b",
      "aligned_positions_a", "aligned_positions_b", "operations"))
    out[[name]] <- I(vector("list", 0L))
  out
}

find_approximate_text_matches <- function(doc_a, doc_b, seed_k = 3L,
    window_size = 200L, min_chars = 30L, min_similarity = 0.8,
    max_windows = 2000L, max_candidates = 500L, max_seed_pairs = 100000L,
    max_cells = 250000L, max_total_cells = 5000000L) {
  minimum <- text_positive_integer(min_chars, "min_chars")
  seed_k <- text_positive_integer(seed_k, "seed_k")
  cells_limit <- text_positive_integer(max_cells, "max_cells")
  total_limit <- text_positive_integer(max_total_cells, "max_total_cells")
  if (!is.numeric(min_similarity) || length(min_similarity) != 1L ||
      is.na(min_similarity) || !is.finite(min_similarity) ||
      min_similarity < 0 || min_similarity > 1)
    stop("min_similarity must be between 0 and 1.")
  wa <- make_text_windows(doc_a, window_size, max_windows)
  wb <- make_text_windows(doc_b, window_size, max_windows)
  candidates <- select_text_candidates(wa, wb, seed_k, max_candidates, max_seed_pairs)
  sizes <- (nchar(wa$text[candidates$window_a]) + 1) *
    (nchar(wb$text[candidates$window_b]) + 1)
  if (any(sizes > cells_limit) || sum(sizes) > total_limit)
    .text_approximation_limit("Alignment work exceeds max_cells or max_total_cells; no partial result produced.")
  lines <- function(text) c(1L, which(strsplit(text, "", fixed = TRUE)[[1L]] == "\n") + 1L)
  la <- lines(doc_a$source); lb <- lines(doc_b$source); rows <- list()
  for (i in seq_len(nrow(candidates))) {
    a <- wa[candidates$window_a[i], , drop = FALSE]
    b <- wb[candidates$window_b[i], , drop = FALSE]
    aligned <- align_text_local(a$text, b$text, max_cells = cells_limit)
    if (aligned$equal_chars < minimum || is.na(aligned$similarity) ||
        aligned$similarity < min_similarity) next
    pa <- a$source_positions[[1L]][aligned$indices_a]
    pb <- b$source_positions[[1L]][aligned$indices_b]
    equal <- aligned$operations == "equal"
    used_a <- aligned$indices_a[!is.na(aligned$indices_a)]
    used_b <- aligned$indices_b[!is.na(aligned$indices_b)]
    row <- data.frame(match_id = "", unit_id_a = a$unit_id,
      unit_id_b = b$unit_id, text_a = substr(a$text, min(used_a), max(used_a)),
      text_b = substr(b$text, min(used_b), max(used_b)),
      aligned_a = aligned$aligned_a, aligned_b = aligned$aligned_b,
      equal_chars = aligned$equal_chars, alignment_columns = aligned$columns,
      similarity = aligned$similarity, score = aligned$score,
      start_line_a = as.integer(findInterval(min(pa, na.rm = TRUE), la)),
      end_line_a = as.integer(findInterval(max(pa, na.rm = TRUE), la)),
      start_line_b = as.integer(findInterval(min(pb, na.rm = TRUE), lb)),
      end_line_b = as.integer(findInterval(max(pb, na.rm = TRUE), lb)), stringsAsFactors = FALSE)
    # Only truly equal aligned characters contribute to the coverage numerator.
    row$source_positions_a <- I(list(pa[equal]))
    row$source_positions_b <- I(list(pb[equal]))
    row$aligned_positions_a <- I(list(pa))
    row$aligned_positions_b <- I(list(pb))
    row$operations <- I(list(aligned$operations))
    rows[[length(rows) + 1L]] <- row
  }
  out <- if (length(rows)) do.call(rbind, rows) else empty_approximate_matches()
  if (nrow(out)) {
    keys <- vapply(seq_len(nrow(out)), function(i) paste(out$unit_id_a[i],
      out$unit_id_b[i], paste(out$source_positions_a[[i]], collapse = ","),
      paste(out$source_positions_b[[i]], collapse = ","), sep = ":"), character(1))
    ord <- order(-out$similarity, -out$equal_chars, -out$score)
    out <- out[ord, , drop = FALSE]; keys <- keys[ord]
    out <- out[!duplicated(keys), , drop = FALSE]
    out$match_id <- sprintf("a%05d", seq_len(nrow(out))); rownames(out) <- NULL
  }
  enough <- any(nchar(wa$text) >= seed_k) && any(nchar(wb$text) >= seed_k)
  list(status = if (enough) "ok" else "insufficient_ngrams", matches = out,
    candidates = candidates, windows_a = nrow(wa), windows_b = nrow(wb),
    alignment_cells = sum(sizes))
}

find_short_text_matches <- function(doc_a, doc_b, min_chars, max_pairs = 10000L) {
  # Use complete units and require a unique counterpart on both sides.
  units_a <- prepare_text_units(doc_a); units_b <- prepare_text_units(doc_b)
  repeated <- c(units_a$normalized_text[duplicated(units_a$normalized_text)],
    units_b$normalized_text[duplicated(units_b$normalized_text)])
  short_units <- function(units) {
    x <- units$normalized_text
    keep <- nchar(x) >= 8L & nchar(x) <= min(min_chars + 4, 60L) &
      grepl("[[:alnum:]]", x) & !x %in% repeated
    units[keep, , drop = FALSE]
  }
  a <- short_units(units_a); b <- short_units(units_b)
  x <- a$normalized_text; y <- b$normalized_text
  na <- nchar(x); nb <- nchar(y)
  exact <- match(x, y)
  ia <- which(!is.na(exact) & na < min_chars)
  ib <- exact[ia]
  xa <- which(is.na(exact) & na >= 12L)
  yb <- which(!y %in% x & nb >= 12L)
  limited <- as.double(length(xa)) * length(yb) > max_pairs
  if (!limited && length(xa) && length(yb)) {
    distance <- utils::adist(x[xa], y[yb])
    lengths <- outer(na[xa], nb[yb], pmax)
    short_enough <- outer(na[xa], nb[yb], pmin) < min_chars
    candidates <- short_enough & distance <= pmax(1L, floor(.15 * lengths))
    pair <- which(candidates & rowSums(candidates) == 1L &
      rep(colSums(candidates) == 1L, each = nrow(candidates)), arr.ind = TRUE)
    ia <- c(ia, xa[pair[, 1L]]); ib <- c(ib, yb[pair[, 2L]])
  }
  matches <- data.frame(start_line_a = a$start_line[ia], end_line_a = a$end_line[ia],
    start_line_b = b$start_line[ib], end_line_b = b$end_line[ib],
    equal_chars = integer(length(ia)), similarity = numeric(length(ia)),
    text_a = a$content[ia], text_b = b$content[ib])
  positions_a <- positions_b <- vector("list", length(ia))
  for (i in seq_along(ia)) {
    j <- ia[i]; k <- ib[i]
    transform <- if (x[j] == y[k]) strrep("M", na[j]) else
      attr(utils::adist(x[j], y[k], counts = TRUE), "trafos")[1L, 1L]
    operations <- strsplit(transform, "", fixed = TRUE)[[1L]]
    equal <- operations == "M"
    positions_a[[i]] <- a$source_positions[[j]][cumsum(operations != "I")[equal]]
    positions_b[[i]] <- b$source_positions[[k]][cumsum(operations != "D")[equal]]
    matches$equal_chars[i] <- sum(equal)
    matches$similarity[i] <- sum(equal) / length(operations)
  }
  matches$source_positions_a <- I(positions_a)
  matches$source_positions_b <- I(positions_b)
  list(matches = matches, limited = limited)
}

analyze_text_pair_approx <- function(doc_a, doc_b, k = 5L, min_chars = 30L,
    min_similarity = 0.8, seed_k = 3L, window_size = 200L,
    max_pairs = 50000L, max_windows = 2000L, max_candidates = 500L,
    max_seed_pairs = 100000L, max_cells = 250000L, max_total_cells = 5000000L) {
  exact <- analyze_text_pair(doc_a, doc_b, k, min_chars, max_pairs)
  approximate <- tryCatch(
    find_approximate_text_matches(doc_a, doc_b, seed_k, window_size,
      min_chars, min_similarity, max_windows, max_candidates, max_seed_pairs,
      max_cells, max_total_cells),
    text_approximation_limit = function(e) list(status = "resource_limit",
      error = conditionMessage(e), matches = empty_approximate_matches(), alignment_cells = NA_real_))
  limited <- approximate$status == "resource_limit"
  columns <- c("source_positions_a", "source_positions_b")
  combined <- rbind(exact$exact_matches[, columns, drop = FALSE],
    approximate$matches[, columns, drop = FALSE])
  short <- if (!limited) find_short_text_matches(doc_a, doc_b, min_chars)
  coverage <- summarize_text_coverage(doc_a, doc_b, combined)
  warnings <- any(doc_a$diagnostics$severity == "warning") ||
    any(doc_b$diagnostics$severity == "warning")
  enough <- exact$jaccard$status == "ok" || approximate$status == "ok"
  list(status = if (limited) "limited" else if (!enough) "insufficient_ngrams" else if (warnings) "limited" else "ok",
    parameters = list(k = k, min_chars = min_chars, min_similarity = min_similarity,
      seed_k = seed_k, window_size = window_size, max_pairs = max_pairs,
      max_windows = max_windows, max_candidates = max_candidates,
      max_seed_pairs = max_seed_pairs, max_cells = max_cells, max_total_cells = max_total_cells),
    jaccard = exact$jaccard, exact_matches = exact$exact_matches,
    approximate_matches = approximate$matches, exact_coverage = exact$coverage,
    approximate_status = approximate$status, approximate_error = if (limited) approximate$error else "",
    coverage = coverage, short_matches = short$matches, short_matching_limited = isTRUE(short$limited),
    coverage_with_short = if (is.null(short) || !nrow(short$matches)) coverage else
      summarize_text_coverage(doc_a, doc_b, rbind(combined, short$matches[, columns])),
    candidate_count = if (limited) NA_integer_ else nrow(approximate$candidates),
    alignment_cells = approximate$alignment_cells,
    diagnostics = exact$diagnostics)
}
