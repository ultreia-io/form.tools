# form.tools 0.3.0

* [feature] Load model tables through SQL files and a supplied table loader, with a db.tools backend.
* [docs] Group package features and provide survey resources in a versioned ZIP archive.
* [build] Run the SQL examples and tests with SQLite.
* [build] Run routine builds on Linux, check all four environments before the release PR, and make CRAN submission opt-in.

# form.tools 0.2.0

* [feature] Write typed data into empty forms using model-defined field names while preserving template formatting.
* [docs] Document writing and splitting with runnable survey examples.
* [dependencies] Require form.model >= 0.6.2 from CRAN.
* [build] Add full CRAN checks, shared caches and Codecov coverage.
* [build] Submit GitHub release archives to CRAN with duplicate protection.
* [build] Use standard pkgdown builds with prepared download assets.

# form.tools 0.1.1

* Preserve source date and datetime formats when splitting workbooks.

# form.tools 0.1.0

* Split workbooks by model keys, preserving templates and shared data.
* Name outputs using the source filename and root key; never overwrite existing files.
