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
check(nrow(manifest$ready) == 20L, "twenty available development pairs")
check(sum(manifest$pairs$status == "pending") == 16L, "missing material is explicit")
check(all(manifest$ready$label == "copied"), "no synthetic independent answer")
check(nrow(manifest$annotations) == 86L, "two-sided text math code origin annotations")
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
check(nrow(experiment$results) == 20L, "all ready pairs run")
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
check(file.exists(file.path(tmp, "results/localization.csv")), "localization CSV written")
check(nrow(saved$localization) == 120L, "three methods and two sides per pair")
metric <- validation_position_metrics(1:5, c(1L, 2L, 2L, 4L), c(1L, 3L, 3L))
check(metric$tp == 1L && metric$fp == 2L && metric$fn == 1L, "hand-calculated localization counts deduplicate")
check(isTRUE(all.equal(metric$precision, 1/3)) && metric$recall == 0.5, "hand-calculated precision and recall")
empty_prediction <- validation_position_metrics(1:5, integer(), 1:2)
check(is.na(empty_prediction$precision) && empty_prediction$recall == 0, "no prediction has zero recall and undefined precision")
empty_gold <- validation_position_metrics(1:5, 1L, integer())
check(is.na(empty_gold$recall) && empty_gold$precision == 0, "no copied-origin gold has undefined recall")
unavailable <- validation_position_metrics(integer(), integer(), integer(), available = FALSE)
check(is.na(unavailable$recall) && is.na(unavailable$tp) && unavailable$evaluation_status == "analysis_unavailable", "analysis failure is not zero recall")
check(fails(function() validation_position_metrics(1:3, 4L, 1L)), "unknown prediction position rejected")
check(fails(function() validation_position_metrics(1:3, 1L, NA_integer_)), "missing gold position rejected")
loc <- experiment$localization
locate <- function(id, method, side) loc[loc$pair_id == id & loc$method == method & loc$side == side, ]
for (side in c("A", "B")) {
  row <- locate("T01_format", "text", side)
  check(row$precision == 1 && row$recall == 1, paste(side, "text formatting origin localization"))
  row <- locate("T03_format", "code_local", side)
  check(row$gold == 20L && row$tp == 20L && row$recall == 1, paste(side, "code token origin localization"))
  row <- locate("T02_light_edit", "formula_sequence", side)
  check(row$gold == 3L && row$tp == 3L && row$recall == 1, paste(side, "renamed formula steps and inserted step"))
  row <- locate("T02_dispersed", "formula_sequence", side)
  check(row$gold == 3L && row$predicted == 0L && row$recall == 0, paste(side, "formula heading boundary limitation retained"))
  row <- locate("T03_dispersed", "code_local", side)
  check(row$gold == 20L && row$predicted == 0L && row$recall == 0, paste(side, "short separated code units limitation retained"))
}
for (side in c("A", "B")) {
  row <- locate("T01_local", "text", side)
  check(row$precision == 1 && row$recall == 1, paste(side, "local text boundaries"))
}
duplicate_gold <- rbind(manifest$annotations, manifest$annotations)
duplicate_loc <- evaluate_validation_localization(experiment$details$T01_format, duplicate_gold, "T01_format")
original_loc <- loc[loc$pair_id == "T01_format", ]
check(identical(duplicate_loc$tp, original_loc$tp) && identical(duplicate_loc$gold, original_loc$gold), "overlapping annotations do not double-count")
failed <- experiment$details$T01_exact; failed$modules$text$status <- "error"; failed$modules$text$value <- NULL
failed_loc <- evaluate_validation_localization(failed, manifest$annotations, "T01_exact")
check(all(is.na(failed_loc$recall[failed_loc$method == "text"])), "failed module does not become a missed detection")
check(identical(saved$localization, experiment$localization), "localization snapshot round trip")
unlink(tmp, recursive = TRUE)
cat("All", checks, "validation-pipeline assertions passed.\n")
