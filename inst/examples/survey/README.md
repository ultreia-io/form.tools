# Survey examples

## Load and transform source tables

The **Load tables from SQL** guide runs the queries against an in-memory SQLite database with sample data.

- `form-source.yaml` defines the source tables and their fields.
- `queries/` contains one SQL file per source table. Each query takes the same bound survey ID.
- `export.yaml` selects observation rows and copies source values for the export preview.

## Write and split workbooks

The website bundles three resources from `form.model` for the workbook examples in **Getting started**.

- `form.yaml`: the workbook form model.
- `form.xlsx`: a populated workbook for splitting.
- `form-empty.xlsx`: the matching template for writing and splitting.
