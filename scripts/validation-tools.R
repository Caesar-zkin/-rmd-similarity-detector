# Development experiments only. No held-out inputs are loaded here.
validation_read_csv <- function(path) {
  utils::read.csv(path, stringsAsFactors = FALSE, fileEncoding = "UTF-8",
    colClasses = "character", check.names = FALSE, na.strings = NULL)
}

validation_input_path <- function(root, relative) {
  if (length(relative) != 1L || is.na(relative) ||
      !grepl("^validation/dev/[A-Za-z0-9_./-]+[.]Rmd$", relative) ||
      any(strsplit(relative, "/", fixed = TRUE)[[1L]] %in% c("", ".", "..")))
    stop("Only explicit validation/dev/*.Rmd inputs are allowed.")
  path <- normalizePath(file.path(root, relative), winslash = "/", mustWork = TRUE)
  base <- paste0(normalizePath(file.path(root, "validation/dev"), winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(path, base) || dir.exists(path)) stop("Input escapes the development directory.")
  path
}

validate_development_manifest <- function(root = ".") {
  tasks <- validation_read_csv(file.path(root, "validation/tasks.csv"))
  pairs <- validation_read_csv(file.path(root, "validation/pairs.csv"))
  annotations <- validation_read_csv(file.path(root, "validation/annotations.csv"))
  require_columns <- function(x, fields) {
    if (!all(fields %in% names(x))) stop("Missing manifest columns.")
  }
  require_columns(tasks, c("task_id", "split", "kind"))
  require_columns(pairs, c("pair_id", "task_id", "split", "variant", "label", "status", "source_file", "target_file", "provenance"))
  require_columns(annotations, c("pair_id", "side", "kind", "start", "end", "quote"))
  if (nrow(tasks) != 6L || anyDuplicated(tasks$task_id) ||
      sum(tasks$split == "dev") != 4L || sum(tasks$split == "holdout") != 2L ||
      !all(tasks$split %in% c("dev", "holdout"))) stop("Expected six fixed tasks: four dev, two holdout.")
  variants <- c("exact", "format", "light_edit", "local", "dispersed", "independent")
  if (nrow(pairs) != 36L || anyDuplicated(pairs$pair_id) ||
      !all(pairs$task_id %in% tasks$task_id) || !all(pairs$variant %in% variants) ||
      !all(pairs$status %in% c("ready", "pending"))) stop("Invalid pair registry.")
  for (id in tasks$task_id) {
    p <- pairs[pairs$task_id == id, , drop = FALSE]
    if (nrow(p) != 6L || !setequal(p$variant, variants) ||
        any(p$split != tasks$split[match(id, tasks$task_id)])) stop("Variants must stay in their task split.")
  }
  # The public registry reserves held-out IDs only; never publish their paths or contents.
  held <- pairs$split == "holdout"
  if (any(pairs$status[held] != "pending") || any(nzchar(pairs$source_file[held])) ||
      any(nzchar(pairs$target_file[held]))) stop("Held-out materials must remain outside this runner.")
  ready <- pairs[pairs$status == "ready", , drop = FALSE]
  if (!nrow(ready) || any(ready$split != "dev") || any(!nzchar(ready$provenance)) ||
      !all(ready$label %in% c("copied", "independent")) ||
      any(ready$variant == "independent" & ready$label != "independent") ||
      any(ready$variant != "independent" & ready$label != "copied")) stop("Invalid ready-pair provenance or label.")
  if (any(!annotations$pair_id %in% ready$pair_id) ||
      !all(annotations$side %in% c("A", "B")) ||
      !all(annotations$kind %in% c("text", "math", "code"))) stop("Invalid annotation reference.")
  for (i in seq_len(nrow(ready))) {
    p <- ready[i, ]; paths <- c(A = p$source_file, B = p$target_file)
    for (side in names(paths)) {
      doc <- read_rmd(validation_input_path(root, paths[[side]]), file_id = side)
      a <- annotations[annotations$pair_id == p$pair_id & annotations$side == side, , drop = FALSE]
      if (p$label == "copied" && !nrow(a)) stop("Copied pairs need source and target annotations.")
      for (j in seq_len(nrow(a))) {
        if (!grepl("^[1-9][0-9]*$", a$start[j]) || !grepl("^[1-9][0-9]*$", a$end[j])) stop("Offsets must be positive integers.")
        s <- as.numeric(a$start[j]); e <- as.numeric(a$end[j])
        if (!is.finite(s) || !is.finite(e) || s > e || e > nchar(doc$source, type = "chars") ||
            !identical(substr(doc$source, s, e), a$quote[j])) stop("Annotation quote does not match normalized source.")
        if (!any(doc$units$type == a$kind[j] & doc$units$start_offset <= e & doc$units$end_offset >= s))
          stop("Annotation kind does not overlap a corresponding parsed unit.")
      }
    }
  }
  list(tasks = tasks, pairs = pairs, ready = ready, annotations = annotations)
}

run_development_validation <- function(root = ".", output = file.path(root, "reports-local/validation")) {
  manifest <- validate_development_manifest(root)
  rows <- list(); details <- list()
  number <- function(x, column, side) {
    if (is.null(x) || !is.data.frame(x) || !column %in% names(x)) return(NA_real_)
    value <- x[[column]][x$side == side]
    if (length(value) != 1L) return(NA_real_)
    as.numeric(value)
  }
  count <- function(x) if (is.data.frame(x)) nrow(x) else NA_integer_
  for (i in seq_len(nrow(manifest$ready))) {
    p <- manifest$ready[i, ]
    result <- analyze_rmd_pair(validation_input_path(root, p$source_file), validation_input_path(root, p$target_file))
    details[[p$pair_id]] <- result
    text <- result$modules$text$value; code <- result$modules$code_local$value
    math <- result$modules$formula_sequence$value
    row <- data.frame(pair_id = p$pair_id, task_id = p$task_id, variant = p$variant,
      label = p$label, overall_status = result$overall_status, verdict = result$verdict,
      text_jaccard = if (is.null(text)) NA_real_ else text$jaccard$similarity,
      text_coverage_a = number(text$coverage, "coverage", "A"), text_coverage_b = number(text$coverage, "coverage", "B"),
      code_coverage_a = number(code$coverage, "coverage", "A"), code_coverage_b = number(code$coverage, "coverage", "B"),
      stringsAsFactors = FALSE)
    for (name in names(result$modules)) {
      row[[paste0(name, "_status")]] <- result$modules[[name]]$status
      row[[paste0(name, "_error")]] <- result$modules[[name]]$error
    }
    row$formula_sequences <- count(math$matches)
    rows[[i]] <- row
    cat(p$pair_id, result$overall_status, "verdict:", result$verdict, "\n")
  }
  inputs <- unique(c(manifest$ready$source_file, manifest$ready$target_file))
  tracked <- unique(c(inputs, "validation/tasks.csv", "validation/pairs.csv", "validation/annotations.csv",
    "scripts/validation-tools.R", "scripts/run-validation.R", "scripts/build-detector.R", detector_module_paths))
  hashes <- data.frame(path = tracked, md5 = unname(tools::md5sum(file.path(root, tracked))), stringsAsFactors = FALSE)
  commit <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(normalizePath(root)), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)), error = function(e) character())
  if (length(commit) != 1L || !grepl("^[a-f0-9]{40}$", commit)) commit <- NA_character_
  bundle <- list(schema_version = "1", created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    commit = commit, hashes = hashes, r_version = as.character(getRversion()), session = sessionInfo(),
    manifest = manifest, results = do.call(rbind, rows), details = details,
    note = "Synthetic development observations only. No verdict, accuracy, or held-out evaluation. Per-module effective parameters are retained in details.")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  utils::write.csv(bundle$results, file.path(output, "results.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  utils::write.csv(hashes, file.path(output, "input-and-code-hashes.csv"), row.names = FALSE, fileEncoding = "UTF-8")
  saveRDS(bundle, file.path(output, "experiment.rds"))
  cat("Development pairs:", nrow(bundle$results), "Pending registry pairs:", sum(manifest$pairs$status == "pending"), "\n")
  cat("Results:", normalizePath(output, winslash = "/"), "\nNo detection accuracy is computed.\n")
  invisible(bundle)
}
