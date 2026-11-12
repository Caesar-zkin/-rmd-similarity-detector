# Explicit public-source exclusions. Never infer exclusions from shared content.
exclusion_empty_records <- function() data.frame(side = character(), start_line = integer(),
  end_line = integer(), quote = character(), reason = character(), reference = character(), stringsAsFactors = FALSE)

exclusion_line_quote <- function(doc, start_line, end_line) {
  chars <- strsplit(doc$source, "", fixed = TRUE)[[1L]]
  starts <- c(1L, which(chars == "\n") + 1L)
  ends <- c(starts[-1L] - 2L, length(chars))
  for (x in list(start_line, end_line)) if (!is.numeric(x) || length(x) != 1L ||
      is.na(x) || !is.finite(x) || x < 1 || x != floor(x) || x > length(starts))
    stop("Exclusion line number is outside normalized source.")
  if (start_line > end_line) stop("Exclusion start_line exceeds end_line.")
  substr(doc$source, starts[start_line], ends[end_line])
}

make_exclusion_record <- function(doc, side, start_line, end_line, reason, reference) {
  if (!inherits(doc, "rmd_document")) stop("Expected an rmd_document.")
  data.frame(side = side, start_line = as.integer(start_line), end_line = as.integer(end_line),
    quote = exclusion_line_quote(doc, start_line, end_line), reason = reason,
    reference = reference, stringsAsFactors = FALSE)
}

prepare_document_exclusions <- function(documents, exclusions) {
  if (is.character(exclusions)) {
    if (length(exclusions) != 1L || is.na(exclusions) || !file.exists(exclusions) || dir.exists(exclusions))
      stop("Exclusion CSV file does not exist or is a directory.")
    if (file.info(exclusions)$size > 1000000) stop("Exclusion CSV exceeds 1 MB.")
    exclusions <- utils::read.csv(exclusions, stringsAsFactors = FALSE, colClasses = "character",
      fileEncoding = "UTF-8-BOM", check.names = FALSE, na.strings = NULL)
  }
  required <- names(exclusion_empty_records())
  if (!is.data.frame(exclusions) || !all(required %in% names(exclusions)) ||
      !nrow(exclusions) || nrow(exclusions) > 1000L) stop("Expected 1-1000 explicit exclusion records with all required columns.")
  records <- exclusions[, required, drop = FALSE]
  for (name in required) {
    if (is.list(records[[name]]) || anyNA(records[[name]])) stop("Exclusion fields cannot contain missing values or lists.")
    records[[name]] <- enc2utf8(as.character(records[[name]]))
  }
  if (!all(records$side %in% c("A", "B")) || any(!nzchar(trimws(records$reason))) ||
      any(!nzchar(trimws(records$reference)))) stop("Each exclusion needs side A/B, reason, and source reference.")
  for (name in c("start_line", "end_line")) {
    if (!all(grepl("^[1-9][0-9]*$", records[[name]])) || any(as.numeric(records[[name]]) > .Machine$integer.max))
      stop("Exclusion line numbers must be positive integers.")
    records[[name]] <- as.integer(records[[name]])
  }
  records$quote <- gsub("\r\n", "\n", records$quote, fixed = TRUE)
  selected <- list(A = integer(), B = integer()); log <- list()
  comparable_types <- c("text", "math", "code", "inline_r", "inline_code")
  for (i in seq_len(nrow(records))) {
    row <- records[i, ]; doc <- documents[[row$side]]
    if (!inherits(doc, "rmd_document")) stop("Both documents must be readable before exclusion.")
    expected <- exclusion_line_quote(doc, row$start_line, row$end_line)
    if (!identical(row$quote, expected)) stop("Exclusion quote mismatch at record ", i, "; source or line range changed.")
    previous <- which(seq_len(nrow(records)) < i & records$side == row$side)
    if (any(records$start_line[previous] <= row$end_line & records$end_line[previous] >= row$start_line))
      stop("Overlapping exclusion ranges on the same side must be combined explicitly.")
    u <- doc$units
    hit <- which(u$start_line <= row$end_line & u$end_line >= row$start_line)
    partial <- hit[u$start_line[hit] < row$start_line | u$end_line[hit] > row$end_line]
    if (length(partial)) stop("Exclusion cuts a parser unit at record ", i, "; cover the complete unit, lines ",
      u$start_line[partial[1L]], "-", u$end_line[partial[1L]], ".")
    if (!any(u$type[hit] %in% comparable_types)) stop("Exclusion selects no text, formula, or code unit.")
    selected[[row$side]] <- c(selected[[row$side]], hit)
    log[[i]] <- data.frame(record = i, side = row$side, unit_id = u$unit_id[hit],
      original_type = u$type[hit], original_status = u$status[hit], start_line = u$start_line[hit], end_line = u$end_line[hit], stringsAsFactors = FALSE)
  }
  # Validate every record before creating either analysis view.
  .apply_excluded_units(documents, selected, records, do.call(rbind, log))
}

.apply_excluded_units <- function(documents, selected, records, log) {
  # Source/offsets stay intact for reports and sequence boundaries.
  views <- documents
  for (side in c("A", "B")) {
    ids <- unique(selected[[side]])
    views[[side]]$units$type[ids] <- "excluded"
    views[[side]]$units$status[ids] <- "excluded"
    views[[side]]$summary$excluded_units <- length(ids)
    views[[side]]$summary$text_units <- sum(views[[side]]$units$type == "text")
    views[[side]]$summary$math_units <- sum(views[[side]]$units$type == "math")
    views[[side]]$summary$code_units <- sum(views[[side]]$units$type %in% c("code", "inline_r"))
    views[[side]]$summary$limited_units <- sum(views[[side]]$units$status == "limited")
  }
  list(status = "applied", error = "", records = records, units = log, documents = views)
}

prepare_reference_exclusions <- function(documents, path) {
  keys <- function(doc) {
    text <- prepare_text_units(doc)
    math <- prepare_math_units(doc)
    code <- prepare_code_units(doc)
    table <- function(units, key, kind) {
      ok <- units$status == "ok" & !is.na(key) & nzchar(key)
      data.frame(id = units$unit_id[ok], key = paste0(kind, ":", key[ok], recycle0 = TRUE))
    }
    rbind(table(text, text$normalized_text, "text"),
      table(math, vapply(math$details, function(x) if (x$status == "ok") x$normalized_key else NA_character_,
        character(1)), "math"),
      table(code, vapply(code$details, function(x) if (x$parse_status == "ok") x$normalized_key else NA_character_,
        character(1)), "code"))
  }
  reference <- read_rmd(path, file_id = "reference")
  reference_keys <- unique(keys(reference)$key)
  selected <- lapply(documents, function(doc) {
    candidates <- keys(doc)
    which(doc$units$unit_id %in% candidates$id[candidates$key %in% reference_keys])
  })
  reference_name <- basename(path)
  if (!sum(lengths(selected))) return(list(status = "no_matches", error = "",
    records = exclusion_empty_records(), units = data.frame(), documents = documents, reference_name = reference_name))
  records <- list(); log <- list(); offset <- 0L
  for (side in names(documents)) {
    u <- documents[[side]]$units[selected[[side]], , drop = FALSE]
    if (!nrow(u)) next
    log[[side]] <- data.frame(record = offset + seq_len(nrow(u)),
      side = side, unit_id = u$unit_id, original_type = u$type, original_status = u$status,
      start_line = u$start_line, end_line = u$end_line, stringsAsFactors = FALSE)
    records[[side]] <- data.frame(side = side, start_line = u$start_line, end_line = u$end_line,
      quote = u$raw, reason = "与公共参考的完整单元一致", reference = reference_name, stringsAsFactors = FALSE)
    offset <- offset + nrow(u)
  }
  result <- .apply_excluded_units(documents, selected, do.call(rbind, records), do.call(rbind, log))
  result$reference_name <- reference_name
  result
}
