# Run from repository root; no core, independent-local or held-out inputs opened.
source("scripts/run-validation.R", encoding = "UTF-8")
source("scripts/extended-validation.R", encoding = "UTF-8")
if (sys.nframe() == 0L) {
  if (length(commandArgs(trailingOnly = TRUE))) stop("Usage: Rscript scripts/run-extended-validation.R (from repository root)")
  run_extended_validation()
}
