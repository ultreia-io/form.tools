# Maintainer guide

`develop` is the integration branch. `main` contains releases. Implementation branches use `feature/`.

## Code organization

The files organize functions in one package namespace. You do not source each file separately.

| File                   | Responsibility                                                          |
| ---------------------- | ----------------------------------------------------------------------- |
| `split.R`              | Select related records and publish split workbooks.                     |
| `read.R`               | Load model tables through SQL files and a supplied backend.             |
| `write.R`              | Encode typed data and write forms using model-defined field names.      |
| `workbook.R`           | Read XLSX parts and populate templates while preserving workbook parts. |
| `form.tools-package.R` | Provide package-level documentation.                                    |

Workbook operations consume `form.model` through its public API.
`xml2` reads and writes worksheet XML; `zip` assembles output XLSX archives.

`read_form_tables()` selects SQL files using the form model and checks the returned columns.

`sql_table_loader()` delegates query execution and parameter binding to `db.tools`.

The SQL example and integration tests use in-memory SQLite databases through `RSQLite`.

## Local verification

Run from the package root with development dependencies and LaTeX installed:

```sh
# Generate documentation, run all checks and build the website.
Rscript tools/check.R
```

This generates documentation, runs tests, builds and checks the archive with `--as-cran`, then builds the website.

Local and CI checks share the CRAN mirror settings in `tools/check.Renviron`.

Local verification and CI run `R CMD check --as-cran`, including CRAN incoming checks.

CI skips remote incoming checks while `db.tools` comes from GitHub and the new article URLs await deployment.

**Build** runs one Linux R-release job for development pushes and ordinary PRs.

It measures coverage with `covr` and uploads it to Codecov.

Run **Actions → Check All Platforms** for Linux with R release and R-devel, macOS, and Windows.

The README coverage badges link to the Codecov report. Website builds do not run coverage checks.

Archives and check output stay in `build/`.

`roxygen2`, `rcmdcheck`, and `pkgload` are development tools, not runtime dependencies.

Review coverage gaps for missing behaviour. Check installed resources, runnable examples, and website navigation.

## Website

Website builds use `pkgdown`, `RSQLite` and `zip`, declared in `Config/Needs/website`.

Run from the package root with website dependencies installed:

``` r
# Prepare example downloads and the licence from their source files.
source("tools/prepare-site-assets.R")
# Build the website with pkgdown.
pkgdown::build_site()
```

The preparation replaces ignored `pkgdown/assets/` copies; the survey files remain in `form.model`'s `inst/examples/`.

Source-model and SQL examples are tracked in this package's `inst/examples/survey/` directory.

The Package resources article links every file and the `form.tools-resources-<version>.zip` archive.

The ZIP combines both packages' example files under `examples/survey/`.

## GitHub Release

1. **Prepare the release on `develop`:**

   1. **Prepare the release files:** update the version in `DESCRIPTION`, finalize `NEWS.md`, `cran-comments.md` and documentation.
   2. **Perform the [local checks](#local-verification).**
   3. **Commit the changes:** use `[form.tools] Release <version>`.
   4. **Push the release commit.**

2. **Start the release on GitHub:**

   1. Open **Actions → Start Release**.
   2. Click **Run workflow**, select `develop`, then click **Run workflow** to confirm.
   3. The workflow checks the selected commit on all four environments and saves the checked Linux archive.
   4. After all four checks pass, it opens the release PR at the checked commit.

3. **Merge the release PR:**

   1. Review the release PR and merge it. Its checks already passed in **Start Release**.
   2. Merging starts **Publish Release**, which verifies that the merged files match the checked candidate.

**Publish Release** publishes the checked archive and checksum, then deploys the documentation.

If the merge changes the checked files, update `develop` and rerun **Start Release** before merging a new PR.

### Enable CRAN submission

The **Submit to CRAN** job is skipped by default. Enable it when the package's required dependencies are on CRAN.

1. Open the repository's **Settings → Secrets and variables → Actions → Variables**.
2. Click **New repository variable** and set `SUBMIT_TO_CRAN` to `true`.

To disable submission, remove the variable or set it to `false`.

## Manual CRAN submission

Use this fallback only if the release has not already been submitted by CI.

Start from a clean working tree. Replace `version` with the release version to submit.

```sh
# Fetch the published release tags.
git fetch origin --tags
# Check out the release tag.
git switch --detach version
```

Run these commands in R from the package root, with `devtools` installed.

```r
# Build and run R CMD check --as-cran, including the PDF manual and incoming checks.
devtools::check(args = "--as-cran", manual = TRUE, remote = TRUE, error_on = "warning")

# After resolving errors and warnings and reviewing NOTES, submit the release to CRAN.
devtools::submit_cran()
```

This manual route rebuilds from the release tag. CI submits the existing GitHub archive unchanged.

Confirm CRAN's email, then wait for its checks and response.

## License

LGPL-2.1. See [LICENSE](LICENSE).
