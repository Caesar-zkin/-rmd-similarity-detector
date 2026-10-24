# Artificial edit demonstration, not an accuracy evaluation.
source("R/parser.R", encoding = "UTF-8")
source("R/text.R", encoding = "UTF-8")
source("R/text-matches.R", encoding = "UTF-8")
source("R/text-approx.R", encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) %in% c(0L, 2L, 3L, 4L))
  stop("Usage: Rscript examples/run-text-approx-demo.R [A.Rmd B.Rmd [min_chars [min_similarity]]]")
file_a <- if (length(args) >= 2L) args[1L] else "examples/text-edits-a.Rmd"
file_b <- if (length(args) >= 2L) args[2L] else "examples/text-edits-b.Rmd"
minimum <- if (length(args) >= 3L) as.numeric(args[3L]) else 8L
identity <- if (length(args) >= 4L) as.numeric(args[4L]) else 0.8
r <- analyze_text_pair_approx(read_rmd(file_a, "A"), read_rmd(file_b, "B"),
  k = 3L, seed_k = 2L, window_size = 100L, min_chars = minimum, min_similarity = identity)
cat("Text-only approximate analysis; demo parameters are not calibrated.\n")
cat("Status:", r$status, " Candidates:", r$candidate_count, "\n")
cat("Jaccard:", r$jaccard$similarity, "\nExact-only coverage:\n")
print(r$exact_coverage, row.names = FALSE)
cat("Combined equal-character coverage:\n")
print(r$coverage, row.names = FALSE)
print(r$approximate_matches[, c("aligned_a", "aligned_b", "equal_chars", "similarity",
  "start_line_a", "start_line_b")], row.names = FALSE)
cat("No plagiarism verdict. Changed characters and gaps are excluded from coverage.\n")
