# Longer developer-authored controls, separate from core and held-out material.
extended_input_path <- function(root, relative) {
  if (!is.character(relative) || length(relative) != 1L || is.na(relative) ||
      !grepl("^validation/extended/fixtures/E0[123]/(base|exact|format|light_edit|local)[.]Rmd$", relative))
    stop("Only registered extended-development fixture paths are allowed.")
  path <- normalizePath(file.path(root, relative), winslash = "/", mustWork = TRUE)
  base <- paste0(normalizePath(file.path(root, "validation/extended/fixtures"), winslash = "/", mustWork = TRUE), "/")
  if (!startsWith(path, base) || dir.exists(path)) stop("Extended input escapes fixture directory.")
  path
}

validate_extended_manifest <- function(root = ".") {
  cases <- validation_read_csv(file.path(root, "validation/extended/cases.csv"))
  annotations <- validation_read_csv(file.path(root, "validation/extended/annotations.csv"))
  fields <- c("pair_id", "family", "kind", "variant", "split", "label", "status", "source_file", "target_file", "provenance")
  afields <- c("pair_id", "side", "kind", "start", "end", "quote")
  variants <- c("exact", "format", "light_edit", "local")
  kinds <- c(E01 = "text", E02 = "math", E03 = "code")
  if (!all(fields %in% names(cases)) || !all(afields %in% names(annotations)) ||
      anyNA(cases[, fields]) || anyNA(annotations[, afields]) || nrow(cases) != 12L ||
      anyDuplicated(cases$pair_id) || !all(cases$family %in% names(kinds)) ||
      !all(cases$variant %in% variants) || any(cases$kind != unname(kinds[cases$family])) ||
      any(cases$pair_id != paste(cases$family, cases$variant, sep = "_")) ||
      any(cases$split != "dev" | cases$label != "copied" | cases$status != "ready") ||
      any(cases$provenance != "project_authored_synthetic; target deliberately derived from base; not independent; not heldout"))
    stop("Invalid extended synthetic development manifest.")
  for (family in names(kinds)) {
    c <- cases[cases$family == family, , drop = FALSE]
    if (nrow(c) != 4L || !setequal(c$variant, variants)) stop("Each family needs four declared transformations.")
  }
  if (any(!annotations$pair_id %in% cases$pair_id) || !all(annotations$side %in% c("A", "B")) ||
      any(annotations$kind != cases$kind[match(annotations$pair_id, cases$pair_id)]))
    stop("Invalid extended origin annotation reference.")
  for (i in seq_len(nrow(cases))) {
    c <- cases[i, ]; prefix <- paste0("validation/extended/fixtures/", c$family, "/")
    if (c$source_file != paste0(prefix, "base.Rmd") || c$target_file != paste0(prefix, c$variant, ".Rmd"))
      stop("Extended paths must agree with family and transformation.")
    for (side in c("A", "B")) {
      path <- if (side == "A") c$source_file else c$target_file
      doc <- read_rmd(extended_input_path(root, path), file_id = side)
      a <- annotations[annotations$pair_id == c$pair_id & annotations$side == side, , drop = FALSE]
      if (!nrow(a)) stop("Both sides need explicit copied-origin annotations.")
      if (!all(grepl("^[1-9][0-9]*$", a$start)) || !all(grepl("^[1-9][0-9]*$", a$end)))
        stop("Origin offsets must be positive integers.")
      s <- as.numeric(a$start); e <- as.numeric(a$end)
      if (any(!is.finite(s) | !is.finite(e) | s > e | e > nchar(doc$source, type = "chars")))
        stop("Invalid origin bounds.")
      indices <- order(s)
      if (length(s) > 1L && any(s[indices][-1L] <= head(e[indices], -1L))) stop("Origin ranges overlap.")
      for (j in seq_len(nrow(a))) {
        if (!identical(substr(doc$source, s[j], e[j]), a$quote[j])) stop("Extended origin quote is stale.")
        if (!any(doc$units$type == a$kind[j] & doc$units$start_offset <= s[j] & doc$units$end_offset >= e[j]))
          stop("Origin range must fit one corresponding parser unit.")
      }
    }
  }
  list(cases = cases, annotations = annotations)
}

run_extended_validation <- function(root = ".", output = file.path(root, "reports-local/extended")) {
  manifest <- validate_extended_manifest(root)
  rows <- localization <- details <- list()
  coverage <- function(table, side) {
    if (!is.data.frame(table)) return(NA_real_)
    x <- table$coverage[table$side == side]
    if (length(x) == 1L) as.numeric(x) else NA_real_
  }
  for (i in seq_len(nrow(manifest$cases))) {
    c <- manifest$cases[i, ]
    r <- analyze_rmd_pair(extended_input_path(root, c$source_file), extended_input_path(root, c$target_file))
    details[[c$pair_id]] <- r
    localization[[c$pair_id]] <- evaluate_validation_localization(r, manifest$annotations, c$pair_id)
    row <- data.frame(pair_id = c$pair_id, family = c$family, kind = c$kind, variant = c$variant,
      label = c$label, overall_status = r$overall_status, verdict = r$verdict,
      candidate_verdict = r$decision$verdict, candidate_label = r$decision$label,
      candidate_pathway = r$decision$pathway, decision_status = r$decision$status,
      rule_version = r$decision$rules$version, decision_stage = r$decision$stage,
      text_coverage_a = coverage(r$modules$text$value$coverage, "A"),
      text_coverage_b = coverage(r$modules$text$value$coverage, "B"),
      code_coverage_a = coverage(r$modules$code_local$value$coverage, "A"),
      code_coverage_b = coverage(r$modules$code_local$value$coverage, "B"), stringsAsFactors = FALSE)
    groups <- r$evidence$value$groups
    for (kind in c("text", "math", "code")) {
      x <- if (is.data.frame(groups)) groups$largest_match[groups$kind == kind] else numeric()
      row[[paste0("largest_", kind, "_match")]] <- if (!is.data.frame(groups)) NA_integer_ else if (length(x)) max(x) else 0L
    }
    for (name in names(r$modules)) {
      row[[paste0(name, "_status")]] <- r$modules[[name]]$status
      row[[paste0(name, "_error")]] <- r$modules[[name]]$error
    }
    rows[[i]] <- row
    cat(c$pair_id, r$overall_status, r$decision$verdict, r$decision$pathway, "\n")
  }
  results <- do.call(rbind, rows)
  summary <- summarize_validation_decisions(manifest$cases, results)
  paths <- unique(c(manifest$cases$source_file, manifest$cases$target_file,
    "validation/extended/cases.csv", "validation/extended/annotations.csv", "validation/extended/README.md",
    "scripts/run-extended-validation.R", "scripts/extended-validation.R", "scripts/validation-tools.R",
    "scripts/validation-localization.R", "scripts/validation-decisions.R", "scripts/build-detector.R", detector_module_paths))
  hashes <- data.frame(path = paths, md5 = unname(tools::md5sum(file.path(root, paths))), stringsAsFactors = FALSE)
  commit <- tryCatch(suppressWarnings(system2("git", c("-C", shQuote(normalizePath(root)), "rev-parse", "HEAD"), stdout = TRUE, stderr = FALSE)), error = function(e) character())
  if (length(commit) != 1L || !grepl("^[a-f0-9]{40}$", commit)) commit <- NA_character_
  bundle <- list(schema_version = "1", group = "extended_synthetic_dev", created_utc = format(Sys.time(), tz = "UTC", usetz = TRUE),
    commit = commit, r_version = as.character(getRversion()), session = sessionInfo(), manifest = manifest,
    results = results, decision_summary = summary, localization = do.call(rbind, localization), hashes = hashes, details = details,
    note = "Longer self-authored copied-origin controls only; three source families, not twelve independent samples. No human-independent or held-out answers. Candidate rates are descriptive; no false-alarm estimate or final verdict. Default rules unchanged.")
  dir.create(output, recursive = TRUE, showWarnings = FALSE)
  for (name in c("results", "localization", "decision_summary", "hashes")) {
    file <- switch(name, decision_summary = "decision-summary.csv", hashes = "input-and-code-hashes.csv", paste0(name, ".csv"))
    utils::write.csv(bundle[[name]], file.path(output, file), row.names = FALSE, fileEncoding = "UTF-8")
  }
  saveRDS(bundle, file.path(output, "experiment.rds"))
  print(results[, c("pair_id", "candidate_verdict", "candidate_pathway")], row.names = FALSE)
  cat("Extended development pairs:", nrow(results), "from", length(unique(results$family)), "source families.\n")
  cat("Results:", normalizePath(output, winslash = "/"), "\nNo independent false-alarm or held-out estimate.\n")
  invisible(bundle)
}
