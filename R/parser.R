# Rmd structural parser. Base R only; never evaluates input or YAML.

rmd_empty_units <- function() {
  data.frame(unit_id = character(), file_id = character(), type = character(),
    context_id = character(), section = character(), language = character(),
    start_offset = integer(), end_offset = integer(), start_line = integer(),
    start_column = integer(), end_line = integer(), end_column = integer(),
    content_start = integer(), content_end = integer(), raw = character(),
    content = character(), status = character(), stringsAsFactors = FALSE)
}

rmd_empty_diagnostics <- function() {
  data.frame(code = character(), severity = character(), line = integer(),
    column = integer(), message = character(), stringsAsFactors = FALSE)
}

parse_rmd_text <- function(text, file_id = "document") {
  if (!is.character(text) || length(text) != 1L || is.na(text))
    stop("text must be one non-missing character string.")
  if (!is.character(file_id) || length(file_id) != 1L || is.na(file_id) || !nzchar(file_id))
    stop("file_id must be one non-empty string.")
  # All positions refer to this normalized source, not to original bytes.
  source <- gsub("\r\n?", "\n", enc2utf8(text), perl = TRUE)
  source <- sub("^\ufeff", "", source)
  n <- nchar(source, type = "chars")
  chars <- if (n) strsplit(source, "", fixed = TRUE)[[1L]] else character()
  line_starts <- c(1L, which(chars == "\n") + 1L)
  units <- list(); diagnostics <- list(); context <- 0L; section <- ""
  cut <- function(a, b) if (a > b || a > n || b < 1L) "" else substr(source, a, b)
  pos <- function(k) {
    li <- findInterval(k, line_starts)
    c(as.integer(li), as.integer(k - line_starts[li] + 1L))
  }
  add_diag <- function(code, at, message, severity = "warning") {
    p <- pos(at)
    diagnostics[[length(diagnostics) + 1L]] <<- data.frame(code = code,
      severity = severity, line = p[1L], column = p[2L], message = message,
      stringsAsFactors = FALSE)
  }
  new_context <- function() { context <<- context + 1L }
  emit <- function(type, a, b, ca = a, cb = b, language = "", status = "ok") {
    if (a > b) return(invisible(NULL))
    p <- pos(a); q <- pos(b)
    units[[length(units) + 1L]] <<- data.frame(
      unit_id = sprintf("u%05d", length(units) + 1L), file_id = file_id,
      type = type, context_id = sprintf("p%05d", context), section = section,
      language = language, start_offset = as.integer(a), end_offset = as.integer(b),
      start_line = p[1L], start_column = p[2L], end_line = q[1L], end_column = q[2L],
      content_start = as.integer(ca), content_end = as.integer(cb), raw = cut(a, b),
      content = cut(ca, cb), status = status, stringsAsFactors = FALSE)
  }
  starts <- function(at, token) identical(cut(at, at + nchar(token) - 1L), token)
  escaped <- function(at) {
    j <- at - 1L; count <- 0L
    while (j >= 1L && chars[j] == "\\") { count <- count + 1L; j <- j - 1L }
    count %% 2L == 1L
  }
  run_length <- function(at, ch) {
    j <- at
    while (j <= n && chars[j] == ch) j <- j + 1L
    j - at
  }
  line_end <- function(at) {
    li <- findInterval(at, line_starts)
    if (li < length(line_starts)) line_starts[li + 1L] - 2L else n
  }
  after_line <- function(end) min(end + 2L, n + 1L)
  find_close <- function(from, token, limit = n, exact_backticks = FALSE) {
    j <- from; size <- nchar(token)
    while (j + size - 1L <= limit) {
      if (starts(j, token) && (exact_backticks || !escaped(j))) {
        if (!exact_backticks ||
            (run_length(j, "`") == size && (j == 1L || chars[j - 1L] != "`")))
          return(j)
      }
      j <- j + 1L
    }
    NA_integer_
  }
  # Inline link/image destinations use balanced parentheses; no external reads.
  link_end <- function(at, limit) {
    label_start <- at + if (starts(at, "![")) 2L else 1L
    j <- label_start
    while (j <= limit && !(chars[j] == "]" && !escaped(j))) j <- j + 1L
    if (j > limit || !starts(j + 1L, "(")) return(NULL)
    depth <- 1L; k <- j + 2L
    while (k <= limit) {
      if (!escaped(k)) {
        if (chars[k] == "(") depth <- depth + 1L
        if (chars[k] == ")") depth <- depth - 1L
        if (depth == 0L) return(c(k, label_start, j - 1L))
      }
      k <- k + 1L
    }
    NULL
  }
  i <- 1L; pending <- NA_integer_
  flush <- function(before) {
    if (!is.na(pending)) {
      kind <- if (nzchar(trimws(cut(pending, before - 1L)))) "text" else "blank"
      emit(kind, pending, before - 1L)
      pending <<- NA_integer_
    }
  }
  while (i <= n) {
    at_line_start <- i == 1L || chars[i - 1L] == "\n"
    end <- line_end(i)
    line <- cut(i, end)
    if (at_line_start) {
      # Header recognized only at the beginning, never interpreted as YAML.
      if (i == 1L && grepl("^---[ \t]*$", line)) {
        flush(i); new_context(); j <- after_line(end); closing <- NA_integer_
        while (j <= n) {
          e <- line_end(j)
          if (grepl("^(---|\\.\\.\\.)[ \t]*$", cut(j, e))) { closing <- j; break }
          j <- after_line(e)
        }
        if (is.na(closing)) {
          emit("yaml", i, n, after_line(end), n, status = "limited")
          add_diag("unclosed_yaml", i, "YAML header is not closed; remaining source retained as limited YAML.")
          i <- n + 1L
        } else {
          e <- line_end(closing)
          emit("yaml", i, e, after_line(end), closing - 2L)
          i <- e + 1L
        }
        new_context(); next
      }
      fence <- regexec("^ {0,3}(`{3,}|~{3,})(.*)$", line, perl = TRUE)
      hit <- regmatches(line, fence)[[1L]]
      if (length(hit)) {
        flush(i); new_context(); marker <- substr(hit[2L], 1L, 1L)
        width <- nchar(hit[2L]); info <- trimws(hit[3L])
        language <- if (grepl("^\\{[A-Za-z][A-Za-z0-9_+-]*", info)) {
          sub("^\\{([A-Za-z][A-Za-z0-9_+-]*).*", "\\1", info)
        } else if (grepl("^[A-Za-z][A-Za-z0-9_+-]*", info)) {
          sub("^([A-Za-z][A-Za-z0-9_+-]*).*", "\\1", info)
        } else ""
        j <- after_line(end); closing <- NA_integer_
        pattern <- paste0("^ {0,3}", marker, "{", width, ",}[ \t]*$")
        while (j <= n) {
          e <- line_end(j)
          if (grepl(pattern, cut(j, e), perl = TRUE)) { closing <- j; break }
          j <- after_line(e)
        }
        status <- if (is.na(closing)) "limited" else "ok"
        if (is.na(closing)) {
          emit("code", i, n, after_line(end), n, language, status)
          add_diag("unclosed_fence", i, "Code fence not closed; remaining source retained as code.")
          i <- n + 1L
        } else {
          e <- line_end(closing)
          emit("code", i, e, after_line(end), closing - 2L, language, status)
          i <- e + 1L
        }
        if (tolower(language) != "r") add_diag("code_language_limited", units[[length(units)]]$start_offset,
          "Unlabelled or non-R code retained; later stages may only compare text.", "info")
        new_context(); next
      }
      if (grepl("^ {0,3}#{1,6}([ \t]+|$)", line, perl = TRUE)) {
        flush(i); new_context()
        section <- trimws(sub("[ \t]+#+[ \t]*$", "", sub("^ {0,3}#{1,6}[ \t]*", "", line)))
        emit("heading", i, end); i <- end + 1L; new_context(); next
      }
      if (grepl("^[ \t]*$", line)) {
        flush(i)
        b <- if (end < n) end + 1L else end
        emit("blank", i, b); i <- b + 1L; new_context(); next
      }
      if (grepl("^( {4}|\t)", line))
        add_diag("indentation_ambiguous", i, "Indented Markdown blocks are retained as text; use fenced code for reliable classification.")
    }
    if (starts(i, "<!--") && !escaped(i)) {
      flush(i); close <- find_close(i + 4L, "-->")
      b <- if (is.na(close)) n else close + 2L
      emit("unsupported", i, b, status = "limited")
      add_diag("html_comment", i, "HTML comment retained but excluded from comparable content.", "info")
      if (is.na(close)) add_diag("unclosed_html_comment", i, "HTML comment is not closed.")
      i <- b + 1L; next
    }
    if (chars[i] == "<" && !escaped(i) && grepl("^</?[A-Za-z]", cut(i, min(n, i + 20L)))) {
      flush(i)
      # Keep script/style bodies out of prose, even when they span lines.
      tag <- regmatches(cut(i, n), regexpr("^<(script|style)([[:space:]>])", cut(i, n), ignore.case = TRUE))
      b <- end
      if (length(tag) && nzchar(tag)) {
        name <- sub("^<([A-Za-z]+).*", "\\1", tolower(tag))
        rest <- cut(i + nchar(tag), n)
        closing <- regexpr(paste0("</", name, "[ \t]*>"), rest, ignore.case = TRUE)
        b <- if (closing[1L] < 0L) n else i + nchar(tag) + closing[1L] + attr(closing, "match.length") - 2L
      }
      emit("unsupported", i, b, status = "limited")
      add_diag("raw_html", i, "Raw HTML line retained; embedded content is not structurally analysed.")
      i <- b + 1L; next
    }
    if (!escaped(i) && (starts(i, "![") || chars[i] == "[")) {
      lk <- link_end(i, end)
      if (!is.null(lk)) {
        flush(i); image <- starts(i, "![")
        emit(if (image) "unsupported" else "text", i, lk[1L], lk[2L], lk[3L],
          status = if (image) "limited" else "ok")
        if (image) add_diag("image_not_read", i, "Image reference recorded; image content is not read.")
        i <- lk[1L] + 1L; next
      }
      if (starts(i, "![")) add_diag("image_syntax_limited", i,
        "Reference-style or complex image syntax is not extracted; retained as text.")
    }
    if (chars[i] == "`" && !escaped(i)) {
      flush(i); size <- run_length(i, "`"); token <- strrep("`", size)
      close <- find_close(i + size, token, end, TRUE)
      if (is.na(close)) {
        emit("unsupported", i, end, status = "limited")
        add_diag("unclosed_inline_code", i, "Inline code is not closed on this line; retained without evaluation.")
        i <- end + 1L
      } else {
        a <- i + size; b <- close - 1L; body <- cut(a, b)
        is_r <- grepl("^r[ \t]+", body)
        if (is_r) a <- a + nchar(regmatches(body, regexpr("^r[ \t]+", body)))
        emit(if (is_r) "inline_r" else "inline_code", i, close + size - 1L, a, b,
          language = if (is_r) "r" else "")
        i <- close + size
      }
      next
    }
    opener <- ""; closer <- ""; display <- FALSE
    if (!escaped(i)) {
      if (starts(i, "$$")) { opener <- "$$"; closer <- "$$"; display <- TRUE
      } else if (chars[i] == "$" && i < n && !grepl("[[:space:]]", chars[i + 1L])) {
        opener <- "$"; closer <- "$"
      } else if (starts(i, "\\(")) { opener <- "\\("; closer <- "\\)"
      } else if (starts(i, "\\[")) { opener <- "\\["; closer <- "\\]"; display <- TRUE
      } else if (starts(i, "\\begin{")) {
        env <- regmatches(cut(i, n), regexpr("^\\\\begin\\{[A-Za-z*]+\\}", cut(i, n)))
        if (length(env) && nzchar(env)) {
          name <- sub("^\\\\begin\\{([^}]+)\\}$", "\\1", env)
          if (name %in% c("equation", "equation*", "align", "align*", "gather", "gather*", "multline", "multline*")) {
            opener <- env; closer <- paste0("\\end{", name, "}"); display <- TRUE
          } else add_diag("latex_environment_limited", i, "Unsupported bare LaTeX environment retained as text.")
        }
      }
    }
    if (nzchar(opener)) {
      flush(i)
      close <- find_close(i + nchar(opener), closer, if (display) n else end)
      # A single-dollar closer must not be a display delimiter or follow whitespace.
      if (opener == "$") {
        while (!is.na(close) && (starts(close, "$$") ||
          (close > 1L && chars[close - 1L] == "$") ||
          grepl("[[:space:]]", chars[close - 1L])))
          close <- find_close(close + 1L, closer, end)
      }
      if (is.na(close)) {
        b <- if (display) n else end
        emit("math", i, b, i + nchar(opener), b, status = "limited")
        add_diag("unclosed_math", i, "Math delimiter is not closed within its supported scope; retained as limited math.")
        i <- b + 1L
      } else {
        emit("math", i, close + nchar(closer) - 1L, i + nchar(opener), close - 1L)
        i <- close + nchar(closer)
      }
      next
    }
    if (is.na(pending)) pending <- i
    i <- i + 1L
  }
  flush(n + 1L)
  if (n == 0L) add_diag("empty_document", 1L, "Document is empty.")
  u <- if (length(units)) do.call(rbind, units) else rmd_empty_units()
  d <- if (length(diagnostics)) do.call(rbind, diagnostics) else rmd_empty_diagnostics()
  structure(list(file_id = file_id, source = source, units = u, diagnostics = d,
    summary = list(characters = n, units = nrow(u), limited_units = sum(u$status == "limited"),
      text_units = sum(u$type == "text"), math_units = sum(u$type == "math"),
      code_units = sum(u$type %in% c("code", "inline_r")))), class = "rmd_document")
}

read_rmd <- function(path, file_id = basename(path), encoding = "UTF-8", keep_bytes = FALSE) {
  if (!is.character(path) || length(path) != 1L || is.na(path) || !nzchar(path))
    stop("path must be one non-empty local file path.")
  if (!file.exists(path) || dir.exists(path)) stop("Input file does not exist or is a directory: ", path)
  if (!grepl("\\.rmd$", path, ignore.case = TRUE)) stop("Input must have an .Rmd extension.")
  con <- file(path, "rb"); on.exit(close(con))
  bytes <- readBin(con, "raw", n = file.info(path)$size)
  if (any(bytes == as.raw(0L))) stop("Input contains NUL bytes; choose a supported text encoding (not UTF-16).")
  raw_text <- rawToChar(bytes)
  text <- iconv(raw_text, from = encoding, to = "UTF-8", sub = NA)
  if (is.na(text)) stop("Input cannot be decoded with encoding=", encoding, "; specify the correct encoding.")
  result <- parse_rmd_text(text, file_id)
  result$encoding <- encoding
  if (keep_bytes) result$input_bytes <- bytes
  result
}
