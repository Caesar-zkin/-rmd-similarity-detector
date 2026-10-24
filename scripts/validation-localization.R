# Side-wise localization of known copied-origin regions. Not a plagiarism verdict.
validation_position_metrics <- function(universe, predicted, gold, available = TRUE) {
  universe <- unique(universe); predicted <- unique(predicted); gold <- unique(gold)
  if (anyNA(universe) || anyNA(predicted) || anyNA(gold) ||
      !all(predicted %in% universe) || !all(gold %in% universe))
    stop("Localization positions must belong to the comparable universe.")
  if (!isTRUE(available)) return(data.frame(comparable = NA_integer_, gold = NA_integer_,
    predicted = NA_integer_, tp = NA_integer_, fp = NA_integer_, fn = NA_integer_,
    precision = NA_real_, recall = NA_real_, evaluation_status = "analysis_unavailable"))
  tp <- length(intersect(predicted, gold))
  data.frame(comparable = length(universe), gold = length(gold), predicted = length(predicted),
    tp = tp, fp = length(setdiff(predicted, gold)), fn = length(setdiff(gold, predicted)),
    precision = if (length(predicted)) tp / length(predicted) else NA_real_,
    recall = if (length(gold)) tp / length(gold) else NA_real_,
    evaluation_status = if (!length(universe)) "no_comparable_content" else if (!length(gold)) "no_gold_for_method" else "ok")
}

evaluate_validation_localization <- function(result, annotations, pair_id) {
  contains <- function(positions, ranges) {
    vapply(positions, function(p) any(as.numeric(ranges$start) <= p & as.numeric(ranges$end) >= p), logical(1))
  }
  contains_token <- function(s, e, ranges) {
    vapply(seq_along(s), function(i) any(as.numeric(ranges$start) <= s[i] & as.numeric(ranges$end) >= e[i]), logical(1))
  }
  rows <- list()
  for (side in c("A", "B")) for (method in c("text", "code_local", "formula_sequence")) {
    m <- result$modules[[method]]; v <- m$value; doc <- result$documents[[side]]
    kind <- switch(method, text = "text", code_local = "code", formula_sequence = "math")
    unit <- switch(method, text = "character", code_local = "token", formula_sequence = "step")
    a <- annotations[annotations$pair_id == pair_id & annotations$side == side & annotations$kind == kind, , drop = FALSE]
    available <- inherits(doc, "rmd_document") && !is.null(v) && !m$status %in% c("error", "not_run")
    universe <- predicted <- gold <- integer()
    if (available && method == "text") {
      u <- prepare_text_units(doc)
      universe <- unique(as.integer(unlist(u$source_positions, use.names = FALSE)))
      column <- paste0("source_positions_", tolower(side))
      predicted <- unique(as.integer(c(unlist(v$exact_matches[[column]], use.names = FALSE),
        unlist(v$approximate_matches[[column]], use.names = FALSE))))
      gold <- universe[contains(universe, a)]
    }
    if (available && method == "code_local") {
      u <- v[[paste0("code_", tolower(side))]]
      tokens <- lapply(u$details, function(d) {
        if (d$parse_status != "ok") return(NULL)
        t <- d$tokens; t[t$kind != "COMMENT" & t$text != ";", , drop = FALSE]
      })
      tokens <- Filter(Negate(is.null), tokens)
      if (length(tokens)) {
        t <- do.call(rbind, tokens)
        universe <- t$start_offset
        gold <- t$start_offset[contains_token(t$start_offset, t$end_offset, a)]
      }
      predicted <- as.integer(unlist(v$matches[[paste0("token_starts_", tolower(side))]], use.names = FALSE))
    }
    if (available && method == "formula_sequence") {
      u <- v[[paste0("formulas_", tolower(side))]]
      u <- u[u$math_status == "ok" & u$token_count > 0L, , drop = FALSE]
      universe <- u$unit_id
      gold <- universe[vapply(u$details, function(d) {
        p <- as.integer(unlist(d$source_positions, use.names = FALSE))
        length(p) > 0L && all(contains(p, a))
      }, logical(1))]
      predicted <- unlist(lapply(v$matches$step_pairs, function(p) p[[paste0("unit_id_", tolower(side))]]), use.names = FALSE)
    }
    metrics <- validation_position_metrics(universe, predicted, gold, available)
    row <- cbind(data.frame(pair_id = pair_id, side = side, method = method, unit = unit,
      analysis_status = m$status, annotated_regions = nrow(a), scope = "comparable_origin_positions_only", stringsAsFactors = FALSE), metrics)
    rows[[length(rows) + 1L]] <- row
  }
  do.call(rbind, rows)
}
