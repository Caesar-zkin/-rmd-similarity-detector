source("scripts/run-extended-validation.R", encoding = "UTF-8")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL ", label)
  checks <<- checks + 1L
  cat("PASS", label, "\n")
}
fails <- function(fun) inherits(tryCatch(fun(), error = identity), "error")
m <- validate_extended_manifest()
check(nrow(m$cases) == 12L && length(unique(m$cases$family)) == 3L, "twelve controls from three source families")
check(all(m$cases$split == "dev" & m$cases$label == "copied"), "no independent or held-out claim")
check(nrow(m$annotations) == 140L, "copied-origin ranges verified on both sides")
for (path in c("validation/dev/T01/base.Rmd", "validation/holdout-local/a.Rmd",
    "validation/independent-local/a.Rmd", "validation/extended/fixtures/E01/../E02/base.Rmd",
    "validation/extended/fixtures/E01/not-registered.Rmd", "C:/private/a.Rmd"))
  check(fails(function() extended_input_path(".", path)), "reject unregistered fixture path")
text <- read_rmd("validation/extended/fixtures/E01/base.Rmd")
check(sum(nchar(prepare_text_units(text)$normalized_text)) > 300L, "coherent longer prose fixture")
math <- read_rmd("validation/extended/fixtures/E02/base.Rmd")
steps <- prepare_math_steps(math)
check(nrow(steps) == 5L && all(steps$math_status == "ok"), "supported five-step mathematical derivation")
code <- read_rmd("validation/extended/fixtures/E03/base.Rmd")
check(nrow(prepare_code_statements(code)) == 12L, "twelve whole top-level code statements")

tmp <- tempfile("extended-validation-"); dir.create(tmp)
dir.create(file.path(tmp, "validation")); dir.create(file.path(tmp, "validation/extended"))
file.copy("validation/extended/fixtures", file.path(tmp, "validation/extended"), recursive = TRUE)
write_cases <- function(cases) utils::write.csv(cases, file.path(tmp, "validation/extended/cases.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write_annotations <- function(a) utils::write.csv(a, file.path(tmp, "validation/extended/annotations.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write_cases(m$cases); write_annotations(m$annotations)
bad <- m$cases; bad$split[1L] <- "holdout"; write_cases(bad)
check(fails(function() validate_extended_manifest(tmp)), "split cannot become held-out evaluation")
bad <- m$cases; bad$label[1L] <- "independent"; write_cases(bad)
check(fails(function() validate_extended_manifest(tmp)), "derived material cannot become independent")
bad <- m$cases; bad$provenance[1L] <- "unknown"; write_cases(bad)
check(fails(function() validate_extended_manifest(tmp)), "explicit synthetic provenance required")
bad <- m$cases; bad$target_file[1L] <- "validation/extended/fixtures/E02/base.Rmd"; write_cases(bad)
check(fails(function() validate_extended_manifest(tmp)), "family and target path must agree")
write_cases(m$cases)
bad <- m$annotations; bad$quote[1L] <- "stale"; write_annotations(bad)
check(fails(function() validate_extended_manifest(tmp)), "stale origin quote rejected")
bad <- m$annotations; bad$start[1L] <- "1.5"; write_annotations(bad)
check(fails(function() validate_extended_manifest(tmp)), "fractional origin offset rejected")
bad <- rbind(m$annotations, m$annotations[1L, ]); write_annotations(bad)
check(fails(function() validate_extended_manifest(tmp)), "overlapping origins rejected")
bad <- m$annotations; bad$kind[1L] <- "code"; write_annotations(bad)
check(fails(function() validate_extended_manifest(tmp)), "origin kind must agree with material")
bad <- m$annotations; bad <- bad[!(bad$pair_id == "E01_exact" & bad$side == "B"), ]; write_annotations(bad)
check(fails(function() validate_extended_manifest(tmp)), "both origin sides required")
write_annotations(m$annotations)

bundle <- run_extended_validation(output = file.path(tmp, "results"))
check(nrow(bundle$results) == 12L && nrow(bundle$localization) == 72L, "all pairs and separate localization units evaluated")
check(all(bundle$results$verdict == "not_enabled"), "formal verdict remains disabled")
check(all(bundle$results$candidate_verdict %in% c("suspected", "no_clear_evidence", "insufficient_evidence")), "observed candidates retained without imposing target outcomes")
check(!any(bundle$results$overall_status %in% c("input_error", "partial_failure")), "all longer controls analyzed without module errors")
check(all(bundle$results$rule_version == decision_rules_v1()$version), "default decision version unchanged")
for (r in bundle$details) check(identical(r$decision$rules, validate_decision_rules(decision_rules_v1())), "all default thresholds retained")
for (variant in c("exact", "format")) {
  row <- bundle$results[bundle$results$pair_id == paste0("E01_", variant), ]
  check(row$text_coverage_a == 1 && row$text_coverage_b == 1, paste("long prose", variant, "full character coverage"))
  row <- bundle$results[bundle$results$pair_id == paste0("E03_", variant), ]
  check(row$code_coverage_a == 1 && row$code_coverage_b == 1, paste("long code", variant, "full token coverage"))
}
loc <- bundle$localization
for (method in c("text", "code_local", "formula_sequence")) {
  family <- switch(method, text = "E01", code_local = "E03", formula_sequence = "E02")
  rows <- loc[loc$pair_id == paste0(family, "_format") & loc$method == method, ]
  check(all(rows$recall == 1 & rows$precision == 1), paste(method, "format origin localization"))
}
saved <- readRDS(file.path(tmp, "results/experiment.rds"))
check(identical(saved$results, bundle$results) && identical(saved$localization, bundle$localization), "results and localization snapshot round trip")
check(identical(saved$decision_summary, bundle$decision_summary), "decision summary snapshot round trip")
check(all(!is.na(saved$hashes$md5)), "all fixture and engine fingerprints available")
check(!any(grepl("holdout|independent-local|validation/dev/", saved$hashes$path)), "no core or private material read")
check(all(saved$decision_summary$evaluated[saved$decision_summary$scope == "all" & saved$decision_summary$label == "independent"] == 0L), "no independent samples invented")
check(all(is.na(saved$decision_summary$false_alarm_rate)), "false-alarm estimate remains unavailable")
for (name in c("results.csv", "localization.csv", "decision-summary.csv", "input-and-code-hashes.csv", "experiment.rds"))
  check(file.exists(file.path(tmp, "results", name)), "experiment output written")
check(identical(validate_development_manifest()$pairs, validation_read_csv("validation/pairs.csv")), "original core registry unchanged")
unlink(tmp, recursive = TRUE)
cat("All", checks, "extended-development assertions passed.\n")
