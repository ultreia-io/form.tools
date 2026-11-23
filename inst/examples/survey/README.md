# Survey examples

`form-source.yaml` and `queries/` demonstrate loading source tables through a caller-supplied SQL connection.

The SQL loading guide creates the synthetic data in an in-memory SQLite database.

Each query uses the same bound survey identifier. Keep the model and queries together.

The website downloads also include three workbook resources from the installed `form.model` package:

- `form.yaml`: the workbook form model.
- `form.xlsx`: a populated workbook for splitting.
- `form-empty.xlsx`: the matching template for writing and splitting.

The source model and workbook model illustrate separate operations; their tables are not an export mapping.

See the Getting started and Load tables from SQL guides for runnable examples.
