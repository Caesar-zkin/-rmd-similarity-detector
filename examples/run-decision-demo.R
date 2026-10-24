source("scripts/build-detector.R", encoding = "UTF-8")
for (path in detector_module_paths) source(path, encoding = "UTF-8")
tmp <- tempfile("draft-decision-demo-"); dir.create(tmp)
a <- file.path(tmp, "a.Rmd"); b <- file.path(tmp, "b.Rmd")
text <- paste0("分析开始前逐项核对观测记录的来源与单位，检查缺失值和可能的录入错误，并记录处理依据。",
  "随后同时报告中心位置、离散程度以及分布图形，避免用一个统计量代替全部特征。",
  "对异常观测先回查原始记录，再说明保留或剔除的理由，并比较不同处理下结论是否稳定。",
  "所有描述只针对当前样本，若要推广到总体，还需要明确抽样方式、适用条件以及不确定性的来源。")
writeLines(enc2utf8(text), a, useBytes = TRUE); writeLines(enc2utf8(text), b, useBytes = TRUE)
cases <- list(long_copied_text = analyze_rmd_pair(a, b),
  unrelated_synthetic_text = analyze_rmd_pair("validation/boundary/fixtures/B06/a.Rmd", "validation/boundary/fixtures/B06/b.Rmd"),
  short_routine_code = analyze_rmd_pair("validation/boundary/fixtures/B05/a.Rmd", "validation/boundary/fixtures/B05/b.Rmd"))
for (name in names(cases)) {
  d <- cases[[name]]$decision
  cat(name, ":", d$label, "[", d$pathway, "]\n")
  print(d$trigger_records, row.names = FALSE)
}
cat("Development rules only. Parameters are uncalibrated; no classification accuracy is claimed.\n")
unlink(tmp, recursive = TRUE)
