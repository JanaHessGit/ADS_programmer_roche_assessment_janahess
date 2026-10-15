# ADS_programmer_roche_assessment_janahess

# Question 2 – ADaM ADSL dataset with {admiral}

Creates the subject-level analysis dataset **ADSL** from the SDTM data in
`{pharmaversesdtm}` (DM, EX, VS, AE, DS), following the
[Pharmaverse ADSL example](https://pharmaverse.github.io/examples/) and the
[{admiral} ADSL vignette](https://pharmaverse.github.io/admiral/cran-release/articles/adsl.html),
with the additional variables requested in the assessment.

## Files

| File | Content |
|---|---|
| `create_adsl.R` | ADSL program (deliverable) |
| `R/adsl_specs.R` | Study-specific rules used by both program and tests: age-group lookup (`agegr9_lookup`) and valid-dose condition (`valid_dose_cond`) |
| `run_question_2.R` | Runs the program with {logrx} (log file) and then the tests |
| `create_adsl.log` | {logrx} log – evidence that the program runs without errors or warnings |
| `output/adsl.rds`, `output/adsl.csv` | Resulting ADSL (306 subjects) |
| `tests/testthat/test-adsl.R` | Unit tests and independent QC (double programming) of all requested variables |
| `tests/test_results.txt` | Results of the last test run |

## How to run

Install the packages once:

```r
install.packages(c("admiral", "pharmaversesdtm", "pharmaverseadam",
                   "dplyr", "lubridate", "stringr", "logrx", "testthat"))
```

Then, **from the repository root** (e.g. open the RStudio project):

```r
# Program + log file + tests
source("question_2_adam/run_question_2.R")
```

or in a terminal: `Rscript question_2_adam/run_question_2.R`

Only the program with a log file:

```r
logrx::axecute("question_2_adam/create_adsl.R",
               log_name = "create_adsl.log",
               log_path = "question_2_adam")
```

Only the tests (after the program has been run):

```r
testthat::test_dir("question_2_adam/tests/testthat")
```

## Derivations

| Variable | Derivation | {admiral} function |
|---|---|---|
| `AGEGR9`, `AGEGR9N` | `"<18"` = 1, `"18 - 50"` = 2 (18 and 50 inclusive), `">50"` = 3; missing if AGE is missing | `derive_vars_cat()` |
| `TRTSDTM`, `TRTSTMF` | First EX record (by start datetime, then EXSEQ) with a **valid dose** and a complete start date. Missing hours/minutes/seconds imputed with 00; flag not set if only seconds are missing | `derive_vars_dtm()` (`highest_imputation = "h"`, `time_imputation = "first"`, `ignore_seconds_flag = TRUE`), `derive_vars_merged()` |
| `ITTFL` | `"Y"` if `DM.ARM` is not missing, else `"N"` | `mutate()` |
| `LSTAVLDT` | Latest of: last complete VS date with a valid result, last complete AE start date, last complete DS start date, last valid-dose date (date part of `TRTEDTM`) | `derive_vars_extreme_event()`, `convert_dtc_to_dt()` |
| Supporting: `TRT01P`, `TRT01A`, `TRTEDTM`/`TRTETMF`, `TRTSDT`, `TRTEDT`, `TRTDURD`, `SAFFL` | As in the Pharmaverse ADSL example (`TRTEDTM` is needed for `LSTAVLDT`) | `derive_vars_merged()`, `derive_vars_dtm_to_dt()`, `derive_var_trtdurd()`, `derive_var_merged_exist_flag()` |

**Valid dose:** `EXDOSE > 0`, or `EXDOSE == 0` and `EXTRT` contains `"PLACEBO"`.

## Assumptions and observations

1. **ITTFL** is implemented exactly as specified (`ARM` not missing). In
   `pharmaversesdtm::dm`, `ARM` is populated for all 306 subjects, including
   the 52 screen failures (`ARM = "Screen Failure"`), so `ITTFL = "Y"` for
   everyone. If screen failures should be excluded from the ITT population,
   the condition would change to
   `!is.na(ARM) & ARM != "Screen Failure"`; this would need to be confirmed
   with the study statistician.
2. **"Complete" dates** for LSTAVLDT: partial dates (e.g. `"2013-05"`) are not
   imputed but excluded, as the specification requires complete dates
   (26 AE start dates are partial).
3. **ignore_seconds_flag:** {admiral} only allows this option when seconds are
   never collected. EX in this study contains dates only, so all `TRTSTMF`
   are `"H"`. If seconds were ever collected, the program would stop with an
   error rather than produce an inconsistent flag (covered by a test).
4. **TRTEDTM** missing times are imputed with 23:59:59, as in the Pharmaverse
   example; only its date part is used for LSTAVLDT.
5. **AGEGR9:** all subjects in this study are 50 or older, so only `"18 - 50"`
   (1 subject, age 50) and `">50"` occur. Boundary values are covered by unit
   tests on dummy data.

## Tests

`tests/testthat/test-adsl.R` contains 13 tests (22 expectations):

- **Unit tests** of the derivation rules on dummy data, including boundary
  values (ages 17, 18, 50, 51, missing), the valid-dose definition and the
  time imputation/flag rules.
- **Independent QC (double programming):** `AGEGR9/N`, `TRTSDTM/TRTSTMF`,
  `ITTFL` and `LSTAVLDT` are re-derived from SDTM with plain
  dplyr/lubridate (no {admiral}) and compared with the production ADSL.
- **Structure:** one record per DM subject, all requested variables present,
  correct types.
- **Reference check:** `TRTSDTM`/`TRTEDTM` agree with `pharmaverseadam::adsl`
  (skipped if {pharmaverseadam} is not installed).
