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

Consumers supply the form model, source data and matching workbook templates.

## Features

**Table loading**

- Read one SQL query per model sheet, including names such as `schema.table.sql`.
- Use a caller-owned database connection through `db.tools`, or supply a consumer backend.
- Bind query parameters with the database driver and preserve its returned values and types.
- Return tables in model order with the declared columns, including empty tables.

**Workbook writing**

- Fill an empty template with typed R data using model-defined field names.
- Write text, numbers, logical values, dates and UTC date-times without losing literal text or leading zeros.
- Preserve template formatting and supporting workbook parts; extend standard validation ranges as needed.
- Publish a new workbook without overwriting existing files.

**Workbook splitting**

- Split a structurally validated form into one workbook per root record.
- Select related rows through primary and parent keys, including composite keys.
- Copy fixed metadata and explicitly selected shared tables into every output.
- Return a manifest of output paths and root keys; keep the source workbook and template unchanged.

## Related packages

- [db.tools](https://github.com/ultreia-io/db.tools) runs database queries, manages connections and restores H2 backups.
- [form.model](https://github.com/ultreia-io/form.model) defines forms, their layouts and constraints.
- [form.references](https://github.com/ultreia-io/form.references) loads reference catalogues and resolves lookups.
- [form.validation](https://github.com/ultreia-io/form.validation) validates submitted forms and produces reports.

## Installation

Install the latest version available on CRAN:

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

Follow [Getting started][getting-started] for runnable survey examples.

[getting-started]: https://ultreia-io.github.io/form.tools/articles/form.tools.html

## Guides

- [Load tables from SQL](https://ultreia-io.github.io/form.tools/articles/sql-loading.html)
- [Package resources](https://ultreia-io.github.io/form.tools/articles/resources.html): models, workbooks and SQL downloads.
- [API reference](https://ultreia-io.github.io/form.tools/reference/index.html)
- [Contributing](https://ultreia-io.github.io/form.tools/CONTRIBUTING.html) and [maintenance](https://ultreia-io.github.io/form.tools/DEVELOPMENT.html)
