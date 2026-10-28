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

**Split structurally validated workbooks using model-defined keys and an empty template.**

## Installation

Install the latest release directly from GitHub:

``` r
install.packages("pak") # Once
pak::pak("ultreia-io/form.tools@*release")
```

`pak` downloads the package and installs its dependencies automatically.

Install the development version:

``` r
pak::pak("ultreia-io/form.tools@develop")
```

## Start here

``` r
library(form.tools)
examples <- system.file("examples", package = "form.model")
model <- form.model::load_form_model("survey", examples)

outputs <- split_form_workbook(
  path = file.path(examples, "survey.xlsx"),
  model = model,
  root_sheet = "Observations",
  template = file.path(examples, "survey-empty.xlsx"),
  directory = "survey-by-observation",
  shared_sheets = "Equipment"
)
outputs
```

The bundled example produces three workbooks, each containing one observation, its related records, and shared data.
For your own workbooks, the source must already pass structural validation.
The template must match the model version and use the same Excel date system as the source.

The output directory must not exist. Each root record produces one workbook, in source order.
The returned manifest includes the output path, source row, and root key components.

## Contract

- Consume neutral form definitions through the public `form.model` API.
- Split a workbook by a caller-selected root sheet and its primary key.
- Follow model-defined parent keys to select related records.
- Populate a matching empty template for each output workbook.
- Reject missing or duplicate primary keys and missing parent keys before writing outputs.
- Keep domain definitions and templates in consuming packages.

## Workbook defaults and conventions

Fixed-cell fields are copied into every output. Descendant tables retain their original row order.
Tables outside the selected hierarchy must be explicitly listed in `shared_sheets` to copy them in full.

Unmodeled template sheets are retained unchanged. Unmodeled source sheets are not copied.
Output filenames combine the original basename and root primary-key values in model order:
`<original basename>_<key components>.xlsx`. Components are separated by `_`.
Invalid filename characters become `_`; case-insensitive collisions and names exceeding 255 bytes are rejected.

Template table data regions must be empty, including formulas.
Additional rows inherit the first template data row's styles and height.
Standard dropdown and conditional-formatting ranges grow with the output data.

Source formulas are copied as cached values. Excel errors and uncached formulas in modeled fields are rejected.
Template formulas outside modeled fields are retained, with recalculation requested when Excel opens the output.
R does not recalculate formulas.

Excel tables and merged cells in template data regions are not supported in this first implementation.
Fixed print areas and extended Excel validation ranges are preserved without expansion.

Outputs are prepared in a temporary sibling directory and published together after all workbooks are written.
Source and template files are never modified; existing outputs are never overwritten.

## Guides

- [Getting
  started](https://ultreia-io.github.io/form.tools/articles/form.tools.html)
- [API
  reference](https://ultreia-io.github.io/form.tools/reference/index.html)
- [Contributing](https://ultreia-io.github.io/form.tools/CONTRIBUTING.html) and [maintenance](https://ultreia-io.github.io/form.tools/DEVELOPMENT.html)

## Boundaries

This package performs neutral workbook operations.

Form definitions belong in `form.model` and its consuming packages.
Submitted-data validation belongs in `form.validation`.
Domain-specific templates and rules remain outside this package.

## License

LGPL-2.1. See
[LICENSE](https://github.com/ultreia-io/form.tools/blob/develop/LICENSE).
