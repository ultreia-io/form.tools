# Public operations ---------------------------------------------------------

#' Write typed data into an empty form workbook
#'
#' Place values by form model field names while preserving the template layout.
#' @param data Named list of data frames, one for every modeled sheet. Each frame
#'   must contain every field exactly once. Column and sheet order may differ
#'   from the model. Fixed-cell sheets require one row; tables may have zero rows.
#' @param model A checked form model supplied by form.model.
#' @param template Empty XLSX form matching the selected model and version.
#' @param path New XLSX output path in an existing directory. Never overwritten.
#' @return The normalized output path, invisibly.
#' @details Character columns supply string and email fields; logical columns
#'   supply Boolean fields. Integer and numeric columns supply numeric fields;
#'   integer fields reject fractional values. Dates require `Date` and date-times
#'   require `POSIXct`; date-times are written in UTC. Missing values leave blank
#'   cells. Factors, list columns, infinities and NaN are rejected. Strings remain
#'   literal text, including leading zeros and strings starting with `=`.
#'
#'   Rows retain their input order, including entirely empty rows. Dates respect
#'   the template's 1900 or 1904 date system. Date formats are `yyyy-mm-dd` and
#'   `yyyy-mm-dd hh:mm:ss`. Excel's numeric precision limits still apply; integral
#'   values with more than 15 decimal digits must be supplied as text fields.
#'
#'   The caller selects the correct template version. Modeled sheets must exist,
#'   table data regions must be empty, and modeled fields must not contain formulas
#'   or merged cells. Excel tables in modeled sheets are unsupported. Headers,
#'   unrelated cells, extra sheets and supporting workbook parts are preserved.
#'   New rows inherit the first template data row's style and height. Standard
#'   validation and conditional-formatting ranges extend with the table.
#'   Formulas elsewhere are retained and recalculation is requested on opening.
#'
#'   This function checks input names, representations and writable positions.
#'   It does not validate requiredness, keys, references or business rules.
#'   A successfully written workbook is not necessarily a valid submission.
#'
#'   The template remains unchanged. A temporary sibling file is published with
#'   a hard link, which refuses an existing destination even during concurrent
#'   writes. Filesystems without hard-link support raise an error. Temporary files
#'   are removed on failure; no partial destination is published.
#' @export
write_form_workbook <- function(data, model, template, path) {
  tool_text(path, "path")
  if (!grepl("[.]xlsx$", path, ignore.case = TRUE)) stop("Output must be an .xlsx file", call. = FALSE)
  existing_link <- Sys.readlink(path)
  if (file.exists(path) || dir.exists(path) || (!is.na(existing_link) && nzchar(existing_link)))
    stop("Output already exists: ", path, call. = FALSE)
  destination_directory <- normalizePath(dirname(path), mustWork = TRUE)
  if (!dir.exists(destination_directory)) stop("Output parent must be a directory", call. = FALSE)
  path <- file.path(destination_directory, basename(path))
  model_definition <- form.model::as_form_model(form.model::form_definition(model))
  sheet_definitions <- form.model::form_sheets(model_definition)
  check_write_names(data, names(sheet_definitions), "data")
  workspace <- tempfile("form-write-")
  dir.create(workspace)
  on.exit(unlink(workspace, recursive = TRUE), add = TRUE)
  template_book <- xlsx_read(template, file.path(workspace, "template"))
  sheet_patterns <- lapply(names(sheet_definitions), function(sheet_name) xlsx_sheet(template_book, sheet_name))
  names(sheet_patterns) <- names(sheet_definitions)
  encoded_sheets <- lapply(names(sheet_definitions), function(sheet_name) {
    sheet_definition <- sheet_definitions[[sheet_name]]
    sheet_data <- data[[sheet_name]]
    if (!is.data.frame(sheet_data)) stop("Expected a data frame for ", sheet_name, call. = FALSE)
    check_write_names(sheet_data, names(sheet_definition$fields), sheet_name)
    if (sheet_definition$layout$kind == "cells" && nrow(sheet_data) != 1L)
      stop("Fixed-cell sheet requires exactly one row: ", sheet_name, call. = FALSE)
    pattern <- sheet_patterns[[sheet_name]]
    if (sheet_definition$layout$kind == "table") {
      check_template_table(pattern, sheet_definition, sheet_name)
    } else {
      check_write_fixed_cells(pattern, sheet_definition, sheet_name)
    }
    lapply(names(sheet_definition$fields), function(field_name) {
      encode_form_column(sheet_data[[field_name]], sheet_definition$fields[[field_name]]$type,
                         template_book$date1904, paste(sheet_name, field_name, sep = "."))
    })
  })
  names(encoded_sheets) <- names(sheet_definitions)
  # Only temporal fields need new number formats; other template styling is retained.
  temporal_styles <- xml2::read_xml(paste0(
    '<styleSheet><numFmts><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/>',
    '<numFmt numFmtId="165" formatCode="yyyy-mm-dd hh:mm:ss"/></numFmts>',
    '<cellXfs><xf numFmtId="164"/><xf numFmtId="165"/></cellXfs></styleSheet>'))
  number_formats <- template_number_formats(temporal_styles, template_book)
  for (sheet_name in names(sheet_definitions)) {
    sheet_definition <- sheet_definitions[[sheet_name]]
    encoded_columns <- encoded_sheets[[sheet_name]]
    names(encoded_columns) <- names(sheet_definition$fields)
    value_at <- function(row, column, field) {
      data_row <- if (sheet_definition$layout$kind == "cells") 1L else row
      encoded_columns[[field]][[data_row]]
    }
    write_template_sheet(sheet_patterns[[sheet_name]], sheet_definition,
      seq_len(nrow(data[[sheet_name]])), file.path(template_book$directory, template_book$parts[[sheet_name]]),
      number_formats, value_at, keep_empty_rows = TRUE)
  }
  number_formats$write(template_book$directory)
  request_workbook_calculation(file.path(template_book$directory, "xl/workbook.xml"))
  staged_path <- tempfile(".form-write-", tmpdir = destination_directory, fileext = ".xlsx")
  on.exit(unlink(staged_path), add = TRUE)
  zip::zipr(staged_path, list.files(template_book$directory, recursive = TRUE, all.files = TRUE, no.. = TRUE),
            root = template_book$directory, mode = "mirror", include_directories = FALSE)
  if (!file.link(staged_path, path)) stop("Cannot publish workbook without overwriting: ", path, call. = FALSE)
  invisible(path)
}

# Internal helpers ----------------------------------------------------------

#' Check exact named input coverage
#' @param data Named list or data frame.
#' @param expected Required names.
#' @param label Input location used in errors.
#' @return No useful value; invalid names raise an error.
#' @keywords internal
check_write_names <- function(data, expected, label) {
  if (!is.list(data) || is.null(names(data)) || anyNA(names(data)) || anyDuplicated(names(data)) ||
      !setequal(names(data), expected))
    stop(label, " must contain each modeled name exactly once: ", paste(expected, collapse = ", "), call. = FALSE)
}

#' Check fixed template fields for unsupported features
#' @param pattern Template worksheet descriptor.
#' @param definition Checked sheet definition.
#' @param name Sheet name for diagnostics.
#' @return No useful value; unsafe target cells raise an error.
#' @keywords internal
check_write_fixed_cells <- function(pattern, definition, name) {
  if (length(xlsx_nodes(pattern$document, "tableParts")))
    stop("Excel tables are not supported in template sheet ", name, call. = FALSE)
  ranges <- xml2::xml_attr(xml2::xml_find_all(pattern$document,
    "./*[local-name()='mergeCells']/*[local-name()='mergeCell']", ns = character()), "ref")
  for (field in definition$fields) {
    position <- xlsx_address(field$location)
    for (range in ranges) {
      bounds <- xlsx_address(strsplit(range, ":", fixed = TRUE)[[1L]])
      if (position$row >= min(bounds$row) && position$row <= max(bounds$row) &&
          position$column >= min(bounds$column) && position$column <= max(bounds$column))
        stop("Merged target cell: ", name, "!", field$location, call. = FALSE)
    }
  }
}

#' Encode a typed field column as XLSX cell values
#' @param values Atomic input column.
#' @param type Form model field type.
#' @param date1904 Whether the template uses the 1904 date system.
#' @param label Field location included in errors.
#' @return List of encoded cell values; missing values are NULL.
#' @keywords internal
encode_form_column <- function(values, type, date1904, label) {
  fail <- function(message) stop(label, ": ", message, call. = FALSE)
  valid <- switch(type,
    string = is.character(values) && !is.object(values),
    email = is.character(values) && !is.object(values),
    boolean = is.logical(values) && !is.object(values),
    date = identical(class(values), "Date"),
    datetime = identical(class(values), c("POSIXct", "POSIXt")),
    is.numeric(values) && !is.object(values))
  if (!isTRUE(valid) || !is.null(dim(values))) fail(paste("unsupported R representation for", type))
  if (is.numeric(values) || type %in% c("date", "datetime")) {
    raw_values <- as.numeric(values)
    if (any(is.nan(raw_values) | is.infinite(raw_values))) fail("non-finite values are not supported")
  }
  if (type == "integer" && any(values != trunc(values), na.rm = TRUE)) fail("expected integral values")
  if (type %in% c("date", "datetime")) {
    days <- as.numeric(values) / if (type == "datetime") 86400 else 1
    if (type == "date" && any(days != trunc(days), na.rm = TRUE)) fail("Date values must represent whole days")
    origin <- as.numeric(as.Date(if (date1904) "1904-01-01" else "1899-12-31"))
    serial <- days - origin
    if (!date1904) serial <- serial + as.integer(days >= as.numeric(as.Date("1900-03-01")))
    if (any(days < as.numeric(as.Date(if (date1904) "1904-01-01" else "1900-01-01")) |
            days >= as.numeric(as.Date("9999-12-31")) + 1, na.rm = TRUE)) fail("date outside Excel's supported range")
    values <- serial
  } else if (is.numeric(values)) {
    if (any(abs(values) >= 1e15 & values == trunc(values), na.rm = TRUE)) fail("integer exceeds Excel's 15-digit precision")
    if (any(values != 0 & abs(values) < .Machine$double.xmin, na.rm = TRUE)) fail("number below Excel's supported range")
  }
  lapply(seq_along(values), function(index) {
    value <- values[[index]]
    if (is.na(value)) return(NULL)
    if (type %in% c("string", "email")) {
      if (is.na(iconv(value, to = "UTF-8"))) fail("invalid text encoding")
      if (grepl("[\001-\010\013\014\016-\037]", value)) fail("unsupported XML control character")
      if (length(iconv(value, to = "UTF-16LE", toRaw = TRUE)[[1L]]) / 2 > 32767) fail("text exceeds Excel's cell limit")
      # Escape literal OOXML escape sequences so Excel retains the submitted text.
      value <- gsub("_x([0-9A-Fa-f]{4})_", "_x005F_x\\1_", value)
      return(list(type = "inlineStr", value = value))
    }
    if (type == "boolean") return(list(type = "b", value = as.character(as.integer(value))))
    encoded <- list(type = "n", value = sprintf("%.17g", value))
    if (type %in% c("date", "datetime")) encoded$style <- if (type == "date") "0" else "1"
    encoded
  })
}
