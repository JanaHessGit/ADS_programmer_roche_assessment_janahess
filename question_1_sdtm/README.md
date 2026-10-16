# Question 1 – SDTM DS domain with {sdtm.oak}

Creates the SDTM **DS (Disposition)** domain from the raw eCRF data
`pharmaverseraw::ds_raw`, following the Subject Disposition annotated CRF
(aCRF) and the SDTMIG v3.4, using {sdtm.oak}.

## Files

| File | Content |
|---|---|
| `01_create_ds_domain.R` | DS program (deliverable) |
| `metadata/sdtm_ct.csv` | Study controlled terminology (from the GitHub link in the assessment: https://github.com/pharmaverse/examples/blob/main/metadata/sdtm_ct.csv) |
| `01_create_ds_domain.log` | {logrx} log – evidence that the program runs without errors or warnings |
| `output/ds.rds`, `output/ds.csv` | Resulting DS domain (850 records, 306 subjects, 12 variables) |
| `tests/testthat/test-ds.R` | Structure checks, independent QC of the aCRF rules and comparison with the reference DS domain |

## How to run

Install the packages once:

Recommended: run

```r
renv::restore()
```

from the repository root (see main README).

OR

```r
install.packages(c("sdtm.oak", "pharmaverseraw", "pharmaversesdtm",
                   "dplyr", "stringr", "lubridate", "logrx", "testthat"))
```


All commands are run **from the repository root**, i.e. with the repository
folder as working directory (see main README).

**Step 1 – Run the program and create the log file**

```r
logrx::axecute(
  file     = "question_1_sdtm/01_create_ds_domain.R",
  log_name = "01_create_ds_domain.log",
  log_path = "question_1_sdtm"
)
```

This runs the program and writes:

- `question_1_sdtm/01_create_ds_domain.log` – the log file. Its **Errors** and
  **Warnings** sections are empty when the program runs error-free. It also
  records the R and package versions, run time and a hash of the program.
- `question_1_sdtm/output/ds.rds` and `ds.csv` – the DS domain.

Alternative in a terminal (without {logrx}, console output only):

```
Rscript question_1_sdtm/01_create_ds_domain.R > question_1_sdtm/01_create_ds_domain.log 2>&1
```

**Step 2 – Run the tests (after step 1)**

```r
testthat::test_dir("question_1_sdtm/tests/testthat")
```

All tests should pass (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 24 ]`).

## Mapping

| DS variable | Source / rule | {sdtm.oak} function |
|---|---|---|
| `STUDYID` | `STUDY` | – |
| `DOMAIN` | `"DS"` | – |
| `USUBJID` | From DM, matched on `PATNUM` = `DM.SITEID-DM.SUBJID` | – |
| `DSSEQ` | Sequence per subject, chronological by `DSSTDTC` | `derive_seq()` |
| `DSTERM` | `IT.DSTERM` if `OTHERSP` is null, else `OTHERSP` (aCRF) | `assign_no_ct()` + `condition_add()` |
| `DSDECOD` | `IT.DSDECOD` (codelist C66727) if `OTHERSP` is null, else `OTHERSP` (aCRF) | `assign_ct()` / `assign_no_ct()` + `condition_add()` |
| `DSCAT` | `"PROTOCOL MILESTONE"` if `IT.DSDECOD = "Randomized"`, `"OTHER EVENT"` if `OTHERSP` not null, else `"DISPOSITION EVENT"` (aCRF; checked against codelist C74558) | `hardcode_ct()` + `condition_add()` |
| `VISIT`, `VISITNUM` | `INSTANCE` via the study visit codelists (pharmaverse VS example) | `assign_ct()` |
| `DSDTC` | `DSDTCOL` + `DSTMCOL` in ISO 8601 (aCRF) | `assign_datetime()` |
| `DSSTDTC` | `IT.DSSTDAT` in ISO 8601 (aCRF) | `assign_datetime()` |
| `DSSTDY` | Study day of `DSSTDTC` relative to `DM.RFXSTDTC`, no day 0 | `derive_study_day()` |

## Assumptions and observations

1. **Variable name:** the aCRF annotates the start date as `IT.DSSDAT`; in
   `ds_raw` the variable is `IT.DSSTDAT`.
2. **DSDECOD and controlled terminology:** `assign_ct()` reports
   "Randomized", "Completed", "Screen Failure", "Lost to Follow-Up" and
   "Study Terminated by Sponsor" as not mapped, because the collected values
   in the study CT differ in wording or case. The upper-cased values equal
   the C66727 submission values (checked by the program and a test).
   "Randomized" is a protocol milestone (CDISC codelist PROTMLST), which is
   not part of C66727 and PROTMLST is not contained in the provided 
   sdtm_ct.
3. **VISITNUM outside the study CT:** "Ambul Ecg Removal" (case differs from
   the CT value "Ambul ECG Removal") and the unscheduled visits
   ("Unscheduled x.y") are not in the study CT. VISITNUM is derived by a
   documented fallback (case-insensitive CT lookup; x.y from the visit name)
   and listed in the log. Alternatively, they could be added to the study CT.
4. **DSSTDY** uses `RFXSTDTC`, as in the pharmaverse examples; it has
   identical values to `RFSTDTC` for all subjects in this study.
5. **Validation:** the output has identical values to `pharmaversesdtm::ds` 
   (the reference DS domain created from the same raw data) for all 
   12 variables.

## Tests

`tests/testthat/test-ds.R` contains 13 tests (24 expectations):

- **Structure:** variable order, record count, unique key, required
  variables, valid DSCAT/VISITNUM values, DSDECOD in C66727, ISO 8601 format
  with valid calendar dates.
- **Independent QC:** DSTERM, DSDECOD, DSCAT, DSDTC, DSSTDTC and VISIT 
  are re-derived from `ds_raw` with plain dplyr/lubridate;
  DSSTDY is recalculated from DM; DSSEQ is checked for chronological order.
- **Reference:** the output is compared with `pharmaversesdtm::ds`.

Tests were drafted with GitHub Copilot, Claude and extended manually.
