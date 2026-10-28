# Internal XLSX reading and template population preserve supporting workbook parts.

#' Validate a required text argument
#' @param value Candidate scalar character value; missing or empty text is rejected.
#' @param name Argument name used in the error message.
#' @return The unchanged string. Invalid arguments raise an error.
#' @keywords internal
tool_text <- function(value, name) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value))
    stop(name, " must be a non-empty string", call. = FALSE)
  value
}

#' Find direct XML children by local name
#' @param node XML node or document to inspect.
#' @param name Local element name, supplied by internal callers.
#' @return An XML node set, possibly empty. Namespace prefixes are ignored.
#' @keywords internal
xlsx_nodes <- function(node, name) {
  xml2::xml_find_all(node, paste0("./*[local-name()='", name, "']"), ns = character())
}

#' Find the first direct XML child by local name
#' @param node XML node or document to inspect.
#' @param name Local element name, supplied by internal callers.
#' @return The first matching XML node, or an `xml_missing` node.
#' @keywords internal
xlsx_one <- function(node, name) {
  xml2::xml_find_first(node, paste0("./*[local-name()='", name, "']"), ns = character())
}

#' Decode worksheet cell addresses
#' @param address Character vector of uppercase A1 addresses without dollar signs.
#' @return A list of numeric `row` and `column` vectors in input order.
#'   Invalid addresses and coordinates beyond XLSX limits raise an error.
#' @keywords internal
xlsx_address <- function(address) {
  if (anyNA(address) || any(!grepl("^[A-Z]+[1-9][0-9]*$", address)))
    stop("Invalid worksheet cell address", call. = FALSE)
  column <- vapply(strsplit(sub("[0-9]+$", "", address), ""), function(chars) {
    Reduce(function(a, b) a * 26 + match(b, LETTERS), chars, init = 0)
  }, numeric(1))
  row <- as.numeric(sub("^[A-Z]+", "", address))
  if (any(column > 16384 | row > 1048576)) stop("Cell exceeds XLSX limits", call. = FALSE)
  list(row = row, column = column)
}

#' Encode a worksheet column number
#' @param number Positive integer column index, using one-based indexing.
#' @return The uppercase Excel column letters. Callers supply a valid index.
#' @keywords internal
xlsx_column <- function(number) {
  result <- ""
  while (number > 0) {
    result <- paste0(LETTERS[(number - 1) %% 26 + 1], result)
    number <- (number - 1) %/% 26
  }
  result
}

#' Extract an XLSX workbook and resolve its worksheet parts
#' @param path Path to an existing XLSX file.
#' @param directory Temporary extraction directory owned and cleaned by the caller.
#' @return A list containing the normalized source `path`, extraction `directory`,
#'   named worksheet `parts`, shared `strings`, the `date1904` flag, and a `read`
#'   callback accepting a relative XML part path.
#' @details Rejects duplicate or unsafe archive paths and worksheet relationships
#'   outside the extracted workbook. XML parsing disables network access.
#'   The source archive is unchanged; extracted files remain until caller cleanup.
#' @keywords internal
xlsx_read <- function(path, directory) {
  tool_text(path, "workbook path")
  if (!file.exists(path) || dir.exists(path) || !grepl("[.]xlsx$", path, ignore.case = TRUE))
    stop("Expected an existing .xlsx file: ", path, call. = FALSE)
  path <- normalizePath(path, mustWork = TRUE)
  entries <- utils::unzip(path, list = TRUE)$Name
  if (!length(entries) || anyDuplicated(entries) ||
      any(grepl("(^/|^[A-Za-z]:|\\\\|(^|/)\\.\\.?(/|$))", entries)))
    stop("Invalid XLSX archive paths", call. = FALSE)
  utils::unzip(path, exdir = directory)
  # Read a relative extracted XML part with network access disabled.
  # Returns an XML document; parsing and missing-file errors propagate.
  read <- function(part) xml2::read_xml(file.path(directory, part), options = "NONET")
  book <- read("xl/workbook.xml")
  rels <- xlsx_nodes(read("xl/_rels/workbook.xml.rels"), "Relationship")
  sheets <- xlsx_nodes(xlsx_one(book, "sheets"), "sheet")
  sheet_names <- xml2::xml_attr(sheets, "name")
  if (anyNA(sheet_names) || anyDuplicated(sheet_names)) stop("Invalid worksheet names", call. = FALSE)
  parts <- vapply(sheets, function(sheet) {
    id <- xml2::xml_text(xml2::xml_find_first(sheet, "./@*[local-name()='id']", ns = character()))
    rel <- rels[xml2::xml_attr(rels, "Id") == id]
    if (length(rel) != 1L || identical(xml2::xml_attr(rel, "TargetMode"), "External"))
      stop("Invalid worksheet relationship", call. = FALSE)
    target <- xml2::xml_attr(rel, "Target")
    part <- if (startsWith(target, "/")) substring(target, 2) else paste0("xl/", target)
    full <- normalizePath(file.path(directory, part), winslash = "/", mustWork = TRUE)
    root <- paste0(normalizePath(directory, winslash = "/", mustWork = TRUE), "/")
    if (!startsWith(full, root)) stop("Worksheet outside workbook", call. = FALSE)
    substring(full, nchar(root) + 1L)
  }, character(1))
  names(parts) <- sheet_names
  strings <- character()
  if (file.exists(file.path(directory, "xl/sharedStrings.xml"))) {
    strings <- vapply(xlsx_nodes(read("xl/sharedStrings.xml"), "si"), function(si) {
      paste0(xml2::xml_text(xml2::xml_find_all(si,
        "./*[local-name()='t'] | ./*[local-name()='r']/*[local-name()='t']", ns = character())), collapse = "")
    }, character(1))
  }
  date1904 <- xml2::xml_attr(xlsx_one(book, "workbookPr"), "date1904", default = "0")
  list(path = path, directory = directory, parts = parts, strings = strings,
       date1904 = date1904 %in% c("1", "true"), read = read)
}

#' Read worksheet cells and cached values
#' @param book Workbook descriptor returned by [xlsx_read()].
#' @param name Exact worksheet name in the workbook.
#' @return A list with the XML `document`, `cells`, `addresses`, numeric `row` and
#'   `column` positions, named `values`, a hashed `lookup` environment, and logical
#'   `formulas` flags. Each value is `NULL` or a list with `type` and `value` strings.
#' @details Shared strings and cached string results become inline-string values.
#'   Formulas are not evaluated. Duplicate addresses and invalid shared-string
#'   indexes raise errors; unsupported value types are checked by the caller.
#' @keywords internal
xlsx_sheet <- function(book, name) {
  if (!name %in% names(book$parts)) stop("Missing worksheet: ", name, call. = FALSE)
  document <- book$read(book$parts[[name]])
  cells <- xml2::xml_find_all(document,
    "/*[local-name()='worksheet']/*[local-name()='sheetData']/*[local-name()='row']/*[local-name()='c']", ns = character())
  addresses <- xml2::xml_attr(cells, "r")
  if (anyDuplicated(addresses)) stop("Duplicate cell addresses in ", name, call. = FALSE)
  positions <- xlsx_address(addresses)
  values <- lapply(cells, function(cell) {
    type <- xml2::xml_attr(cell, "t", default = "n")
    value <- xlsx_one(cell, "v")
    if (type == "inlineStr") {
      value <- paste0(xml2::xml_text(xml2::xml_find_all(cell,
        "./*[local-name()='is']/*[local-name()='t'] | ./*[local-name()='is']/*[local-name()='r']/*[local-name()='t']", ns = character())), collapse = "")
      return(list(type = "inlineStr", value = value))
    }
    if (inherits(value, "xml_missing")) return(NULL)
    value <- xml2::xml_text(value)
    if (type == "s") {
      index <- suppressWarnings(as.integer(value)) + 1L
      if (is.na(index) || index < 1L || index > length(book$strings))
        stop("Invalid shared string in ", name, call. = FALSE)
      value <- book$strings[[index]]
      type <- "inlineStr"
    }
    if (type == "str") type <- "inlineStr"
    list(type = type, value = value)
  })
  names(values) <- addresses
  formulas <- vapply(cells, function(cell) length(xlsx_nodes(cell, "f")) > 0, logical(1))
  lookup <- new.env(hash = TRUE, parent = emptyenv())
  if (length(values)) list2env(values, envir = lookup)
  list(document = document, cells = cells, addresses = addresses,
       row = positions$row, column = positions$column, values = values,
       lookup = lookup, formulas = formulas)
}

#' Recognize an absent or empty cell value
#' @param value `NULL` or a cell-value list containing a scalar `value` string.
#' @return Whether the value is absent or the string is empty.
#'   Whitespace is retained and is not considered blank.
#' @keywords internal
xlsx_blank <- function(value) {
  is.null(value) || !nzchar(value$value)
}

#' Look up a worksheet cell value
#' @param sheet Worksheet descriptor returned by [xlsx_sheet()].
#' @param row One-based physical row number.
#' @param column One-based physical column number.
#' @return The stored cell-value list, or `NULL` when no value exists.
#' @keywords internal
xlsx_value <- function(sheet, row, column) {
  get0(paste0(xlsx_column(column), row), sheet$lookup, inherits = FALSE)
}

#' Encode complete composite keys for worksheet rows
#' @param sheet Worksheet descriptor returned by [xlsx_sheet()].
#' @param rows Physical row numbers to encode, in the requested order.
#' @param columns Physical column numbers defining the key, in component order.
#' @param label Sheet label included in diagnostics.
#' @return An unnamed character vector of byte-length-prefixed composite keys.
#' @details Missing components and nonfinite numeric keys raise errors. Numeric
#'   and Boolean components use a common 17-digit numeric representation; text is
#'   retained verbatim. Length prefixes distinguish component boundaries.
#' @keywords internal
xlsx_key <- function(sheet, rows, columns, label) {
  vapply(rows, function(row) {
    components <- vapply(columns, function(column) {
      value <- xlsx_value(sheet, row, column)
      if (xlsx_blank(value)) stop("Missing key component in ", label, " at row ", row, call. = FALSE)
      if (value$type %in% c("n", "b")) {
        number <- suppressWarnings(as.numeric(value$value))
        if (!is.finite(number)) stop("Invalid numeric key in ", label, call. = FALSE)
        text <- sprintf("%.17g", number)
      } else text <- value$value
      paste0(nchar(text, type = "bytes"), ":", text)
    }, character(1))
    paste0(components, collapse = "")
  }, character(1), USE.NAMES = FALSE)
}

# Template population preserves cell styles and untouched XLSX parts.

#' Request formula recalculation when Excel opens a workbook
#' @param path Path to the extracted `xl/workbook.xml` part to update in place.
#' @return The invisible result of [xml2::write_xml()].
#' @details Creates or updates `calcPr` with automatic calculation and full
#'   recalculation flags. This function does not calculate formulas in R.
#' @keywords internal
request_workbook_calculation <- function(path) {
  document <- xml2::read_xml(path, options = "NONET")
  properties <- xlsx_one(document, "calcPr")
  if (inherits(properties, "xml_missing")) {
    # calcPr follows definedNames and precedes these optional workbook elements.
    following <- xml2::xml_find_first(document,
      "./*[local-name()='oleSize' or local-name()='customWorkbookViews' or local-name()='pivotCaches' or local-name()='smartTagPr' or local-name()='smartTagTypes' or local-name()='webPublishing' or local-name()='fileRecoveryPr' or local-name()='webPublishObjects' or local-name()='extLst'][1]", ns = character())
    if (inherits(following, "xml_missing")) properties <- xml2::xml_add_child(document, "calcPr")
    else properties <- xml2::xml_add_sibling(following, "calcPr", .where = "before")
  }
  xml2::xml_set_attr(properties, "fullCalcOnLoad", "1")
  xml2::xml_set_attr(properties, "forceFullCalc", "1")
  xml2::xml_set_attr(properties, "calcMode", "auto")
  xml2::write_xml(document, path)
}

#' Check that a template table can receive split records
#' @param sheet Template worksheet descriptor returned by [xlsx_sheet()].
#' @param definition Model sheet definition with a table layout and start row.
#' @param name Worksheet name used in diagnostics.
#' @return No useful value. Raises an error for populated data rows, formulas,
#'   Excel tables, or merged ranges reaching the data region.
#' @details Styled empty cells are permitted. The worksheet is not modified.
#' @keywords internal
check_template_table <- function(sheet, definition, name) {
  start <- definition$layout$start_row
  data <- sheet$row >= start
  if (any(data & (!vapply(sheet$values, xlsx_blank, logical(1)) | sheet$formulas)))
    stop("Template data region is not empty in ", name, call. = FALSE)
  if (length(xlsx_nodes(sheet$document, "tableParts")))
    stop("Excel tables are not supported in template sheet ", name, call. = FALSE)
  merged <- xml2::xml_attr(xml2::xml_find_all(sheet$document,
    "./*[local-name()='mergeCells']/*[local-name()='mergeCell']", ns = character()), "ref")
  if (length(merged) && any(vapply(strsplit(merged, ":", fixed = TRUE), function(range) {
    max(xlsx_address(range)$row) >= start
  }, logical(1)))) stop("Merged data cells are not supported in ", name, call. = FALSE)
}

#' Replace a cell payload while retaining its formatting
#' @param cell XML cell node to modify in place.
#' @param value `NULL` or a supported cell-value list with `type` and `value`.
#' @return Invisible `NULL`.
#' @details Removes existing value, inline-string and formula children and the
#'   old type attribute. Blank values leave a styled empty cell. Inline strings
#'   preserve whitespace; other values are written with their supplied type.
#' @keywords internal
write_cell_value <- function(cell, value) {
  xml2::xml_remove(xml2::xml_find_all(cell,
    "./*[local-name()='v' or local-name()='is' or local-name()='f']", ns = character()))
  xml2::xml_set_attr(cell, "t", NULL)
  if (xlsx_blank(value)) return(invisible(NULL))
  xml2::xml_set_attr(cell, "t", value$type)
  if (value$type == "inlineStr") {
    inline <- xml2::xml_add_child(cell, "is")
    text <- xml2::xml_add_child(inline, "t", value$value)
    xml2::xml_set_attr(text, "xml:space", "preserve")
  } else xml2::xml_add_child(cell, "v", value$value)
  invisible(NULL)
}

#' Extend standard worksheet ranges to cover added rows
#' @param document Worksheet XML document to modify in place.
#' @param start First model data row.
#' @param last Last output data row; may precede `start` when no rows are selected.
#' @param columns Number of modeled columns, starting at column A.
#' @return No useful value; matching range attributes are updated in place.
#' @details Extends standard validation, conditional-formatting and autofilter
#'   ranges overlapping the data boundary. Existing longer ranges are retained.
#'   Unsupported range syntax, extended Excel elements and print areas are unchanged.
#' @keywords internal
extend_sheet_ranges <- function(document, start, last, columns) {
  ranges <- xml2::xml_find_all(document,
    "./*[local-name()='dataValidations']/*[local-name()='dataValidation']/@sqref | ./*[local-name()='conditionalFormatting']/@sqref | ./*[local-name()='autoFilter']/@ref", ns = character())
  for (attribute in ranges) {
    value <- xml2::xml_text(attribute)
    parts <- strsplit(value, " +")[[1]]
    updated <- vapply(parts, function(part) {
      bounds <- strsplit(gsub("$", "", part, fixed = TRUE), ":", fixed = TRUE)[[1]]
      if (!all(grepl("^[A-Z]+[1-9][0-9]*$", bounds))) return(part)
      position <- xlsx_address(bounds)
      is_filter <- xml2::xml_name(xml2::xml_parent(attribute)) == "autoFilter"
      if (min(position$column) > columns || max(position$row) < start - as.integer(is_filter) ||
          min(position$row) > start || max(position$row) >= last) return(part)
      paste0(bounds[[1]], ":", xlsx_column(max(position$column)), last)
    }, character(1))
    xml2::xml_set_attr(xml2::xml_parent(attribute), xml2::xml_name(attribute), paste(updated, collapse = " "))
  }
}

#' Populate a copy of a template worksheet
#' @param source Source worksheet descriptor returned by [xlsx_sheet()].
#' @param pattern Empty template worksheet descriptor returned by [xlsx_sheet()].
#' @param definition Model sheet definition with fields and physical layout.
#' @param rows Selected physical source rows for table layouts; unused for fixed cells.
#' @param destination Path of the extracted worksheet XML part to write.
#' @return The invisible result of [xml2::write_xml()].
#' @details Copies fixed fields or compacts selected table records from the model
#'   start row. New rows inherit the first template data row where available.
#'   Existing styles are retained, standard ranges are extended, and the sheet
#'   dimension is updated. Source and template descriptors are not modified.
#'   Formula-bearing fixed template fields and excessive output extents raise errors.
#' @keywords internal
write_split_sheet <- function(source, pattern, definition, rows, destination) {
  document <- xml2::read_xml(as.character(pattern$document), options = "NONET")
  sheet_data <- xlsx_one(document, "sheetData")
  if (inherits(sheet_data, "xml_missing")) stop("Template worksheet has no sheetData", call. = FALSE)
  existing <- xlsx_nodes(sheet_data, "row")
  row_numbers <- as.integer(xml2::xml_attr(existing, "r"))
  if (anyNA(row_numbers) || anyDuplicated(row_numbers)) stop("Invalid template rows", call. = FALSE)
  # Keep lookups local to this output; never mutate the reusable template tree.
  row_cache <- new.env(parent = emptyenv())
  for (i in seq_along(existing)) row_cache[[as.character(row_numbers[[i]])]] <- existing[[i]]
  prototype <- NULL
  if (definition$layout$kind == "table") {
    template_rows <- xlsx_nodes(xlsx_one(pattern$document, "sheetData"), "row")
    index <- match(as.character(definition$layout$start_row), xml2::xml_attr(template_rows, "r"))
    if (!is.na(index)) prototype <- template_rows[[index]]
  }
  # Return the output XML row at the one-based number, creating it in order.
  # Clone the template prototype when present; update row_cache and row_numbers.
  get_row <- function(number) {
    key <- as.character(number)
    if (exists(key, row_cache, inherits = FALSE)) return(row_cache[[key]])
    # Existing template rows are usually a prefix. Insert before the next row if needed.
    after <- which(row_numbers > number)
    node <- if (is.null(prototype)) xml2::read_xml(paste0('<row r="', number, '"/>')) else prototype
    if (length(after)) {
      next_row <- min(row_numbers[after])
      result <- xml2::xml_add_sibling(row_cache[[as.character(next_row)]], node, .where = "before")
    } else result <- xml2::xml_add_child(sheet_data, node)
    xml2::xml_set_attr(result, "r", key)
    for (cell in xlsx_nodes(result, "c")) {
      address <- xml2::xml_attr(cell, "r")
      xml2::xml_set_attr(cell, "r", paste0(sub("[0-9]+$", "", address), key))
    }
    row_cache[[key]] <- result
    row_numbers <<- c(row_numbers, number)
    result
  }
  # Write a cell-value list at one-based coordinates, inserting a cell in order.
  # Mutates the output XML tree and returns invisible NULL through write_cell_value.
  put <- function(row, column, value) {
    node <- get_row(row)
    address <- paste0(xlsx_column(column), row)
    cells <- xlsx_nodes(node, "c")
    addresses <- xml2::xml_attr(cells, "r")
    index <- match(address, addresses)
    if (is.na(index)) {
      later <- which(xlsx_address(addresses)$column > column)
      cell <- xml2::read_xml(paste0('<c r="', address, '"/>'))
      if (length(later)) cell <- xml2::xml_add_sibling(cells[[later[[1]]]], cell, .where = "before")
      else cell <- xml2::xml_add_child(node, cell)
    } else cell <- cells[[index]]
    write_cell_value(cell, value)
  }
  if (definition$layout$kind == "cells") {
    for (field in definition$fields) {
      index <- match(field$location, pattern$addresses)
      if (!is.na(index) && pattern$formulas[[index]])
        stop("Template fixed field contains a formula: ", field$location, call. = FALSE)
      address <- xlsx_address(field$location)
      put(address$row, address$column, xlsx_value(source, address$row, address$column))
    }
  } else {
    start <- definition$layout$start_row
    last <- start + length(rows) - 1L
    if (last > 1048576 || (!is.null(definition$layout$row_count) && last > definition$layout$row_count))
      stop("Output exceeds declared worksheet extent", call. = FALSE)
    for (i in seq_along(rows)) {
      for (column in seq_along(definition$fields)) {
        value <- xlsx_value(source, rows[[i]], column)
        if (!xlsx_blank(value)) put(start + i - 1L, column, value)
      }
    }
    extend_sheet_ranges(document, start, last, length(definition$fields))
  }
  dimension <- xlsx_one(document, "dimension")
  if (!inherits(dimension, "xml_missing")) {
    cells <- xml2::xml_find_all(sheet_data, "./*[local-name()='row']/*[local-name()='c']", ns = character())
    positions <- xlsx_address(xml2::xml_attr(cells, "r"))
    if (length(cells)) xml2::xml_set_attr(dimension, "ref",
      paste0("A1:", xlsx_column(max(positions$column)), max(positions$row)))
  }
  xml2::write_xml(document, destination)
}
