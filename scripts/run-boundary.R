# Run from repository root. This entry does not open core or held-out registries.
source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
source("scripts/validation-tools.R", encoding = "UTF-8")
source("scripts/boundary-tools.R", encoding = "UTF-8")
if (sys.nframe() == 0L) {
  if (length(commandArgs(trailingOnly = TRUE))) stop("Usage: Rscript scripts/run-boundary.R (from repository root)")
  run_boundary_validation()
}
