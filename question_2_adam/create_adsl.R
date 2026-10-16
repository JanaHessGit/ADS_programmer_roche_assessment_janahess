# =============================================================================
# Program     : create_adsl.R
# Purpose     : Create the ADaM ADSL (Subject-Level Analysis Dataset) from SDTM
#               using the {admiral} family of packages and tidyverse tools,
#               following the Pharmaverse ADSL example and the {admiral} ADSL
#               vignette, with the additional variables requested in the
#               assessment specification.
#
# Input       : pharmaversesdtm::dm  - Demographics (basis of ADSL)
#               pharmaversesdtm::ex  - Exposure
#               pharmaversesdtm::vs  - Vital Signs
#               pharmaversesdtm::ae  - Adverse Events
#               pharmaversesdtm::ds  - Disposition
# Output      : question_2_adam/output/adsl.rds  (R data, keeps attributes)
#               question_2_adam/output/adsl.csv  (for easy viewing)
#
# Derived variables (assessment specification):
#   AGEGR9 / AGEGR9N  Age groups "<18" (1), "18 - 50" (2), ">50" (3),
#                     "Missing" (4) if AGE is missing
#   TRTSDTM / TRTSTMF Datetime of first exposure with a valid dose and a
#                     complete date; missing time parts imputed with 00,
#                     imputation flag not set if only seconds are missing
#   ITTFL             "Y" if DM.ARM is not missing, else "N"
#   LSTAVLDT          Last known alive date: max of last complete vital signs
#                     date with a valid result, last complete AE onset date,
#                     last complete disposition date and last valid dose date
#
# Supporting variables (kept for traceability of LSTAVLDT):
#   TRTEDTM / TRTETMF  Datetime of last exposure with a valid dose
#                      (referenced as ADSL.TRTEDTM in the specification)
#   TRTSDT / TRTEDT    Date parts of TRTSDTM / TRTEDTM
#
# How to run  : from the repository root, with log file (see README.md):
#                 logrx::axecute("question_2_adam/create_adsl.R",
#                                log_name = "create_adsl.log",
#                                log_path = "question_2_adam")
#               Tests (after running the program):
#                 testthat::test_dir("question_2_adam/tests/testthat")
#
# =============================================================================

library(admiral)
library(dplyr, warn.conflicts = FALSE)
library(lubridate, warn.conflicts = FALSE)
library(stringr)

# All paths are relative to the repository root
prog_dir <- "question_2_adam"
out_dir <- file.path(prog_dir, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# -----------------------------------------------------------------------------
# 1. Read input SDTM data
# -----------------------------------------------------------------------------
# convert_blanks_to_na(): SDTM data imported from SAS stores missing character
# values as "". admiral expects NA, so blanks are converted first.
dm <- convert_blanks_to_na(pharmaversesdtm::dm)
vs <- convert_blanks_to_na(pharmaversesdtm::vs)
ex <- convert_blanks_to_na(pharmaversesdtm::ex)
ds <- convert_blanks_to_na(pharmaversesdtm::ds)
ae <- convert_blanks_to_na(pharmaversesdtm::ae)


# Study-specific derivation rules shared with the tests:
#   agegr9_lookup   - definition of AGEGR9 / AGEGR9N
#   valid_dose_cond - definition of a valid dose in EX
source(file.path(prog_dir, "specs", "adsl_specs.R"))

# -----------------------------------------------------------------------------
# 2. DM is the basis of ADSL: one record per subject
# -----------------------------------------------------------------------------
adsl <- dm %>%
  select(-DOMAIN)

# -----------------------------------------------------------------------------
# 3. AGEGR9 / AGEGR9N - age groups
# -----------------------------------------------------------------------------
adsl <- adsl %>%
  derive_vars_cat(definition = agegr9_lookup)

# -----------------------------------------------------------------------------
# 4. TRTSDTM / TRTSTMF and TRTEDTM / TRTETMF - treatment start/end datetime
# -----------------------------------------------------------------------------
# Convert EX start/end dates (ISO 8601 character) to numeric datetimes:
#   * highest_imputation = "h": only time parts (hours, minutes, seconds) are
#     imputed; records with an incomplete date part get a missing datetime and
#     are therefore excluded, as required by the specification
#   * time_imputation = "first": missing time parts imputed with 00
#     (start) / "last": imputed with 23:59:59 (end, as in the Pharmaverse
#     example)
#   * ignore_seconds_flag = TRUE: if only the seconds are missing, the
#     imputation flag (--TMF) is not populated
ex_ext <- ex %>%
  derive_vars_dtm(
    dtc                 = EXSTDTC,
    new_vars_prefix     = "EXST",
    highest_imputation  = "h",
    time_imputation     = "first",
    ignore_seconds_flag = TRUE
  ) %>%
  # EXENDTC not specifically mentioned in specifications but needed for LSTAVLDT
  derive_vars_dtm(
    dtc                 = EXENDTC,
    new_vars_prefix     = "EXEN",
    highest_imputation  = "h",
    time_imputation     = "last",
    ignore_seconds_flag = TRUE
  )

adsl <- adsl %>%
  # First exposure record with a valid dose and a complete start date
  derive_vars_merged(
    dataset_add = ex_ext,
    by_vars = exprs(STUDYID, USUBJID),
    filter_add = !!valid_dose_cond & !is.na(EXSTDTM),
    new_vars = exprs(TRTSDTM = EXSTDTM, TRTSTMF = EXSTTMF),
    order = exprs(EXSTDTM, EXSEQ),
    mode = "first"
  ) %>%
  # Last exposure record with a valid dose and a complete end date
  derive_vars_merged(
    dataset_add = ex_ext,
    by_vars = exprs(STUDYID, USUBJID),
    filter_add = !!valid_dose_cond & !is.na(EXENDTM),
    new_vars = exprs(TRTEDTM = EXENDTM, TRTETMF = EXENTMF),
    order = exprs(EXENDTM, EXSEQ),
    mode = "last"
  ) %>%
  # Treatment start/end dates (TRTSDT, TRTEDT)
  derive_vars_dtm_to_dt(source_vars = exprs(TRTSDTM, TRTEDTM))


# -----------------------------------------------------------------------------
# 5. Population flags
# -----------------------------------------------------------------------------
# ITTFL: "Y" if DM.ARM is not missing, else "N" (as specified).
# Note: in pharmaversesdtm::dm, ARM is populated for all subjects, including
# screen failures (ARM = "Screen Failure"), so ITTFL = "Y" for all subjects.
# The specification is implemented as written; see README for details.
adsl <- adsl %>%
  derive_var_merged_exist_flag(
    dataset_add   = dm,
    by_vars       = exprs(STUDYID, USUBJID),
    new_var       = ITTFL,
    condition     = !is.na(ARM),
    false_value   = "N",
    missing_value = "N"
  )


# -----------------------------------------------------------------------------
# 6. LSTAVLDT - last known alive date
# -----------------------------------------------------------------------------
# For each source, only COMPLETE dates are used: convert_dtc_to_dt() with the
# default highest_imputation = "n" returns NA for partial dates, so those
# records do not meet the event condition. The latest date over all events is
# selected (mode = "last").
#   (1) VS: valid result (VSSTRESN and VSSTRESC not both missing) and complete
#       date part of VSDTC
#   (2) AE: complete date part of AESTDTC
#   (3) DS: complete date part of DSSTDTC
#   (4) ADSL: date part of TRTEDTM, i.e. last valid dose (TRTEDT)
adsl <- adsl %>%
  derive_vars_extreme_event(
    by_vars = exprs(STUDYID, USUBJID),
    events = list(
      event(
        dataset_name = "vs",
        order = exprs(VSDTC, VSSEQ),
        condition = !(is.na(VSSTRESN) & is.na(VSSTRESC)) &
          !is.na(convert_dtc_to_dt(VSDTC)),
        set_values_to = exprs(
          LSTAVLDT = convert_dtc_to_dt(VSDTC),
          seq      = VSSEQ
        )
      ),
      event(
        dataset_name = "ae",
        order = exprs(AESTDTC, AESEQ),
        condition = !is.na(convert_dtc_to_dt(AESTDTC)),
        set_values_to = exprs(
          LSTAVLDT = convert_dtc_to_dt(AESTDTC),
          seq      = AESEQ
        )
      ),
      event(
        dataset_name = "ds",
        order = exprs(DSSTDTC, DSSEQ),
        condition = !is.na(convert_dtc_to_dt(DSSTDTC)),
        set_values_to = exprs(
          LSTAVLDT = convert_dtc_to_dt(DSSTDTC),
          seq      = DSSEQ
        )
      ),
      event(
        dataset_name  = "adsl",
        condition     = !is.na(TRTEDT),
        set_values_to = exprs(LSTAVLDT = TRTEDT, seq = 0)
      )
    ),
    source_datasets = list(vs = vs, ae = ae, ds = ds, adsl = adsl),
    tmp_event_nr_var = event_nr,
    order = exprs(LSTAVLDT, seq, event_nr),
    mode = "last",
    new_vars = exprs(LSTAVLDT)
  )

# Intermediate variables are kept for 
# traceability (TRTEDTM, TRTETMF, TRTSDT, TRTEDT)

# -----------------------------------------------------------------------------
# 7. Variable labels
# -----------------------------------------------------------------------------
new_labels <- c(
  AGEGR9   = "Pooled Age Group 9",
  AGEGR9N  = "Pooled Age Group 9 (N)",
  TRTSDTM  = "Datetime of First Exposure to Treatment",
  TRTSTMF  = "Time of First Exposure Imput. Flag",
  TRTEDTM  = "Datetime of Last Exposure to Treatment",
  TRTETMF  = "Time of Last Exposure Imput. Flag",
  TRTSDT   = "Date of First Exposure to Treatment",
  TRTEDT   = "Date of Last Exposure to Treatment",
  ITTFL    = "Intent-To-Treat Population Flag",
  LSTAVLDT = "Last Date Known Alive"
)
for (v in names(new_labels)) attr(adsl[[v]], "label") <- new_labels[[v]]

# -----------------------------------------------------------------------------
# 8. Checks (the program stops with an error if any check fails)
# -----------------------------------------------------------------------------
stopifnot(
  "One record per subject" = !any(duplicated(adsl$USUBJID)),
  "All DM subjects are in ADSL" = setequal(adsl$USUBJID, dm$USUBJID),
  "All new variables present" = all(names(new_labels) %in% names(adsl)),
  "AGEGR9 only uses defined values" =
    all(adsl$AGEGR9 %in% c("<18", "18 - 50", ">50", "Missing")),
  "ITTFL is Y or N" = all(adsl$ITTFL %in% c("Y", "N"))
)

# Summaries for the log
message("ADSL: ", nrow(adsl), " subjects, ", ncol(adsl), " variables")
print(count(adsl, AGEGR9N, AGEGR9))
print(count(adsl, ITTFL))
print(count(adsl, TRTSTMF, has_TRTSDTM = !is.na(TRTSDTM)))
print(summary(adsl$LSTAVLDT))

# -----------------------------------------------------------------------------
# 9. Save the output
# -----------------------------------------------------------------------------
saveRDS(adsl, file.path(out_dir, "adsl.rds"))
write.csv(adsl, file.path(out_dir, "adsl.csv"), row.names = FALSE, na = "")

message("ADSL saved to ", out_dir)
