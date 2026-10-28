#' Split a workbook by the primary key of a root sheet
#'
#' Produce one workbook per root record using an empty, version-matched template.
#' Child records are selected through the model's parent keys in declaration order.
#' @param path Source XLSX workbook, already structurally validated against `model`.
#' @param model A checked `form.model` model with primary and parent keys.
#' @param root_sheet Name of a table sheet with a primary key and no parent key.
#' @param template Empty XLSX template matching the exact model and source date system.
#' @param directory New output directory. An existing path is never overwritten.
#' @param shared_sheets Table sheets outside the root hierarchy to copy in full.
#'   All such tables must be explicitly listed. Fixed-cell sheets are always copied.
#' @return A data frame with `file`, `source_row`, and the root primary-key columns
#'   prefixed with `key.`. Files are returned in source root-row order.
#' @details The caller must validate structure beforehand. This operation rechecks
#'   model consistency, required sheets, data extents, key completeness, uniqueness,
#'   and parent existence. Business-rule findings do not prevent splitting.
#'
#'   Fixed-cell fields are copied to their declared locations. Tables retain source
#'   row order and are compacted from the model's start row. Empty rows are omitted.
#'   Unmodeled template sheets are retained; unmodeled source sheets are not copied.
#'   The template must have no values or formulas in modeled table data regions.
#'
#'   Existing template styles, header cells, and workbook parts are retained.
#'   Additional rows inherit the first template data row's style and height.
#'   Standard validation and conditional-formatting ranges are extended when needed.
#'   Excel tables, merged data cells, and formulas in template data rows are rejected.
#'   Source formulas contribute cached values only; Excel errors or formulas lacking
#'   a cached value in modeled fields are rejected. Formulas elsewhere in the template
#'   are retained, with recalculation requested on opening in Excel. R does not
#'   recalculate formulas. Fixed print areas are not expanded.
#'
#'   Output names combine the source basename (without its XLSX extension) and
#'   root primary-key values in model order, separated by underscores, then `.xlsx`.
#'   Filename-invalid characters become underscores. Names exceeding 255 bytes
#'   and case-insensitive collisions after sanitization are rejected before writing.
#'
#'   Outputs are assembled in a temporary sibling directory, then published together.
#'   No partial output directory remains on failure. Source and template are unchanged.
#' @export
split_form_workbook <- function(path, model, root_sheet, template, directory,
                                shared_sheets = character()) {
  tool_text(root_sheet, "root_sheet")
  tool_text(directory, "directory")
  model <- form.model::as_form_model(form.model::form_definition(model))
  definitions <- form.model::form_sheets(model)
  if (!root_sheet %in% names(definitions)) stop("Unknown root sheet", call. = FALSE)
  root <- definitions[[root_sheet]]
  if (root$layout$kind != "table" || !length(root$primary_key) || !is.null(root$parent_key))
    stop("Root must be a table with a primary key and no parent key", call. = FALSE)
  if (!is.character(shared_sheets) || anyNA(shared_sheets) || anyDuplicated(shared_sheets))
    stop("shared_sheets must contain unique table names", call. = FALSE)
  tables <- names(definitions)[vapply(definitions, function(x) x$layout$kind == "table", logical(1))]
  hierarchy <- root_sheet
  for (name in tables) {
    parent <- definitions[[name]]$parent_key
    if (!is.null(parent) && parent$sheet %in% hierarchy) hierarchy <- c(hierarchy, name)
  }
  if (!setequal(shared_sheets, setdiff(tables, hierarchy)))
    stop("Explicitly list every table outside the root hierarchy in shared_sheets: ",
         paste(setdiff(tables, hierarchy), collapse = ", "), call. = FALSE)
  if (file.exists(directory) || dir.exists(directory)) stop("Output directory already exists", call. = FALSE)
  parent_directory <- normalizePath(dirname(directory), mustWork = TRUE)
  directory <- file.path(parent_directory, basename(directory))
  workspace <- tempfile("form-tools-")
  dir.create(workspace)
  on.exit(unlink(workspace, recursive = TRUE), add = TRUE)
  source <- xlsx_read(path, file.path(workspace, "source"))
  blank <- xlsx_read(template, file.path(workspace, "template"))
  if (!identical(source$date1904, blank$date1904))
    stop("Source and template must use the same Excel date system", call. = FALSE)
  data <- lapply(names(definitions), function(name) xlsx_sheet(source, name))
  names(data) <- names(definitions)
  patterns <- lapply(names(definitions), function(name) xlsx_sheet(blank, name))
  names(patterns) <- names(definitions)
  rows <- keys <- parent_rows <- list()
  for (name in names(definitions)) {
    definition <- definitions[[name]]
    sheet <- data[[name]]
    layout <- definition$layout
    occupied <- !vapply(sheet$values, xlsx_blank, logical(1)) | sheet$formulas
    if (any(occupied & sheet$column > layout$column_count))
      stop("Data outside declared columns in ", name, call. = FALSE)
    if (!is.null(layout$row_count) && any(occupied & sheet$row > layout$row_count))
      stop("Data outside declared rows in ", name, call. = FALSE)
    if (layout$kind == "table") {
      selected <- sheet$row >= layout$start_row & sheet$column <= layout$column_count
      rows[[name]] <- sort(unique(sheet$row[selected & occupied]))
      check_template_table(patterns[[name]], definition, name)
      key_columns <- match(unlist(definition$primary_key), names(definition$fields))
      if (length(key_columns)) {
        keys[[name]] <- xlsx_key(sheet, rows[[name]], key_columns, name)
        if (anyDuplicated(keys[[name]])) stop("Duplicate primary keys in ", name, call. = FALSE)
      }
      if (!is.null(definition$parent_key)) {
        parent <- definition$parent_key
        child <- xlsx_key(sheet, rows[[name]], match(unlist(parent$fields), names(definition$fields)), name)
        if (any(!child %in% keys[[parent$sheet]])) stop("Missing parent keys in ", name, call. = FALSE)
        parent_rows[[name]] <- rows[[parent$sheet]][match(child, keys[[parent$sheet]])]
      }
    } else selected <- sheet$addresses %in% vapply(definition$fields, `[[`, character(1), "location")
    for (i in which(selected)) {
      value <- sheet$values[[i]]
      if ((!is.null(value) && !value$type %in% c("n", "b", "d", "inlineStr")) ||
          (sheet$formulas[[i]] && is.null(value)))
        stop("Unsupported or uncached value in ", name, "!", sheet$addresses[[i]], call. = FALSE)
    }
  }
  root_rows <- rows[[root_sheet]]
  count <- length(root_rows)
  if (!count) stop("Root sheet has no records", call. = FALSE)
  prefix <- sub("[.]xlsx$", "", basename(source$path), ignore.case = TRUE)
  key_columns <- match(unlist(root$primary_key), names(root$fields))
  output_names <- vapply(root_rows, function(row) {
    components <- vapply(key_columns, function(column) {
      xlsx_value(data[[root_sheet]], row, column)$value
    }, character(1))
    stem <- paste(c(prefix, components), collapse = "_")
    stem <- gsub('[<>:"/\\\\|?*[:cntrl:]]', "_", stem)
    stem <- sub("[. ]+$", "_", stem)
    if (grepl("^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])([.]|$)", stem, ignore.case = TRUE))
      stem <- paste0("_", stem)
    paste0(stem, ".xlsx")
  }, character(1), USE.NAMES = FALSE)
  if (any(nchar(output_names, type = "bytes") > 255L))
    stop("Source filename and primary key produce a filename longer than 255 bytes", call. = FALSE)
  if (anyDuplicated(tolower(output_names)))
    stop("Primary keys produce duplicate output filenames after sanitization", call. = FALSE)
  stage <- tempfile(".form-tools-", tmpdir = parent_directory)
  dir.create(stage)
  on.exit(unlink(stage, recursive = TRUE), add = TRUE)
  for (i in seq_len(count)) {
    chosen <- rows
    chosen[[root_sheet]] <- root_rows[[i]]
    for (name in setdiff(hierarchy, root_sheet)) {
      definition <- definitions[[name]]
      parent <- definition$parent_key
      chosen[[name]] <- rows[[name]][parent_rows[[name]] %in% chosen[[parent$sheet]]]
    }
    output <- file.path(workspace, "output")
    dir.create(output)
    for (entry in list.files(blank$directory, all.files = TRUE, no.. = TRUE)) {
      if (!file.copy(file.path(blank$directory, entry), output, recursive = TRUE))
        stop("Cannot copy template", call. = FALSE)
    }
    for (name in names(definitions)) {
      write_split_sheet(data[[name]], patterns[[name]], definitions[[name]], chosen[[name]],
                        file.path(output, blank$parts[[name]]))
    }
    request_workbook_calculation(file.path(output, "xl/workbook.xml"))
    zip::zipr(file.path(stage, output_names[[i]]),
      list.files(output, recursive = TRUE, all.files = TRUE, no.. = TRUE),
      root = output, mode = "mirror", include_directories = FALSE)
    unlink(output, recursive = TRUE)
  }
  if (file.exists(directory) || !file.rename(stage, directory))
    stop("Cannot publish output directory", call. = FALSE)
  result <- data.frame(file = file.path(directory, output_names), source_row = root_rows,
                       stringsAsFactors = FALSE)
  for (key in unlist(root$primary_key)) {
    column <- match(key, names(root$fields))
    result[[paste0("key.", key)]] <- vapply(root_rows,
      function(row) xlsx_value(data[[root_sheet]], row, column)$value, character(1))
  }
  result
}
