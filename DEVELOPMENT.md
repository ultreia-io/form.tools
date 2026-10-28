# Maintainer guide

`develop` is the integration branch. `main` contains releases. Implementation branches use `feature/`.

## Code organization

| Directory    | Responsibility                                    |
| ------------ | ------------------------------------------------- |
| `R/`         | Package documentation and future workbook APIs.   |
| `inst/`      | Future installed resources and neutral examples.  |
| `man/`       | Generated roxygen documentation.                  |
| `tests/`     | Test runner and future approved tests.            |
| `tools/`     | Coverage and pkgdown site generation.             |
| `vignettes/` | Package guides and coverage article.              |
| `.github/`   | Issue templates, CI, release, and site workflows. |

The scaffold exports no functions and contains no behavioural tests or domain resources.

Add runtime dependencies when their first implementation requires them.
Workbook operations will consume `form.model` through its public API.

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

The test runner runs tests only once test files exist. The skeleton has no tests to execute.

The site includes a native coverage page at `docs/articles/coverage.html`, using the shared theme and navigation.
Coverage is not measured until executable code and tests are introduced.

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

LGPL-2.1. See [LICENSE](LICENSE).
