#' Require a nonempty string
#' @param value Value to check without coercion or trimming.
#' @param label Argument name used in error messages.
#' @return The original character scalar. Invalid values raise an error naming the argument.
#' @export
require_nonempty_string <- function(value, label) {
  if (!is.character(value) || length(value) != 1L || is.na(value) || !nzchar(value))
    stop(label, " must be a non-empty string", call. = FALSE)
  value
}
