source("scripts/run-validation.R", encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL ", label)
  checks <<- checks + 1L
  cat("PASS", label, "\n")
}
fails <- function(fun) inherits(tryCatch(fun(), error = identity), "error")
manifest <- validate_development_manifest()
check(nrow(manifest$tasks) == 6L, "six fixed tasks")
check(sum(manifest$tasks$split == "dev") == 4L, "four development tasks")
check(sum(manifest$tasks$split == "holdout") == 2L, "two reserved held-out tasks")
check(nrow(manifest$pairs) == 36L, "36 planned pairs")
check(nrow(manifest$ready) == 8L, "eight available baseline pairs")
check(sum(manifest$pairs$status == "pending") == 28L, "missing material is explicit")
check(all(manifest$ready$label == "copied"), "no synthetic independent answer")
check(nrow(manifest$annotations) == 24L, "two-sided text math code annotations")
for (path in c("validation/dev/../holdout-local/a.Rmd", "validation/holdout-local/a.Rmd", "C:/private/a.Rmd", "validation/dev/a.Rmd/../../a.Rmd"))
  check(fails(function() validation_input_path(".", path)), "reject input outside development scope")

tmp <- tempfile("validation-tests-"); dir.create(tmp)
# A disposable manifest copy permits negative tests without altering the real registry.
dir.create(file.path(tmp, "validation"))
file.copy(list.files("validation", pattern = "[.]csv$", full.names = TRUE), file.path(tmp, "validation"))
file.copy("validation/dev", file.path(tmp, "validation"), recursive = TRUE)
write_pairs <- function(x) utils::write.csv(x, file.path(tmp, "validation/pairs.csv"), row.names = FALSE, fileEncoding = "UTF-8")
broken <- manifest$pairs; broken$split[1L] <- "holdout"; write_pairs(broken)
check(fails(function() validate_development_manifest(tmp)), "task variants cannot move across splits")
broken <- manifest$pairs; held <- which(broken$split == "holdout")[1L]
broken$source_file[held] <- "private.Rmd"; write_pairs(broken)
check(fails(function() validate_development_manifest(tmp)), "held-out paths cannot enter public registry")
broken <- manifest$pairs; broken$provenance[1L] <- ""; write_pairs(broken)
check(fails(function() validate_development_manifest(tmp)), "ready pairs require provenance")
write_pairs(manifest$pairs)
bad_annotations <- manifest$annotations; bad_annotations$quote[1L] <- "wrong quote"
utils::write.csv(bad_annotations, file.path(tmp, "validation/annotations.csv"), row.names = FALSE, fileEncoding = "UTF-8")
check(fails(function() validate_development_manifest(tmp)), "stale offsets or changed source are rejected")

experiment <- run_development_validation(output = file.path(tmp, "results"))
check(nrow(experiment$results) == 8L, "all ready pairs run")
check(all(experiment$results$verdict == "not_enabled"), "no premature classification")
check(!any(experiment$results$overall_status %in% c("input_error", "partial_failure")), "all baseline analyses complete without errors")
for (id in c("T01_exact", "T01_format", "T04_exact", "T04_format")) {
  r <- experiment$results[experiment$results$pair_id == id, ]
  check(r$text_coverage_a == 1 && r$text_coverage_b == 1, paste(id, "text formatting invariant"))
}
for (id in c("T03_exact", "T03_format", "T04_exact", "T04_format")) {
  r <- experiment$results[experiment$results$pair_id == id, ]
  check(r$code_coverage_a == 1 && r$code_coverage_b == 1, paste(id, "code formatting invariant"))
}
for (id in c("T02_exact", "T02_format"))
  check(any(experiment$details[[id]]$modules$formula_sequence$value$matches$matched_steps == 3L), paste(id, "three formula steps"))
check(is.na(experiment$results$text_coverage_a[experiment$results$pair_id == "T03_exact"]), "missing text coverage stays NA")
check(is.na(experiment$results$code_coverage_a[experiment$results$pair_id == "T01_exact"]), "missing code coverage stays NA")
saved <- readRDS(file.path(tmp, "results/experiment.rds"))
check(identical(saved$results, experiment$results), "experiment snapshot round trip")
check(all(!is.na(saved$hashes$md5)), "all input and engine fingerprints recorded")
check(!any(grepl("holdout", saved$hashes$path, fixed = TRUE)), "held-out material never opened")
check(length(saved$details$T01_exact$modules$text$value$parameters) > 0L, "effective parameters preserved")
check(file.exists(file.path(tmp, "results/results.csv")), "CSV summary written")
unlink(tmp, recursive = TRUE)
cat("All", checks, "validation-pipeline assertions passed.\n")
