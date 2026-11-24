csv_example_model <- function() {
  form.model::as_form_model(list(
    schema_version = "1.0.0",
    form = list(id = "source", version = "1.0"),
    references = list(),
    sheets = list(
      "source.trips" = list(
        layout = list(kind = "table", start_row = 2L), primary_key = list("id"),
        fields = list(id = list(type = "string"), note = list(type = "string"),
          email = list(type = "email"), crew = list(type = "integer"),
          length = list(type = "number"), observed = list(type = "boolean"),
          lat = list(type = "latitude"), lon = list(type = "longitude"),
          day = list(type = "date"), time = list(type = "datetime"))),
      "source.sets" = list(
        layout = list(kind = "table", start_row = 2L),
        parent_key = list(sheet = "source.trips", fields = list("trip")),
        fields = list(trip = list(type = "string"), count = list(type = "integer")))
    )
  ))
}

write_csv_records <- function(path, records) {
  writeBin(charToRaw(enc2utf8(paste0(paste(records, collapse = "\r\n"), "\r\n"))), path)
}

test_that("CSV loading follows model types and retains exact text values", {
  model <- csv_example_model()
  directory <- withr::local_tempdir()
  write_csv_records(file.path(directory, "source.trips.csv"), c(
    "id,note,email,crew,length,observed,lat,lon,day,time",
    '"001","","leader@example.org","12","1.2e2","true","-15.25","67.5","2025-01-02","2025-01-02 03:04:05.25"',
    '"002",,,,"2.0000","F","-90","180",,"2025-01-02T03:04:06Z"',
    '"003","  caf\u00e9, ""note""\r\nnext  ",,"2147483648",,,,,,',
    '"004","NA",,,,,,,,'
  ))
  write_csv_records(file.path(directory, "source.sets.csv"), "trip,count")

  tables <- read_form_csv_tables(model, directory)
  expect_identical(names(tables), c("source.trips", "source.sets"))
  trip <- tables[["source.trips"]]
  expect_s3_class(trip, "data.frame")
  expect_identical(trip$id, c("001", "002", "003", "004"))
  expect_identical(trip$note, c("", NA, "  caf\u00e9, \"note\"\r\nnext  ", "NA"))
  expect_identical(trip$email, c("leader@example.org", rep(NA_character_, 3L)))
  expect_identical(trip$crew, c(12, NA, 2147483648, NA))
  expect_identical(trip$length, c(120, 2, NA, NA))
  expect_identical(trip$observed, c(TRUE, FALSE, NA, NA))
  expect_identical(trip$lat, c(-15.25, -90, NA, NA))
  expect_identical(trip$lon, c(67.5, 180, NA, NA))
  expect_identical(trip$day, as.Date(c("2025-01-02", NA, NA, NA)))
  expect_identical(trip$time, as.POSIXct(c("2025-01-02 03:04:05", "2025-01-02 03:04:06", NA, NA),
    tz = "UTC", format = "%Y-%m-%d %H:%M:%S") + c(0.25, 0, 0, 0))
  expect_identical(tables[["source.sets"]], data.frame(trip = character(), count = integer()))
})

test_that("CSV loading requires every model file and its exact column names", {
  model <- csv_example_model()
  directory <- withr::local_tempdir()
  write_csv_records(file.path(directory, "source.trips.csv"), "id,note,email,crew,length,observed,lat,lon,day,time")
  expect_error(read_form_csv_tables(model, directory), "CSV file not found for source.sets")

  for (header in c("trip", "count,trip", "trip,trip", "trip,count,other")) {
    write_csv_records(file.path(directory, "source.sets.csv"), header)
    expect_error(read_form_csv_tables(model, directory), "CSV columns differ.*source.sets")
  }
  write_csv_records(file.path(directory, "source.sets.csv"), c("trip,count", "001,2,3"))
  expect_error(read_form_csv_tables(model, directory), "source.sets.*records have different numbers of columns")
  write_csv_records(file.path(directory, "source.sets.csv"), c("trip,count", '"001,2'))
  expect_error(read_form_csv_tables(model, directory), "source.sets.*invalid CSV quoting")
})

test_that("unparseable CSV values report the field and row", {
  model <- csv_example_model()
  directory <- withr::local_tempdir()
  write_csv_records(file.path(directory, "source.sets.csv"), "trip,count")
  path <- file.path(directory, "source.trips.csv")
  header <- "id,note,email,crew,length,observed,lat,lon,day,time"
  valid <- c("001", "", "", "12", "3", "true", "1", "2", "2025-01-02", "2025-01-02 03:04:05")
  invalid <- c(crew = "1.5", length = "Infinity", observed = '""',
    day = "2025-02-29", time = "2025-01-02 24:00:00")
  for (field in names(invalid)) {
    record <- valid
    record[match(field, strsplit(header, ",", fixed = TRUE)[[1L]])] <- invalid[[field]]
    write_csv_records(path, c(header, paste(valid, collapse = ","), paste(record, collapse = ",")))
    expect_error(read_form_csv_tables(model, directory),
      paste0("source.trips.", field, " at data row 2"), fixed = TRUE)
  }
})
