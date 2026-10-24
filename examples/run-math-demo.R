source("R/parser.R", encoding = "UTF-8")
source("R/math.R", encoding = "UTF-8")

args <- commandArgs(trailingOnly = TRUE)
if (!length(args)) {
  a <- parse_rmd_text("推导：$\\frac{x+x}{2}$", file_id = "A")
  b <- parse_rmd_text("推导：$\\dfrac{ a + a }{2}$", file_id = "B")
} else {
  if (length(args) != 2L) stop("Usage: Rscript examples/run-math-demo.R [A.Rmd B.Rmd]")
  a <- read_rmd(args[1L], file_id = "A")
  b <- read_rmd(args[2L], file_id = "B")
}
result <- compare_math_pair(a, b)
cat("Formula status:", result$status, "\n")
print(result$matches[, setdiff(names(result$matches), "variable_map"), drop = FALSE])
if (nrow(result$matches)) print(result$matches$variable_map[[1L]])
cat("Single-formula lexical comparison only. No mathematical equivalence or plagiarism verdict.\n")
