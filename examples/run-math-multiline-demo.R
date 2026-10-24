source("R/parser.R", encoding = "UTF-8")
source("R/math.R", encoding = "UTF-8")
source("R/math-sequences.R", encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  a <- parse_rmd_text(paste0("# A\n\n\\begin{align}\nx &= y \\\\\ny &= z \\\\\nz &= 1\n\\end{align}"), file_id = "A")
  b <- parse_rmd_text(paste0("# B\n\n$$\n\\begin{aligned}\na &= b \\\\\n7 &= 8 \\\\\nb &= c \\\\\nc &= 1\n\\end{aligned}\n$$"), file_id = "B")
} else {
  if (length(args) != 2L) stop("Usage: Rscript examples/run-math-multiline-demo.R [A.Rmd B.Rmd]")
  a <- read_rmd(args[1L], file_id = "A"); b <- read_rmd(args[2L], file_id = "B")
}
result <- find_math_sequences(a, b, min_steps = 3L)
cat("Multiline formula status:", result$status, "\n")
print(result$matches[, c("matched_steps", "skipped_steps", "step_similarity", "start_line_a", "end_line_a", "start_line_b", "end_line_b"), drop = FALSE])
if (nrow(result$matches)) {
  print(result$matches$variable_map[[1L]])
  print(result$matches$step_pairs[[1L]][, c("unit_id_a", "content_a", "content_b", "start_line_a", "start_line_b")])
  cat("Skipped B steps:", result$matches$skipped_units_b[[1L]], "\n")
}
cat("Supported multiline subset only. No mathematical equivalence or plagiarism verdict.\n")
