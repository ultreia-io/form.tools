## Check results

R CMD check --as-cran for form.tools on:

* Local computer: Linux (elementary OS 8), R 4.6.2.
* GitHub Actions: Ubuntu, R 4.6.2 (release).
* GitHub Actions: Ubuntu, R-devel (2026-11-10 r90874).
* GitHub Actions: macOS, R 4.6.2 (release).
* GitHub Actions: Windows, R 4.6.2 (release, UCRT).

CI results: 0 errors, 0 warnings, 1 NOTE on all four environments.

The NOTE identifies this as a new submission.

CI run: https://github.com/ultreia-io/form.tools/actions/runs/43020553214

## First submission

This is the first CRAN submission of form.tools.

The package uses form.model, available on CRAN, to write and split Excel forms using their declared layouts and keys.

It preserves template formatting and supporting workbook parts while keeping domain-specific rules in consumers.

Thank you for reviewing this submission and for supporting the R open-source community.
