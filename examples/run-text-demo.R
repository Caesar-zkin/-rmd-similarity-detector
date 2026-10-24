# Run from the repository root. No output files are written.
source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")
source("R/text-matches.R", encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(0L, 2L, 3L, 4L))
  stop("Usage: Rscript examples/run-text-demo.R [A.Rmd B.Rmd [k [min_chars]]]")
file_a <- if (length(args) >= 2L) args[1L] else "examples/text-a.Rmd"
file_b <- if (length(args) >= 2L) args[2L] else "examples/text-b.Rmd"
k <- if (length(args) >= 3L) as.numeric(args[3L]) else 2L
minimum <- if (length(args) >= 4L) as.numeric(args[4L]) else 2L
result <- analyze_text_pair(read_rmd(file_a, "A"), read_rmd(file_b, "B"),
  k = k, min_chars = minimum)
cat("Text-only analysis. Demo parameters are not calibrated thresholds.\n")
cat("Status:", result$status, "\n")
cat("Jaccard:", result$jaccard$similarity, "\n")
print(result$coverage, row.names = FALSE)
print(result$exact_matches[, c("text", "matched_chars", "start_line_a",
  "end_line_a", "start_line_b", "end_line_b")], row.names = FALSE)
cat("No plagiarism verdict is produced. Formula/code similarity is not analysed.\n")
if (nrow(result$diagnostics$a)) print(result$diagnostics$a)
if (nrow(result$diagnostics$b)) print(result$diagnostics$b)
