# Public operations ---------------------------------------------------------

#' Cache an identity under the current target field name
#' @param inputs Identifier supplied as `value` and optional `source_id` for a
#'   field with a separate value per source record.
#' @param context Target field and identity cache for the current export run.
#' @param parameters Arguments supplied by the export engine.
#' @return The identifier stored for the target field.
#' @seealso [run_form_export()], [export_identity_cache_read()]
#' @export
export_identity_cache_write <- function(inputs, context, parameters) {
  value <- require_nonempty_string(inputs$value, context$field)
  cache <- context$identity_cache
  if (!is.environment(cache)) stop("The export run must provide an identity cache.", call. = FALSE)
  key <- export_identity_cache_build_key(inputs, context$field)
  existing <- cache[[key]]
  if (!is.null(existing) && !identical(existing, value))
    stop("Conflicting cached identity for ", key, ".", call. = FALSE)
  cache[[key]] <- value
  value
}

#' Read the identity cached for the current target field
#' @param inputs Optional `source_id` for a field cached per source record.
#' @param context Target field and identity cache for the current export run.
#' @param parameters Arguments supplied by the export engine.
#' @return The cached identifier or an unresolved diagnostic.
#' @seealso [run_form_export()], [export_identity_cache_write()]
#' @export
export_identity_cache_read <- function(inputs, context, parameters) {
  key <- export_identity_cache_build_key(inputs, context$field)
  value <- context$identity_cache[[key]]
  if (is.null(value))
    return(list(status = EXPORT_RESULT_STATUS_UNRESOLVED,
      message = paste0("No cached identity for ", key, ".")))
  value
}

# Internal helpers ----------------------------------------------------------

#' Identify a cached field value within an export run
#' @param inputs Rule inputs carrying an optional source record identifier.
#' @param field Target field name.
#' @return A cache key for the field or for one source record.
#' @keywords internal
export_identity_cache_build_key <- function(inputs, field) {
  if (!"source_id" %in% names(inputs)) return(field)
  source_id <- require_nonempty_string(inputs$source_id, "source_id")
  paste(field, source_id, sep = "/")
}
