source("R/parser.R", encoding = "UTF-8")
source("R/code.R", encoding = "UTF-8")
count <- 0L
check <- function(ok, label) {
  if (!isTRUE(ok)) stop(label)
  count <<- count + 1L; cat("PASS", label, "\n")
}
fails <- function(expr, label) check(inherits(try(force(expr), silent = TRUE), "try-error"), label)
doc <- function(code, id = "document", language = "r") parse_rmd_text(
  paste0("```{", language, "}\n", code, "\n```"), file_id = id)
compare <- function(a, b) compare_code_pair(doc(a, "A"), doc(b, "B"))
a <- "values <- c(1, 2, 3)\ncenter <- mean(values)\nprint(center)"
b <- "nums<-c(1,2,3)\navg<-mean(nums)\nprint(avg)"
x <- tokenize_r_code(a)
check(x$status == "ok" && x$parse_status == "ok", "complete R code parsed")
check(identical(x$variable_map$name, c("values", "center")), "simple local assignment candidates")
r <- compare(a, b)
check(r$status == "ok" && nrow(r$matches) == 1L, "renamed code match")
check(r$matches$renamed_equal && !r$matches$tokens_equal && !r$matches$raw_equal, "three comparison layers separated")
check(identical(r$matches$variable_map[[1L]], data.frame(a = c("values", "center"), b = c("nums", "avg"))), "explicit consistent variable map")
same <- compare(a, a)
check(same$matches$raw_equal && same$matches$tokens_equal && same$matches$renamed_equal, "identical code layers")
formatted <- compare("x<-c(1,2)\ny<-sum(x)", "x <- c( 1 , 2 ); y <- sum( x )")
check(nrow(formatted$matches) == 1L && formatted$matches$tokens_equal, "spaces and statement separators")
different_boundary <- compare("x <- 1\n-y", "x <- 1 - y")
check(nrow(different_boundary$matches) == 0L, "newline-sensitive expression structure retained")
comments <- compare("x<-1 # first\nprint(x)", "x <- 1 # second\nprint(x)")
check(comments$matches$tokens_equal && nrow(comments$comment_matches) == 0L, "comments excluded from code key")
same_comment <- compare("x<-1 # explanation", "y<-2 # explanation")
check(nrow(same_comment$matches) == 0L && same_comment$comment_matches$comment_count == 1L, "comment match supplementary only")
only_comment <- compare("# explanation", "# explanation")
check(nrow(only_comment$matches) == 0L && nrow(only_comment$comment_matches) == 1L, "comment-only block is not code evidence")
check(only_comment$status == "insufficient_content", "comment-only status")
for (pair in list(
  c("x<-mean(c(1,2))", "a<-sum(c(1,2))"),
  c("x<-1", "a<-2"),
  c("x<-1L", "a<-1"),
  c("x<-'data.csv'", "a<-'other.csv'"),
  c("x<-incoming+1", "a<-different+1"),
  c("x<-1\ny<-x+x", "a<-1\nb<-a+b"),
  c("x<-1\ny<-x+2", "a<-1\nb<-a-2"),
  c("x<-c(1,2)\ny<-mean(x, trim=0)", "a<-c(1,2)\nb<-mean(a, other=0)")
)) check(nrow(compare(pair[1L], pair[2L])$matches) == 0L, "function constants names and reference relations preserved")
member_a <- "x<-1\nframe<-data.frame(x=2)\nans<-frame$x+x"
member_b <- "v<-1\ntable<-data.frame(x=2)\nout<-table$x+v"
check(compare(member_a, member_b)$matches$renamed_equal, "local objects renamed while member and argument names stay literal")
check(nrow(compare(member_a, gsub("table$x", "table$y", member_b, fixed = TRUE))$matches) == 0L, "member name change retained")
check(nrow(compare("data$x<-1", "data$y<-1")$matches) == 0L, "member assignment not treated as simple variable definition")
check(nrow(compare("x<-x+1", "a<-a+1")$matches) == 0L, "self-dependent initialization retained literally")
check(nrow(compare("print(x)\nx<-1", "print(a)\na<-1")$matches) == 0L, "read before initialization retained literally")
check(nrow(compare("mean(x)", "mean(y)")$matches) == 0L, "external input identifiers not renamed")
for (code in c("f<-function(x) x+1", "for(i in 1:3) print(i)", "if(TRUE) x<-1", "x=1", "x<<-1", "1->x",
    "x<-magic(data)", "x<-get('a')", "x<-y~z", "x<-local({a<-1;a})", "f<-1\n(f)(2)")) {
  parsed <- tokenize_r_code(code)
  check(parsed$parse_status == "ok" && parsed$rename_status == "restricted", "complex scope or call preserves names")
  check(is.na(parsed$renamed_key) && !is.na(parsed$normalized_key), "restricted renaming keeps lexical analysis")
}
scope_same <- compare("f<-function(x) x+1", "f <- function(x) x + 1")
check(scope_same$matches$tokens_equal && !scope_same$matches$renamed_equal && scope_same$status == "limited", "complex code still compared lexically")
stop_code <- tokenize_r_code("stop('must not execute')")
check(stop_code$parse_status == "ok", "stop call parsed without evaluation")
path <- tempfile("rmd-code-no-eval-", fileext = ".txt")
invisible(tokenize_r_code(paste0("writeLines('must not execute', ", encodeString(path, quote = "\""), ")")))
check(!file.exists(path), "submitted file write never executed")
check(tokenize_r_code("library(package_that_does_not_exist)")$parse_status == "ok", "submitted package load never executed")
directive <- tokenize_r_code("#line 1 'file_that_must_not_be_read.R'\nx<-1")
check(directive$status == "limited" && is.na(directive$normalized_key), "source location directive not interpreted")
check(tokenize_r_code("x <- '#line 1 file'")$parse_status == "ok", "directive-like string is literal")
for (code in c("x<-", "mean(", "x<-'unfinished")) {
  broken <- tokenize_r_code(code)
  check(broken$status == "limited" && broken$parse_status == "error", "incomplete R syntax diagnosed")
  check(is.na(broken$normalized_key) && is.na(broken$renamed_key), "no high-level claim for parse failure")
}
broken_pair <- compare("x<-", "x<-")
check(broken_pair$status == "limited" && broken_pair$matches$raw_equal && !broken_pair$matches$tokens_equal, "broken source retained for raw comparison")
for (code in c("x\t<-\t1\nprint(x)", "均值 <- mean(c(1,2))", "x <- '中文🙂'\nprint(x)",
    "x <- r\"(a#b)\"", paste0("x <- '", paste0(rep("a", 1200L), collapse = ""), "'"), "x <- '# not a comment'")) {
  parsed <- tokenize_r_code(code)
  check(parsed$parse_status == "ok", "Unicode tabs raw strings and long strings")
  recovered <- substring(parsed$source, parsed$tokens$start_offset, parsed$tokens$end_offset)
  check(identical(unname(recovered), parsed$tokens$text), "all token source spans reconstruct exactly")
}
mapped_doc <- parse_rmd_text("# 标题\n\n```{r}\nx <- 1\nprint(x)\n```", file_id = "A")
mapped <- prepare_code_units(mapped_doc)
check(mapped$details[[1L]]$tokens$start_line[1L] == 4L, "global code line mapping")
tokens <- mapped$details[[1L]]$tokens
check(identical(substring(mapped_doc$source, tokens$start_offset, tokens$end_offset), tokens$text), "global token source spans")
inline <- prepare_code_units(parse_rmd_text("正文 `r mean(c(1,2))` 与 `fit`。"))
check(nrow(inline) == 1L && inline$type == "inline_r" && inline$code_status == "ok", "only executable inline R selected")
non_r <- compare_code_pair(doc("print('a')", language = "python"), doc("print('a')", language = "python"))
check(non_r$status == "limited" && non_r$matches$raw_equal && !non_r$matches$tokens_equal, "non-R raw-only limited comparison")
unclosed <- parse_rmd_text("```{r}\nx<-1")
limited <- compare_code_pair(unclosed, unclosed)
check(limited$status == "limited" && !limited$matches$tokens_equal, "parser limitation propagated")
empty <- compare_code_pair(parse_rmd_text("只有正文 $x$"), doc(a))
check(empty$status == "not_applicable" && nrow(empty$matches) == 0L, "no code status")
check(identical(names(empty$matches), names(r$matches)), "stable empty match schema")
check(nrow(prepare_code_units(parse_rmd_text("`fit`"))) == 0L, "ordinary inline code excluded")
original <- mapped_doc; invisible(compare_code_pair(mapped_doc, mapped_doc))
check(identical(mapped_doc, original), "parser input not modified")
for (bad in list(NA_character_, 2, c("x", "y"))) fails(tokenize_r_code(bad), "invalid code input")
for (name in c("max_chars", "max_tokens", "max_nodes")) for (bad in list(0, -1, 1.5, Inf, NA_real_, "2")) {
  args <- list(code = "x<-1"); args[[name]] <- bad
  fails(do.call(tokenize_r_code, args), paste("invalid", name))
}
fails(tokenize_r_code("x<-1", max_chars = 2L), "code character limit")
fails(tokenize_r_code("x<-1", max_tokens = 1L), "code token limit")
fails(tokenize_r_code("x<-1", max_nodes = 1L), "code node limit")
two <- parse_rmd_text("```{r}\nx<-1\n```\n\n```{r}\ny<-2\n```")
fails(prepare_code_units(two, max_units = 1L), "code unit limit")
fails(prepare_code_units(two, max_total_chars = 1L), "total code size limit")
fails(compare_code_pair(two, two, max_pairs = 1L), "code pair limit")
fails(compare_code_pair(two, two, max_pair_chars = 1L), "code pair work limit")
fails(prepare_code_units("bad"), "invalid document")
cat("All", count, "code-foundation assertions passed.\n")
