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
  tool_text(queries_directory, "queries_directory")
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
