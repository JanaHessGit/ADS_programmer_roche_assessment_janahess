# =============================================================================
# Tests for question_1_sdtm/01_create_ds_domain.R
#
# Three types of tests:
#   1. Structure and SDTM conformance of the output dataset.
#   2. Independent QC ("double programming"): the aCRF mapping rules and the
#      derived variables are re-derived from the raw data with plain
#      dplyr/lubridate (no {sdtm.oak}) and compared with the output.
#   3. Comparison with the reference DS domain pharmaversesdtm::ds, which was
#      created from the same raw data.
#
# Prerequisite: the program has been run (output/ds.rds exists).
# Run from the repository root:
#   testthat::test_dir("question_1_sdtm/tests/testthat")
#
# Tests drafted with GitHub Copilot and reviewed/extended manually.
# =============================================================================

library(testthat, warn.conflicts = FALSE)
library(dplyr, warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)

# testthat 3rd edition (needed for expect_equal(..., ignore_attr = TRUE))
local_edition(3)

# testthat runs the tests with tests/testthat as working directory
ds <- readRDS(test_path("..", "..", "output", "ds.rds"))
ds_raw <- pharmaverseraw::ds_raw
dm <- pharmaversesdtm::dm

# Independent derivation of the collected variables from the raw data.
# USUBJID = DM.SITEID-DM.SUBJID prefixed as in DM (joined, not hard-coded).
qc <- ds_raw %>%
  left_join(
    transmute(dm, PATNUM = paste0(SITEID, "-", SUBJID), USUBJID),
    by = "PATNUM"
  ) %>%
  transmute(
    USUBJID,
    DSTERM  = toupper(if_else(is.na(OTHERSP), IT.DSTERM, OTHERSP)),
    DSDECOD = toupper(if_else(is.na(OTHERSP), IT.DSDECOD, OTHERSP)),
    DSCAT   = case_when(
      !is.na(OTHERSP)            ~ "OTHER EVENT",
      IT.DSDECOD == "Randomized" ~ "PROTOCOL MILESTONE",
      TRUE                       ~ "DISPOSITION EVENT"
    ),
    VISIT   = toupper(INSTANCE),
    DSSTDTC = format(mdy(IT.DSSTDAT), "%Y-%m-%d"),
    DSDTC   = if_else(
      is.na(DSTMCOL),
      format(mdy(DSDTCOL), "%Y-%m-%d"),
      paste0(format(mdy(DSDTCOL), "%Y-%m-%d"), "T", DSTMCOL)
    )
  )

# Helper: sort all rows by all columns, so that two datasets with the same
# records in a different order compare equal
sort_all <- function(x) arrange(x, across(everything()))

# =============================================================================
# 1. Structure and SDTM conformance
# =============================================================================
test_that("DS has the expected variables in the expected order", {
  expected_vars <- c(
    "STUDYID", "DOMAIN", "USUBJID", "DSSEQ", "DSTERM", "DSDECOD", "DSCAT",
    "VISITNUM", "VISIT", "DSDTC", "DSSTDTC", "DSSTDY"
  )
  expect_identical(names(ds), expected_vars)
})

test_that("DS keeps all raw records and only DM subjects", {
  expect_equal(nrow(ds), nrow(ds_raw))
  expect_true(all(ds$USUBJID %in% dm$USUBJID))
  expect_true(all(ds$DOMAIN == "DS"))
})

test_that("USUBJID/DSSEQ is a unique key and DSSEQ starts at 1", {
  expect_false(any(duplicated(ds[c("USUBJID", "DSSEQ")])))
  first_seq <- ds %>% group_by(USUBJID) %>% summarise(m = min(DSSEQ))
  expect_true(all(first_seq$m == 1))
})

test_that("Required variables are populated on every record", {
  required_vars <- c("STUDYID", "DOMAIN", "USUBJID", "DSSEQ",
                     "DSTERM", "DSDECOD", "DSCAT")
  expect_false(anyNA(ds[required_vars]))
})

test_that("DSCAT and VISITNUM have valid values", {
  expect_true(all(ds$DSCAT %in% c("PROTOCOL MILESTONE", "DISPOSITION EVENT",
                                  "OTHER EVENT")))
  expect_type(ds$VISITNUM, "double")
  expect_false(anyNA(ds$VISITNUM))
})

test_that("DSDECOD of disposition events is in codelist C66727", {
  ct <- read.csv(test_path("..", "..", "metadata", "sdtm_ct.csv"))
  ncomplete <- ct$term_value[ct$codelist_code == "C66727"]
  dispo <- filter(ds, DSCAT == "DISPOSITION EVENT")
  expect_true(all(dispo$DSDECOD %in% ncomplete))
})

test_that("DTC variables are ISO 8601 character values with valid dates", {
  iso <- "^\\d{4}-\\d{2}-\\d{2}(T\\d{2}:\\d{2}(:\\d{2})?)?$"
  for (v in c("DSDTC", "DSSTDTC")) {
    expect_type(ds[[v]], "character")
    expect_true(all(grepl(iso, ds[[v]])))
    # real calendar dates (e.g. no month 13)
    expect_false(anyNA(as.Date(substr(ds[[v]], 1, 10))))
  }
})

# =============================================================================
# 2. Independent QC of the aCRF rules and derivations
# =============================================================================
test_that("DSTERM, DSDECOD, DSCAT follow the aCRF rules", {
  vars <- c("USUBJID", "DSTERM", "DSDECOD", "DSCAT")
  expect_equal(
    sort_all(select(ds, all_of(vars))),
    sort_all(select(qc, all_of(vars))),
    ignore_attr = TRUE
  )
})

test_that("DSDTC and DSSTDTC are correctly converted to ISO 8601", {
  vars <- c("USUBJID", "DSTERM", "DSDTC", "DSSTDTC")
  expect_equal(
    sort_all(select(ds, all_of(vars))),
    sort_all(select(qc, all_of(vars))),
    ignore_attr = TRUE
  )
})

test_that("VISIT is the upper-cased collected visit name", {
  vars <- c("USUBJID", "DSTERM", "VISIT")
  expect_equal(
    sort_all(select(ds, all_of(vars))),
    sort_all(select(qc, all_of(vars))),
    ignore_attr = TRUE
  )
})

test_that("DSSTDY follows the SDTM study day formula (no day 0)", {
  check <- ds %>%
    left_join(select(dm, USUBJID, RFXSTDTC), by = "USUBJID") %>%
    mutate(
      diff = as.numeric(ymd(DSSTDTC) - ymd(substr(RFXSTDTC, 1, 10))),
      expected = if_else(diff >= 0, diff + 1, diff)
    )
  expect_equal(check$DSSTDY, check$expected, ignore_attr = TRUE)
  expect_false(any(ds$DSSTDY == 0, na.rm = TRUE))
})

test_that("DSSEQ follows the chronological order within each subject", {
  ordered <- ds %>%
    group_by(USUBJID) %>%
    summarise(sorted = !is.unsorted(DSSTDTC[order(DSSEQ)]))
  expect_true(all(ordered$sorted))
})

# =============================================================================
# 3. Comparison with the reference DS domain
# =============================================================================
test_that("DS is identical to the pharmaversesdtm::ds reference", {
  ref <- pharmaversesdtm::ds[names(ds)]
  expect_equal(
    arrange(ds, USUBJID, DSSEQ),
    arrange(ref, USUBJID, DSSEQ),
    ignore_attr = TRUE
  )
})
