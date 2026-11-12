if (!requireNamespace("rmarkdown", quietly = TRUE) || !rmarkdown::pandoc_available())
  stop("Install rmarkdown and Pandoc before running render integration tests.")
if (!requireNamespace("shiny", quietly = TRUE))
  stop("Install shiny before running interactive report integration tests.")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L; cat("PASS", label, "\n")
}
temp <- tempfile("rmd-standalone-report-"); dir.create(temp)
file.copy("detector.Rmd", file.path(temp, "detector.Rmd"))
check(identical(rmarkdown::yaml_front_matter(file.path(temp, "detector.Rmd"))$runtime, "shiny"),
  "main document opens as a Shiny app in RStudio")
pa <- file.path(temp, "示例 A.Rmd"); pb <- file.path(temp, "示例 B.Rmd")
file.copy("examples/report-a.Rmd", pa); file.copy("examples/report-b.Rmd", pb)
prompt_a <- "validation/boundary/fixtures/B03/a.Rmd"
prompt_b <- "validation/boundary/fixtures/B03/b.Rmd"
prompt <- file.path(temp, "共同题干.Rmd")
writeLines(enc2utf8(readLines(prompt_a, encoding = "UTF-8")[3L]), prompt, useBytes = TRUE)
shiny::testServer(function(input, output, session) {
  app_path <- rmarkdown::render(file.path(temp, "detector.Rmd"), runtime = "shiny",
    output_file = "app.html", output_dir = temp, envir = environment(), quiet = TRUE)
  app_html <- paste(readLines(app_path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  check(all(vapply(c('id="assignment_a"', 'id="assignment_b"', 'id="public_reference"', 'id="analyze"', 'id="analysis_result"'),
    grepl, logical(1), x = app_html, fixed = TRUE)), "interactive document renders both file inputs and an inline result")
  check(!grepl("class='detector-report'", app_html, fixed = TRUE), "interactive document waits for submitted files")
  check(!grepl("rmd_empty_units", app_html, fixed = TRUE), "interactive page hides the bundled engine")
}, {
  upload <- function(path, name = basename(path)) {
    data.frame(name = name, size = file.info(path)$size, type = "text/plain", datapath = path)
  }
  session$setInputs(assignment_a = upload(pa), assignment_b = upload(pb), analyze = 1L)
  check(all(vapply(c(basename(pa), basename(pb), "分析结果速览"), grepl, logical(1),
    x = output$analysis_result$html, fixed = TRUE)), "submitted files produce a report with their original names")
  session$setInputs(assignment_b = upload(pb, "replacement.Rmd"))
  message <- tryCatch(output$analysis_result, error = conditionMessage)
  check(is.character(message) && grepl("文件已更换", message, fixed = TRUE), "replacing a file invalidates the previous report")
  session$setInputs(analyze = 2L)
  check(grepl("replacement.Rmd", output$analysis_result$html, fixed = TRUE), "submitting the replacement updates the inline report")
  session$setInputs(assignment_a = upload(prompt_a), assignment_b = upload(prompt_b),
    public_reference = upload(prompt), analyze = 3L)
  check(grepl("已按公共参考排除 2 个完整单元", output$analysis_result$html, fixed = TRUE) &&
    grepl("共同题干.Rmd", output$analysis_result$html, fixed = TRUE),
    "optional reference excludes the shared prompt in the interactive report")
})
render <- function(a, b, output, exclusions = "") {
  path <- rmarkdown::render(file.path(temp, "detector.Rmd"), runtime = "static", output_file = output, output_dir = temp,
    params = list(input_a = normalizePath(a, winslash = "/"), input_b = normalizePath(b, winslash = "/"),
      exclusion_file = if (nzchar(exclusions)) normalizePath(exclusions, winslash = "/") else ""),
    envir = new.env(parent = globalenv()), quiet = TRUE)
  paste(readLines(path, encoding = "UTF-8", warn = FALSE), collapse = "\n")
}
offline <- function(html) {
  # Retain script opening tags but remove JS bodies before inspecting resource tags.
  tags_only <- gsub("(?is)(<script\\b[^>]*>).*?</script>", "\\1</script>", html, perl = TRUE)
  tags <- regmatches(tags_only, gregexpr("(?i)<(?:script|link|img|iframe|source|audio|video)\\b[^>]*>", tags_only, perl = TRUE))[[1L]]
  attributes <- unlist(lapply(tags, function(tag) regmatches(tag,
    gregexpr("(?i)(?:src|href)\\s*=\\s*[\"'][^\"']*[\"']", tag, perl = TRUE))[[1L]]), use.names = FALSE)
  urls <- sub("^[^=]*=\\s*[\"']", "", attributes, perl = TRUE)
  urls <- sub("[\"']$", "", urls)
  all(grepl("^(data:|#|$)", urls))
}
html <- render(pa, pb, "report.html")
check(file.exists(file.path(temp, "report.html")), "standalone Rmd produces HTML")
check(!dir.exists(file.path(temp, "R")), "render needs no module directory")
check(grepl("未启用最终判定", html, fixed = TRUE), "verdict status in rendered HTML")
check(grepl("开发规则试判（未标定）", html, fixed = TRUE) && grepl("development-v1", html, fixed = TRUE), "draft tri-state decision and rule version survive standalone render")
check(grepl("局部代码对应", html, fixed = TRUE) && grepl("推导步骤对应", html, fixed = TRUE), "code and multiline formula evidence rendered")
check(grepl("证据整理：位置重叠与方法来源", html, fixed = TRUE) && grepl("largest_match", html, fixed = TRUE), "consolidated position evidence survives standalone rendering")
check(!any(vapply(c("rmd_empty_units", "group_position_evidence", "# BEGIN R/parser.R"),
  function(marker) grepl(marker, html, fixed = TRUE), logical(1))), "bundled implementation hidden after HTML escaping")
check(offline(html), "no external or relative resource dependencies")
sentinel <- file.path(temp, "must-not-exist.txt")
poison <- paste0("---\nauthor: !expr stop('YAML must not run')\n---\n\n```{r}\n",
  "danger <- \"<script id='rmd-poison'>alert(1)</script>\"\n",
  "# <img src='https://example.invalid/never-fetch' onerror='alert(1)'>\n",
  "stop('chunk must not run')\nwriteLines('executed', ", encodeString(sentinel, quote = "\""), ")\n```\n")
writeLines(enc2utf8(poison), pa, useBytes = TRUE); writeLines(enc2utf8(poison), pb, useBytes = TRUE)
safe <- render(pa, pb, "escaped-report.html")
check(!file.exists(sentinel), "render does not evaluate submitted YAML or chunks")
check(grepl("&lt;script id=", safe, fixed = TRUE), "input script payload escaped in final HTML")
check(!grepl("<script id=['\"]rmd-poison", safe, perl = TRUE), "no active injected script")
check(!grepl("<img src=['\"]https://example.invalid", safe, perl = TRUE), "no active injected image")
check(offline(safe), "poison input introduces no resource requests")
file.copy("validation/boundary/fixtures/B03/a.Rmd", pa, overwrite = TRUE)
file.copy("validation/boundary/fixtures/B03/b.Rmd", pb, overwrite = TRUE)
exclusion_csv <- file.path(temp, "公共 来源.csv")
file.copy("examples/prompt-exclusions.csv", exclusion_csv)
filtered <- render(pa, pb, "excluded-report.html", exclusion_csv)
check(grepl("公共来源：明确标注与排除前后", filtered, fixed = TRUE), "standalone file renders CSV exclusions")
check(grepl("排除前", filtered, fixed = TRUE) && grepl("排除后", filtered, fixed = TRUE), "rendered report retains both scopes")
check(grepl("操作者确认其公共来源", filtered, fixed = TRUE), "rendered source reference retained")
check(offline(filtered), "exclusion report stays self-contained offline")

# Exercise the actual command-line entry in a clean standalone installation.
# Direct rmarkdown::render tests do not cover its intermediates_dir behavior.
cli_root <- file.path(temp, "独立 CLI")
dir.create(file.path(cli_root, "scripts"), recursive = TRUE)
file.copy("detector.Rmd", file.path(cli_root, "detector.Rmd"))
file.copy("scripts/render-detector.R", file.path(cli_root, "scripts/render-detector.R"))
cli_script <- normalizePath(file.path(cli_root, "scripts/render-detector.R"), winslash = "/")
rscript <- unname(Sys.which("Rscript"))
if (!nzchar(rscript)) rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
cli <- function(a, b, name, exclusions = "") {
  output <- file.path(cli_root, name)
  args <- c(cli_script, normalizePath(a, winslash = "/"), normalizePath(b, winslash = "/"), output)
  if (nzchar(exclusions)) args <- c(args, normalizePath(exclusions, winslash = "/"))
  log <- suppressWarnings(system2(rscript, vapply(args, shQuote, character(1)), stdout = TRUE, stderr = TRUE))
  status <- attr(log, "status"); if (is.null(status)) status <- 0L
  if (status != 0L) cat(paste(tail(log, 30L), collapse = "\n"), "\n")
  check(status == 0L && file.exists(output), "standalone CLI generates an HTML report")
  check(!any(grepl("Could not convert TeX math", log, fixed = TRUE)), "CLI does not parse hidden R source as TeX")
  value <- paste(readLines(output, encoding = "UTF-8", warn = FALSE), collapse = "\n")
  has_container <- grepl("<div[^>]*class=['\"]detector-report['\"]", value, perl = TRUE)
  has_heading <- grepl("<h2[^>]*>\\s*开发规则试判（未标定）\\s*</h2>", value, perl = TRUE)
  if (!has_container || !has_heading) {
    lines <- strsplit(value, "\n", fixed = TRUE)[[1L]]
    cat(paste(lines[grepl("detector-report|开发规则试判|<h2|</h2>", lines)], collapse = "\n"), "\n")
  }
  check(has_container, "CLI contains actual rendered evidence container")
  check(has_heading, "CLI contains actual rendered decision heading")
  check(!any(vapply(c("rmd_empty_units", "group_position_evidence", "# BEGIN R/parser.R"),
    function(marker) grepl(marker, value, fixed = TRUE), logical(1))), "CLI HTML contains no bundled implementation")
  check(offline(value), "CLI HTML remains self-contained")
  value
}
cli_filtered <- cli(pa, pb, "题干 排除.html", exclusion_csv)
check(grepl("排除后", cli_filtered, fixed = TRUE), "CLI fourth-argument exclusions retained")
writeLines(enc2utf8(poison), pa, useBytes = TRUE); writeLines(enc2utf8(poison), pb, useBytes = TRUE)
cli_safe <- cli(pa, pb, "输入 转义.html")
check(!file.exists(sentinel), "CLI never evaluates submitted Rmd")
check(grepl("&lt;script id=", cli_safe, fixed = TRUE) &&
  !grepl("<script id=['\"]rmd-poison", cli_safe, perl = TRUE), "CLI preserves escaped input payload")
check(!dir.exists(file.path(cli_root, "R")), "CLI installation requires no R module directory")
unlink(temp, recursive = TRUE)
cat("All", count, "standalone-render assertions passed.\n")
