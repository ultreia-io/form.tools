#' Locate the installed survey example and its empty template
#' @return Paths and the checked model supplied by form.model.
survey_example <- function() {
  # Resolve one filename from the installed example directory.
  resource <- function(name) form.model::form_resource(paste0('examples/', name), 'form.model')
  list(source = resource('survey.xlsx'), template = resource('survey-empty.xlsx'),
       model = form.model::read_form_model(resource('survey-form.yaml')))
}

#' Read example records independently of the splitter
#' @param path Workbook filename.
#' @param sheet Worksheet name.
#' @param columns Number of model columns to read.
#' @return A character data frame with entirely empty rows removed.
example_records <- function(path, sheet = 'Observations', columns = 11L) {
  records <- as.data.frame(readxl::read_excel(path, sheet = sheet,
    range = paste0('A6:', LETTERS[[columns]], '20'),
    col_names = FALSE, col_types = 'text', .name_repair = 'minimal'))
  if (!ncol(records)) records <- as.data.frame(rep(list(character()), columns))
  names(records) <- paste0('V', seq_len(columns))
  records <- records[rowSums(!is.na(records)) > 0, , drop = FALSE]
  rownames(records) <- NULL
  records
}

#' Read one archive part without using workbook implementation helpers
#' @param path Workbook filename.
#' @param part Relative ZIP entry name.
#' @return Raw uncompressed bytes.
example_part <- function(path, part) {
  connection <- unz(path, part, open = 'rb')
  on.exit(close(connection))
  readBin(connection, 'raw', n = 10000000L)
}

#' Change existing cells in a disposable copy of the example workbook
#' @param path Workbook to copy.
#' @param sheet Physical worksheet number in the example archive.
#' @param values Named character vector mapping cell addresses to new strings.
#' @param directory Temporary parent directory for the copy.
#' @return The modified workbook path. The source workbook remains untouched.
change_example_cells <- function(path, sheet, values, directory) {
  extracted <- tempfile('parts-', tmpdir = directory)
  dir.create(extracted)
  on.exit(unlink(extracted, recursive = TRUE))
  utils::unzip(path, exdir = extracted)
  part <- file.path(extracted, sprintf('xl/worksheets/sheet%d.xml', sheet))
  document <- xml2::read_xml(part)
  for (address in names(values)) {
    cell <- xml2::xml_find_first(document, sprintf("//*[local-name()='c'][@r='%s']", address))
    xml2::xml_remove(xml2::xml_children(cell))
    xml2::xml_set_attr(cell, 't', 'inlineStr')
    xml2::xml_add_child(xml2::xml_add_child(cell, 'is'), 't', values[[address]])
  }
  xml2::write_xml(document, part)
  output <- tempfile('changed-', tmpdir = directory, fileext = '.xlsx')
  zip::zipr(output, list.files(extracted, recursive = TRUE), root = extracted, mode = 'mirror')
  output
}
