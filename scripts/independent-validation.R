# Local reviewed self-reports only. This code cannot authenticate human authorship.
independent_references <- function() data.frame(
  task_id = c("T01", "T02", "T03", "T04", "E01", "E02", "E03"),
  cohort = c(rep("core", 4L), rep("extended", 3L)),
  source_file = c(paste0("validation/dev/T0", 1:4, "/base.Rmd"),
    paste0("validation/extended/fixtures/E0", 1:3, "/base.Rmd")), stringsAsFactors = FALSE)

.independent_dir <- function(root, relative, create = FALSE) {
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  path <- paste0(root, "/", relative)
  key <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  ancestor <- path
  while (!file.exists(ancestor) && ancestor != root) ancestor <- dirname(ancestor)
  if (file.exists(ancestor) && key(normalizePath(ancestor, winslash = "/", mustWork = TRUE)) != key(ancestor))
    stop("Local directory ancestor must not redirect through a symlink.")
  if (create) dir.create(path, recursive = TRUE, showWarnings = FALSE)
  if (file.exists(path)) {
    actual <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (!dir.exists(path) || key(actual) != key(path)) stop("Local directory must not redirect through a symlink.")
  }
  path
}

independent_answer_path <- function(root, relative) {
  prefix <- "validation/independent-local/"
  if (!is.character(relative) || length(relative) != 1L || is.na(relative) ||
      !startsWith(relative, prefix) || !grepl("[.]Rmd$", relative, ignore.case = TRUE) ||
      grepl("[\\\\:]", relative) || any(strsplit(relative, "/", fixed = TRUE)[[1L]] %in% c("", ".", "..")))
    stop("Answers must be explicit paths inside validation/independent-local/.")
  base <- .independent_dir(root, "validation/independent-local")
  path <- normalizePath(file.path(root, relative), winslash = "/", mustWork = TRUE)
  if (!startsWith(path, paste0(base, "/")) || dir.exists(path) || file.info(path)$size > 1000000)
    stop("Answer escapes the private directory, is a directory, or exceeds 1 MB.")
  path
}

independent_source_path <- function(root, task_id) {
  refs <- independent_references(); index <- match(task_id, refs$task_id)
  if (length(index) != 1L || is.na(index)) stop("Unknown independent task; held-out tasks are not allowed.")
  relative <- refs$source_file[index]
  path <- if (refs$cohort[index] == "core") validation_input_path(root, relative) else extended_input_path(root, relative)
  expected <- paste0(normalizePath(root, winslash = "/", mustWork = TRUE), "/", relative)
  key <- function(x) if (.Platform$OS.type == "windows") tolower(x) else x
  if (key(path) != key(expected)) stop("Reference source must not redirect through a symlink.")
  path
}

read_independent_metadata <- function(root = ".") {
  base <- .independent_dir(root, "validation/independent-local")
  path <- file.path(base, "metadata.csv")
  fallback <- !file.exists(path)
  if (fallback) path <- file.path(root, "validation/independent-metadata-template.csv") else {
    actual <- normalizePath(path, winslash = "/", mustWork = TRUE)
    if (!startsWith(actual, paste0(base, "/"))) stop("Metadata escapes the private directory.")
    path <- actual
  }
  if (dir.exists(path) || !file.exists(path) || file.info(path)$size > 1000000) stop("Invalid metadata CSV or metadata exceeds 1 MB.")
  fingerprint <- unname(tools::md5sum(path))
  metadata <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character",
    fileEncoding = "UTF-8-BOM", check.names = FALSE, na.strings = NULL)
  fields <- c("pair_id", "task_id", "status", "participant_code", "completed_on", "prior_answer_access",
    "authorship", "assistance_kind", "assistance", "consent_to_local_use", "file_path",
    "source_md5", "answer_md5", "reviewed_by", "reviewed_on", "notes")
  if (anyDuplicated(names(metadata)) || !all(fields %in% names(metadata)))
    stop("Missing metadata fields; upgrade old metadata using the current template without overwriting collected information.")
  if (nrow(metadata) > 100L || anyNA(metadata[, fields]) || anyDuplicated(metadata$pair_id) ||
      !all(grepl("^[A-Za-z][A-Za-z0-9_-]{0,63}$", metadata$pair_id)) ||
      !all(metadata$task_id %in% independent_references()$task_id) ||
      !all(metadata$status %in% c("pending", "received", "verified", "excluded")) ||
      !all(metadata$prior_answer_access %in% c("no", "yes", "unknown")) ||
      !all(metadata$authorship %in% c("human_self_report", "ai_generated", "mixed", "unknown")) ||
      !all(metadata$assistance_kind %in% c("none", "reference_only", "ai_or_human_help", "unknown")) ||
      !all(metadata$consent_to_local_use %in% c("yes", "no", "unknown")))
    stop("Invalid local metadata, duplicate ID, or forbidden task.")
  if (is.na(fingerprint) || !identical(fingerprint, unname(tools::md5sum(path)))) stop("Metadata changed while reading.")
  list(metadata = metadata, path = path, fingerprint = fingerprint, using_template = fallback)
}

.independent_review_issues <- function(row, require_review = FALSE) {
  issues <- character()
  add <- function(condition, message) if (!isTRUE(condition)) issues <<- c(issues, message)
  valid_date <- function(x) {
    parsed <- tryCatch(as.Date(x, format = "%Y-%m-%d"), error = function(e) as.Date(NA))
    grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", x) && !is.na(parsed) && format(parsed, "%Y-%m-%d") == x
  }
  add(row$consent_to_local_use == "yes", "local consent is required")
  add(row$prior_answer_access == "no", "prior answer access must be no")
  add(row$authorship == "human_self_report", "human self-report is required")
  add(row$assistance_kind %in% c("none", "reference_only"), "AI/human help or unknown assistance is outside the independent group")
  add(nzchar(trimws(row$assistance)), "assistance must be disclosed; use none if absent")
  add(grepl("^[A-Za-z][A-Za-z0-9_-]{0,31}$", row$participant_code), "anonymous participant code is required")
  add(valid_date(row$completed_on), "completion date must be YYYY-MM-DD")
  add(nzchar(trimws(row$notes)), "collection notes are required")
  add(nzchar(row$file_path), "answer path is required")
  if (require_review) {
    add(grepl("^[A-Za-z][A-Za-z0-9_-]{0,31}$", row$reviewed_by), "anonymous reviewer code is required")
    add(valid_date(row$reviewed_on), "review date must be YYYY-MM-DD")
    add(grepl("^[a-f0-9]{32}$", row$source_md5), "reviewed source fingerprint is required")
    add(grepl("^[a-f0-9]{32}$", row$answer_md5), "reviewed answer fingerprint is required")
  }
  issues
}

audit_independent_metadata <- function(root = ".", write = TRUE) {
  intake <- read_independent_metadata(root); metadata <- intake$metadata
  rows <- list()
  for (i in seq_len(nrow(metadata))) {
    row <- metadata[i, ]; status <- row$status; issues <- character(); source_hash <- answer_hash <- ""
    # Pending and excluded rows never cause answer files to be opened.
    if (status %in% c("received", "verified")) {
      issues <- .independent_review_issues(row, require_review = status == "verified")
      # No file access when consent/provenance requirements fail.
      if (!length(.independent_review_issues(row))) {
        paths <- tryCatch(c(source = independent_source_path(root, row$task_id),
          answer = independent_answer_path(root, row$file_path)), error = identity)
        if (inherits(paths, "error")) issues <- c(issues, conditionMessage(paths)) else {
          hashes <- unname(tools::md5sum(paths)); source_hash <- hashes[1L]; answer_hash <- hashes[2L]
          if (anyNA(hashes)) issues <- c(issues, "file fingerprint unavailable")
          if (status == "verified" && (!identical(source_hash, row$source_md5) || !identical(answer_hash, row$answer_md5)))
            issues <- c(issues, "reviewed fingerprints do not match current files")
        }
      }
      status <- if (length(issues)) "blocked" else if (row$status == "verified") "review_record_matches" else "needs_human_review"
    }
    rows[[i]] <- data.frame(pair_id = row$pair_id, task_id = row$task_id, metadata_status = row$status,
      check_status = status, issues = paste(unique(issues), collapse = "; "),
      observed_source_md5 = source_hash, observed_answer_md5 = answer_hash, stringsAsFactors = FALSE)
  }
  table <- if (length(rows)) do.call(rbind, rows) else data.frame(pair_id = character(), task_id = character(),
    metadata_status = character(), check_status = character(), issues = character(),
    observed_source_md5 = character(), observed_answer_md5 = character())
  if (write) {
    output <- .independent_dir(root, "validation/independent-local", create = TRUE)
    audit_path <- file.path(output, "audit.csv")
    if (file.exists(audit_path) && !startsWith(normalizePath(audit_path, winslash = "/", mustWork = TRUE), paste0(output, "/")))
      stop("Audit output escapes the private directory.")
    utils::write.csv(table, audit_path, row.names = FALSE, fileEncoding = "UTF-8")
    cat("Audit:", audit_path, "\nMetadata statuses were not changed. This is not proof of authorship.\n")
  }
  list(intake = intake, audit = table)
}

.empty_independent_results <- function() data.frame(pair_id = character(), task_id = character(), cohort = character(),
  participant_code = character(), overall_status = character(), verdict = character(), candidate_verdict = character(),
  candidate_label = character(), candidate_pathway = character(), decision_status = character(), rule_version = character(),
  decision_stage = character(), stringsAsFactors = FALSE)

summarize_independent_validation <- function(metadata, results) {
  refs <- independent_references(); verified <- metadata[metadata$status == "verified", , drop = FALSE]
  required <- names(.empty_independent_results())
  if (!all(required %in% names(results)) || anyNA(results[, required]) || anyDuplicated(results$pair_id) ||
      !setequal(results$pair_id, verified$pair_id)) stop("Results must match every verified row exactly once.")
  aligned <- results[match(verified$pair_id, results$pair_id), , drop = FALSE]
  if (!identical(as.character(aligned$task_id), as.character(verified$task_id)) ||
      !identical(as.character(aligned$participant_code), as.character(verified$participant_code)) ||
      any(aligned$cohort != refs$cohort[match(aligned$task_id, refs$task_id)]) ||
      !all(aligned$candidate_verdict %in% c("suspected", "no_clear_evidence", "insufficient_evidence")) ||
      !all(aligned$decision_status %in% c("ok", "error")) ||
      any(aligned$decision_status == "error" & aligned$candidate_verdict != "insufficient_evidence") ||
      !all(aligned$verdict == "not_enabled") || !all(aligned$decision_stage == "development_unvalidated") ||
      (nrow(aligned) > 0L && (length(unique(aligned$rule_version)) != 1L || any(!nzchar(aligned$rule_version)))))
    stop("Mismatched task, participant, stage or invalid candidate outcome.")
  scopes <- rbind(data.frame(scope = "cohort", task_id = "all", cohort = c("core", "extended")),
    data.frame(scope = "task", task_id = refs$task_id, cohort = refs$cohort))
  rows <- list()
  for (i in seq_len(nrow(scopes))) {
    scope <- scopes[i, ]; ids <- refs$task_id[refs$cohort == scope$cohort]
    if (scope$scope == "task") ids <- scope$task_id
    m <- metadata[metadata$task_id %in% ids, , drop = FALSE]
    r <- aligned[aligned$task_id %in% ids, , drop = FALSE]; n <- nrow(r)
    suspected <- sum(r$candidate_verdict == "suspected"); insufficient <- sum(r$candidate_verdict == "insufficient_evidence")
    rows[[i]] <- cbind(scope, data.frame(registered = nrow(m), pending = sum(m$status == "pending"),
      received = sum(m$status == "received"), excluded = sum(m$status == "excluded"), verified = sum(m$status == "verified"),
      evaluated = n, participants = length(unique(r$participant_code)), suspected = suspected,
      no_clear_evidence = sum(r$candidate_verdict == "no_clear_evidence"), insufficient_evidence = insufficient,
      decision_errors = sum(r$decision_status == "error"), false_alarm_rate = if (n) suspected / n else NA_real_,
      abstention_rate = if (n) insufficient / n else NA_real_, stringsAsFactors = FALSE))
  }
  do.call(rbind, rows)
}

run_independent_validation <- function(root = ".") {
  reviewed <- audit_independent_metadata(root, write = FALSE)
  metadata <- reviewed$intake$metadata; audit <- reviewed$audit
  selected <- metadata$status == "verified"
  if (any(audit$check_status[selected] != "review_record_matches")) stop("Verified rows failed audit; run --audit and correct the review record before analysis.")
  verified <- metadata[selected, , drop = FALSE]
  if (anyDuplicated(paste(verified$participant_code, verified$task_id, sep = ":")))
    stop("One participant/task may only be evaluated once; mark superseded records excluded.")
  answer_paths <- vapply(verified$file_path, function(p) independent_answer_path(root, p), character(1))
  keys <- if (.Platform$OS.type == "windows") tolower(answer_paths) else answer_paths
  if (anyDuplicated(keys)) stop("The same answer file cannot be counted more than once.")
  results <- .empty_independent_results(); details <- list(); refs <- independent_references()
  for (i in seq_len(nrow(verified))) {
    row <- verified[i, ]; source <- independent_source_path(root, row$task_id)
    r <- analyze_rmd_pair(source, answer_paths[i]); details[[row$pair_id]] <- r
    if (!identical(unname(tools::md5sum(c(source, answer_paths[i]))), c(row$source_md5, row$answer_md5)))
      stop("An input changed during analysis; audit and rerun before using results.")
    results <- rbind(results, data.frame(pair_id = row$pair_id, task_id = row$task_id,
      cohort = refs$cohort[match(row$task_id, refs$task_id)], participant_code = row$participant_code,
      overall_status = r$overall_status, verdict = r$verdict, candidate_verdict = r$decision$verdict,
      candidate_label = r$decision$label, candidate_pathway = r$decision$pathway, decision_status = r$decision$status,
      rule_version = r$decision$rules$version, decision_stage = r$decision$stage, stringsAsFactors = FALSE))
  }
  summary <- summarize_independent_validation(metadata, results)
  if (!identical(reviewed$intake$fingerprint, unname(tools::md5sum(reviewed$intake$path))))
    stop("Metadata changed during analysis; review and rerun.")
  input_paths <- unique(c(verified$file_path, refs$source_file[match(verified$task_id, refs$task_id)]))
  tracked <- unique(c(input_paths, "scripts/independent-validation.R", "scripts/run-independent-validation.R",
    "scripts/run-validation.R", "scripts/validation-tools.R", "scripts/validation-localization.R", "scripts/validation-decisions.R",
    "scripts/extended-validation.R", "scripts/build-detector.R",
    "validation/independent-tasks.md", "validation/independent-extended-tasks.md", "validation/independent-collection.md", detector_module_paths))
  paths <- c(metadata = reviewed$intake$path, setNames(file.path(root, tracked), tracked))
  hashes <- data.frame(path = c(if (reviewed$intake$using_template) "validation/independent-metadata-template.csv" else "validation/independent-local/metadata.csv", tracked),
    md5 = unname(tools::md5sum(paths)), stringsAsFactors = FALSE)
  commit <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(normalizePath(root)), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)), error = function(e) character())
  if (length(commit) != 1L || !grepl("^[a-f0-9]{40}$", commit)) commit <- NA_character_
  bundle <- list(schema_version = "1", group = "reviewed_self_report_independent_dev", created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    commit = commit, r_version = as.character(getRversion()), session = sessionInfo(), metadata = metadata, audit = audit,
    references = refs, results = results, summary = summary, hashes = hashes, details = details,
    using_template = reviewed$intake$using_template,
    note = "Reviewed self-reports cannot prove independence. Core and extended cohorts are separate; repeated answers from one participant are correlated. Rates describe these local answers, not population performance or accuracy. Insufficient evidence stays in the denominator. No held-out inputs or final verdict. The snapshot contains private answers and metadata; do not publish it.")
  output <- .independent_dir(root, "reports-local/independent", create = TRUE)
  targets <- file.path(output, c("results.csv", "summary.csv", "input-and-code-hashes.csv", "experiment.rds"))
  for (path in targets[file.exists(targets)]) if (!startsWith(normalizePath(path, winslash = "/", mustWork = TRUE), paste0(output, "/")))
    stop("Independent result output escapes its local directory.")
  utils::write.csv(results, targets[1L], row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(summary, targets[2L], row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(hashes, targets[3L], row.names = FALSE, fileEncoding = "UTF-8")
  saveRDS(bundle, targets[4L])
  cat("Verified answers evaluated:", nrow(results), "\n")
  print(summary[summary$scope == "cohort", ], row.names = FALSE)
  cat("Local results:", output, "\nNo population accuracy, authorship proof or held-out evaluation.\n")
  invisible(bundle)
}
