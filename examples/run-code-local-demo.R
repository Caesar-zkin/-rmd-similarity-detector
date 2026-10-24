source("R/parser.R", encoding = "UTF-8")
source("R/code.R", encoding = "UTF-8")
source("R/code-local.R", encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  a <- parse_rmd_text("```{r}\nirrelevant<--99\nvalues<-c(1,2,3)\ncenter<-mean(values)\nprint(center)\ntailvalue<-99\n```", file_id = "A")
  b <- parse_rmd_text("```{r}\nnums<-c(1,2,3)\nextra<-0\navg<-mean(nums)\nprint(avg)\n```", file_id = "B")
} else {
  if (length(args) != 2L) stop("Usage: Rscript examples/run-code-local-demo.R [A.Rmd B.Rmd]")
  a <- read_rmd(args[1L], file_id = "A"); b <- read_rmd(args[2L], file_id = "B")
}
r <- analyze_code_pair_local(a, b)
cat("Local code status:", r$status, " Candidates:", nrow(r$candidates), "\n")
cat("Lexical-only token coverage:\n"); print(r$lexical_coverage)
cat("Coverage including consistent renaming:\n"); print(r$coverage)
print(r$matches[, c("method", "matched_statements", "matched_tokens", "skipped_statements", "skipped_tokens", "alignment_ratio"), drop = FALSE])
if (nrow(r$matches)) {
  print(r$matches$variable_map[[1L]])
  print(r$matches$statement_pairs[[1L]][, c("content_a", "content_b", "start_line_a", "start_line_b")])
}
cat("Whole top-level statements only. Renamed coverage counts corresponding tokens, not equal characters. No plagiarism verdict.\n")
