source("R/parser.R", encoding = "UTF-8")
source("R/code.R", encoding = "UTF-8")
args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  a <- parse_rmd_text("```{r}\nvalues <- c(1, 2, 3)\ncenter <- mean(values)\nprint(center)\n```", file_id = "A")
  b <- parse_rmd_text("```{r}\nnums<-c(1,2,3)\navg<-mean(nums)\nprint(avg)\n```", file_id = "B")
} else {
  if (length(args) != 2L) stop("Usage: Rscript examples/run-code-demo.R [A.Rmd B.Rmd]")
  a <- read_rmd(args[1L], file_id = "A"); b <- read_rmd(args[2L], file_id = "B")
}
result <- compare_code_pair(a, b)
cat("Code status:", result$status, "\n")
print(result$matches[, setdiff(names(result$matches), "variable_map"), drop = FALSE])
if (nrow(result$matches)) print(result$matches$variable_map[[1L]])
cat("Parsed without evaluation. Whole-unit comparison only; no code coverage or plagiarism verdict.\n")
