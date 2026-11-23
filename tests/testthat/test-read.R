sql_example <- function(directory) {
  model <- form.model::as_form_model(list(schema_version = "1.0.0",
    form = list(id = "source", version = "1.0"), references = list(),
    sheets = list(
      "source.trips" = list(layout = list(kind = "table", start_row = 2L), primary_key = list("id"),
        fields = list(id = list(type = "string"), note = list(type = "string"))),
      "source.sets" = list(layout = list(kind = "table", start_row = 2L), primary_key = list("id"),
        parent_key = list(sheet = "source.trips", fields = list("trip")),
        fields = list(id = list(type = "string"), trip = list(type = "string"), count = list(type = "integer"))))))
  writeLines("SELECT id, note FROM trips WHERE id = ? ORDER BY id", file.path(directory, "source.trips.sql"))
  writeLines("SELECT id, trip, count FROM sets WHERE trip = ? ORDER BY id", file.path(directory, "source.sets.sql"))
  model
}

sqlite_connection <- function() {
  skip_if_not_installed("RSQLite")
  DBI::dbConnect(RSQLite::SQLite(), ":memory:")
}

test_that("SQL binding selects literal keys and preserves source values and empty tables", {
  directory <- withr::local_tempdir()
  model <- sql_example(directory)
  connection <- sqlite_connection()
  on.exit(DBI::dbDisconnect(connection))
  selected <- "x' OR 1=1 --"
  DBI::dbWriteTable(connection, "trips", data.frame(id = c(selected, "other"), note = c("", NA)))
  DBI::dbWriteTable(connection, "sets", data.frame(id = c("02", "01"), trip = selected, count = c(NA_integer_, 0L)))
  loader <- sql_table_loader(connection)
  result <- read_form_tables(model, directory, loader, params = list(selected))
  expect_identical(names(result), c("source.trips", "source.sets"))
  expect_identical(result[[1]]$id, selected)
  expect_identical(result[[1]]$note, "")
  expect_identical(result[[2]]$id, c("01", "02"))
  expect_identical(result[[2]]$count, c(0L, NA_integer_))
  empty <- read_form_tables(model, directory, loader, params = list("other"))
  expect_true(is.na(empty[[1]]$note))
  expect_identical(names(empty[[2]]), c("id", "trip", "count"))
  expect_identical(nrow(empty[[2]]), 0L)
  expect_type(empty[[2]]$count, "integer")
  expect_true(DBI::dbIsValid(connection))
})

test_that("all query files are checked before any backend request", {
  directory <- withr::local_tempdir()
  model <- sql_example(directory)
  calls <- 0L
  loader <- function(sql, params) { calls <<- calls + 1L; data.frame() }
  unlink(file.path(directory, "source.sets.sql"))
  expect_error(read_form_tables(model, directory, loader), "SQL file not found")
  expect_identical(calls, 0L)
  writeLines("", file.path(directory, "source.sets.sql"))
  expect_error(read_form_tables(model, directory, loader), "Empty SQL file")
  expect_identical(calls, 0L)
})

test_that("every backend must return the exact modeled columns", {
  directory <- withr::local_tempdir()
  model <- sql_example(directory)
  for (columns in list(c("id"), c("id", "note", "extra"), c("note", "id"), c("id", "id"))) {
    loader <- function(sql, params) {
      result <- as.data.frame(rep(list(character()), length(columns)))
      names(result) <- columns
      result
    }
    expect_error(read_form_tables(model, directory, loader), "columns differ.*source.trips")
  }
  expect_error(read_form_tables(model, directory, function(sql, params) NULL), "data frame.*source.trips")
})

test_that("backend errors identify the sheet and retain connection ownership", {
  directory <- withr::local_tempdir()
  model <- sql_example(directory)
  connection <- sqlite_connection()
  on.exit(DBI::dbDisconnect(connection))
  DBI::dbWriteTable(connection, "trips", data.frame(id = "trip", note = "source"))
  expect_error(read_form_tables(model, directory, sql_table_loader(connection), list("trip")),
               "Cannot load source.sets")
  expect_true(DBI::dbIsValid(connection))
  expect_identical(DBI::dbGetQuery(connection, "SELECT count(*) AS n FROM trips")$n, 1L)
})
