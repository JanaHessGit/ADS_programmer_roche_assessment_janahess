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
| `specs/adsl_specs.R` | Study-specific rules used by both program and tests: age-group lookup (`agegr9_lookup`) and valid-dose condition (`valid_dose_cond`) |
| `create_adsl.log` | {logrx} log – evidence that the program runs without errors or warnings |
| `output/adsl.rds`, `output/adsl.csv` | Resulting ADSL (306 subjects; DM variables + AGEGR9, AGEGR9N, TRTSDTM, TRTSTMF, ITTFL, LSTAVLDT and the supporting variables TRTEDTM, TRTETMF, TRTSDT, TRTEDT) |
| `tests/testthat/test-adsl.R` | Unit tests and independent QC (double programming) of all requested variables |

## How to run

Set up the packages as described in the main README (start R in the repository folder, then renv::restore()). Restart R before running each program or

```r
install.packages(c("admiral", "pharmaversesdtm", "pharmaverseadam",
                   "dplyr", "lubridate", "stringr", "logrx", "testthat"))
```

All commands are run **from the repository root**, i.e. with the repository
folder as working directory (see main README).

**Step 1 – Run the program and create the log file**

```r
logrx::axecute(
  file     = "question_2_adam/create_adsl.R",
  log_name = "create_adsl.log",
  log_path = "question_2_adam"
)
```

This runs `create_adsl.R` and writes:

- `question_2_adam/create_adsl.log` – the log file. Its **Errors** and
  **Warnings** sections are empty when the program runs error-free. It also
  records the R and package versions, run time and a hash of the program.
- `question_2_adam/output/adsl.rds` and `adsl.csv` – the ADSL dataset.

Alternative in a terminal (without {logrx}, console output only):

```
Rscript question_2_adam/create_adsl.R > question_2_adam/create_adsl.log 2>&1
```

**Step 2 – Run the tests (after step 1)**

```r
testthat::test_dir("question_2_adam/tests/testthat")
```

All tests should pass (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 23 ]`). The
reference check against `pharmaverseadam::adsl` is skipped if
{pharmaverseadam} is not installed.

## Derivations

| Variable | Derivation | {admiral} function |
|---|---|---|
| `AGEGR9`, `AGEGR9N` | `"<18"` = 1, `"18 - 50"` = 2 (18 and 50 inclusive), `">50"` = 3; `"Missing"` = 4 if AGE is missing | `derive_vars_cat()` |
| `TRTSDTM`, `TRTSTMF` | First EX record (by start datetime, then EXSEQ) with a **valid dose** and a complete start date. Missing hours/minutes/seconds imputed with 00; flag not set if only seconds are missing | `derive_vars_dtm()` (`highest_imputation = "h"`, `time_imputation = "first"`, `ignore_seconds_flag = TRUE`), `derive_vars_merged()` |
| `ITTFL` | `"Y"` if the subject was randomized, i.e. `DM.ARM` is not missing and not `"Screen Failure"`, else `"N"` | `derive_var_merged_exist_flag()` |
| `LSTAVLDT` | Latest of: last complete VS date with a valid result, last complete AE start date, last complete DS start date, last valid-dose date (date part of `TRTEDTM`) | `derive_vars_extreme_event()`, `convert_dtc_to_dt()` |
| Supporting: `TRTEDTM`, `TRTETMF` | Last EX record with a valid dose and a complete end date (missing time imputed with 23:59:59) and its time imputation flag. TRTEDTM is referenced as ADSL.TRTEDTM in the LSTAVLDT specification | `derive_vars_merged()` |
| Supporting: `TRTSDT`, `TRTEDT` | Date parts of TRTSDTM and TRTEDTM; TRTEDT is the last valid-dose date used for LSTAVLDT | `derive_vars_dtm_to_dt()` |

**Valid dose:** `EXDOSE > 0`, or `EXDOSE == 0` and `EXTRT` contains `"PLACEBO"`.

## Assumptions and observations

1. **ITTFL** flags randomized subjects, as specified. The specification
   identifies them by a non-missing `DM.ARM`, but in `pharmaversesdtm::dm`
   `ARM` is also populated for the 52 screen failures
   (`ARM = "Screen Failure"`), who were not randomized. They are therefore
   excluded explicitly: `ITTFL = "Y"` for 254 subjects, `"N"` for 52. These
   are exactly the subjects with a `"RANDOMIZED"` record in DS, which the
   tests use as an independent check.
2. **"Complete" dates** for LSTAVLDT: partial dates (e.g. `"2013-05"`) are not
   imputed but excluded, as the specification requires complete dates
   (26 AE start dates are partial).
3. **ignore_seconds_flag:** {admiral} only allows this option when seconds are
   never collected. EX in this study contains dates only (no times), so the
   whole time is imputed (00:00:00) and `TRTSTMF = "H"` for all 254 subjects
   with a valid dose. The 52 screen failures have no exposure, so `TRTSDTM`
   and `TRTSTMF` are missing for them. If seconds were ever collected, the
   program would stop with an error rather than produce an inconsistent flag
   (covered by a test).
4. **TRTEDTM** missing times are imputed with 23:59:59, as in the Pharmaverse
   example; only its date part is used for LSTAVLDT.
5. **AGEGR9:** all subjects in this study are 50 or older, so only `"18 - 50"`
   (1 subject, age 50) and `">50"` occur. Boundary values are covered by unit
   tests on dummy data.
6. **Missing age:** the specification defines no category for a missing age.
   Subjects with missing AGE are assigned `AGEGR9 = "Missing"`,
   `AGEGR9N = 4` (as `AGEGR1` in the Pharmaverse ADSL example), so that they
   are visible as their own category in tables instead of being dropped. No
   subject in this study has a missing age.
7. **Supporting variables:** `TRTEDTM`, `TRTETMF`, `TRTSDT` and `TRTEDT` are
   not requested, but are needed to derive `LSTAVLDT` and are kept in ADSL so
   that the derivation can be traced.

## Tests

`tests/testthat/test-adsl.R` contains 12 tests (23 expectations):

- **Unit tests** of the derivation rules on dummy data, including boundary
  values (ages 17, 18, 50, 51, missing), the valid-dose definition and the
  time imputation/flag rules.
- **Independent QC:** `AGEGR9/N`, `TRTSDTM/TRTSTMF`,
  `ITTFL` and `LSTAVLDT` are re-derived from SDTM with plain
  dplyr/lubridate (no {admiral}) and compared with the production ADSL.
  ITTFL is checked against a different source than the program uses: the
  subjects with a `"RANDOMIZED"` record in DS.
- **Structure:** one record per DM subject, all requested variables present,
  correct types.
- **Reference check:** `TRTSDTM`/`TRTEDTM` agree with `pharmaverseadam::adsl`
  (skipped if {pharmaverseadam} is not installed).

Tests were drafted with GitHub Copilot, Claude and extended manually.

