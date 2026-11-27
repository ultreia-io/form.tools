test_that("export identities can be cached per field or per source record", {
  cache <- new.env(parent = emptyenv())
  root_context <- list(field = "root_id", identity_cache = cache)
  record_context <- list(field = "record_id", identity_cache = cache)

  expect_identical(export_identity_cache_write(list(value = "root"), root_context, NULL), "root")
  expect_identical(export_identity_cache_write(list(value = "A", source_id = "source-a"), record_context, NULL), "A")
  expect_identical(export_identity_cache_write(list(value = "B", source_id = "source-b"), record_context, NULL), "B")

  expect_identical(export_identity_cache_read(list(source_id = "source-b"), record_context, NULL), "B")
  expect_identical(export_identity_cache_read(list(source_id = "source-a"), record_context, NULL), "A")
  expect_identical(export_identity_cache_read(list(), root_context, NULL), "root")
  expect_identical(export_identity_cache_read(list(source_id = "missing"), record_context, NULL)$status, "unresolved")
  expect_error(export_identity_cache_write(list(value = "B", source_id = "source-a"), record_context, NULL),
    "Conflicting cached identity", fixed = TRUE)
})
