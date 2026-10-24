source("R/parser.R", encoding = "UTF-8")
source("R/math.R", encoding = "UTF-8")
source("R/math-sequences.R", encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  a <- parse_rmd_text("# 推导A\n\n$x=y$\n\n$y=z$\n\n$z=1$", file_id = "A")
  b <- parse_rmd_text("# 推导B\n\n$a=b$\n\n$7=8$\n\n$b=c$\n\n$c=1$", file_id = "B")
} else {
  if (length(args) != 2L) stop("Usage: Rscript examples/run-math-sequence-demo.R [A.Rmd B.Rmd]")
  a <- read_rmd(args[1L], file_id = "A"); b <- read_rmd(args[2L], file_id = "B")
}
result <- find_math_sequences(a, b, min_steps = 3L)
cat("Formula sequence status:", result$status, "\n")
print(result$matches[, c("matched_steps", "skipped_steps", "step_similarity", "token_count",
  "start_line_a", "end_line_a", "start_line_b", "end_line_b"), drop = FALSE])
if (nrow(result$matches)) {
  print(result$matches$variable_map[[1L]])
  print(result$matches$step_pairs[[1L]][, c("content_a", "content_b", "start_line_a", "start_line_b")])
  cat("Skipped B units:", result$matches$skipped_units_b[[1L]], "\n")
}
cat("Supported formula steps only. Step ratio is not plagiarism probability or formula coverage.\n")
