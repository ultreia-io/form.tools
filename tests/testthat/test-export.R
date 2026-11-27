test_that("export plans resolve row and field callbacks separately", {
  survey_model <- form.model::read_form_model(
    system.file("examples", "survey", "form-source.yaml", package = "form.tools"))
  survey_export <- read_form_export("examples/survey/export.yaml", "form.tools")
  row_rules <- list(each = function(inputs, context, parameters) {
    as.list(seq_len(nrow(inputs$records)))
  })
  field_rules <- list(copy = function(inputs, context, parameters) inputs$value)

  plan <- prepare_form_export(survey_model, survey_model, survey_export$source$root,
    survey_export$sheets, row_rules = row_rules, field_rules = field_rules)
  observations <- data.frame(survey = "S01", count = 3L)
  result <- run_form_export(plan, list(surveys = data.frame(id = "S01"), observations = observations))
  expect_identical(result$tables$observations, observations)
  expect_equal(nrow(result$diagnostics), 0L)

  expect_error(
    prepare_form_export(survey_model, survey_model, survey_export$source$root,
      survey_export$sheets, row_rules = list(), field_rules = c(row_rules, field_rules)),
    "observations rows: no registered row rule each", fixed = TRUE
  )
  expect_error(
    prepare_form_export(survey_model, survey_model, survey_export$source$root,
      survey_export$sheets, row_rules = c(row_rules, field_rules), field_rules = list()),
    "observations.survey: no registered field rule copy", fixed = TRUE
  )
})

test_that("missing field results follow requiredness in the target model", {
  source_model <- form.model::read_form_model(
    system.file("examples", "survey", "form-source.yaml", package = "form.tools"))
  required_definition <- form.model::form_definition(source_model)
  required_definition$sheets$observations$fields$count$mandatory <- TRUE
  required_model <- form.model::as_form_model(required_definition)
  survey_export <- read_form_export("examples/survey/export.yaml", "form.tools")
  survey_export$sheets$observations$fields$count$rule <- "read_count"
  row_rules <- list(each = function(inputs, context, parameters) {
    as.list(seq_len(nrow(inputs$records)))
  })
  source_tables <- list(
    surveys = data.frame(id = "S01"),
    observations = data.frame(survey = "S01", count = NA_integer_)
  )
  export_count <- function(target_model, callback) {
    field_rules <- list(copy = function(inputs, context, parameters) inputs$value, read_count = callback)
    plan <- prepare_form_export(source_model, target_model, survey_export$source$root,
      survey_export$sheets, row_rules = row_rules, field_rules = field_rules)
    run_form_export(plan, source_tables)
  }

  for (callback in list(function(inputs, context, parameters) inputs$value,
                        function(inputs, context, parameters) NULL)) {
    optional <- export_count(source_model, callback)
    expect_identical(optional$tables$observations$count, NA_integer_)
    expect_equal(nrow(optional$diagnostics), 0L)

    required <- export_count(required_model, callback)
    expect_identical(required$tables$observations$count, NA_integer_)
    expect_identical(required$diagnostics$field, "count")
    expect_identical(required$diagnostics$status, "missing_value")
  }

  unresolved <- export_count(source_model, function(inputs, context, parameters) {
    list(status = "unresolved", message = "Review the source value.")
  })
  expect_identical(unresolved$tables$observations$count, NA_integer_)
  expect_identical(unresolved$diagnostics$status, "unresolved")
})

test_that("field warnings keep the value and allow a complete export to be written", {
  survey_model <- form.model::read_form_model(
    system.file("examples", "survey", "form-source.yaml", package = "form.tools"))
  survey_export <- read_form_export("examples/survey/export.yaml", "form.tools")
  survey_export$sheets$surveys <- list(
    rows = list(rule = "each", inputs = list(records = list(sheet = "surveys"))),
    fields = list(id = list(rule = "copy", inputs = list(value = list(field = "id"))))
  )
  survey_export$sheets$observations$fields$count$rule <- "read_count"
  plan <- prepare_form_export(survey_model, survey_model, survey_export$source$root,
    survey_export$sheets,
    row_rules = list(each = function(inputs, context, parameters) as.list(seq_len(nrow(inputs$records)))),
    field_rules = list(
      copy = function(inputs, context, parameters) inputs$value,
      read_count = function(inputs, context, parameters) {
        list(status = "warning", value = inputs$value, message = "Review the count.",
          details = list(omitted = 1L))
      }
    )
  )
  source_tables <- list(surveys = data.frame(id = "S01"),
    observations = data.frame(survey = "S01", count = 3L))
  result <- run_form_export(plan, source_tables)
  expect_identical(result$tables$observations$count, 3L)
  expect_identical(result$diagnostics$status, "warning")
  expect_identical(result$diagnostics$details[[1L]], list(omitted = 1L))
  expect_true(result$ready_to_write)

  source_tables$observations$count <- NA_integer_
  invalid <- run_form_export(plan, source_tables)
  expect_identical(invalid$diagnostics$status, "rule_error")
  expect_false(invalid$ready_to_write)
})

test_that("row warnings keep the selection and can report an empty selection", {
  survey_model <- form.model::read_form_model(
    system.file("examples", "survey", "form-source.yaml", package = "form.tools"))
  survey_export <- read_form_export("examples/survey/export.yaml", "form.tools")
  row_rules <- list(each = function(inputs, context, parameters) {
    groups <- as.list(which(inputs$records$count > 0L))
    list(status = EXPORT_RESULT_STATUS_WARNING, groups = groups,
      message = "Some observations were skipped.", details = list(selected = length(groups)))
  })
  plan <- prepare_form_export(survey_model, survey_model, survey_export$source$root,
    survey_export$sheets, row_rules, list(copy = function(inputs, context, parameters) inputs$value))
  data <- list(surveys = data.frame(id = "S01"),
    observations = data.frame(survey = c("S01", "S01"), count = c(0L, 3L)))

  result <- run_form_export(plan, data)
  expect_identical(result$tables$observations$count, 3L)
  expect_identical(result$diagnostics$status, "warning")
  expect_identical(result$diagnostics$details[[1L]], list(selected = 1L))

  data$observations$count <- c(0L, 0L)
  result <- run_form_export(plan, data)
  expect_equal(nrow(result$tables$observations), 0L)
  expect_identical(result$diagnostics$status, "warning")
  expect_identical(result$diagnostics$details[[1L]], list(selected = 0L))
})
