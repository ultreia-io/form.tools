# Public operations ---------------------------------------------------------

#' Prepare a model-driven export plan
#'
#' Bind table and field declarations to supplied R callbacks before processing data.
#' @param source_model,target_model Checked form models from form.model.
#' @param root_sheet Name of the source table containing one selected root record.
#' @param sheets Named list of target sheet declarations. Each declaration has
#'   `rows` and `fields`, with one declaration per writable field. A fixed-cell
#'   sheet can use `fields_from` in place of `rows` and `fields` to populate one
#'   block from a named caller input section. Use `preserve_fields` to keep
#'   named template cells.
#'   Use `sheets` from [read_form_export()] or supply a subset of target sheets.
#' @param rules Named list of R functions called with `inputs`, `context` and
#'   `parameters`. Row rules receive a data frame as `inputs$records`. They
#'   return a list of integer vectors indexing that frame, one per target row.
#'   An empty list selects zero rows. Each vector can group several source rows.
#'   Field rules return a typed scalar or a list with `status`, optional `value`,
#'   `message` and `details`. Use `"resolved"` with a value or `"omitted"` for
#'   an intentional blank. Other statuses produce diagnostics.
#' @return A prepared plan for [run_form_export()].
#' @details Field declarations default to `"specified"` and use the exact
#'   target field name as the callback name when `rule` is absent. A named
#'   `rule` overrides that default. Active rules may supply named `inputs`
#'   and `parameters`. An active row declaration must name its rule and
#'   bind `records` to a source sheet. The status `"omitted"`
#'   leaves a cell blank or a table empty. The statuses `"pending"` and
#'   `"unavailable"` are reported when encountered. Inactive rules are not bound.
#'
#'   An input can name a source `sheet` and optionally a `field` or `fields`.
#'   The engine reads the current record or follows parent keys to an ancestor.
#'   Add `within` to select related records under the current record or its
#'   named ancestor. A `field` binding returns a vector; a sheet or `fields`
#'   binding returns a data frame. An `input` binding reads an exact key in the
#'   caller's input list. A binding with `model = "target"`, `sheet` and `field`
#'   reads the target field definition.
#' @examples
#' # Load the SQL example's form model.
#' survey_model <- form.model::read_form_model(
#'   system.file("examples", "survey", "form-source.yaml", package = "form.tools"))
#' # Register one callback for row selection and one for copying a value.
#' export_rules <- list(
#'   each = function(inputs, context, parameters) as.list(seq_len(nrow(inputs$records))),
#'   copy = function(inputs, context, parameters) inputs$value)
#' # Read the row and field declarations for the observation sheet.
#' survey_export <- read_form_export("examples/survey/export.yaml", "form.tools")
#' # Prepare the observation sheet as a preview of the target form.
#' survey_export_plan <- prepare_form_export(survey_model, survey_model,
#'   survey_export$source$root, survey_export$sheets, export_rules)
#' # Supply the extracted tables for one survey.
#' survey_source_tables <- list(surveys = data.frame(id = "S01"),
#'   observations = data.frame(survey = "S01", count = 3L))
#' # Inspect the transformed table.
#' run_form_export(survey_export_plan, survey_source_tables)$tables$observations
#' @export
prepare_form_export <- function(source_model, target_model, root_sheet, sheets, rules) {
  source <- form.model::form_sheets(form.model::as_form_model(form.model::form_definition(source_model)))
  target <- form.model::form_sheets(form.model::as_form_model(form.model::form_definition(target_model)))
  require_nonempty_string(root_sheet, "root_sheet")
  if (!root_sheet %in% names(source) || source[[root_sheet]]$layout$kind != "table" ||
      is.null(source[[root_sheet]]$primary_key) || !is.null(source[[root_sheet]]$parent_key))
    stop("root_sheet must be a source table with a primary key and no parent", call. = FALSE)
  export_mapping(sheets, "sheets")
  export_mapping(rules, "rules")
  if (!length(sheets) || !all(names(sheets) %in% names(target)))
    stop("sheets must name at least one known target sheet", call. = FALSE)
  if (!all(vapply(rules, is.function, logical(1))))
    stop("rules must contain functions", call. = FALSE)

  # The form model orders parents before children.
  declarations <- lapply(intersect(names(target), names(sheets)), function(sheet_name) {
    definition <- sheets[[sheet_name]]
    export_mapping(definition, sheet_name)
    preserve_fields <- definition$preserve_fields
    if (is.list(preserve_fields)) preserve_fields <- vapply(preserve_fields, identity, character(1))
    writable <- writable_form_fields(target[[sheet_name]], preserve_fields, sheet_name)
    fields_from <- definition[["fields_from"]]
    if (!is.null(fields_from)) {
      require_nonempty_string(fields_from, paste(sheet_name, "fields_from"))
      if (target[[sheet_name]]$layout$kind != "cells")
        stop(sheet_name, ": fields_from requires a fixed-cell sheet", call. = FALSE)
      if (any(c("rows", "fields") %in% names(definition)))
        stop(sheet_name, ": fields_from cannot be combined with rows or fields", call. = FALSE)
      return(list(name = sheet_name, fields_from = fields_from, fields = writable,
        preserve_fields = preserve_fields))
    }
    check_write_names(definition$fields, names(writable), paste(sheet_name, "fields"))
    rows <- prepare_export_rule(definition$rows, root_sheet, source, target, rules,
      paste(sheet_name, "rows"))
    if (rows$status == "omitted" && target[[sheet_name]]$layout$kind == "cells")
      stop(sheet_name, " cannot omit the row of a fixed-cell sheet", call. = FALSE)
    fields <- definition$fields[names(writable)]
    if (rows$status == "specified") {
      records <- rows$inputs[["records"]]
      if (is.null(records$sheet) || !is.null(records[["field"]]))
        stop(sheet_name, " rows must bind records to a source data frame", call. = FALSE)
      for (name in names(fields))
        fields[[name]] <- prepare_export_rule(fields[[name]], records$sheet, source, target, rules,
          paste(sheet_name, name, sep = "."), field = name)
    }
    list(name = sheet_name, rows = rows, fields = fields, preserve_fields = preserve_fields)
  })
  structure(list(source = source, target = target, root_sheet = root_sheet,
    declarations = declarations), class = "form_export_plan")
}

#' Transform one extracted dataset into target form tables
#'
#' @param plan Result of [prepare_form_export()].
#' @param data Named list of source data frames, one per source sheet. The root
#'   table must contain exactly one record. Key columns must identify their rows
#'   and refer to existing parent rows.
#' @param inputs Named values used by caller input bindings. A sheet with
#'   `fields_from: section` reads the named list at `inputs$section` and matches
#'   its writable fields by name. Missing required fields and invalid types
#'   produce diagnostics. Missing optional fields are left blank.
#' @param resources Caller-supplied resources for callbacks, such as prepared
#'   reference lookups or shared identifiers.
#' @param finalize Optional function called once with the assembled export result
#'   and `resources`. Return the result to deliver to the caller.
#' @return A list containing `tables`, a `diagnostics` data frame, `source_rows`
#'   mapping target rows to their source keys, `preserve_fields` for the writer,
#'   and `ready_to_write`. The latter
#'   is true when all target sheets ran without export diagnostics.
#' @details Callbacks receive the target sheet, field and row in `context`,
#'   together with `source_keys`, caller `resources` and completed
#'   `target_tables`. Field callbacks can read earlier values of the current
#'   row in `context$target_row`. Fields run in target form model order.
#'   An empty `identity_cache` environment is shared by
#'   callbacks within each run. Row callbacks receive the same context with no
#'   field or target row yet. Callbacks may return an unresolved status with details such
#'   as lookup candidates. A failed field is represented by a typed missing
#'   value. The result can be inspected before calling [write_form_workbook()].
#'   Required fields and target business rules are checked by form validation.
#'   The finalizer receives all target tables and any diagnostics from the rules.
#' @export
run_form_export <- function(plan, data, inputs = list(), resources = list(), finalize = NULL) {
  if (!inherits(plan, "form_export_plan"))
    stop("Use prepare_form_export() to prepare the plan", call. = FALSE)
  if (!is.null(finalize) && !is.function(finalize))
    stop("finalize must be a function or NULL", call. = FALSE)
  export_mapping(inputs, "inputs")
  source <- index_export_data(plan$source, data, plan$root_sheet)
  identity_cache <- new.env(parent = emptyenv())
  tables <- lineage <- diagnostics <- preserve_fields <- list()
  for (declaration in plan$declarations) {
    sheet <- declaration$name
    if (length(declaration$preserve_fields)) preserve_fields[[sheet]] <- declaration$preserve_fields
    context <- list(sheet = sheet, field = NA_character_, row = NA_integer_,
      source_keys = NULL, resources = resources, target_tables = tables,
      identity_cache = identity_cache)
    if (!is.null(declaration$fields_from)) {
      block <- evaluate_export_input_block(declaration, inputs, context)
      tables[[sheet]] <- block$table
      lineage[[sheet]] <- list(NULL)
      diagnostics <- c(diagnostics, block$diagnostics)
      next
    }
    fields <- plan$target[[sheet]]$fields[names(declaration$fields)]
    row_rule <- declaration$rows
    root <- list(sheet = plan$root_sheet, rows = 1L)
    context$source_keys <- export_source_keys(source, root)
    selection <- evaluate_export_rows(row_rule, source, root, inputs, context,
      plan$target[[sheet]]$layout$kind)
    if (!is.null(selection$problem))
      diagnostics[[length(diagnostics) + 1L]] <- export_diagnostic(context, row_rule, selection$problem)
    groups <- selection$groups
    columns <- lapply(fields, function(field) rep(export_missing_value(field$type), length(groups)))
    lineage[[sheet]] <- lapply(groups, function(group) export_source_keys(source, group))
    for (row in seq_along(groups)) {
      context$row <- row
      context$source_keys <- lineage[[sheet]][[row]]
      context$target_row <- list()
      for (name in names(fields)) {
        rule <- declaration$fields[[name]]
        context$field <- name
        result <- evaluate_export_field(rule, source, groups[[row]], inputs, context, fields[[name]]$type)
        if (!is.null(result$problem))
          diagnostics[[length(diagnostics) + 1L]] <- export_diagnostic(context, rule, result$problem)
        columns[[name]][row] <- result$value
        context$target_row[[name]] <- result$value
      }
    }
    tables[[sheet]] <- if (!length(columns)) data.frame(row.names = seq_along(groups)) else
      as.data.frame(columns, row.names = seq_along(groups),
                                     check.names = FALSE, stringsAsFactors = FALSE)
  }
  prototype <- data.frame(sheet = character(), field = character(), row = integer(),
    rule = character(), status = character(), message = character(),
    source_keys = I(list()), details = I(list()))
  export_result <- list(tables = tables, diagnostics = do.call(rbind, c(list(prototype), diagnostics)),
    source_rows = lineage, preserve_fields = preserve_fields,
    ready_to_write = length(tables) == length(plan$target) && !length(diagnostics))
  if (is.null(finalize)) return(export_result)
  finalize(export_result, resources)
}

# Internal helpers ----------------------------------------------------------

#' Fill one fixed-cell block from a named caller input section
#' @param declaration Prepared fixed-cell sheet declaration.
#' @param inputs Named caller inputs.
#' @param context Target location for diagnostics.
#' @return One data frame row and any diagnostics for its fields.
#' @keywords internal
evaluate_export_input_block <- function(declaration, inputs, context) {
  section <- declaration$fields_from
  values <- inputs[[section]]
  export_mapping(values, paste0("inputs.", section))
  fields <- declaration$fields
  table <- data.frame(row.names = 1L)
  diagnostics <- list()
  context$row <- 1L
  for (name in names(fields)) {
    field <- fields[[name]]
    value <- values[[name]]
    scalar <- is.atomic(value) && length(value) == 1L && is.null(dim(value))
    missing <- is.null(value) || (scalar &&
      ((is.na(value) && !(is.numeric(value) && is.nan(value))) ||
        (is.character(value) && !nzchar(trimws(value)))))
    if (!missing && export_scalar(value, field$type)) {
      table[[name]] <- value
      next
    }
    table[[name]] <- export_missing_value(field$type)
    if (missing && !isTRUE(field$mandatory)) next
    label <- paste0("inputs.", section, ".", name)
    problem <- if (missing) export_problem("missing_value", paste(label, "is required")) else
      export_problem("invalid_value", paste(label, "must contain one value of type", field$type))
    context$field <- name
    diagnostics[[length(diagnostics) + 1L]] <-
      export_diagnostic(context, list(rule = "fields_from"), problem)
  }
  list(table = table, diagnostics = diagnostics)
}

#' Require a named list with unique, nonempty keys.
#' @param value Object to check.
#' @param label Location shown in errors.
#' @return Returns silently or raises an error.
#' @keywords internal
export_mapping <- function(value, label) {
  keys <- names(value)
  if (!is.list(value) || is.data.frame(value) ||
      (length(value) && (is.null(keys) || anyNA(keys) || any(!nzchar(keys)) || anyDuplicated(keys))))
    stop(label, " must be a named list", call. = FALSE)
}

#' Supply export rule defaults for a row or field
#' @param rule Row or field declaration.
#' @param field Target field name, or `NULL` for a row declaration.
#' @return The declaration with its default status and field rule filled in.
#' @keywords internal
apply_export_rule_defaults <- function(rule, field = NULL) {
  if (!"status" %in% names(rule) && (!is.null(field) || !is.null(rule[["rule"]])))
    rule$status <- "specified"
  if (!is.null(field) && identical(rule[["status"]], "specified") && !"rule" %in% names(rule))
    rule$rule <- field
  rule
}

#' Bind an active declaration to its callback and resolve its input paths.
#' @param rule Export declaration.
#' @param anchor Starting source sheet.
#' @param source,target Source and target sheet definitions.
#' @param rules Named callback registry.
#' @param label Location shown in errors.
#' @param field Target field name, or `NULL` for a row declaration.
#' @return Declaration with its callback and prepared inputs.
#' @keywords internal
prepare_export_rule <- function(rule, anchor, source, target, rules, label, field = NULL) {
  export_mapping(rule, label)
  rule <- apply_export_rule_defaults(rule, field)
  require_nonempty_string(rule$status, paste(label, "status"))
  if (!rule$status %in% c("specified", "pending", "unavailable", "omitted"))
    stop(label, ": unknown export status ", rule$status, call. = FALSE)
  if (!is.null(rule$note) && !identical(rule$note, "")) require_nonempty_string(rule$note, paste(label, "note"))
  if (rule$status != "specified") return(rule)
  require_nonempty_string(rule$rule, paste(label, "rule"))
  if (!rule$rule %in% names(rules))
    stop(label, ": no registered rule ", rule$rule, call. = FALSE)
  rule$callback <- rules[[rule$rule]]
  if (is.null(rule$inputs)) rule$inputs <- list()
  if (is.null(rule$parameters)) rule$parameters <- list()
  export_mapping(rule$inputs, paste(label, "inputs"))
  export_mapping(rule$parameters, paste(label, "parameters"))
  for (name in names(rule$inputs))
    rule$inputs[[name]] <- prepare_export_binding(rule$inputs[[name]], anchor, source, target,
      paste(label, name))
  rule
}

#' Check a declared input and prepare its source or target lookup.
#' @param binding Input declaration.
#' @param anchor Starting source sheet.
#' @param source,target Source and target sheet definitions.
#' @param label Location shown in errors.
#' @return Prepared input binding.
#' @keywords internal
prepare_export_binding <- function(binding, anchor, source, target, label) {
  export_mapping(binding, label)
  if (!is.null(binding$input)) {
    check_write_names(binding, "input", label)
    require_nonempty_string(binding$input, label)
    return(binding)
  }
  if (identical(binding$model, "target")) {
    check_write_names(binding, c("model", "sheet", "field"), label)
    require_nonempty_string(binding$sheet, label)
    require_nonempty_string(binding$field, label)
    definition <- target[[binding$sheet]]$fields[[binding$field]]
    if (is.null(definition)) stop(label, ": unknown target field", call. = FALSE)
    return(list(definition = definition))
  }
  if (!all(names(binding) %in% c("sheet", "field", "fields", "within")))
    stop(label, ": unsupported source binding", call. = FALSE)
  require_nonempty_string(binding$sheet, label)
  if (!binding$sheet %in% names(source)) stop(label, ": unknown source sheet", call. = FALSE)
  field <- binding[["field"]]
  if (!is.null(field) && !is.null(binding$fields))
    stop(label, ": supply either field or fields", call. = FALSE)
  if (!is.null(field)) require_nonempty_string(field, label)
  binding$columns <- unlist(c(field, binding$fields), use.names = FALSE)
  if (!all(binding$columns %in% names(source[[binding$sheet]]$fields)) || anyDuplicated(binding$columns))
    stop(label, ": unknown or repeated source fields", call. = FALSE)
  owner <- binding$within
  if (!is.null(owner)) require_nonempty_string(owner, label)
  if (is.null(owner)) owner <- binding$sheet
  binding$up <- export_parent_path(source, anchor, owner, label)
  binding$down <- rev(export_parent_path(source, binding$sheet, owner, label))
  binding
}

#' Find the chain of child sheets leading to an ancestor.
#' @param source Source sheet definitions.
#' @param child,ancestor Starting and destination sheet names.
#' @param label Location shown in errors.
#' @return Child sheet names in the parent chain.
#' @keywords internal
export_parent_path <- function(source, child, ancestor, label) {
  path <- character()
  while (child != ancestor) {
    parent <- source[[child]]$parent_key$sheet
    if (is.null(parent))
      stop(label, ": no parent path from ", child, " to ", ancestor, call. = FALSE)
    path <- c(path, child)
    child <- parent
  }
  path
}

#' Check source table shapes and index their parent relationships.
#' @param definitions Source sheet definitions.
#' @param data Named source data frames.
#' @param root_sheet Table holding the selected root record.
#' @return Source tables and row indices for both directions.
#' @keywords internal
index_export_data <- function(definitions, data, root_sheet) {
  check_write_names(data, names(definitions), "source data")
  primary <- parents <- children <- list()
  for (sheet in names(definitions)) {
    definition <- definitions[[sheet]]
    rows <- data[[sheet]]
    if (!is.data.frame(rows)) stop(sheet, " must be a data frame", call. = FALSE)
    check_write_names(rows, names(definition$fields), sheet)
    rows <- data[[sheet]] <- as.data.frame(rows)
    if (sheet == root_sheet && nrow(rows) != 1L)
      stop(root_sheet, " must contain exactly one record", call. = FALSE)
    if (!is.null(definition$primary_key)) {
      primary[[sheet]] <- export_key(rows, definition$primary_key, paste(sheet, "primary key"))
      if (anyDuplicated(primary[[sheet]])) stop(sheet, ": duplicate primary key", call. = FALSE)
    }
    parent <- definition$parent_key
    if (!is.null(parent)) {
      keys <- export_key(rows, parent$fields, paste(sheet, "parent key"))
      parents[[sheet]] <- match(keys, primary[[parent$sheet]])
      if (anyNA(parents[[sheet]])) stop(sheet, ": parent key has no matching row", call. = FALSE)
      children[[sheet]] <- split(seq_len(nrow(rows)), parents[[sheet]])
    }
  }
  list(data = data, definitions = definitions, parents = parents, children = children)
}

#' Encode key fields for exact matching without merging distinct values.
#' @param rows Source data frame.
#' @param fields Ordered key field names.
#' @param label Location shown in errors.
#' @return Character vector of keys in row order.
#' @keywords internal
export_key <- function(rows, fields, label) {
  if (!nrow(rows)) return(character())
  key <- rep("", nrow(rows))
  for (field in unlist(fields, use.names = FALSE)) {
    value <- rows[[field]]
    type <- if (is.numeric(value) && !is.object(value)) "number" else class(value)[[1L]]
    if (anyNA(value) || length(value) != nrow(rows) || !is.null(dim(value)))
      stop(label, ": missing or invalid key field ", field, call. = FALSE)
    if (type %in% c("number", "Date", "POSIXct")) {
      value <- as.numeric(value)
      if (any(!is.finite(value))) stop(label, ": non-finite key", call. = FALSE)
      value[value == 0] <- 0
      value <- sprintf("%.17g", value)
    } else if (type %in% c("character", "logical")) {
      value <- enc2utf8(as.character(value))
    } else stop(label, ": unsupported key type ", type, call. = FALSE)
    if (any(!nzchar(value))) stop(label, ": empty key field ", field, call. = FALSE)
    key <- paste0(key, type, ":", nchar(value, type = "bytes"), ":", value)
  }
  key
}

#' Follow a prepared input path to its source row indices.
#' @param binding Prepared input binding.
#' @param source Indexed source dataset.
#' @param group Source sheet and row indices to start from.
#' @return Source row indices for the bound input.
#' @keywords internal
export_binding_rows <- function(binding, source, group) {
  rows <- group$rows
  for (sheet in binding$up) rows <- unique(source$parents[[sheet]][rows])
  for (sheet in binding$down)
    rows <- sort(unique(as.integer(unlist(source$children[[sheet]][as.character(rows)]))))
  rows
}

#' Record the source sheet, row indices and primary key values.
#' @param source Indexed source dataset.
#' @param group Source sheet and row indices.
#' @return Source sheet, row indices and a data frame of key values.
#' @keywords internal
export_source_keys <- function(source, group) {
  columns <- unlist(source$definitions[[group$sheet]]$primary_key, use.names = FALSE)
  list(sheet = group$sheet, rows = group$rows,
    keys = source$data[[group$sheet]][group$rows, columns, drop = FALSE])
}

#' Read a callback's declared inputs for the current source rows.
#' @param bindings Prepared input bindings.
#' @param source Indexed source dataset.
#' @param group Current source sheet and row indices.
#' @param inputs Named caller inputs.
#' @return Named list of values for the callback.
#' @keywords internal
resolve_export_inputs <- function(bindings, source, group, inputs) {
  lapply(bindings, function(binding) {
    if (!is.null(binding$definition)) return(binding$definition)
    if (!is.null(binding$input)) return(inputs[[binding$input]])
    rows <- export_binding_rows(binding, source, group)
    columns <- binding$columns
    table <- source$data[[binding$sheet]]
    if (!is.null(binding[["field"]])) {
      if (is.null(binding$within) && length(rows) != 1L)
        stop("Expected one source row for ", binding$sheet, ".", binding$field, call. = FALSE)
      return(table[[binding$field]][rows])
    }
    if (!length(columns)) columns <- names(table)
    table[rows, columns, drop = FALSE]
  })
}

#' Build the status, message and details for an unresolved result.
#' @param status Outcome code.
#' @param message Diagnostic text.
#' @param details Optional evidence supplied by the rule.
#' @return List describing the unresolved result.
#' @keywords internal
export_problem <- function(status, message = "", details = NULL) {
  list(status = status, message = message, details = details)
}

#' Describe why a pending or unavailable declaration could not run.
#' @param rule Inactive export declaration.
#' @return Diagnostic status and any explanatory note.
#' @keywords internal
export_inactive <- function(rule) {
  message <- if (is.null(rule$note)) "" else rule$note
  export_problem(rule$status, message)
}

#' Run a row rule and translate its selections into source row groups.
#' @param rule Prepared row rule.
#' @param source Indexed source dataset.
#' @param root Selected source root record.
#' @param inputs Named caller inputs.
#' @param context Callback context for the target sheet.
#' @param layout Target layout kind.
#' @return Selected source groups and any diagnostic.
#' @keywords internal
evaluate_export_rows <- function(rule, source, root, inputs, context, layout) {
  if (rule$status == "omitted") return(list(groups = list()))
  if (rule$status != "specified")
    return(list(groups = list(), problem = export_inactive(rule)))
  tryCatch({
    arguments <- resolve_export_inputs(rule$inputs, source, root, inputs)
    records <- rule$inputs$records
    rows <- export_binding_rows(records, source, root)
    selected <- rule$callback(arguments, context, rule$parameters)
    if (!is.list(selected) || is.data.frame(selected))
      stop("Row rule must return a list of source row index vectors")
    if (layout == "cells" && length(selected) != 1L)
      stop("Fixed-cell sheet requires exactly one target row")
    groups <- lapply(selected, function(indices) {
      if (!is.integer(indices) || !length(indices) || anyNA(indices) ||
          any(indices < 1L | indices > length(rows)) || anyDuplicated(indices))
        stop("Invalid source row indices returned by row rule")
      list(sheet = records$sheet, rows = rows[indices])
    })
    list(groups = groups)
  }, error = function(error) list(groups = list(),
    problem = export_problem("rule_error", conditionMessage(error))))
}

#' Return a missing value of the declared target field type.
#' @param type Form model field type.
#' @return Typed missing scalar.
#' @keywords internal
export_missing_value <- function(type) {
  switch(type, string = NA_character_, email = NA_character_, boolean = NA,
    integer = NA_integer_, date = as.Date(NA_character_),
    datetime = as.POSIXct(NA_character_, tz = "UTC"), NA_real_)
}

#' Run one field rule and collect any unresolved result.
#' @param rule Prepared field rule.
#' @param source Indexed source dataset.
#' @param group Source sheet and row indices for this target row.
#' @param inputs Named caller inputs.
#' @param context Callback context for the target field.
#' @param type Target form model field type.
#' @return Typed value and any diagnostic.
#' @keywords internal
evaluate_export_field <- function(rule, source, group, inputs, context, type) {
  missing <- export_missing_value(type)
  if (rule$status == "omitted") return(list(value = missing))
  if (rule$status != "specified")
    return(list(value = missing, problem = export_inactive(rule)))
  tryCatch({
    arguments <- resolve_export_inputs(rule$inputs, source, group, inputs)
    result <- rule$callback(arguments, context, rule$parameters)
    if (is.list(result)) {
      require_nonempty_string(result$status, "field result status")
      if (result$status == "omitted") return(list(value = missing))
      if (result$status != "resolved") {
        message <- if (is.null(result$message)) "" else result$message
        if (!identical(message, "")) require_nonempty_string(message, "field result message")
        return(list(value = missing, problem = export_problem(result$status, message, result$details)))
      }
      result <- result$value
    }
    if (is.null(result) || (is.atomic(result) && length(result) == 1L &&
        is.na(result) && !(is.numeric(result) && is.nan(result))))
      return(list(value = missing, problem = export_problem("missing_value", "Rule returned no value")))
    if (!export_scalar(result, type))
      stop("Field rule must return one value of type ", type)
    list(value = result)
  }, error = function(error) list(value = missing,
    problem = export_problem("rule_error", conditionMessage(error))))
}

#' Check whether one value fits the target field's R representation.
#' @param value Callback result to check.
#' @param type Target form model field type.
#' @return Whether the value has the expected representation.
#' @keywords internal
export_scalar <- function(value, type) {
  if (length(value) != 1L || !is.null(dim(value))) return(FALSE)
  switch(type, string = is.character(value) && !is.object(value),
    email = is.character(value) && !is.object(value),
    boolean = is.logical(value) && !is.object(value),
    date = identical(class(value), "Date") && is.finite(value) && as.numeric(value) == trunc(as.numeric(value)),
    datetime = identical(class(value), c("POSIXct", "POSIXt")) && is.finite(value),
    integer = is.numeric(value) && !is.object(value) && is.finite(value) && value == trunc(value),
    is.numeric(value) && !is.object(value) && is.finite(value))
}

#' Record an export issue with its target location and source keys.
#' @param context Current source and target locations.
#' @param rule Export declaration.
#' @param problem Unresolved result from the rule.
#' @return One diagnostic row.
#' @keywords internal
export_diagnostic <- function(context, rule, problem) {
  rule_name <- if (is.null(rule$rule)) NA_character_ else rule$rule
  data.frame(sheet = context$sheet, field = context$field, row = context$row,
    rule = rule_name, status = problem$status, message = problem$message,
    source_keys = I(list(context$source_keys)), details = I(list(problem$details)))
}
