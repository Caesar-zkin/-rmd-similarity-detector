source("R/parser.R", encoding = "UTF-8")
source("R/math.R", encoding = "UTF-8")
source("R/math-sequences.R", encoding = "UTF-8")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L; cat("PASS", label, "\n")
}
fails <- function(expr, label) check(inherits(try(force(expr), silent = TRUE), "try-error"), label)
env <- function(name, rows, display = FALSE) {
  text <- paste0("\\begin{", name, "}\n", paste(rows, collapse = " \\\\\n"), "\n\\end{", name, "}")
  if (display) paste0("$$\n", text, "\n$$") else text
}
doc <- function(x, id = "document") parse_rmd_text(x, file_id = id)
a <- doc(paste0("# 标题\n\n", env("align", c("x &= y", "y &= z", "z &= 1"))), "A")
b <- doc(env("aligned", c("a &= b", "7 &= 8", "b &= c", "c &= 1"), TRUE), "B")
steps <- prepare_math_steps(a)
check(nrow(steps) == 3L && all(steps$math_status == "ok"), "bare align split into three supported steps")
check(identical(steps$normalized, c("x=y", "y=z", "z=1")), "alignment markers removed")
check(identical(steps$start_line, c(4L, 5L, 6L)), "multiline source start lines")
check(identical(steps$end_line, c(4L, 5L, 6L)), "multiline source end lines")
check(length(unique(steps$parent_unit_id)) == 1L && length(unique(steps$unit_id)) == 3L, "unique steps share parent")
check(identical(steps$step_index, 1:3), "step indices")
check(all(steps$environment == "align"), "environment recorded")
check(identical(steps$content, c("x &= y", "y &= z", "z &= 1")), "raw row content retained")
check(identical(steps$details[[1L]]$source_positions[[2L]], 24L), "equal sign original source position")
crlf <- prepare_math_steps(doc(gsub("\n", "\r\n", a$source, fixed = TRUE)))
check(identical(crlf$start_line, steps$start_line), "CRLF normalized line positions")
check(identical(crlf$details[[1L]]$source_positions, steps$details[[1L]]$source_positions), "CRLF normalized token positions")
for (i in seq_len(nrow(steps))) {
  raw <- substring(a$source, steps$content_start[i], steps$content_end[i])
  check(identical(raw, steps$content[i]), "continuous raw row span")
  detail <- steps$details[[i]]
  recovered <- vapply(detail$source_positions, function(p) paste0(substring(a$source, p, p), collapse = ""), character(1))
  check(identical(recovered, detail$tokens), "row token source reconstruction")
  pos <- steps$comparison_positions[[i]]
  check(identical(paste0(substring(a$source, pos, pos), collapse = ""), steps$comparison_content[i]), "comparison source reconstruction")
}
r <- find_math_sequences(a, b, min_steps = 3L)
check(r$status == "ok" && nrow(r$matches) == 1L, "bare align matches display aligned")
check(r$matches$matched_steps == 3L && r$matches$skipped_steps == 1L, "multiline insertion")
check(r$matches$step_similarity == 0.75, "multiline step ratio")
check(identical(r$matches$variable_map[[1L]], data.frame(a = c("x", "y", "z"), b = c("a", "b", "c"))), "mapping across multiline rows")
check(length(r$matches$skipped_units_b[[1L]]) == 1L, "skipped multiline row ID")
check(r$formulas_b$content[match(r$matches$skipped_units_b[[1L]], r$formulas_b$unit_id)] == "7 &= 8", "skipped row lookup")
check(all(r$matches$step_pairs[[1L]]$parent_unit_id_a == steps$parent_unit_id[1L]), "pair parent traceability")
separate <- doc("$a=b$\n\n$b=c$\n\n$c=1$")
cross <- find_math_sequences(a, separate, min_steps = 3L)
check(cross$matches$matched_steps == 3L && cross$matches$skipped_steps == 0L, "multiline to separately delimited formulas")
for (name in c("align", "align*", "aligned", "gather", "gather*", "gathered")) {
  wrapped <- name %in% c("aligned", "gathered")
  text <- env(name, if (startsWith(name, "align")) c("x&=y", "y&=1") else c("x=y", "y=1"), wrapped)
  prepared <- prepare_math_steps(doc(text))
  check(nrow(prepared) == 2L && all(prepared$math_status == "ok"), paste("supported environment", name))
}
nested <- doc(env("equation", env("aligned", c("x&=y", "y&=1"))))
check(nrow(prepare_math_steps(nested)) == 2L && all(prepare_math_steps(nested)$math_status == "ok"), "aligned inside equation")
display_nested <- doc(paste0("$$", env("equation*", env("gathered", c("x=y", "y=1"))), "$$"))
check(nrow(prepare_math_steps(display_nested)) == 2L, "equation wrapper inside display")
equation <- prepare_math_steps(doc(env("equation", "x=1")))
check(nrow(equation) == 1L && equation$math_status == "ok", "single equation row")
inline_rows <- prepare_math_steps(doc("$$\\begin{aligned}x&=y\\\\y&=1\\end{aligned}$$"))
check(nrow(inline_rows) == 2L && all(inline_rows$start_line == 1L), "multiple rows on one source line")
check(inline_rows$start_column[2L] > inline_rows$end_column[1L], "same-line row column positions")
alias <- prepare_math_steps(doc(env("align", c("x&=\\dfrac{y}{2}", "y&=1"))))
alias_detail <- alias$details[[1L]]
alias_positions <- alias_detail$source_positions[[match("\\frac", alias_detail$tokens)]]
alias_doc <- doc(env("align", c("x&=\\dfrac{y}{2}", "y&=1")))
check(paste0(substring(alias_doc$source, alias_positions, alias_positions), collapse = "") == "\\dfrac", "fraction alias keeps original command range")
spacing <- doc("\\begin{align}\nx&=y\\\\*[2pt]\ny&=1\\nonumber\\\\\n\\end{align}")
spaced <- prepare_math_steps(spacing)
check(nrow(spaced) == 2L && all(spaced$math_status == "ok"), "spacing star numbering and trailing row break")
check(identical(spaced$normalized, c("x=y", "y=1")), "numbering control removed")
notag <- prepare_math_steps(doc(env("align", c("x&=y\\notag", "y&=1"))))
check(all(notag$math_status == "ok") && notag$normalized[1L] == "x=y", "notag supported")
protected <- prepare_math_steps(doc(env("align", c("x&=\\text{a\\\\b & c}", "y&=1"))))
check(nrow(protected) == 2L && all(protected$math_status == "ok"), "text group row break and ampersand protected")
check(grepl("a\\\\b & c", protected$normalized[1L], fixed = TRUE), "text payload preserved literally")
escaped <- prepare_math_steps(doc(env("align", c("x&=\\&", "y&=1"))))
check(escaped$math_status[1L] == "ok" && escaped$normalized[1L] == "x=\\&", "escaped ampersand retained")
control_space <- prepare_math_steps(doc("$$x\\ $$"))
check(control_space$math_status == "ok" && control_space$normalized == "x", "trailing escaped space is normalized intact")
aligned_space <- prepare_math_steps(doc(env("align", c("x&=y\\ ", "y&=1"))))
check(all(aligned_space$math_status == "ok") && aligned_space$normalized[1L] == "x=y", "escaped space before row separator")
changed <- doc(env("align", c("a&=b", "c&=d", "d&=1")))
check(nrow(find_math_sequences(a, changed, min_steps = 3L)$matches) == 0L, "inconsistent multiline mapping rejected")
for (text in c(
  env("align", c("x&=y&z", "y&=1")),
  env("gather", c("x&=y", "y=1")),
  env("align", c("x&=\\mystery{y}", "y&=1")),
  env("align", c("x&=y\\label{eq:a}", "y&=1")),
  env("align", c("x&=y", "\\intertext{说明}", "y&=1")),
  env("align", c("x&=y", "", "y&=1")),
  env("align", c("x&=y", "\\notag", "y&=1")),
  env("align", c("x&=y", env("matrix", "a&b"))),
  env("multline", c("x+y", "=z")),
  "$$x=y\\\\y=1$$",
  "$$\\begin{aligned}x&=y\\\\y&=1$$",
  "\\begin{align}x&={y\\\\y&=1\\end{align}",
  "\\begin{align}x&=y\\\\[\\jot]y&=1\\end{align}"
)) {
  prepared <- prepare_math_steps(doc(text))
  check(nrow(prepared) > 0L && all(prepared$math_status == "limited"), "unsupported parent remains limited")
  check(all(vapply(prepared$details, function(d) is.na(d$structure_key), logical(1))), "limited parent has no structural key")
}
unknown_between <- doc(env("align", c("a&=b", "\\mystery{q}", "b&=c", "c&=1")))
check(nrow(find_math_sequences(a, unknown_between, min_steps = 3L, max_skips = 2L)$matches) == 0L, "unknown multiline row is a barrier")
one <- prepare_math_steps(doc("说明 $x+y$。"))
check(one$unit_id == one$parent_unit_id && one$normalized == "x+y", "ordinary formula compatible")
original <- a; invisible(prepare_math_steps(a))
check(identical(a, original), "parser document untouched")
empty <- prepare_math_steps(doc("正文"))
check(nrow(empty) == 0L && identical(names(empty), names(steps)), "empty step schema")
code <- doc("```{r}\nstop('never run')\nx <- '\\begin{align}a&=b\\end{align}'\n```")
check(nrow(prepare_math_steps(code)) == 0L, "code not split or executed")
check(find_math_sequences(a, code)$status == "not_applicable", "absent formula side")
fails(prepare_math_steps(a, max_steps = 2L), "expanded step limit")
fails(find_math_sequences(a, b, max_formulas = 2L), "sequence expanded formula limit")
fails(find_math_sequences(a, b, max_pairs = 3L), "expanded pair limit")
for (bad in list(0, -1, 1.5, Inf, NA_real_, "3")) fails(prepare_math_steps(a, bad), "invalid expanded step limit")
fails(prepare_math_steps("bad"), "invalid document")
cat("All", count, "multiline-formula assertions passed.\n")
