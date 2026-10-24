# Exact normalized text matching. Load parser.R and text.R first.

empty_text_blocks <- function() {
  out <- data.frame(
    match_id = character(), file_id_a = character(), file_id_b = character(),
    unit_id_a = character(), unit_id_b = character(), text = character(),
    matched_chars = integer(), normalized_start_a = integer(),
    normalized_end_a = integer(), normalized_start_b = integer(),
    normalized_end_b = integer(), start_line_a = integer(), end_line_a = integer(),
    start_line_b = integer(), end_line_b = integer(), stringsAsFactors = FALSE
  )
  out$source_positions_a <- I(vector("list", 0L))
  out$source_positions_b <- I(vector("list", 0L))
  out
}

# Merge overlapping/adjacent seeds with the same unit pair and alignment shift.
merge_exact_text_matches <- function(
    doc_a, doc_b, k = 5L, min_chars = 30L, max_pairs = 50000L) {
  if (!is.numeric(min_chars) || length(min_chars) != 1L ||
      is.na(min_chars) || !is.finite(min_chars) || min_chars < 1 ||
      min_chars != floor(min_chars) || min_chars > .Machine$integer.max) {
    stop("min_chars must be a positive integer.")
  }
  hits <- match_text_ngrams(doc_a, doc_b, k = k, max_pairs = max_pairs)
  if (!nrow(hits)) return(empty_text_blocks())
  a <- prepare_text_units(doc_a); b <- prepare_text_units(doc_b)
  rows <- list()
  # which() handles a newline at position 1 correctly, including empty sources.
  line_starts <- function(text) {
    chars <- strsplit(text, "", fixed = TRUE)[[1L]]
    c(1L, which(chars == "\n") + 1L)
  }
  lines_a <- line_starts(doc_a$source)
  lines_b <- line_starts(doc_b$source)

  emit <- function(ia, ib, sa, ea, sb, eb) {
    len <- ea - sa + 1L
    if (len < min_chars) return(invisible(NULL))
    ta <- substr(a$normalized_text[ia], sa, ea)
    tb <- substr(b$normalized_text[ib], sb, eb)
    if (!identical(ta, tb)) stop("Internal error: merged text does not agree.")
    pa <- a$source_positions[[ia]][seq.int(sa, ea)]
    pb <- b$source_positions[[ib]][seq.int(sb, eb)]
    row <- data.frame(
      match_id = "", file_id_a = doc_a$file_id, file_id_b = doc_b$file_id,
      unit_id_a = a$unit_id[ia], unit_id_b = b$unit_id[ib], text = ta,
      matched_chars = as.integer(len), normalized_start_a = as.integer(sa),
      normalized_end_a = as.integer(ea), normalized_start_b = as.integer(sb),
      normalized_end_b = as.integer(eb),
      start_line_a = as.integer(findInterval(pa[1L], lines_a)),
      end_line_a = as.integer(findInterval(tail(pa, 1L), lines_a)),
      start_line_b = as.integer(findInterval(pb[1L], lines_b)),
      end_line_b = as.integer(findInterval(tail(pb, 1L), lines_b)),
      stringsAsFactors = FALSE
    )
    row$source_positions_a <- I(list(pa))
    row$source_positions_b <- I(list(pb))
    rows[[length(rows) + 1L]] <<- row
  }

  shift <- hits$normalized_start_b - hits$normalized_start_a
  keys <- paste(hits$unit_id_a, hits$unit_id_b, shift, sep = ":")
  groups <- split(seq_len(nrow(hits)), keys)
  for (indices in groups) {
    g <- hits[indices, , drop = FALSE]
    g <- g[order(g$normalized_start_a), , drop = FALSE]
    ia <- match(g$unit_id_a[1L], a$unit_id)
    ib <- match(g$unit_id_b[1L], b$unit_id)
    sa <- g$normalized_start_a[1L]; ea <- g$normalized_end_a[1L]
    sb <- g$normalized_start_b[1L]; eb <- g$normalized_end_b[1L]
    for (j in seq_len(nrow(g))[-1L]) {
      if (g$normalized_start_a[j] <= ea + 1L) {
        ea <- max(ea, g$normalized_end_a[j])
        eb <- max(eb, g$normalized_end_b[j])
      } else {
        emit(ia, ib, sa, ea, sb, eb)
        sa <- g$normalized_start_a[j]; ea <- g$normalized_end_a[j]
        sb <- g$normalized_start_b[j]; eb <- g$normalized_end_b[j]
      }
    }
    emit(ia, ib, sa, ea, sb, eb)
  }
  if (!length(rows)) return(empty_text_blocks())
  out <- do.call(rbind, rows)
  out <- out[order(-out$matched_chars, out$unit_id_a,
    out$normalized_start_a, out$unit_id_b, out$normalized_start_b), , drop = FALSE]
  rownames(out) <- NULL
  out$match_id <- sprintf("m%05d", seq_len(nrow(out)))
  out
}

# Coverage uses actual source character sets, not lengths of bounding intervals.
summarize_text_coverage <- function(doc_a, doc_b, blocks) {
  if (!is.data.frame(blocks) ||
      !all(c("source_positions_a", "source_positions_b") %in% names(blocks))) {
    stop("blocks must be a text block table with both position columns.")
  }
  positions <- function(x) sort(unique(as.integer(unlist(x, use.names = FALSE))))
  valid_a <- positions(prepare_text_units(doc_a)$source_positions)
  valid_b <- positions(prepare_text_units(doc_b)$source_positions)
  matched_a <- positions(blocks$source_positions_a)
  matched_b <- positions(blocks$source_positions_b)
  if (!all(matched_a %in% valid_a) || !all(matched_b %in% valid_b)) {
    stop("Matched positions must belong to comparable text in each document.")
  }
  total <- c(length(valid_a), length(valid_b))
  covered <- c(length(matched_a), length(matched_b))
  ratio <- rep(NA_real_, 2L)
  ratio[total > 0L] <- covered[total > 0L] / total[total > 0L]
  data.frame(side = c("A", "B"), file_id = c(doc_a$file_id, doc_b$file_id),
    comparable_chars = total, matched_chars = covered, coverage = ratio,
    status = ifelse(total > 0L, "ok", "no_comparable_text"),
    stringsAsFactors = FALSE)
}

# This is a text-only analysis, not a plagiarism verdict.
analyze_text_pair <- function(
    doc_a, doc_b, k = 5L, min_chars = 30L, max_pairs = 50000L) {
  jaccard <- compare_text_jaccard(doc_a, doc_b, k = k)
  blocks <- merge_exact_text_matches(doc_a, doc_b, k, min_chars, max_pairs)
  coverage <- summarize_text_coverage(doc_a, doc_b, blocks)
  has_warnings <- any(doc_a$diagnostics$severity == "warning") ||
    any(doc_b$diagnostics$severity == "warning")
  status <- if (jaccard$status != "ok") "insufficient_ngrams" else
    if (has_warnings) "limited" else "ok"
  list(status = status,
    parameters = list(k = as.integer(k), min_chars = as.integer(min_chars),
      max_pairs = max_pairs),
    jaccard = jaccard, exact_matches = blocks, coverage = coverage,
    diagnostics = list(a = doc_a$diagnostics, b = doc_b$diagnostics))
}
