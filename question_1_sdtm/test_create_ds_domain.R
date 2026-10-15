# Run from the repository root with:
#   Rscript -e 'testthat::test_file("question_1_sdtm/test_create_ds_domain.R")'
# Tests were created by GitHub Copilot 


# Find the repository root so the script's relative input and output paths work
# whether this file is run from the root or from the question_1_sdtm folder.
if (file.exists(file.path("question_1_sdtm", "01_create_ds_domain.R"))) {
  repo_root <- getwd()
} else if (file.exists("01_create_ds_domain.R") &&
           basename(getwd()) == "question_1_sdtm") {
  repo_root <- dirname(getwd())
} else {
  stop("Run this test from the repository root.", call. = FALSE)
}

# Run the production script in an isolated environment to avoid adding its
# variables to the test runner's global environment.
test_env <- withr::with_dir(repo_root, {
  env <- new.env(parent = globalenv())
  source(file.path("question_1_sdtm", "01_create_ds_domain.R"), local = env)
  env
})

# Confirm the output includes every expected DS variable in the specified
# order, including the required identifier and disposition columns.
testthat::test_that("DS output has the expected SDTM structure", {
  expected_vars <- c(
    "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM", "DSDECOD", "DSCAT",
    "VISITNUM", "VISIT", "DSDTC", "DSSTDTC", "DSSTDY"
  )

  testthat::expect_identical(names(test_env$ds), expected_vars)
  testthat::expect_true(all(expected_vars[1:7] %in% names(test_env$ds)))
})

# Check that no raw records were lost, every output subject exists in DM, and
# each record is labeled as belonging to the DS domain.
testthat::test_that("DS preserves the raw record count and subject membership", {
  testthat::expect_equal(nrow(ds), nrow(test_env$ds_raw))
  testthat::expect_true(all(ds$USUBJID %in% test_env$dm$USUBJID))
  testthat::expect_true(all(ds$DOMAIN == "DS"))
})

# DSSEQ should be a positive integer and identify each record uniquely within
# its subject.
testthat::test_that("DS subject sequence keys are unique and valid", {
  testthat::expect_false(anyDuplicated(ds[c("USUBJID", "DSSEQ")]) > 0L)
  testthat::expect_true(all(ds$DSSEQ >= 1L))
  testthat::expect_true(all(ds$DSSEQ == as.integer(ds$DSSEQ)))
})

# Required SDTM variables must be present on every record.
testthat::test_that("required DS variables are populated", {
  required_vars <- c(
    "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM", "DSDECOD", "DSCAT"
  )

  testthat::expect_false(anyNA(ds[required_vars]))
})

# Ensure DSCAT uses only the allowed values and each record has a finite,
# successfully mapped visit number.
testthat::test_that("DS categories and visit numbers are valid", {
  expected_categories <- c(
    "PROTOCOL MILESTONE", "DISPOSITION EVENT", "OTHER EVENT"
  )

  testthat::expect_true(all(ds$DSCAT %in% expected_categories))
  testthat::expect_false(anyNA(ds$VISITNUM))
  testthat::expect_true(all(is.finite(ds$VISITNUM)))
})

# SDTM DTC variables are character strings; verify each nonmissing value is a
# full ISO 8601 date, optionally followed by a time.
testthat::test_that("SDTM date/time values are ISO 8601 character strings", {
  testthat::expect_type(ds$DSDTC, "character")
  testthat::expect_type(ds$DSSTDTC, "character")

  iso_datetime <- "^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2}(:\\d{2}(\\.\\d+)?)?)?$"
  for (date_var in c("DSDTC", "DSSTDTC")) {
    values <- ds[[date_var]]
    testthat::expect_true(any(!is.na(values)))
    testthat::expect_true(all(is.na(values) | grepl(iso_datetime, values)))
  }
})

# Confirm the script creates both output formats and that their schemas and
# record counts match the in-memory DS domain.
testthat::test_that("the script writes matching CSV and RDS outputs", {
  csv_path <- file.path(repo_root, "question_1_sdtm", "output", "ds.csv")
  rds_path <- file.path(repo_root, "question_1_sdtm", "output", "ds.rds")

  testthat::expect_true(file.exists(csv_path))
  testthat::expect_true(file.exists(rds_path))

  csv_ds <- utils::read.csv(csv_path, stringsAsFactors = FALSE)
  rds_ds <- readRDS(rds_path)
  testthat::expect_identical(names(csv_ds), names(ds))
  testthat::expect_identical(names(rds_ds), names(ds))
  testthat::expect_equal(nrow(csv_ds), nrow(ds))
  testthat::expect_equal(nrow(rds_ds), nrow(ds))
})
