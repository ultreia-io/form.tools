# form.tools

[![Build](https://img.shields.io/github/actions/workflow/status/ultreia-io/form.tools/Build.yaml?branch=develop&label=Build&logo=githubactions&logoColor=white)](https://github.com/ultreia-io/form.tools/actions/workflows/Build.yaml?query=branch%3Adevelop)
[![Website](https://img.shields.io/badge/website-documentation-blue?logo=readthedocs&logoColor=white)](https://ultreia-io.github.io/form.tools/index.html)
[![License](https://img.shields.io/badge/license-LGPL--2.1-blue?logo=gnu&logoColor=white)](https://github.com/ultreia-io/form.tools/blob/main/LICENSE)

[![Latest release](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fapi.github.com%2Frepos%2Fultreia-io%2Fform.tools%2Freleases%2Flatest&query=%24.tag_name&label=Latest%20release&color=blue&logo=github&logoColor=white)](https://github.com/ultreia-io/form.tools/releases/latest)
![CRAN release](https://img.shields.io/badge/dynamic/json?url=https%3A%2F%2Fcrandb.r-pkg.org%2Fform.tools&query=%24.Version&label=CRAN%20release&color=brightgreen&logo=r&logoColor=white)

[![Coverage develop](https://img.shields.io/codecov/c/github/ultreia-io/form.tools/develop?label=coverage%20develop&logo=codecov)](https://app.codecov.io/gh/ultreia-io/form.tools/tree/develop)
[![Coverage main](https://img.shields.io/codecov/c/github/ultreia-io/form.tools/main?label=coverage%20main&logo=codecov)](https://app.codecov.io/gh/ultreia-io/form.tools/tree/main)

## About this project

> `form.tools` performs operations on Excel forms using their form models.

Read the [Terminology](https://ultreia-io.github.io/form.tools/articles/terminology.html) for the concepts used throughout this documentation.

A form is an Excel workbook used to collect data. Its form model describes the expected structure and rules in YAML.

The writer fills an empty form with typed R data, placing values by the field names defined in the form model.

The splitter creates one form per root record, selecting related records through primary and parent keys.

Both operations preserve template formatting and supporting workbook parts. Source files remain unchanged.

Consumers supply the form model, matching empty form and data to write or split.

## Related packages

- [form.model](https://github.com/ultreia-io/form.model) defines forms, their layouts and constraints.
- [form.references](https://github.com/ultreia-io/form.references) loads reference catalogues and resolves lookups.
- [form.validation](https://github.com/ultreia-io/form.validation) validates submitted forms and produces reports.

## Installation

The first CRAN submission is pending. Once available, install the latest version from CRAN:

``` r
# Install form.tools from CRAN.
install.packages("form.tools")
```

Alternatively, install the latest GitHub release:

``` r
# Install the package installer once.
install.packages("pak")
# Install the latest released form.tools package.
pak::pak("ultreia-io/form.tools@*release")
```

`pak` downloads the package and installs its dependencies automatically.

For the development version:

``` r
# Install form.tools from the development branch.
pak::pak("ultreia-io/form.tools@develop")
```

## Getting started

Follow the [Getting started guide](https://ultreia-io.github.io/form.tools/articles/form.tools.html) for the runnable survey example and downloadable files.

## Guides

- [API reference](https://ultreia-io.github.io/form.tools/reference/index.html)
- [Contributing](https://ultreia-io.github.io/form.tools/CONTRIBUTING.html) and [maintenance](https://ultreia-io.github.io/form.tools/DEVELOPMENT.html)
