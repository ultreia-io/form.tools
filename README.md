# form.tools

[![Build](https://github.com/ultreia-io/form.tools/actions/workflows/Build.yaml/badge.svg?branch=develop)](https://github.com/ultreia-io/form.tools/actions/workflows/Build.yaml?query=branch%3Adevelop)
[![Test Coverage](https://github.com/ultreia-io/form.tools/actions/workflows/TestCoverage.yaml/badge.svg?branch=main)](https://github.com/ultreia-io/form.tools/actions/workflows/TestCoverage.yaml?query=branch%3Amain)
[![Coverage](https://img.shields.io/badge/dynamic/xml?url=https%3A%2F%2Fultreia-io.github.io%2Fform.tools%2Fcoverage%2Fcoverage.xml&query=round%28%2Fcoverage%2F%40line-rate+%2A+1000%29+div+10&label=coverage&suffix=%25&color=brightgreen)](https://ultreia-io.github.io/form.tools/articles/coverage.html)
[![Website](https://img.shields.io/badge/website-documentation-blue)](https://ultreia-io.github.io/form.tools/)
[![Latest
release](https://img.shields.io/github/v/release/ultreia-io/form.tools?display_name=tag&sort=semver)](https://github.com/ultreia-io/form.tools/releases/latest)
[![License](https://img.shields.io/github/license/ultreia-io/form.tools)](https://github.com/ultreia-io/form.tools/blob/main/LICENSE)

Neutral, model-driven workbook operations using form definitions and
matching workbook templates.

**Initial package skeleton. Workbook operations are not implemented yet.**

## Installation

Once the first release is published, install it directly from GitHub:

``` r
install.packages("pak") # Once
pak::pak("ultreia-io/form.tools@*release")
```

`pak` downloads the package and installs its dependencies automatically.

Once the skeleton is pushed to `develop`, install the development version:

``` r
pak::pak("ultreia-io/form.tools@develop")
```

## Start here

``` r
library(form.tools)
```

The package currently provides its skeleton and documentation only.
No workbook functions are exported yet.

## Contract

The planned workbook operations will:

- Consume neutral form definitions through the public `form.model` API.
- Split a workbook by a caller-selected root sheet and its primary key.
- Follow model-defined parent keys to select related records.
- Populate a matching empty template for each output workbook.
- Keep domain definitions and templates in consuming packages.

## Workbook defaults and conventions

The caller supplies the model, source workbook, and matching empty template.

Source workbooks must pass structural validation and have no primary-key
or parent-key findings before splitting.

Shared-sheet copying, output naming, and preservation of Excel features
remain design decisions. No defaults are implemented yet.

## Guides

- [Getting
  started](https://ultreia-io.github.io/form.tools/articles/form.tools.html)
- [API
  reference](https://ultreia-io.github.io/form.tools/reference/index.html)
- [Contributing](https://ultreia-io.github.io/form.tools/CONTRIBUTING.html) and [maintenance](https://ultreia-io.github.io/form.tools/DEVELOPMENT.html)

## Boundaries

This package is intended for neutral workbook operations.

Form definitions belong in `form.model` and its consuming packages.
Submitted-data validation belongs in `form.validation`.
Domain-specific templates and rules remain outside this package.

## License

LGPL-2.1. See
[LICENSE](https://github.com/ultreia-io/form.tools/blob/develop/LICENSE).
