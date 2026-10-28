library(testthat)
library(form.tools)

# The skeleton has no tests yet. Use the standard runner once tests are added.
if (length(list.files("testthat", pattern = "^test.*[.][Rr]$"))) {
  test_check("form.tools")
}
