if (!requireNamespace("rmarkdown", quietly = TRUE) || !rmarkdown::pandoc_available())
  stop("Install rmarkdown and Pandoc before running render integration tests.")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L; cat("PASS", label, "\n")
}
temp <- tempfile("rmd-standalone-report-"); dir.create(temp)
file.copy("detector.Rmd", file.path(temp, "detector.Rmd"))
pa <- file.path(temp, "示例 A.Rmd"); pb <- file.path(temp, "示例 B.Rmd")
file.copy("examples/report-a.Rmd", pa); file.copy("examples/report-b.Rmd", pb)
render <- function(a, b, output) {
  path <- rmarkdown::render(file.path(temp, "detector.Rmd"), output_file = output, output_dir = temp,
    params = list(input_a = normalizePath(a, winslash = "/"), input_b = normalizePath(b, winslash = "/")),
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
check(grepl("局部代码对应", html, fixed = TRUE) && grepl("推导步骤对应", html, fixed = TRUE), "code and multiline formula evidence rendered")
check(!grepl("rmd_empty_units <- function", html, fixed = TRUE), "bundled implementation hidden in report")
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
unlink(temp, recursive = TRUE)
cat("All", count, "standalone-render assertions passed.\n")
