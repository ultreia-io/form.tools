test_that('survey observations split by their complete composite primary key', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  before <- tools::md5sum(c(example$source, example$template))
  outputs <- split_form_workbook(example$source, example$model, 'Observations', example$template,
    file.path(directory, 'split'), shared_sheets = 'Equipment')

  expect_identical(basename(outputs$file),
    c('survey_ST01_OBS-001.xlsx', 'survey_ST02_OBS-001.xlsx', 'survey_ST01_OBS-002.xlsx'))
  expect_equal(outputs$source_row, c(6, 8, 9))
  expect_identical(outputs$key.station, c('ST01', 'ST02', 'ST01'))
  expect_identical(outputs$key.observation_id, c('OBS-001', 'OBS-001', 'OBS-002'))

  observations <- example_records(example$source)
  samples <- example_records(example$source, 'Samples', 6)
  measurements <- example_records(example$source, 'Measurements', 5)
  equipment <- example_records(example$source, 'Equipment', 3)
  sample_rows <- list(c(1L, 3L), 2L, integer())
  measurement_rows <- list(c(1L, 3L, 4L), 2L, integer())
  metadata <- readxl::read_excel(example$source, sheet = 'Metadata', range = 'C2:C5',
    col_names = FALSE, col_types = 'text', .name_repair = 'minimal')
  expect_identical(metadata[[1]][[1]], '001')
  for (i in seq_len(3)) {
    expected <- observations[i, , drop = FALSE]; rownames(expected) <- NULL
    expect_equal(example_records(outputs$file[[i]]), expected)
    children <- samples[sample_rows[[i]], , drop = FALSE]; rownames(children) <- NULL
    grandchildren <- measurements[measurement_rows[[i]], , drop = FALSE]; rownames(grandchildren) <- NULL
    expect_equal(example_records(outputs$file[[i]], 'Samples', 6), children)
    expect_equal(example_records(outputs$file[[i]], 'Measurements', 5), grandchildren)
    expect_equal(example_records(outputs$file[[i]], 'Equipment', 3), equipment)
    expect_equal(readxl::read_excel(outputs$file[[i]], sheet = 'Metadata', range = 'C2:C5',
      col_names = FALSE, col_types = 'text', .name_repair = 'minimal'), metadata)
    expect_identical(example_part(outputs$file[[i]], 'xl/styles.xml'), example_part(example$template, 'xl/styles.xml'))
    expect_identical(example_part(outputs$file[[i]], 'xl/worksheets/sheet3.xml'),
      example_part(example$template, 'xl/worksheets/sheet3.xml'))
  }
  expect_identical(tools::md5sum(c(example$source, example$template)), before)
  expect_equal(readxl::read_excel(outputs$file[[2]], sheet = 'Observations', range = 'B6:C6',
    col_names = FALSE, .name_repair = 'minimal')[[1]], 0)
  expect_identical(readxl::read_excel(outputs$file[[2]], sheet = 'Observations', range = 'E6',
    col_names = FALSE, .name_repair = 'minimal')[[1]], FALSE)

  template <- xml2::read_xml(example_part(example$template, 'xl/worksheets/sheet2.xml'))
  output <- xml2::read_xml(example_part(outputs$file[[1]], 'xl/worksheets/sheet2.xml'))
  expect_identical(xml2::xml_attr(xml2::xml_find_first(output, "//*[local-name()='c'][@r='C6']"), 's'),
    xml2::xml_attr(xml2::xml_find_first(template, "//*[local-name()='c'][@r='C6']"), 's'))
  expect_identical(xml2::xml_attr(xml2::xml_find_first(output, "//*[local-name()='dataValidation']"), 'sqref'), 'D6')
})

test_that('missing and duplicate survey keys are rejected before publishing', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  duplicate <- change_example_cells(example$source, 2, c(A8 = 'ST01'), directory)
  missing <- change_example_cells(example$source, 2, c(I6 = ''), directory)
  for (case in list(list(path = duplicate, message = 'Duplicate primary keys'),
                   list(path = missing, message = 'Missing key component'))) {
    output <- file.path(directory, 'split')
    expect_error(split_form_workbook(case$path, example$model, 'Observations', example$template, output, 'Equipment'), case$message)
    expect_false(dir.exists(output))
  }
})

test_that('different keys cannot overwrite each other after filename sanitization', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  source <- change_example_cells(example$source, 2, c(A6 = 'ST/01', A8 = 'ST:01'), directory)
  source <- change_example_cells(source, 4, c(A6 = 'ST/01', A7 = 'ST:01', A9 = 'ST/01'), directory)
  source <- change_example_cells(source, 5, c(A6 = 'ST/01', A7 = 'ST:01', A8 = 'ST/01', A9 = 'ST/01'), directory)
  output <- file.path(directory, 'split')
  expect_error(split_form_workbook(source, example$model, 'Observations', example$template, output, 'Equipment'),
    'duplicate output filenames after sanitization')
  expect_false(dir.exists(output))
})

test_that('a populated survey template cannot silently add records', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'split')
  expect_error(split_form_workbook(example$source, example$model, 'Observations', example$source, output, 'Equipment'),
    'Template data region is not empty')
  expect_false(dir.exists(output))
})

test_that('existing output files and directories are never overwritten', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  sentinel <- file.path(directory, 'keep.txt')
  writeLines('retain this file', sentinel)
  for (output in c(directory, sentinel)) {
    expect_error(split_form_workbook(example$source, example$model, 'Observations', example$template, output, 'Equipment'),
      'Output directory already exists')
    expect_identical(readLines(sentinel), 'retain this file')
  }
})


test_that('independent tables must be declared shared', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  output <- file.path(directory, 'split')
  expect_error(split_form_workbook(example$source, example$model, 'Observations', example$template, output),
    'shared_sheets: Equipment')
  expect_false(dir.exists(output))
})

test_that('orphan children are rejected before publishing', {
  example <- survey_example()
  directory <- withr::local_tempdir()
  orphan <- change_example_cells(example$source, 4, c(A6 = 'unknown'), directory)
  output <- file.path(directory, 'split')
  expect_error(split_form_workbook(orphan, example$model, 'Observations', example$template, output, 'Equipment'),
    'Missing parent keys')
  expect_false(dir.exists(output))
})
