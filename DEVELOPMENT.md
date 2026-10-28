# Maintainer guide

`develop` is the integration branch. `main` contains releases. Implementation branches use `feature/`.

## Code organization

| Directory    | Responsibility                                    |
| ------------ | ------------------------------------------------- |
| `R/`         | Package documentation and workbook APIs.          |
| `inst/`      | Future installed resources and neutral examples.  |
| `man/`       | Generated roxygen documentation.                  |
| `tests/`     | Split behaviour tests and test helpers.           |
| `tools/`     | Coverage and pkgdown site generation.             |
| `vignettes/` | Package guides and coverage article.              |
| `.github/`   | Issue templates, CI, release, and site workflows. |

`split.R` selects records and manages output publication.
`workbook.R` reads XLSX parts, resolves values and keys, and populates template worksheets
while preserving other workbook parts.

Workbook operations consume `form.model` through its public API.
`xml2` reads and writes worksheet XML; `zip` assembles output XLSX archives.

## Local verification

Run from the package root with development dependencies installed:

```sh
Rscript -e 'roxygen2::roxygenise()'
mkdir -p build
(cd build && R CMD build --no-manual ..)
package_version=$(Rscript -e 'cat(read.dcf("DESCRIPTION")[1, "Version"])')
R CMD check --no-manual --output=build "build/form.tools_${package_version}.tar.gz"
Rscript tools/build-site.R
```

The split tests use the installed survey model, source workbook and empty template from `form.model`.

The site includes a native coverage page at `docs/articles/coverage.html`, using the shared theme and navigation.
The tests cover composite keys, metadata, template preservation and rejection of unsafe split inputs.

Coverage CSV and XML stay in `docs/coverage/`. Archives and check output stay in `build/`.

Run `Rscript tools/coverage.R` to refresh coverage data alone; rebuild the site to refresh its page.

`roxygen2`, `rcmdcheck`, and `pkgload` are development tools, not runtime dependencies.

Review coverage gaps for missing behaviour. Check installed resources, runnable examples, and website navigation.

## Release

1. **Prepare the release on `develop`:**

   1. **Prepare the release files:** update the version in `DESCRIPTION`, finalize `NEWS.md` and documentation.
   2. **Perform the [local checks](#local-verification).**
   3. **Commit the changes:** use `[form.tools] Release <version>`, for example `[form.tools] Release 0.1.0`.
   4. **Push the release commit.**

2. **Start the release on GitHub:**

   1. Open **Actions → Start Release**.
   2. Click **Run workflow**, select `develop`, then click **Run workflow** to confirm.
   3. Open the release PR created by the workflow.

3. **Merge the release PR:**

   1. **Wait for the checks:** all checks on the release PR must be green.
   2. **Merge:** click **Merge pull request**, then **Confirm merge**.

**Publish Release** publishes the package, checksum and documentation automatically.

## License

LGPL-2.1. See the [license text](https://www.gnu.org/licenses/old-licenses/lgpl-2.1.html).
