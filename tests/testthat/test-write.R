writer_example <- function() {
  example <- survey_example()
  definitions <- form.model::form_sheets(example$model)
  data <- lapply(definitions, function(definition) {
    columns <- lapply(definition$fields, function(field) switch(field$type,
      string = NA_character_, email = NA_character_, boolean = NA,
      date = as.Date(NA), datetime = as.POSIXct(NA, tz = 'UTC'),
      integer = NA_integer_, NA_real_))
    frame <- as.data.frame(columns, check.names = FALSE)
    if (definition$layout$kind == 'table') frame[FALSE, , drop = FALSE] else frame
  })
  data$Metadata$submission <- '001'
  data$Metadata$date <- as.Date('2026-11-11')
  data$Metadata$comment <- '=1+1'
  data$Observations <- data.frame(station = c('001', '002', NA), count = c(2L, 3L, NA),
    length = c(1.5, 2.25, NA), unit = c('m', 'm', NA), active = c(TRUE, FALSE, NA),
    observed_at = as.POSIXct(c('2026-11-11 12:34:56', '2026-11-12 01:02:03', NA), tz = 'UTC'),
    latitude = c(-12.5, 0, NA), longitude = c(34, 0, NA),
    observation_id = c('OBS-001', 'OBS-002', NA), quality = c(1L, 2L, NA),
    observer = c('  literal  ', '_x0041_', NA), check.names = FALSE)
  list(model = example$model, template = example$template, data = data)
}

writer_xml <- function(path, part) xml2::read_xml(example_part(path, part))
writer_cell <- function(document, address) xml2::xml_find_first(document,
  paste0("//*[local-name()='c'][@r='", address, "']"))

writer_template <- function(path, directory, change, part = 'xl/workbook.xml') {
  extracted <- tempfile('writer-template-', tmpdir = directory)
  dir.create(extracted)
  utils::unzip(path, exdir = extracted)
  document <- xml2::read_xml(file.path(extracted, part))
  change(document)
  xml2::write_xml(document, file.path(extracted, part))
  output <- tempfile('template-', tmpdir = directory, fileext = '.xlsx')
  zip::zipr(output, list.files(extracted, recursive = TRUE, all.files = TRUE, no.. = TRUE),
    root = extracted, mode = 'mirror')
  output
}

test_that('writer maps names, retains literal values and preserves template parts', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'written.xlsx')
  original_hash <- tools::md5sum(example$template)
  example$data <- rev(lapply(example$data, function(frame) frame[rev(names(frame))]))
  written_path <- write_form_workbook(example$data, example$model, example$template, output)
  expect_identical(normalizePath(written_path, winslash = '/', mustWork = TRUE),
    normalizePath(output, winslash = '/', mustWork = TRUE))
  expect_identical(tools::md5sum(example$template), original_hash)
  metadata <- readxl::read_excel(output, sheet = 'Metadata', range = 'C2:C5', col_names = FALSE, col_types = 'text')
  expect_identical(metadata[[1]][c(1, 4)], c('001', '=1+1'))
  observations <- readxl::read_excel(output, sheet = 'Observations', range = 'A6:K8', col_names = FALSE)
  expect_identical(observations[[1]], c('001', '002', NA_character_))
  expect_equal(observations[[2]], c(2, 3, NA))
  expect_identical(observations[[5]], c(TRUE, FALSE, NA))
  expect_equal(observations[[6]], example$data$Observations$observed_at)
  expect_identical(observations[[11]], c('literal', '_x0041_', NA_character_))
  worksheet <- writer_xml(output, 'xl/worksheets/sheet2.xml')
  expect_length(xml2::xml_find_all(worksheet, "//*[local-name()='row'][@r='8']"), 1L)
  expect_identical(xml2::xml_text(xml2::xml_find_first(writer_cell(worksheet, 'K6'), ".//*[local-name()='t']")), '  literal  ')
  template_worksheet <- writer_xml(example$template, 'xl/worksheets/sheet2.xml')
  expect_identical(as.character(writer_cell(worksheet, 'A5')), as.character(writer_cell(template_worksheet, 'A5')))
  expect_equal(example_records(output, 'Samples', 6), example_records(example$template, 'Samples', 6))
  for (part in c('xl/theme/theme1.xml', 'xl/worksheets/sheet3.xml'))
    expect_identical(example_part(output, part), example_part(example$template, part))
})

test_that('writer uses both Excel date systems and the 1900 leap-year boundary', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  for (date1904 in c(FALSE, TRUE)) {
    template <- writer_template(example$template, directory, function(document) {
      properties <- xml2::xml_find_first(document, "//*[local-name()='workbookPr']")
      if (inherits(properties, 'xml_missing')) properties <- xml2::xml_add_child(document,
        xml2::read_xml('<workbookPr xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"/>'),
        .where = 0)
      xml2::xml_set_attr(properties, 'date1904', if (date1904) '1' else '0')
    })
    output <- file.path(directory, paste0(date1904, '.xlsx'))
    write_form_workbook(example$data, example$model, template, output)
    worksheet <- writer_xml(output, 'xl/worksheets/sheet1.xml')
    number <- as.numeric(xml2::xml_text(xml2::xml_find_first(writer_cell(worksheet, 'C3'), "./*[local-name()='v']")))
    expected <- as.numeric(example$data$Metadata$date - as.Date(if (date1904) '1904-01-01' else '1899-12-30'))
    expect_equal(number, expected)
    date_value <- readxl::read_excel(output, sheet = 'Metadata', range = 'C3', col_names = FALSE)[[1]]
    expect_equal(as.Date(date_value), example$data$Metadata$date)
  }
  for (day in c('1900-02-28', '1900-03-01')) {
    example$data$Metadata$date <- as.Date(day)
    output <- file.path(directory, paste0(day, '.xlsx'))
    write_form_workbook(example$data, example$model, example$template, output)
    document <- writer_xml(output, 'xl/worksheets/sheet1.xml')
    serial <- xml2::xml_text(xml2::xml_find_first(writer_cell(document, 'C3'), "./*[local-name()='v']"))
    expect_identical(serial, if (day == '1900-02-28') '59' else '61')
  }
})

test_that('writer refuses malformed data and never overwrites destinations', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'written.xlsx')
  expect_error(write_form_workbook(example$data[-1], example$model, example$template, output), 'modeled name')
  bad <- example$data
  names(bad$Observations)[2] <- 'unknown'
  expect_error(write_form_workbook(bad, example$model, example$template, output), 'modeled name')
  bad <- example$data
  bad$Observations$count <- c(1.5, 2, NA)
  expect_error(write_form_workbook(bad, example$model, example$template, output), 'integral')
  bad$Observations$count <- c(Inf, 2, NA)
  expect_error(write_form_workbook(bad, example$model, example$template, output), 'non-finite')
  bad <- example$data
  bad$Metadata$date <- '2026-11-11'
  expect_error(write_form_workbook(bad, example$model, example$template, output), 'representation')
  expect_false(file.exists(output))
  expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
  writeLines('existing content', output)
  expect_error(write_form_workbook(example$data, example$model, example$template, output), 'already exists')
  expect_identical(readLines(output), 'existing content')
})

test_that('unsupported templates fail without publishing a partial form', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'written.xlsx')
  populated <- change_example_cells(example$template, 2, c(A6 = 'existing'), directory)
  expect_error(write_form_workbook(example$data, example$model, populated, output), 'not empty')
  formula <- writer_template(example$template, directory, function(document) {
    cell <- writer_cell(document, 'C2')
    xml2::xml_add_child(cell, 'f', '1+1')
  }, 'xl/worksheets/sheet1.xml')
  expect_error(write_form_workbook(example$data, example$model, formula, output), 'formula')
  merged <- writer_template(example$template, directory, function(document) {
    merges <- xml2::xml_add_child(document, 'mergeCells')
    xml2::xml_add_child(merges, 'mergeCell', ref = 'A6:B6')
  }, 'xl/worksheets/sheet2.xml')
  expect_error(write_form_workbook(example$data, example$model, merged, output), 'Merged')
  expect_false(file.exists(output))
  expect_length(list.files(directory, pattern = '^\\.form-write-', all.files = TRUE), 0L)
})

test_that('writer rejects values outside Excel limits without leaving output', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'limits.xlsx')
  invalid_values <- list(
    list(sheet = 'Observations', field = 'count', value = 1e15, message = '15-digit precision'),
    list(sheet = 'Observations', field = 'length', value = .Machine$double.xmin / 2, message = 'supported range'),
    list(sheet = 'Observations', field = 'length', value = NaN, message = 'non-finite'),
    list(sheet = 'Metadata', field = 'date', value = as.Date('1899-12-31'), message = 'date outside'),
    list(sheet = 'Metadata', field = 'date', value = as.Date('2026-01-01') + 0.5, message = 'whole days'),
    list(sheet = 'Metadata', field = 'comment', value = paste0('text', intToUtf8(1)), message = 'control character'),
    list(sheet = 'Metadata', field = 'comment', value = strrep('a', 32768), message = 'cell limit'))
  for (invalid in invalid_values) {
    sheet_data <- example$data
    sheet_data[[invalid$sheet]][[invalid$field]][1] <- invalid$value
    expect_error(write_form_workbook(sheet_data, example$model, example$template, output), invalid$message)
    expect_false(file.exists(output))
  }
  expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
  example$data$Metadata$comment <- strrep('a', 32767)
  example$data$Observations$count[1] <- 999999999999999
  write_form_workbook(example$data, example$model, example$template, output)
  worksheet <- writer_xml(output, 'xl/worksheets/sheet1.xml')
  expect_identical(nchar(xml2::xml_text(writer_cell(worksheet, 'C5'))), 32767L)
  observation_values <- readxl::read_excel(output, sheet = 'Observations', range = 'B6',
    col_names = FALSE, .name_repair = 'minimal')
  expect_identical(observation_values[[1]][1], 999999999999999)
})

test_that('failed publication removes staging files and preserves the template', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'unpublished.xlsx')
  original_hash <- tools::md5sum(example$template)
  local_mocked_bindings(file.link = function(from, to) FALSE, .package = 'base')
  expect_error(write_form_workbook(example$data, example$model, example$template, output),
    'Cannot publish workbook without overwriting')
  expect_false(file.exists(output))
  expect_length(list.files(directory, all.files = TRUE, no.. = TRUE), 0L)
  expect_identical(tools::md5sum(example$template), original_hash)
})

test_that('publication refuses a destination created while the workbook is prepared', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'concurrent.xlsx')
  local_mocked_bindings(file.link = function(from, to) {
    writeLines('another writer owns this file', to)
    FALSE
  }, .package = 'base')
  expect_error(write_form_workbook(example$data, example$model, example$template, output),
    'Cannot publish workbook without overwriting')
  expect_identical(readLines(output), 'another writer owns this file')
  expect_identical(list.files(directory, all.files = TRUE, no.. = TRUE), 'concurrent.xlsx')
})

test_that('new rows inherit formatting and extend standard worksheet ranges', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  template <- writer_template(example$template, directory, function(document) {
    sheet_data <- xml2::xml_find_first(document, "//*[local-name()='sheetData']")
    prototype <- xml2::xml_find_first(sheet_data, "./*[local-name()='row'][@r='6']")
    if (inherits(prototype, 'xml_missing')) prototype <- xml2::xml_add_child(sheet_data, 'row', r = '6')
    xml2::xml_set_attr(prototype, 'ht', '27')
    xml2::xml_set_attr(prototype, 'customHeight', '1')
    prototype_cell <- writer_cell(document, 'A6')
    if (inherits(prototype_cell, 'xml_missing')) prototype_cell <- xml2::xml_add_child(prototype, 'c', r = 'A6')
    xml2::xml_set_attr(prototype_cell, 's', '0')
    validations <- xml2::xml_find_first(document, "//*[local-name()='dataValidations']")
    if (inherits(validations, 'xml_missing')) validations <- xml2::xml_add_child(document, 'dataValidations')
    validation <- xml2::xml_add_child(validations, 'dataValidation', type = 'list', sqref = 'A6:A6')
    xml2::xml_set_attr(validations, 'count', as.character(length(xml2::xml_children(validations))))
    xml2::xml_add_child(validation, 'formula1', '"001,002"')
    conditional <- xml2::xml_add_child(document, 'conditionalFormatting', sqref = 'B6:B6')
    rule <- xml2::xml_add_child(conditional, 'cfRule', type = 'expression', priority = '1')
    xml2::xml_add_child(rule, 'formula', 'B6>0')
    xml2::xml_add_child(document, 'autoFilter', ref = 'A5:K6')
  }, 'xl/worksheets/sheet2.xml')
  output <- file.path(directory, 'styled.xlsx')
  write_form_workbook(example$data, example$model, template, output)
  worksheet <- writer_xml(output, 'xl/worksheets/sheet2.xml')
  new_row <- xml2::xml_find_first(worksheet, "//*[local-name()='row'][@r='7']")
  expect_identical(xml2::xml_attr(new_row, 'ht'), '27')
  expect_identical(xml2::xml_attr(new_row, 'customHeight'), '1')
  expect_identical(xml2::xml_attr(writer_cell(worksheet, 'A7'), 's'), '0')
  expect_identical(xml2::xml_attr(xml2::xml_find_first(worksheet,
    "//*[local-name()='dataValidation'][starts-with(@sqref, 'A6:')]"), 'sqref'), 'A6:A8')
  expect_identical(xml2::xml_attr(xml2::xml_find_first(worksheet,
    "//*[local-name()='conditionalFormatting']"), 'sqref'), 'B6:B8')
  expect_identical(xml2::xml_attr(xml2::xml_find_first(worksheet,
    "//*[local-name()='autoFilter']"), 'ref'), 'A5:K8')
  expect_identical(xml2::xml_text(xml2::xml_find_first(worksheet,
    "//*[local-name()='dataValidation'][starts-with(@sqref, 'A6:')]/*[local-name()='formula1']")), '"001,002"')
})

test_that('date writing creates and registers styles when the template has none', {
  example <- writer_example()
  directory <- withr::local_tempdir()
  extracted <- file.path(directory, 'template-parts')
  utils::unzip(example$template, exdir = extracted)
  unlink(file.path(extracted, 'xl/styles.xml'))
  for (part in list.files(file.path(extracted, 'xl/worksheets'), pattern = '[.]xml$', full.names = TRUE)) {
    worksheet <- xml2::read_xml(part)
    xml2::xml_set_attr(xml2::xml_find_all(worksheet, "//*[local-name()='c']"), 's', NULL)
    xml2::write_xml(worksheet, part)
  }
  relationships_path <- file.path(extracted, 'xl/_rels/workbook.xml.rels')
  relationships <- xml2::read_xml(relationships_path)
  xml2::xml_remove(xml2::xml_find_all(relationships, "//*[@Target='styles.xml' or @Target='/xl/styles.xml']"))
  xml2::write_xml(relationships, relationships_path)
  content_types_path <- file.path(extracted, '[Content_Types].xml')
  content_types <- xml2::read_xml(content_types_path)
  xml2::xml_remove(xml2::xml_find_all(content_types, "//*[@PartName='/xl/styles.xml']"))
  xml2::write_xml(content_types, content_types_path)
  template <- file.path(directory, 'unstyled.xlsx')
  zip::zipr(template, list.files(extracted, recursive = TRUE, all.files = TRUE, no.. = TRUE),
    root = extracted, mode = 'mirror')
  output <- file.path(directory, 'styled.xlsx')
  write_form_workbook(example$data, example$model, template, output)
  expect_true('xl/styles.xml' %in% utils::unzip(output, list = TRUE)$Name)
  output_relationships <- writer_xml(output, 'xl/_rels/workbook.xml.rels')
  expect_length(xml2::xml_find_all(output_relationships, "//*[@Target='styles.xml']"), 1L)
  output_content_types <- writer_xml(output, '[Content_Types].xml')
  expect_length(xml2::xml_find_all(output_content_types, "//*[@PartName='/xl/styles.xml']"), 1L)
  written_date <- readxl::read_excel(output, sheet = 'Metadata', range = 'C3',
    col_names = FALSE, .name_repair = 'minimal')[[1]]
  expect_identical(as.Date(written_date), example$data$Metadata$date)
})
