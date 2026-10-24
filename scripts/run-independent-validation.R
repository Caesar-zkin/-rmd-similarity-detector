# Local only. No directory scanning and no rendering/evaluation of input Rmd.
source("scripts/run-validation.R", encoding = "UTF-8")
source("scripts/extended-validation.R", encoding = "UTF-8")
source("scripts/independent-validation.R", encoding = "UTF-8")
if (sys.nframe() == 0L) {
  args <- commandArgs(trailingOnly = TRUE)
  if (!length(args)) run_independent_validation() else if (identical(args, "--audit"))
    audit_independent_metadata() else stop("Usage: Rscript scripts/run-independent-validation.R [--audit] (from repository root)")
}
