# Run from any directory. Dependencies must already be installed.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(0L, 2L, 3L, 4L)) stop("Usage: Rscript scripts/render-detector.R [A.Rmd B.Rmd [report.html [exclusions.csv]]]")
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
root <- dirname(dirname(normalizePath(sub("^--file=", "", script_arg[1L]), winslash = "/", mustWork = TRUE)))
if (!requireNamespace("rmarkdown", quietly = TRUE))
  stop("rmarkdown is not installed. Install it before offline detection: install.packages('rmarkdown')")
if (.Platform$OS.type == "windows" && !nzchar(Sys.getenv("RSTUDIO_PANDOC"))) {
  candidates <- file.path(Sys.getenv("ProgramFiles"), "RStudio", c("resources/app/bin/quarto/bin/tools", "bin/pandoc"))
  for (path in candidates) if (file.exists(file.path(path, "pandoc.exe"))) { Sys.setenv(RSTUDIO_PANDOC = path); break }
}
if (!rmarkdown::pandoc_available()) stop("Pandoc is not available. Use RStudio Knit or set RSTUDIO_PANDOC to an installed Pandoc directory.")
absolute <- function(path) {
  if (!grepl("^(/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path)) path <- file.path(getwd(), path)
  suppressWarnings(normalizePath(path, winslash = "/", mustWork = FALSE))
}
input_a <- if (length(args)) absolute(args[1L]) else file.path(root, "examples/report-a.Rmd")
input_b <- if (length(args)) absolute(args[2L]) else file.path(root, "examples/report-b.Rmd")
output <- if (length(args) >= 3L) absolute(args[3L]) else file.path(root, "reports-local/detector-report.html")
exclusion_file <- if (length(args) == 4L) absolute(args[4L]) else ""
if (!grepl("\\.html$", output, ignore.case = TRUE)) stop("Output must have an .html extension.")
dir.create(dirname(output), recursive = TRUE, showWarnings = FALSE)
temp <- tempfile("rmd-report-intermediates-"); dir.create(temp)
env <- new.env(parent = globalenv())
result <- tryCatch(rmarkdown::render(file.path(root, "detector.Rmd"), output_file = basename(output),
  output_dir = dirname(output), intermediates_dir = temp, params = list(input_a = input_a, input_b = input_b, exclusion_file = exclusion_file),
  envir = env, quiet = TRUE), finally = unlink(temp, recursive = TRUE))
cat("Report written:", result, "\n")
cat("Analysis status:", env$report_result$overall_status, "\nFinal verdict: not enabled.\n")
