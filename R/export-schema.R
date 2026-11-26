# Public operations ---------------------------------------------------------

#' Read the export configuration schema
#' @param version Schema version; currently `"1.0.0"`.
#' @return The packaged schema as a nested list.
#' @details Uses the `form.tools/export-schema/1` dialect.
#' @examples
#' # Inspect the export contract version.
#' export_schema()$contract_version
#' @export
export_schema <- function(version = "1.0.0") {
  require_nonempty_string(version, "version")
  if (!identical(version, "1.0.0"))
    abort_export_yaml("<schema>", "version", "unsupported schema version")
  read_export_yaml(export_yaml_resource("schema/export-1.0.0.yaml", "form.tools"))
}

#' Read and check a YAML export configuration
#' @param path File path, or package-relative path when `package` is supplied.
#' @param package Optional installed package name.
#' @return A checked list with `schema_version`, `source$root` and `sheets`.
#'   Invalid YAML or definitions raise `form_export_error` with the resource
#'   and the path to the offending entry.
#' @details The configuration selects its schema using `schema_version`.
#'   The caller supplies the source and target models and the rule callbacks to
#'   [prepare_form_export()]. Supply the source root and sheets from this list.
#'   A fixed-cell sheet may use `fields_from` in place of `rows` and `fields`
#'   to name the caller input section for all writable fields.
#'   Field declarations default to `status: specified`. An active field
#'   declaration without `rule` uses its field name. Active row declarations
#'   name their rule explicitly. [prepare_form_export()] checks that each
#'   active rule has a registered callback.
#'   A field rule's source input can omit `sheet` to use the row source sheet
#'   at `rows.inputs.records.sheet`.
#'   Uses YAML 1.1 types. Quote version strings and identifiers that could be
#'   parsed as numbers or booleans. Tags, anchors, aliases, merges, directives
#'   and document markers are unsupported.
#' @examples
#' # Read the packaged survey export configuration.
#' survey_export <- read_form_export("examples/survey/export.yaml", "form.tools")
#' # Inspect which source sheet contains the selected survey.
#' survey_export$source$root
#' @export
read_form_export <- function(path, package = NULL) {
  if (!is.null(package)) path <- export_yaml_resource(path, package)
  configuration <- read_export_yaml(path)
  resource <- normalizePath(path, winslash = "/", mustWork = TRUE)
  if (!is.list(configuration) || is.null(names(configuration)))
    abort_export_yaml(resource, "$", "expected mapping")
  version <- configuration[["schema_version"]]
  if (!is.character(version) || length(version) != 1L || is.na(version) || !nzchar(version))
    abort_export_yaml(resource, "$.schema_version", "expected a nonempty version string")
  schema <- tryCatch(export_schema(version), form_export_error = function(error) {
    if (identical(error$resource, "<schema>"))
      abort_export_yaml(resource, "$.schema_version", "unsupported schema version")
    stop(error)
  })
  check_export_schema(configuration, schema$definitions[[schema$root]], schema$definitions,
    resource, "$")
  configuration$sheets <- check_export_declarations(configuration$sheets, resource)
  configuration
}

# Internal helpers ----------------------------------------------------------

#' Raise a configuration error that identifies the resource and YAML path.
#' @param resource Source file or resource name.
#' @param path Location in the YAML.
#' @param message Error description.
#' @return Raises a form export error.
#' @keywords internal
abort_export_yaml <- function(resource, path, message) {
  stop(structure(list(message = paste0(resource, ": ", path, ": ", message),
    call = NULL, resource = resource, path = path),
    class = c("form_export_error", "error", "condition")))
}

#' Resolve a YAML file within the named package directory.
#' @param path Package-relative YAML path.
#' @param package Package supplying the file.
#' @return Absolute file path.
#' @keywords internal
export_yaml_resource <- function(path, package) {
  require_nonempty_string(path, "path")
  require_nonempty_string(package, "package")
  if (grepl("^[/\\\\~]|^[A-Za-z]:|(^|[/\\\\])\\.\\.([/\\\\]|$)", path))
    abort_export_yaml(package, path, "expected a relative path without parent traversal")
  root <- system.file(package = package)
  if (!nzchar(root)) abort_export_yaml(package, path, "package is not installed")
  file <- file.path(root, path)
  if (!file.exists(file) || dir.exists(file))
    abort_export_yaml(package, path, "resource file does not exist")
  root <- normalizePath(root, winslash = "/", mustWork = TRUE)
  file <- normalizePath(file, winslash = "/", mustWork = TRUE)
  if (!startsWith(file, paste0(root, "/")))
    abort_export_yaml(package, path, "resource escapes package directory")
  file
}

#' Parse restricted YAML into named mappings and ordered sequences.
#' @param path Local YAML file.
#' @return Parsed YAML data.
#' @keywords internal
read_export_yaml <- function(path) {
  require_nonempty_string(path, "path")
  if (!file.exists(path) || dir.exists(path))
    abort_export_yaml(path, "$", "file does not exist or is not a regular file")
  tryCatch({
    lines <- readLines(path, warn = FALSE, encoding = "UTF-8")
    check_export_yaml_profile(lines, path)
    handlers <- list(seq = identity, map = function(value) {
      keys <- attr(value, "keys")
      if (!all(vapply(keys, function(key) is.character(key) && length(key) == 1L &&
          !is.na(key) && nzchar(key), logical(1))))
        stop("mapping keys must be nonempty strings; quote numeric or boolean codes")
      attr(value, "keys") <- NULL
      names(value) <- vapply(keys, identity, character(1))
      value
    })
    withCallingHandlers(yaml::yaml.load(paste(lines, collapse = "\n"), as.named.list = FALSE,
      handlers = handlers, eval.expr = FALSE),
      warning = function(warning) stop(conditionMessage(warning)))
  }, error = function(error) {
    if (inherits(error, "form_export_error")) stop(error)
    abort_export_yaml(path, "$", conditionMessage(error))
  })
}

#' Reject unsupported YAML syntax outside quoted text and block scalars.
#' @param lines Lines of YAML text.
#' @param resource Source label for errors.
#' @return Returns silently or raises a profile error.
#' @keywords internal
check_export_yaml_profile <- function(lines, resource) {
  quote <- ""
  block_indent <- NULL
  for (i in seq_along(lines)) {
    line <- lines[[i]]
    indent <- nchar(line) - nchar(sub("^ *", "", line))
    if (!is.null(block_indent)) {
      if (!nzchar(trimws(line)) || indent > block_indent) next
      block_indent <- NULL
    }
    characters <- strsplit(line, "", fixed = TRUE)[[1L]]
    visible <- ""
    position <- 1L
    while (position <= length(characters)) {
      character <- characters[[position]]
      if (nzchar(quote)) {
        if (quote == '"' && character == "\\") {
          position <- position + 2L
          next
        }
        if (character == quote) {
          if (quote == "'" && position < length(characters) && characters[[position + 1L]] == "'") {
            position <- position + 2L
            next
          }
          quote <- ""
        }
        visible <- paste0(visible, " ")
      } else if (character %in% c("'", '"') &&
                 (position == 1L || grepl("[[:space:]:,\\[{?-]$", visible))) {
        quote <- character
        visible <- paste0(visible, "Q")
      } else {
        if (character == "#" && (position == 1L || grepl("[[:space:]]$", visible))) break
        visible <- paste0(visible, character)
      }
      position <- position + 1L
    }
    if (grepl("(^[[:space:]]*([-?][[:space:]]+)?|:[[:space:]]+|[\\[{,][[:space:]]*)[!&*]|(^|[[:space:],{])<<[[:space:]]*:|^%|^---|^\\.\\.\\.", visible))
      abort_export_yaml(resource, paste0("$ (line ", i, ")"),
        "YAML tags, anchors, aliases, merges, directives and document markers are unsupported")
    if (grepl("[|>][-+0-9]*[[:space:]]*$", visible)) block_indent <- indent
  }
}

#' Check a value and its children against a schema node.
#' @param value Parsed value to check.
#' @param node,definitions Schema node and its named definitions.
#' @param resource,path Source label and location for errors.
#' @return Returns silently or raises a schema error.
#' @keywords internal
check_export_schema <- function(value, node, definitions, resource, path) {
  while (!is.null(node$ref)) node <- definitions[[node$ref]]
  valid <- switch(node$type,
    mapping = is.list(value) && !is.null(names(value)),
    sequence = is.list(value) && is.null(names(value)),
    string = is.character(value) && length(value) == 1L && !is.na(value),
    data = TRUE)
  if (!valid) abort_export_yaml(resource, path, paste("expected", node$type))
  if (!is.null(node$min_items) && length(value) < node$min_items)
    abort_export_yaml(resource, path, paste("requires at least", node$min_items, "items"))
  if (node$type == "mapping") {
    keys <- names(value)
    if (is.null(node$values)) {
      unknown <- setdiff(keys, names(node$properties))
      missing <- setdiff(unlist(node$required), keys)
      if (length(unknown)) abort_export_yaml(resource, paste(path, unknown[[1L]], sep = "."), "unsupported property")
      if (length(missing)) abort_export_yaml(resource, paste(path, missing[[1L]], sep = "."), "missing required property")
    }
    for (key in keys) {
      location <- paste(path, key, sep = ".")
      if (!is.null(node$key_pattern) && !grepl(node$key_pattern, key))
        abort_export_yaml(resource, location, "key does not match the required pattern")
      child <- if (is.null(node$values)) node$properties[[key]] else node$values
      check_export_schema(value[[key]], child, definitions, resource, location)
    }
  } else if (node$type == "sequence") {
    for (i in seq_along(value))
      check_export_schema(value[[i]], node$items, definitions, resource, paste0(path, "[", i, "]"))
  } else if (node$type == "string") {
    if (!is.null(node$enum) && !value %in% unlist(node$enum))
      abort_export_yaml(resource, path, "unsupported value")
    if (!is.null(node$pattern) && !grepl(node$pattern, value))
      abort_export_yaml(resource, path, "does not match the required pattern")
  }
}

#' Check each sheet's row declaration and field declarations.
#' @param sheets Target sheet declarations.
#' @param resource Source label for errors.
#' @return Checked declarations with default statuses filled in.
#' @keywords internal
check_export_declarations <- function(sheets, resource) {
  for (sheet in names(sheets)) {
    declaration <- sheets[[sheet]]
    path <- paste0("$.sheets.", sheet)
    explicit <- c("rows", "fields")
    if (!is.null(declaration[["fields_from"]])) {
      if (any(explicit %in% names(declaration)))
        abort_export_yaml(resource, path, "fields_from cannot be combined with rows or fields")
      next
    }
    missing <- setdiff(explicit, names(declaration))
    if (length(missing))
      abort_export_yaml(resource, paste0(path, ".", missing[[1L]]), "missing required property")
    declaration$rows <- check_export_declaration(declaration$rows, resource,
      paste0(path, ".rows"))
    for (field in names(declaration$fields))
      declaration$fields[[field]] <- check_export_declaration(declaration$fields[[field]], resource,
        paste0(path, ".fields.", field), field = field)
    sheets[[sheet]] <- declaration
  }
  sheets
}

#' Check the rule name and allowed combinations of input properties.
#' @param rule Rule declaration.
#' @param resource,path Source label and location for errors.
#' @param field Target field name, or `NULL` for a row declaration.
#' @return The checked declaration with its defaults filled in.
#' @keywords internal
check_export_declaration <- function(rule, resource, path, field = NULL) {
  rule <- apply_export_rule_defaults(rule, field)
  if (is.null(rule$status))
    abort_export_yaml(resource, paste0(path, ".status"), "required when no rule is named")
  if (rule$status == "specified" && is.null(rule$rule))
    abort_export_yaml(resource, paste0(path, ".rule"), "specified declarations require a rule")
  if (is.null(field) && rule$status == "specified") {
    records <- rule$inputs[["records"]]
    if (is.null(records$sheet) || !is.null(records$model) || !is.null(records[["field"]]))
      abort_export_yaml(resource, paste0(path, ".inputs.records"), "expected a source data frame binding")
  }
  for (name in names(rule$inputs)) {
    binding <- rule$inputs[[name]]
    location <- paste0(path, ".inputs.", name)
    keys <- names(binding)
    if ("input" %in% keys) {
      if (!identical(keys, "input"))
        abort_export_yaml(resource, location, "caller input cannot include other binding properties")
    } else if ("model" %in% keys) {
      if (!setequal(keys, c("model", "sheet", "field")))
        abort_export_yaml(resource, location, "target field binding requires model, sheet and field")
    } else {
      if (is.null(field) && !"sheet" %in% keys)
        abort_export_yaml(resource, location, "source binding requires a sheet")
      if (all(c("field", "fields") %in% keys) || anyDuplicated(unlist(binding$fields)))
        abort_export_yaml(resource, location, "supply one field or a list of distinct fields")
    }
  }
  rule
}
