# Run from the repository root. This script never opens held-out material.
source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
source("scripts/validation-tools.R", encoding = "UTF-8")
source("scripts/validation-localization.R", encoding = "UTF-8")
source("scripts/validation-decisions.R", encoding = "UTF-8")
if (sys.nframe() == 0L) {
  if (length(commandArgs(trailingOnly = TRUE))) stop("Usage: Rscript scripts/run-validation.R (from repository root)")
  run_development_validation()
}
