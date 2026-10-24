# Deterministic bundle; does not evaluate module code or install dependencies.
detector_module_paths <- c("R/parser.R", "R/text.R", "R/text-matches.R", "R/text-approx.R",
  "R/math.R", "R/math-sequences.R", "R/code.R", "R/code-local.R", "R/exclusions.R", "R/evidence.R", "R/report.R")
build_detector <- function(root = ".", output = file.path(root, "detector.Rmd"), check = FALSE) {
  read <- function(path) paste(readLines(file.path(root, path), encoding = "UTF-8", warn = FALSE), collapse = "\n")
  template <- read("templates/detector-template.Rmd")
  parts <- strsplit(template, "@@DETECTOR_MODULES@@", fixed = TRUE)[[1L]]
  if (length(parts) != 2L) stop("Template must contain exactly one module marker.")
  modules <- vapply(detector_module_paths, function(path) {
    code <- read(path)
    if (grepl("(?m)^``````", code, perl = TRUE)) stop("Module contains a conflicting code fence.")
    paste0("# BEGIN ", path, "\n", code, "\n# END ", path, "\n")
  }, character(1))
  text <- paste0(parts[1L], paste0(modules, collapse = "\n"), parts[2L], "\n")
  bytes <- charToRaw(enc2utf8(text))
  if (check) {
    if (!file.exists(output) || !identical(readBin(output, "raw", n = file.info(output)$size), bytes))
      stop("detector.Rmd is stale; run Rscript scripts/build-detector.R")
  } else {
    con <- file(output, "wb"); on.exit(close(con)); writeBin(bytes, con)
  }
  invisible(output)
}
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (length(args) && !identical(args, "--check")) stop("Usage: Rscript scripts/build-detector.R [--check]")
  build_detector(check = length(args) > 0L)
  cat(if (length(args)) "Detector bundle is current.\n" else "Built detector.Rmd\n")
}
