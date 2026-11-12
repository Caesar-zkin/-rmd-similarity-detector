main <- function() {
  packages <- c("rmarkdown", "shiny")
  missing <- packages[!vapply(packages, requireNamespace, logical(1), quietly = TRUE)]
  if (length(missing))
    stop("Missing R packages: ", paste(missing, collapse = ", "),
      ". Install them in R before launching the detector.", call. = FALSE)

  if (!rmarkdown::pandoc_available()) {
    candidates <- file.path(Sys.getenv("ProgramFiles"), "RStudio",
      c("resources/app/bin/quarto/bin/tools", "bin/pandoc"))
    found <- candidates[file.exists(file.path(candidates, "pandoc.exe"))]
    if (length(found)) Sys.setenv(RSTUDIO_PANDOC = found[1L])
  }
  if (!rmarkdown::pandoc_available())
    stop("Pandoc was not found. Install Pandoc or RStudio, or set RSTUDIO_PANDOC.", call. = FALSE)

  rmarkdown::run("detector.Rmd", auto_reload = FALSE,
    shiny_args = list(host = "127.0.0.1", launch.browser = TRUE))
}

main()
