# Synthetic contract fixtures only. No real participant data or false-alarm estimate.
source("scripts/run-independent-validation.R", encoding = "UTF-8")
cat("Synthetic temporary contract fixtures only; no human answers or empirical false-alarm estimate.\n")
checks <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAIL ", label)
  checks <<- checks + 1L; cat("PASS", label, "\n")
}
fails <- function(fun) inherits(tryCatch(fun(), error = identity), "error")
tmp <- tempfile("independent-contract-"); dir.create(tmp)
file.copy("R", tmp, recursive = TRUE); file.copy("scripts", tmp, recursive = TRUE)
dir.create(file.path(tmp, "validation"))
for (folder in c("dev", "extended")) file.copy(file.path("validation", folder), file.path(tmp, "validation"), recursive = TRUE)
for (name in c("independent-metadata-template.csv", "independent-tasks.md", "independent-extended-tasks.md", "independent-collection.md"))
  file.copy(file.path("validation", name), file.path(tmp, "validation", name))
refs <- independent_references()
check(nrow(refs) == 7L && !any(refs$task_id %in% c("T05", "T06")), "only seven development tasks may be referenced")
check(fails(function() independent_source_path(tmp, "T05")), "held-out task rejected")
intake <- read_independent_metadata(tmp)
check(intake$using_template && nrow(intake$metadata) == 7L && all(intake$metadata$status == "pending"), "missing local metadata uses pending template")
check(!dir.exists(file.path(tmp, "validation/independent-local")), "reading template does not create private data")
zero <- run_independent_validation(tmp)
check(nrow(zero$results) == 0L && all(is.na(zero$summary$false_alarm_rate)), "no collected answers means undefined false-alarm rates")
check(all(zero$summary$pending[zero$summary$scope == "cohort"] == c(4L, 3L)), "core and extended pending slots remain separate")
check(!any(grepl("fixtures/.*/base|validation/dev/", zero$hashes$path)), "pending references are not opened or fingerprinted")
check(!any(grepl("holdout", zero$hashes$path)), "held-out files never opened")

private <- file.path(tmp, "validation/independent-local"); dir.create(private)
metadata_path <- file.path(private, "metadata.csv")
write_metadata <- function(m) utils::write.csv(m, metadata_path, row.names = FALSE, fileEncoding = "UTF-8")
m <- intake$metadata; m$file_path[1L] <- "validation/holdout-local/not-opened.Rmd"; write_metadata(m)
check(audit_independent_metadata(tmp, write = FALSE)$audit$check_status[1L] == "pending", "pending file path never opened")
m$status[1L] <- "excluded"; write_metadata(m)
check(audit_independent_metadata(tmp, write = FALSE)$audit$check_status[1L] == "excluded", "excluded file path never opened")
m <- intake$metadata
m$status[1L] <- "received"; m$participant_code[1L] <- "I01"; m$completed_on[1L] <- "2026-10-24"
m$prior_answer_access[1L] <- "no"; m$authorship[1L] <- "human_self_report"
m$assistance_kind[1L] <- "none"; m$assistance[1L] <- "none"; m$consent_to_local_use[1L] <- "yes"
m$file_path[1L] <- "validation/independent-local/I01-T01.Rmd"
m$notes[1L] <- "SYNTHETIC CONTRACT FIXTURE; no human answer was collected."
sentinel <- file.path(tmp, "must-not-exist.txt")
answer <- c("---", "title: test", "---", "", "This is a synthetic contract input and is not evidence of independent human authorship.",
  "", "`r stop('inline input must never run')`", "", "```{r}",
  paste0("writeLines('must not run', ", encodeString(sentinel, quote = '"'), ")"), "stop('block input must never run')", "```")
writeLines(answer, file.path(tmp, m$file_path[1L]), useBytes = TRUE)
write_metadata(m)
audit <- audit_independent_metadata(tmp, write = FALSE)
check(audit$audit$check_status[1L] == "needs_human_review", "received is not automatically verified")
check(grepl("^[a-f0-9]{32}$", audit$audit$observed_source_md5[1L]) && grepl("^[a-f0-9]{32}$", audit$audit$observed_answer_md5[1L]), "review fingerprints computed")
before <- unname(tools::md5sum(metadata_path)); invisible(audit_independent_metadata(tmp))
check(identical(before, unname(tools::md5sum(metadata_path))), "audit never changes metadata statuses or fields")
check(file.exists(file.path(private, "audit.csv")), "audit output remains private")
for (field in c("consent_to_local_use", "prior_answer_access", "authorship", "assistance_kind")) {
  bad <- m; bad[[field]][1L] <- switch(field, consent_to_local_use = "no", prior_answer_access = "yes", authorship = "ai_generated", assistance_kind = "ai_or_human_help")
  bad$file_path[1L] <- "validation/holdout-local/not-opened.Rmd"; write_metadata(bad)
  a <- audit_independent_metadata(tmp, write = FALSE)$audit
  check(a$check_status[1L] == "blocked" && a$observed_answer_md5[1L] == "" && a$observed_source_md5[1L] == "", paste(field, "blocks file access"))
}
for (path in c("validation/independent-local/../holdout-local/a.Rmd", "validation/dev/T01/base.Rmd",
    "validation/holdout-local/a.Rmd", "C:/private/a.Rmd", "validation/independent-local/a.R"))
  check(fails(function() independent_answer_path(tmp, path)), "answer path outside local Rmd scope rejected")
unicode <- "validation/independent-local/I02-独立 答案.Rmd"
writeLines("contract fixture", file.path(tmp, unicode), useBytes = TRUE)
check(file.exists(independent_answer_path(tmp, unicode)), "Chinese and space answer path supported")

verified <- m; verified$status[1L] <- "verified"
verified$source_md5[1L] <- audit$audit$observed_source_md5[1L]
verified$answer_md5[1L] <- audit$audit$observed_answer_md5[1L]
verified$reviewed_by[1L] <- "R01"; verified$reviewed_on[1L] <- "2026-10-24"
write_metadata(verified)
check(audit_independent_metadata(tmp, write = FALSE)$audit$check_status[1L] == "review_record_matches", "matching human review record allows analysis")
bundle <- run_independent_validation(tmp)
check(nrow(bundle$results) == 1L && bundle$results$pair_id == verified$pair_id[1L], "only verified row evaluated")
check(!file.exists(sentinel), "input code and inline R remain unevaluated")
check(bundle$results$verdict == "not_enabled" && bundle$results$decision_stage == "development_unvalidated", "formal verdict remains disabled")
check(all(!is.na(bundle$hashes$md5)), "input metadata and engine fingerprints retained")
check(identical(bundle$details[[1L]]$decision$rules, validate_decision_rules(decision_rules_v1())), "default detection thresholds unchanged")
saved <- readRDS(file.path(tmp, "reports-local/independent/experiment.rds"))
check(identical(saved$results, bundle$results) && identical(saved$summary, bundle$summary), "private snapshot round trip")
check(inherits(saved$details[[1L]]$documents$B, "rmd_document"), "full private analysis available locally")
snapshot <- file.path(tmp, "reports-local/independent/experiment.rds"); snapshot_hash <- unname(tools::md5sum(snapshot))
for (field in c("source_md5", "answer_md5", "reviewed_by", "reviewed_on", "completed_on", "assistance", "notes")) {
  bad <- verified; bad[[field]][1L] <- ""; write_metadata(bad)
  check(fails(function() run_independent_validation(tmp)), paste("verified missing", field, "rejected"))
}
check(identical(snapshot_hash, unname(tools::md5sum(snapshot))), "failed intake does not overwrite previous experiment")
write_metadata(verified)
cat("\nchanged", file = file.path(tmp, verified$file_path[1L]), append = TRUE)
check(fails(function() run_independent_validation(tmp)), "changed answer invalidates review fingerprint")
writeLines(answer, file.path(tmp, verified$file_path[1L]), useBytes = TRUE)
source <- independent_source_path(tmp, "T01"); original_source <- readBin(source, "raw", n = file.info(source)$size)
cat("changed", file = source, append = TRUE)
check(fails(function() run_independent_validation(tmp)), "changed reference invalidates review fingerprint")
con <- file(source, "wb"); writeBin(original_source, con); close(con)
duplicate <- rbind(verified, verified[1L, ]); duplicate$pair_id[nrow(duplicate)] <- "extra_answer"
duplicate$participant_code[nrow(duplicate)] <- "I02"; write_metadata(duplicate)
check(fails(function() run_independent_validation(tmp)), "one file cannot count for two participants")
file.copy(file.path(tmp, verified$file_path[1L]), file.path(private, "second.Rmd"))
duplicate$participant_code[nrow(duplicate)] <- "I01"
duplicate$file_path[nrow(duplicate)] <- "validation/independent-local/second.Rmd"; write_metadata(duplicate)
check(fails(function() run_independent_validation(tmp)), "same participant and task cannot count twice")
bad <- verified; bad$task_id[1L] <- "T05"; write_metadata(bad)
check(fails(function() read_independent_metadata(tmp)), "held-out metadata row rejected")
write_metadata(verified[, names(verified) != "assistance_kind"])
check(fails(function() read_independent_metadata(tmp)), "old metadata requires explicit upgrade")
bad <- verified; bad$completed_on[1L] <- "2026-02-30"; write_metadata(bad)
check(fails(function() run_independent_validation(tmp)), "invalid calendar date rejected")

# Hand-calculated summary accounting, not an empirical false-alarm experiment.
contract <- verified[c(1L, 2L, 3L, 5L, 6L), ]; contract$status <- "verified"
contract$participant_code <- c("I01", "I01", "I02", "I03", "I03")
observed <- data.frame(pair_id = contract$pair_id, task_id = contract$task_id,
  cohort = c("core", "core", "core", "extended", "extended"), participant_code = contract$participant_code,
  overall_status = "completed", verdict = "not_enabled",
  candidate_verdict = c("suspected", "no_clear_evidence", "insufficient_evidence", "suspected", "insufficient_evidence"),
  candidate_label = "contract only", candidate_pathway = "contract only", decision_status = c("ok", "ok", "error", "ok", "ok"),
  rule_version = "contract-v1", decision_stage = "development_unvalidated", stringsAsFactors = FALSE)
summary <- summarize_independent_validation(contract, observed)
core <- summary[summary$scope == "cohort" & summary$cohort == "core", ]
extended <- summary[summary$scope == "cohort" & summary$cohort == "extended", ]
check(core$evaluated == 3L && core$participants == 2L, "answers and participants counted separately")
check(isTRUE(all.equal(core$false_alarm_rate, 1/3)) && isTRUE(all.equal(core$abstention_rate, 1/3)), "hand-calculated rates retain insufficient denominator")
check(core$decision_errors == 1L && core$insufficient_evidence == 1L, "failure stays within insufficient count")
check(extended$evaluated == 2L && extended$participants == 1L && extended$false_alarm_rate == 0.5, "extended cohort not pooled into core")
check(all(is.na(summary$false_alarm_rate[summary$evaluated == 0L])), "empty task rates remain undefined")
check(all(summary$suspected + summary$no_clear_evidence + summary$insufficient_evidence == summary$evaluated), "three outcomes partition evaluated answers")
check(identical(summary, summarize_independent_validation(contract, observed[5:1, ])), "summary joins by ID")
check(fails(function() summarize_independent_validation(contract, observed[-1L, ])), "missing verified result rejected")
check(fails(function() summarize_independent_validation(contract, rbind(observed, observed[1L, ]))), "duplicate result rejected")
for (field in c("participant_code", "task_id", "cohort", "rule_version", "decision_stage", "verdict")) {
  bad <- observed; bad[[field]][1L] <- "wrong"
  check(fails(function() summarize_independent_validation(contract, bad)), paste("mismatched", field, "rejected"))
}
bad <- observed; bad$candidate_verdict[3L] <- "no_clear_evidence"
check(fails(function() summarize_independent_validation(contract, bad)), "decision failure cannot become no evidence")
if (.Platform$OS.type == "unix") {
  outside <- tempfile("outside-answer-"); writeLines("must not open", outside)
  linked <- file.path(private, "linked.Rmd")
  if (file.symlink(outside, linked)) check(fails(function() independent_answer_path(tmp, "validation/independent-local/linked.Rmd")), "symlink escape rejected")
  unlink(outside)
}
check(all(c("reports-local/", "validation/independent-local/") %in% readLines(".gitignore")), "private inputs and results ignored by Git")
unlink(tmp, recursive = TRUE)
cat("All", checks, "independent-validation contract assertions passed. No human data collected.\n")
