# =============================================================================
# Tests for question_2_adam/create_adsl.R
#
# Three types of tests:
#   1. Unit tests of the derivation rules in specs/adsl_specs.R on small dummy
#      data, including boundary values (e.g. age 17/18/50/51) that do not
#      occur in the study data.
#   2. Independent QC ("double programming"): every requested variable is
#      re-derived from SDTM with plain dplyr/lubridate, without {admiral},
#      and compared with the production ADSL.
#   3. Structural checks of the output dataset.
#
# Prerequisite: create_adsl.R has been run (output/adsl.rds exists).
# Run from the repository root:
#   testthat::test_dir("question_2_adam/tests/testthat")
# =============================================================================

library(testthat, warn.conflicts = FALSE)
library(admiral)
library(dplyr, warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)
library(stringr)
library(pharmaversesdtm)
# testthat 3rd edition (needed for expect_equal(..., ignore_attr = TRUE))
local_edition(3)

# testthat runs the tests with tests/testthat as working directory
source(test_path("..", "..", "specs", "adsl_specs.R"))
adsl_path <- test_path("..", "..", "output", "adsl.rds")

# -----------------------------------------------------------------------------
# Input data for the independent QC
# -----------------------------------------------------------------------------
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)

# Helper: date part of an ISO 8601 value, only if it is a complete date
complete_date <- function(dtc) {
  date_part <- substr(dtc, 1, 10)
  if_else(
    str_detect(date_part, "^\\d{4}-\\d{2}-\\d{2}$"),
    ymd(date_part, quiet = TRUE),
    as.Date(NA)
  )
}

# Helper: ISO 8601 datetime with complete date -> POSIXct (UTC), missing time
# parts filled with `fill` ("00" for start, "59"/"23" handled by caller)
impute_time <- function(dtc, time_fill = "00:00:00") {
  date_ok <- !is.na(complete_date(dtc))
  time_part <- if_else(nchar(dtc) > 11, substr(dtc, 12, 19), "")
  full_time <- paste0(time_part, substr(time_fill, nchar(time_part) + 1, 8))
  if_else(date_ok, ymd_hms(paste(substr(dtc, 1, 10), full_time),
    tz = "UTC", quiet = TRUE
  ),
  as.POSIXct(NA, tz = "UTC")
  )
}

adsl <- readRDS(adsl_path)

# =============================================================================
# 1. Unit tests of the derivation rules
# =============================================================================
test_that("AGEGR9/AGEGR9N follow the specified categories incl. boundaries", {
  dummy <- tibble(AGE = c(0, 17, 17.9, 18, 35, 50, 50.5, 51, 89, NA))
  out <- derive_vars_cat(dummy, definition = agegr9_lookup)

  expect_identical(
    out$AGEGR9,
    c(
      "<18", "<18", "<18", "18 - 50", "18 - 50", "18 - 50",
      ">50", ">50", ">50", NA
    )
  )
  expect_identical(out$AGEGR9N, c(1, 1, 1, 2, 2, 2, 3, 3, 3, NA))
})

test_that("valid dose definition matches the specification NOTE", {
  dummy <- tibble(
    EXDOSE = c(54, 0, 0, 0, NA),
    EXTRT  = c("XANOMELINE", "PLACEBO", "XANOMELINE", "MY PLACEBO", "PLACEBO")
  )
  out <- filter(dummy, !!valid_dose_cond)

  # dose > 0, or dose = 0 and EXTRT contains "PLACEBO"
  expect_identical(out$EXDOSE, c(54, 0, 0))
  expect_identical(out$EXTRT, c("XANOMELINE", "PLACEBO", "MY PLACEBO"))
})

test_that("TRTSDTM imputation: 00 for missing time, no flag if only seconds", {
  dummy_ex <- tibble(
    STUDYID = "S1",
    USUBJID = c("A", "B", "C", "D"),
    EXSEQ = 1,
    EXSTDTC = c(
      "2024-01-05", # time missing   -> 00:00:00, flag H
      "2024-01-05T10", # min/sec missing -> 10:00:00, flag M
      "2024-01-05T10:30", # only seconds    -> 10:30:00, no flag
      "2024-01"
    ) # partial date    -> excluded (NA)
  )
  out <- derive_vars_dtm(
    dummy_ex,
    dtc = EXSTDTC, new_vars_prefix = "EXST",
    highest_imputation = "h", time_imputation = "first",
    ignore_seconds_flag = TRUE
  )

  expect_identical(
    format(out$EXSTDTM, "%Y-%m-%d %H:%M:%S"),
    c("2024-01-05 00:00:00", "2024-01-05 10:00:00", "2024-01-05 10:30:00", NA)
  )
  expect_identical(out$EXSTTMF, c("H", "M", NA, NA))
})

test_that("ignore_seconds_flag stops the program if seconds are collected", {
  # admiral only allows ignore_seconds_flag = TRUE when seconds are never
  # collected. If EXSTDTC ever contains seconds, the program fails loudly
  # instead of silently producing an inconsistent flag - this test documents
  # that assumption.
  dummy_ex <- tibble(
    STUDYID = "S1", USUBJID = "A", EXSEQ = 1,
    EXSTDTC = "2024-01-05T10:30:15"
  )
  expect_error(
    derive_vars_dtm(
      dummy_ex,
      dtc = EXSTDTC, new_vars_prefix = "EXST",
      highest_imputation = "h", time_imputation = "first",
      ignore_seconds_flag = TRUE
    ),
    "Seconds detected"
  )
})

# =============================================================================
# 2. Independent QC of the production ADSL
# =============================================================================
test_that("AGEGR9/AGEGR9N match an independent derivation from DM.AGE", {
  qc <- dm %>%
    transmute(
      USUBJID,
      AGEGR9 = case_when(
        AGE < 18 ~ "<18",
        AGE >= 18 & AGE <= 50 ~ "18 - 50",
        AGE > 50 ~ ">50"
      ),
      AGEGR9N = case_when(
        AGE < 18 ~ 1,
        AGE >= 18 & AGE <= 50 ~ 2,
        AGE > 50 ~ 3
      )
    )
  prod <- adsl %>% select(USUBJID, AGEGR9, AGEGR9N)

  expect_equal(
    arrange(prod, USUBJID), arrange(qc, USUBJID),
    ignore_attr = TRUE
  )
})

test_that("TRTSDTM/TRTSTMF match an independent derivation from EX", {
  qc <- ex %>%
    filter(EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) %>%
    mutate(
      dtm = impute_time(EXSTDTC, "00:00:00"),
      # flag: H if hours missing, M if minutes missing, none if only seconds
      tmf = case_when(
        nchar(EXSTDTC) <= 10 ~ "H",
        nchar(EXSTDTC) == 13 ~ "M",
        TRUE ~ NA_character_
      )
    ) %>%
    filter(!is.na(dtm)) %>%
    arrange(USUBJID, dtm, EXSEQ) %>%
    group_by(USUBJID) %>%
    slice(1) %>%
    ungroup() %>%
    select(USUBJID, TRTSDTM = dtm, TRTSTMF = tmf)

  prod <- adsl %>%
    filter(!is.na(TRTSDTM)) %>%
    select(USUBJID, TRTSDTM, TRTSTMF)

  expect_equal(
    arrange(prod, USUBJID), arrange(qc, USUBJID),
    ignore_attr = TRUE
  )
})

test_that("Subjects without a valid dose have missing TRTSDTM", {
  dosed <- ex %>%
    filter(EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) %>%
    pull(USUBJID) %>%
    unique()

  not_dosed <- filter(adsl, !USUBJID %in% dosed)
  expect_true(all(is.na(not_dosed$TRTSDTM)))
  expect_true(all(is.na(not_dosed$TRTSTMF)))
})

test_that("ITTFL is Y if DM.ARM is not missing, else N", {
  qc <- dm %>%
    transmute(USUBJID, ITTFL = if_else(!is.na(ARM), "Y", "N"))
  prod <- adsl %>% select(USUBJID, ITTFL)

  expect_equal(
    arrange(prod, USUBJID), arrange(qc, USUBJID),
    ignore_attr = TRUE
  )
})

test_that("LSTAVLDT matches an independent derivation from VS, AE, DS, EX", {
  vs_dt <- vs %>%
    filter(!(is.na(VSSTRESN) & is.na(VSSTRESC))) %>%
    transmute(USUBJID, dt = complete_date(VSDTC))
  ae_dt <- ae %>% transmute(USUBJID, dt = complete_date(AESTDTC))
  ds_dt <- ds %>% transmute(USUBJID, dt = complete_date(DSSTDTC))
  # last valid dose: date part of the latest complete EXENDTC
  ex_dt <- ex %>%
    filter(EXDOSE > 0 | (EXDOSE == 0 & str_detect(EXTRT, "PLACEBO"))) %>%
    transmute(USUBJID, dt = complete_date(EXENDTC))

  qc <- bind_rows(vs_dt, ae_dt, ds_dt, ex_dt) %>%
    filter(!is.na(dt)) %>%
    group_by(USUBJID) %>%
    summarise(LSTAVLDT = max(dt), .groups = "drop")

  prod <- adsl %>%
    filter(!is.na(LSTAVLDT)) %>%
    select(USUBJID, LSTAVLDT)

  expect_equal(
    arrange(prod, USUBJID), arrange(qc, USUBJID),
    ignore_attr = TRUE
  )
})

# =============================================================================
# 3. Structural checks
# =============================================================================
test_that("ADSL has one record per DM subject and all requested variables", {
  expect_false(any(duplicated(adsl$USUBJID)))
  expect_setequal(adsl$USUBJID, dm$USUBJID)
  expect_true(all(c(
    "AGEGR9", "AGEGR9N", "TRTSDTM", "TRTSTMF",
    "ITTFL", "LSTAVLDT"
  ) %in% names(adsl)))
})

test_that("Derived variables have the expected types", {
  expect_type(adsl$AGEGR9, "character")
  expect_type(adsl$AGEGR9N, "double")
  expect_s3_class(adsl$TRTSDTM, "POSIXct")
  expect_s3_class(adsl$LSTAVLDT, "Date")
  expect_true(all(adsl$ITTFL %in% c("Y", "N")))
})

test_that("TRTSDTM/TRTEDTM agree with the pharmaverseadam reference ADSL", {
  skip_if_not_installed("pharmaverseadam")
  ref <- pharmaverseadam::adsl %>% select(USUBJID, TRTSDTM, TRTEDTM)
  prod <- adsl %>% select(USUBJID, TRTSDTM, TRTEDTM)

  expect_equal(
    arrange(prod, USUBJID), arrange(ref, USUBJID),
    ignore_attr = TRUE
  )
})
