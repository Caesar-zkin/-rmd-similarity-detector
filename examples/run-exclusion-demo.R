source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
result <- analyze_rmd_pair("validation/boundary/fixtures/B03/a.Rmd",
  "validation/boundary/fixtures/B03/b.Rmd", exclusions = "examples/prompt-exclusions.csv")
cat("Explicit public-source exclusion status:", result$exclusions$status, "\n")
cat("Before exclusion:\n"); print(result$baseline_modules$text$value$coverage, row.names = FALSE)
cat("After exclusion:\n"); print(result$modules$text$value$coverage, row.names = FALSE)
cat("Excluded parser units:\n"); print(result$exclusions$units, row.names = FALSE)
cat("Source references are operator assertions. No automatic public-source recognition or plagiarism verdict.\n")
