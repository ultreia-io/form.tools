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
