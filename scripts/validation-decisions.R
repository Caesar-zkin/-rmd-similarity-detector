# Descriptive development observations, never final-classifier accuracy.
# Pending material is reported but never treated as an observed negative.
summarize_validation_decisions <- function(pairs, results) {
  required_pairs <- c("pair_id", "split", "variant", "label", "status")
  required_results <- c("pair_id", "label", "candidate_verdict", "decision_status",
    "rule_version", "decision_stage")
  if (!is.data.frame(pairs) || !is.data.frame(results) ||
      !all(required_pairs %in% names(pairs)) || !all(required_results %in% names(results)))
    stop("Missing decision-summary columns.")
  if (anyNA(pairs[, required_pairs]) || anyNA(results[, required_results]) ||
      anyDuplicated(pairs$pair_id) || anyDuplicated(results$pair_id) ||
      any(!nzchar(pairs$pair_id)) ||
      !all(pairs$split %in% c("dev", "holdout")) ||
      !all(pairs$status %in% c("ready", "pending")) ||
      !all(pairs$label %in% c("copied", "independent", "unassigned")) ||
      any(pairs$status == "ready" & pairs$label == "unassigned") ||
      !all(nzchar(pairs$variant))) stop("Invalid summary registry or duplicate results.")
  dev <- pairs[pairs$split == "dev", , drop = FALSE]
  ready <- dev[dev$status == "ready", , drop = FALSE]
  # A pending slot's variant describes its planned material, not an observed truth.
  pending <- dev$status == "pending" & dev$label == "unassigned"
  dev$label[pending] <- ifelse(dev$variant[pending] == "independent", "independent", "copied")
  if (!setequal(results$pair_id, ready$pair_id))
    stop("Results must contain exactly the ready development pairs.")
  aligned <- results[match(ready$pair_id, results$pair_id), , drop = FALSE]
  if (!identical(as.character(aligned$label), as.character(ready$label)) ||
      !all(aligned$candidate_verdict %in% c("suspected", "no_clear_evidence", "insufficient_evidence")) ||
      !all(aligned$decision_status %in% c("ok", "error")) ||
      any(aligned$decision_status == "error" & aligned$candidate_verdict != "insufficient_evidence"))
    stop("Invalid candidate outcome or mismatched truth label.")
  if (nrow(aligned) && (length(unique(aligned$rule_version)) != 1L ||
      any(!nzchar(aligned$rule_version)) ||
      !all(aligned$decision_stage == "development_unvalidated")))
    stop("Do not mix rule versions or decision stages.")
  rows <- list()
  scopes <- c("all", unique(dev$variant))
  for (scope in scopes) for (truth in c("copied", "independent")) {
    p <- dev[dev$label == truth & (scope == "all" | dev$variant == scope), , drop = FALSE]
    if (!nrow(p) && scope != "all") next
    r <- aligned[aligned$pair_id %in% p$pair_id, , drop = FALSE]
    n <- nrow(r)
    suspected <- sum(r$candidate_verdict == "suspected")
    clear <- sum(r$candidate_verdict == "no_clear_evidence")
    insufficient <- sum(r$candidate_verdict == "insufficient_evidence")
    ratio <- function(value) if (n) value / n else NA_real_
    rows[[length(rows) + 1L]] <- data.frame(scope = scope, label = truth,
      planned = nrow(p), evaluated = n, pending = sum(p$status == "pending"),
      suspected = suspected, no_clear_evidence = clear, insufficient_evidence = insufficient,
      decision_errors = sum(r$decision_status == "error"),
      detection_rate = if (truth == "copied") ratio(suspected) else NA_real_,
      clear_miss_rate = if (truth == "copied") ratio(clear) else NA_real_,
      false_alarm_rate = if (truth == "independent") ratio(suspected) else NA_real_,
      abstention_rate = ratio(insufficient),
      rule_version = if (nrow(aligned)) aligned$rule_version[1L] else NA_character_,
      decision_stage = "development_unvalidated", stringsAsFactors = FALSE)
  }
  do.call(rbind, rows)
}
