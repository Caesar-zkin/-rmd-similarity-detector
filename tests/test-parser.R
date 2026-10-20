# Run from repository root: Rscript tests/test-parser.R
source("R/parser.R", encoding = "UTF-8")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop("FAILED: ", label, call. = FALSE)
  count <<- count + 1L
  cat("PASS ", label, "\n", sep = "")
}
has_diag <- function(d, code) code %in% d$diagnostics$code
check_spans <- function(d) {
  u <- d$units
  check(identical(paste0(u$raw, collapse = ""), d$source), "source reconstructs exactly")
  if (nrow(u)) {
    check(u$start_offset[1L] == 1L && tail(u$end_offset, 1L) == nchar(d$source), "full source bounds")
    check(nrow(u) == 1L || all(tail(u$start_offset, -1L) == head(u$end_offset, -1L) + 1L), "no gaps or duplicate spans")
    for (k in seq_len(nrow(u))) {
      pre <- if (u$start_offset[k] > 1L) substr(d$source, 1L, u$start_offset[k] - 1L) else ""
      nl <- gregexpr("\n", pre, fixed = TRUE)[[1L]]
      expected_line <- 1L + if (nl[1L] == -1L) 0L else length(nl)
      check(u$start_line[k] == expected_line, paste("line map", k))
      check(identical(substr(d$source, u$start_offset[k], u$end_offset[k]), u$raw[k]), paste("raw span", k))
      expected_content <- if (u$content_start[k] > u$content_end[k]) "" else
        substr(d$source, u$content_start[k], u$content_end[k])
      check(identical(expected_content, u$content[k]), paste("content span", k))
    }
  }
}

sample <- paste(c("---", "title: 示例", "---", "# 第一题", "",
  "正文含 $x_i$ 与 `r mean(x)`，以及 `lm`。", "",
  "```{r fitting, eval=FALSE}", "# $not_math$", "stop('never execute')", "```", "",
  "\\[", "x+y=z", "\\]", "", "![图](plot.png)", "[资料](https://example.org/a(b))"), collapse = "\n")
d <- parse_rmd_text(sample, "A")
check_spans(d)
check(sum(d$units$type == "yaml") == 1L, "YAML isolated")
check(sum(d$units$type == "heading") == 1L, "heading isolated")
check(sum(d$units$type == "math") == 2L, "inline and display math")
check(identical(d$units$content[d$units$type == "inline_r"], "mean(x)"), "inline R body")
check(identical(d$units$content[d$units$type == "inline_code"], "lm"), "ordinary inline code")
code <- d$units[d$units$type == "code", ]
check(code$language == "r" && code$start_line == 8L && code$end_line == 11L, "code fence range and language")
check(grepl("stop('never execute')", code$content, fixed = TRUE), "code read without evaluation")
check(all(d$units$section[d$units$start_line >= 6L] == "第一题"), "section association")
check(has_diag(d, "image_not_read"), "image limitation recorded")
check("资料" %in% d$units$content, "link label extracted without destination")
check(length(unique(d$units$context_id[d$units$start_line == 6L])) == 1L, "inline pieces share context")

math <- parse_rmd_text("$a$ $$b$$ \\(c\\) \\[d\\] \\begin{align}e&=f\\\\g&=h\\end{align}")
check_spans(math)
check(sum(math$units$type == "math") == 5L, "supported math delimiters and environment")
check(!any(math$units$status == "limited"), "closed math recognized")
escaped <- parse_rmd_text("价格为 \\$100，变量 $x$，正文。")
check(sum(escaped$units$type == "math") == 1L, "escaped dollar is prose")

fences <- parse_rmd_text("````{r}\nx <- '$y$'\n```\n````\n~~~python\nx = 2\n~~~")
check_spans(fences)
check(sum(fences$units$type == "code") == 2L, "variable fence length and tildes")
check(sum(fences$units$type == "math") == 0L, "dollars inside code not math")
check(has_diag(fences, "code_language_limited"), "non-R limitation")

inline <- parse_rmd_text("普通 ``a ` b`` 和 `r 1+1`。")
check("a ` b" %in% inline$units$content, "variable inline backtick length")
check("1+1" %in% inline$units$content, "inline R not evaluated")

for (case in list(c("---\ntitle: x", "unclosed_yaml"),
                 c("```{r}\nx <- 1", "unclosed_fence"),
                 c("公式 $x\n后续文字", "unclosed_math"),
                 c("$$\nx", "unclosed_math"),
                 c("文字 `x", "unclosed_inline_code"),
                 c("<!-- x", "unclosed_html_comment"))) {
  broken <- parse_rmd_text(case[1L]); check_spans(broken)
  check(has_diag(broken, case[2L]), paste("diagnostic", case[2L]))
  check(any(broken$units$status == "limited"), "broken content is limited")
}

html <- parse_rmd_text("<!-- $x$ -->\n<script>\nlet z = '$y$';\n</script>\n正文")
check_spans(html)
check(!any(html$units$type == "math"), "HTML comments and scripts excluded from math")
check(has_diag(html, "raw_html"), "HTML limitation")
check(has_diag(parse_rmd_text("    x <- 1"), "indentation_ambiguous"), "indented block limitation")
check(has_diag(parse_rmd_text("\\begin{unknown}x\\end{unknown}"), "latex_environment_limited"), "unknown environment limitation")
check(has_diag(parse_rmd_text("![图][ref]"), "image_syntax_limited"), "reference image limitation")

empty <- parse_rmd_text("")
check(nrow(empty$units) == 0L && has_diag(empty, "empty_document"), "empty schema and diagnostic")
check(identical(names(empty$units), names(d$units)), "stable empty schema")
for (s in c("x", "\n", "\n\n", "# 标题\n", "```{r}\n```", "---\n---", "$$x\n\ny$$", "a\r\nb\rc")) check_spans(parse_rmd_text(s))

tmp <- tempfile("rmd-parser-")
dir.create(tmp)
on.exit_cleanup <- function() unlink(tmp, recursive = TRUE)
tryCatch({
  path <- file.path(tmp, "中文作业.Rmd")
  con <- file(path, "wb")
  writeBin(charToRaw(enc2utf8(paste0("\ufeff", "# 标题\r\n正文 $x$\r\n"))), con); close(con)
  decoded <- read_rmd(path, "B")
  check(identical(decoded$source, "# 标题\n正文 $x$\n"), "UTF-8 BOM and CRLF normalized")
  check_spans(decoded)
  check(inherits(try(read_rmd(file.path(tmp, "absent.Rmd")), silent = TRUE), "try-error"), "missing file error")
  writeBin(as.raw(c(255L, 254L)), path)
  check(inherits(try(read_rmd(path), silent = TRUE), "try-error"), "invalid UTF-8 rejected")
  writeBin(as.raw(c(97L, 0L, 98L)), path)
  check(inherits(try(read_rmd(path), silent = TRUE), "try-error"), "NUL rejected")
  check(inherits(try(read_rmd(tmp), silent = TRUE), "try-error"), "directory rejected")
}, finally = on.exit_cleanup())
check(inherits(try(parse_rmd_text(NA_character_), silent = TRUE), "try-error"), "missing text rejected")
cat(sprintf("All %d assertions passed.\n", count))
