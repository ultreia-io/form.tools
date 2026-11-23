# Identify the resource archive with the package version being built.
resources_version <- read.dcf("DESCRIPTION", fields = "Version")[[1L]]
resources_archive <- paste0("form.tools-resources-", resources_version, ".zip")

# Locate the survey files supplied by form.model.
example_directory <- system.file("examples", "survey", package = "form.model")
example_files <- file.path(example_directory, c("form.yaml", "form.xlsx", "form-empty.xlsx"))
if (!nzchar(example_directory) || !all(file.exists(example_files)))
  stop("Install form.model with its survey example files.", call. = FALSE)

# Replace generated assets so removed files cannot remain in the site input.
website_assets <- "pkgdown/assets"
unlink(website_assets, recursive = TRUE)
dir.create(website_assets, recursive = TRUE, showWarnings = FALSE)
# Publish the SQL source model and queries with their original directory layout.
if (!file.copy("inst/examples", website_assets, recursive = TRUE, overwrite = TRUE))
  stop("Could not prepare package resource downloads.", call. = FALSE)
website_examples <- file.path(website_assets, "examples", "survey")

# Copy the example files without modifying the installed resources.
if (!all(file.copy(example_files, website_examples, overwrite = TRUE)))
  stop("Could not prepare example downloads.", call. = FALSE)

# Bundle both the packaged SQL example and the shared workbook resources.
zip::zipr(resources_archive, "examples", root = website_assets)

# Copy the licence used by the website footer and maintainer guide.
if (!file.copy("LICENSE", file.path(website_assets, "LICENSE"), overwrite = TRUE))
  stop("Could not prepare the website licence.", call. = FALSE)
