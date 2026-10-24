# Boundary observations are separate from core development and held-out evaluation.
boundary_input_path <- function(root, relative) {
  prefix <- "validation/boundary/fixtures/"
  if (!is.character(relative) || length(relative) != 1L || is.na(relative) ||
      !startsWith(relative, prefix) || !endsWith(relative, ".Rmd") ||
      grepl("[\\\\:]", relative) || any(strsplit(relative, "/", fixed = TRUE)[[1L]] %in% c("", ".", "..")))
    stop("Only explicit boundary fixture paths are allowed.")
  path <- normalizePath(file.path(root, relative), winslash = "/", mustWork = TRUE)
  base <- paste0(normalizePath(file.path(root, "validation/boundary/fixtures"), winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(path, base) || dir.exists(path)) stop("Boundary input escapes fixture directory.")
  path
}

validate_boundary_manifest <- function(root = ".") {
  cases <- validation_read_csv(file.path(root, "validation/boundary/cases.csv"))
  required <- c("case_id", "kind", "role", "source_file", "target_file", "expected_behavior", "provenance")
  if (!all(required %in% names(cases)) || !nrow(cases) || anyDuplicated(cases$case_id) ||
      !all(grepl("^B[0-9]{2}$", cases$case_id)) || any(!nzchar(cases$expected_behavior)) ||
      any(!nzchar(cases$provenance))) stop("Invalid boundary manifest.")
  roles <- c(empty = "insufficient_content", yaml_only = "insufficient_content",
    shared_prompt = "risk_control", routine_formula = "risk_control", routine_code = "risk_control",
    unrelated = "synthetic_control", incomplete_code = "unsupported_content",
    unsupported_math = "unsupported_content", non_r = "unsupported_content", long_local = "copied_positive_control")
  if (!all(cases$kind %in% names(roles)) || any(unname(roles[cases$kind]) != cases$role))
    stop("Boundary roles describe controls; they are not copied/independent verdict labels.")
  for (path in unique(c(cases$source_file, cases$target_file))) boundary_input_path(root, path)
  cases
}

run_boundary_validation <- function(root = ".", output = file.path(root, "reports-local/boundary")) {
  cases <- validate_boundary_manifest(root); rows <- list(); details <- list()
  count <- function(x) if (is.data.frame(x)) nrow(x) else NA_integer_
  coverage_value <- function(x, column, side) {
    if (!is.data.frame(x) || !column %in% names(x)) return(NA_real_)
    v <- x[[column]][x$side == side]
    if (length(v) == 1L) as.numeric(v) else NA_real_
  }
  for (i in seq_len(nrow(cases))) {
    c <- cases[i, ]
    r <- analyze_rmd_pair(boundary_input_path(root, c$source_file), boundary_input_path(root, c$target_file))
    details[[c$case_id]] <- r
    text <- r$modules$text$value; code <- r$modules$code_local$value
    single <- r$modules$formula_single$value; sequence <- r$modules$formula_sequence$value
    row <- data.frame(case_id = c$case_id, kind = c$kind, reference_role = c$role,
      expected_behavior = c$expected_behavior, overall_status = r$overall_status, verdict = r$verdict,
      text_jaccard = if (is.null(text)) NA_real_ else text$jaccard$similarity,
      text_coverage_a = coverage_value(text$coverage, "coverage", "A"),
      text_coverage_b = coverage_value(text$coverage, "coverage", "B"),
      text_matched_a = coverage_value(text$coverage, "matched_chars", "A"),
      text_matched_b = coverage_value(text$coverage, "matched_chars", "B"),
      formula_single_matches = count(single$matches), formula_sequence_matches = count(sequence$matches),
      code_whole_matches = count(r$modules$code_whole$value$matches),
      code_local_matches = count(code$matches),
      code_coverage_a = coverage_value(code$coverage, "coverage", "A"),
      code_coverage_b = coverage_value(code$coverage, "coverage", "B"), stringsAsFactors = FALSE)
    for (name in names(r$modules)) {
      row[[paste0(name, "_status")]] <- r$modules[[name]]$status
      row[[paste0(name, "_error")]] <- r$modules[[name]]$error
    }
    row$risk_observation <- switch(c$kind,
      shared_prompt = if (is.null(text)) "analysis_unavailable" else if (isTRUE(row$text_matched_a > 0)) "shared_prompt_is_matching_evidence" else "no_risk_match_observed",
      routine_formula = if (is.null(single)) "analysis_unavailable" else if (isTRUE(row$formula_single_matches > 0)) "routine_formula_is_matching_evidence" else "no_risk_match_observed",
      routine_code = if (is.null(r$modules$code_whole$value)) "analysis_unavailable" else if (isTRUE(row$code_whole_matches > 0)) "routine_code_is_matching_evidence" else "no_risk_match_observed",
      "not_a_classification")
    rows[[i]] <- row
    cat(c$case_id, c$kind, r$overall_status, row$risk_observation, "\n")
  }
  paths <- unique(c(cases$source_file, cases$target_file, "validation/boundary/cases.csv",
    "scripts/boundary-tools.R", "scripts/run-boundary.R", "scripts/validation-tools.R",
    "scripts/build-detector.R", detector_module_paths))
  hashes <- data.frame(path = paths, md5 = unname(tools::md5sum(file.path(root, paths))), stringsAsFactors = FALSE)
  commit <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(normalizePath(root)), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)), error = function(e) character())
  if (length(commit) != 1L || !grepl("^[a-f0-9]{40}$", commit)) commit <- NA_character_
  experiment <- list(schema_version = "1", group = "boundary_only", created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    commit = commit, r_version = as.character(getRversion()), session = sessionInfo(), cases = cases,
    results = do.call(rbind, rows), details = details, hashes = hashes,
    note = "Synthetic boundary observations only. Roles are not classification labels. No false-positive rate, detection accuracy or held-out estimate is computed.")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(experiment$results, file.path(output, "results.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(hashes, file.path(output, "input-and-code-hashes.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  saveRDS(experiment, file.path(output, "experiment.rds"))
  cat("Boundary cases:", nrow(cases), "\nNo classification error rate is computed.\n")
  cat("Results:", normalizePath(output, winslash = "/"), "\n")
  invisible(experiment)
}
