# Public operations ---------------------------------------------------------

#' Read model tables through a supplied SQL loader
#'
#' Execute one SQL file per model sheet, in model declaration order.
#' @param model A checked form model supplied by form.model, with table layouts.
#' @param queries_directory Directory containing one `<sheet>.sql` file per sheet.
#'   Qualified sheet names such as `schema.table` are kept unchanged.
#' @param table_loader Function accepting `sql` and `params` and returning a data
#'   frame. Use [sql_table_loader()] for a caller-owned DBI connection, or supply
#'   an implementation from a consuming package.
#' @param params Parameter list passed unchanged to every query; NULL for none.
#'   Placeholder syntax and supported values belong to the selected backend.
#' @return A named list of data frames in model order. Columns retain their names,
#'   values and backend-provided R types; rows retain query order, including empty
#'   tables. No partial list is returned on failure.
#' @details Every SQL file is read before the first query runs. Query output must
#'   contain exactly the model fields, in declaration order. Missing, additional,
#'   duplicated or reordered columns raise an error naming the sheet.
#'
#'   Queries are trusted, consumer-owned statements. This function neither builds
#'   joins from parent keys nor applies reference mappings, defaults or value
#'   validation. The caller selects records through query parameters and controls
#'   connection permissions, transactions and snapshot consistency.
#'
#'   The loader owns no connection and writes no files. Reference catalogue tables
#'   are not implicitly downloaded. Results are held in memory; streaming and
#'   automatic pagination are outside this first implementation.
#' @seealso [db.tools::read_sql_file()], [sql_table_loader()]
#' @export
read_form_tables <- function(model, queries_directory, table_loader, params = NULL) {
  model <- form.model::as_form_model(form.model::form_definition(model))
  definitions <- form.model::form_sheets(model)
  require_nonempty_string(queries_directory, "queries_directory")
  if (!dir.exists(queries_directory)) stop("Query directory does not exist", call. = FALSE)
  if (!is.function(table_loader)) stop("table_loader must be a function", call. = FALSE)
  if (!is.null(params) && (!is.list(params) || is.data.frame(params)))
    stop("params must be a list or NULL", call. = FALSE)
  queries <- lapply(names(definitions), function(sheet) {
    if (definitions[[sheet]]$layout$kind != "table")
      stop("SQL loading requires a table layout: ", sheet, call. = FALSE)
    if (grepl("[/\\\\]", sheet) || sheet %in% c(".", ".."))
      stop("Sheet name cannot identify a query filename: ", sheet, call. = FALSE)
    query <- db.tools::read_sql_file(file.path(queries_directory, paste0(sheet, ".sql")))
    query <- sub("^\ufeff", "", query)
    if (!nzchar(trimws(query))) stop("Empty SQL file for ", sheet, call. = FALSE)
    query
  })
  result <- vector("list", length(definitions))
  names(result) <- names(definitions)
  for (i in seq_along(definitions)) {
    sheet <- names(definitions)[[i]]
    data <- tryCatch(table_loader(sql = queries[[i]], params = params), error = function(error) {
      stop("Cannot load ", sheet, ": ", conditionMessage(error), call. = FALSE)
    })
    if (!is.data.frame(data)) stop("Loader must return a data frame for ", sheet, call. = FALSE)
    if (!identical(names(data), names(definitions[[i]]$fields)))
      stop("Query columns differ from model fields for ", sheet, call. = FALSE)
    result[[i]] <- as.data.frame(data)
  }
  result
}

#' Create a table loader for an existing SQL connection
#' @param connection A valid DBI connection supplied and owned by the caller.
#' @return A function with arguments `sql` and `params = NULL`, returning a data
#'   frame through [db.tools::db_query()]. Use it with [read_form_tables()].
#' @details [db.tools::db_query()] passes parameters to the driver for binding.
#'   The loader does not open, close, commit or roll back the connection, including
#'   after query failure. The caller supplies its driver and transaction policy.
#' @export
sql_table_loader <- function(connection) {
  if (!inherits(connection, "DBIConnection") || !isTRUE(DBI::dbIsValid(connection)))
    stop("connection must be a valid DBI connection", call. = FALSE)
  force(connection)
  function(sql, params = NULL) {
    as.data.frame(db.tools::db_query(connection, sql, params = params))
  }
}

#' Read typed tables from CSV files using a form model
#'
#' Read one `<sheet>.csv` file per model sheet and check its header against
#' the declared field names and order.
#' @param form_model A checked form model with table layouts.
#' @param directory Directory containing the UTF-8, comma-separated CSV files.
#' @return A named list of data frames in model order. Header-only files return
#'   empty data frames with the declared columns and types.
#' @details Text and email fields retain their original text, including leading
#'   zeros. Bare empty fields become missing values. Quoted empty strings stay
#'   empty in text columns.
#'
#'   Booleans accept `true`/`false` and `t`/`f`, ignoring case. Integer fields
#'   accept signed decimal integers. Numbers and coordinates accept decimal
#'   notation with an optional exponent. Dates are read as `Date` from
#'   `YYYY-MM-DD`. Date-times are read as UTC `POSIXct` from
#'   `YYYY-MM-DDTHH:MM:SSZ` or SQL timestamps such as
#'   `YYYY-MM-DD HH:MM:SS`, with optional fractional seconds.
#'
#'   CSV rows start immediately after the header. An unreadable file, a
#'   mismatched header or an unparseable value raises an error.
#' @examples
#' # Load the survey source form model.
#' survey_form_model <- form.model::read_form_model("examples/survey/form-source.yaml", "form.tools")
#' # Create a directory for the two source CSVs.
#' survey_csv_directory <- tempfile("survey-csv-")
#' dir.create(survey_csv_directory)
#' # Write one survey and its observation.
#' writeLines(c("id", "001"), file.path(survey_csv_directory, "surveys.csv"))
#' writeLines(c("survey,count", "001,12"), file.path(survey_csv_directory, "observations.csv"))
#' # Load the tables with their declared column types.
#' survey_tables <- read_form_csv_tables(survey_form_model, survey_csv_directory)
#' # Show the typed observations.
#' survey_tables$observations
#' # Remove the temporary example files.
#' unlink(survey_csv_directory, recursive = TRUE)
#' @seealso [read_form_tables()]
#' @export
read_form_csv_tables <- function(form_model, directory) {
  definitions <- form.model::form_sheets(form_model)
  require_nonempty_string(directory, "directory")
  if (!dir.exists(directory)) stop("CSV directory does not exist", call. = FALSE)

  tables <- lapply(names(definitions), function(sheet) {
    definition <- definitions[[sheet]]
    if (definition$layout$kind != "table")
      stop("CSV loading requires a table layout: ", sheet, call. = FALSE)
    if (grepl("[/\\\\]", sheet) || sheet %in% c(".", ".."))
      stop("Sheet name cannot identify a CSV filename: ", sheet, call. = FALSE)
    path <- file.path(directory, paste0(sheet, ".csv"))
    if (!file.exists(path) || dir.exists(path))
      stop("CSV file not found for ", sheet, ": ", path, call. = FALSE)

    table <- read_form_csv_file(path, sheet)
    if (!identical(names(table), names(definition$fields)))
      stop("CSV columns differ from model fields for ", sheet, call. = FALSE)

    for (column in names(definition$fields)) {
      type <- definition$fields[[column]]$type
      table[[column]] <- parse_form_csv_column(table[[column]], type, paste0(sheet, ".", column))
    }
    table
  })
  stats::setNames(tables, names(definitions))
}

# Internal helpers ----------------------------------------------------------

#' Read UTF-8 CSV records with quoting and missing fields preserved
#' @param path Path to one CSV file with a header.
#' @param sheet Model sheet name for errors.
#' @return A character data frame. Bare empty fields are missing values.
#' @keywords internal
read_form_csv_file <- function(path, sheet) {
  fail <- function(message) stop("Cannot read CSV for ", sheet, ": ", message, call. = FALSE)
  bytes <- tryCatch(readBin(path, what = "raw", n = file.size(path)),
    error = function(error) fail(conditionMessage(error)))
  if (any(bytes == as.raw(0L))) fail("NUL bytes are invalid in a CSV file")
  text <- rawToChar(bytes)
  Encoding(text) <- "UTF-8"
  if (!validUTF8(text)) fail("expected UTF-8 text")
  text <- sub("^\ufeff", "", text)
  if (!nzchar(text)) fail("missing header")
  if (!endsWith(text, "\n") && !endsWith(text, "\r")) text <- paste0(text, "\n")

  # Match a quoted or unquoted field together with its following delimiter.
  # A gap between matches indicates invalid CSV syntax.
  delimiter <- "(?:,|\r\n|[\r\n])"
  field <- '(?:"(?:[^"]++|"")*+"|[^",\r\n]*+)'
  matches <- gregexpr(paste0(field, delimiter), text, perl = TRUE, useBytes = TRUE)
  if (sum(attr(matches[[1L]], "match.length")) != nchar(text, type = "bytes"))
    fail("invalid CSV quoting")
  tokens <- regmatches(text, matches)[[1L]]
  Encoding(tokens) <- "UTF-8"

  record_ends <- which(!endsWith(tokens, ","))
  record_sizes <- diff(c(0L, record_ends))
  if (any(record_sizes != record_sizes[[1L]]))
    fail("records have different numbers of columns")

  values <- sub(paste0(delimiter, "$"), "", tokens, perl = TRUE)
  quoted <- startsWith(values, '"')
  values[quoted] <- gsub('""', '"', substring(values[quoted], 2L, nchar(values[quoted]) - 1L),
    fixed = TRUE)
  values[!quoted & !nzchar(values)] <- NA_character_
  cells <- matrix(values, ncol = record_sizes[[1L]], byrow = TRUE)
  table <- as.data.frame(cells[-1L, , drop = FALSE], stringsAsFactors = FALSE)
  names(table) <- cells[1L, ]
  table
}

#' Convert CSV text to the declared R column type
#' @param values Character column with missing fields represented by NA.
#' @param type Form model field type.
#' @param field Qualified field name for errors.
#' @return A typed vector, with missing values retained.
#' @keywords internal
parse_form_csv_column <- function(values, type, field) {
  parsed <- switch(type,
    string = values,
    email = values,
    boolean = unname(c("true" = TRUE, "false" = FALSE, "t" = TRUE, "f" = FALSE)[tolower(values)]),
    date = {
      dates <- as.Date(values, format = "%Y-%m-%d")
      dates[which(format(dates, "%Y-%m-%d") != values)] <- NA
      dates
    },
    datetime = parse_form_csv_datetime(values),
    parse_form_csv_number(values, integer = type == "integer"))

  invalid <- which(!is.na(values) & is.na(parsed))
  if (length(invalid))
    stop("Invalid ", type, " in CSV field ", field, " at data row ", invalid[[1L]], call. = FALSE)
  parsed
}

#' Parse decimal CSV fields
#' @param values Character column from a CSV file.
#' @param integer Whether the field requires whole numbers.
#' @return Numeric values, with invalid values marked missing. Whole-number
#'   columns use R integers when all values fit that representation.
#' @keywords internal
parse_form_csv_number <- function(values, integer) {
  pattern <- if (integer) "^[+-]?[0-9]+$" else
    "^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$"
  valid <- grepl(pattern, values)
  numbers <- rep(NA_real_, length(values))
  numbers[valid] <- as.numeric(values[valid])
  numbers[!is.finite(numbers)] <- NA_real_
  if (integer) {
    numbers[which(abs(numbers) > 2^53 - 1)] <- NA_real_
    if (all(abs(numbers) <= .Machine$integer.max, na.rm = TRUE))
      return(as.integer(numbers))
  } else {
    mantissas <- sub("[eE].*$", "", values)
    numbers[which(numbers == 0 & grepl("[1-9]", mantissas))] <- NA_real_
  }
  numbers
}

#' Parse UTC date-times from a CSV column
#' @param values Character column in ISO or SQL timestamp format.
#' @return UTC POSIXct values, with invalid values marked missing.
#' @keywords internal
parse_form_csv_datetime <- function(values) {
  pattern <- "^[0-9]{4}-[0-9]{2}-[0-9]{2}[T ][0-9]{2}:[0-9]{2}:[0-9]{2}([.][0-9]+)?Z?$"
  normalized <- sub("T", " ", sub("Z$", "", values), fixed = TRUE)
  whole_seconds <- substr(normalized, 1L, 19L)
  timestamp_format <- "%Y-%m-%d %H:%M:%S"
  timestamps <- as.POSIXct(whole_seconds, format = timestamp_format, tz = "UTC")
  valid <- grepl(pattern, values) & !is.na(timestamps) &
    format(timestamps, timestamp_format, tz = "UTC") == whole_seconds
  timestamps[!valid] <- NA
  fraction <- which(valid & nchar(normalized) > 19L)
  timestamps[fraction] <- timestamps[fraction] + as.numeric(substring(normalized[fraction], 20L))
  timestamps
}
