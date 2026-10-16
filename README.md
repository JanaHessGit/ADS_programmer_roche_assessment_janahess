# ADS Programmer Coding Assessment – Jana Heß

Solutions to the coding assessment for the **Senior Analytical Data Science
(ADS) Programmer** position at Roche, written in R with the
[pharmaverse](https://pharmaverse.org/) packages.

| Question | Topic | Main packages | Folder |
|---|---|---|---|
| 1 | SDTM DS (Disposition) domain from raw eCRF data | {sdtm.oak} | [`question_1_sdtm/`](question_1_sdtm/) |
| 2 | ADaM ADSL (Subject-Level Analysis Dataset) | {admiral} | [`question_2_adam/`](question_2_adam/) |
| 3 | TLG – adverse events summary table and plots | {gtsummary}, {ggplot2} | [`question_3_tlg/`](question_3_tlg/) |

Each folder contains:

- the **program(s)** required by the assessment,
- the **output** (datasets, table, plots) in `output/`,
- a **{logrx} log file** per program as evidence that it runs without errors
  or warnings,
- **tests** (`tests/testthat/`): structural checks, independent re-derivation
  of the results (double programming) and, where available, comparison with
  the pharmaverse reference datasets,
- a **README** describing the derivations, assumptions and how to run the code.

## Repository structure

```
.
├── README.md                        # this overview
├── renv.lock                        # package versions used (renv::restore())
├── .Rprofile                        # activates renv when R starts here
├── renv/                            # renv infrastructure (activate.R, settings)
├── question_1_sdtm/
│   ├── README.md                    # mapping, assumptions, how to run
│   ├── 01_create_ds_domain.R        # DS domain program
│   ├── 01_create_ds_domain.log      # logrx log
│   ├── metadata/sdtm_ct.csv         # study controlled terminology
│   ├── output/                      # ds.rds, ds.csv
│   └── tests/testthat/test-ds.R
├── question_2_adam/
│   ├── README.md                    # derivations, assumptions, how to run
│   ├── create_adsl.R                # ADSL program
│   ├── create_adsl.log              # logrx log
│   ├── specs/adsl_specs.R           # derivation rules shared with the tests
│   ├── output/                      # adsl.rds, adsl.csv
│   └── tests/testthat/test-adsl.R
└── question_3_tlg/
    ├── README.md                    # table/plot derivations, assumptions, how to run
    ├── 01_create_ae_summary_table.R # TEAE summary table
    ├── 02_create_visualizations.R   # AE plots
    ├── *.log                        # logrx logs
    ├── dependencies.R               # library(logrx), so renv records {logrx}
    ├── R/tlg_functions.R            # helper functions shared with the tests
    ├── output/                      # table (HTML/DOCX/RDS), plots (PNG), plot data (CSV)
    └── tests/testthat/test-tlg.R
```

## How to run

1. Clone the repository and open it in RStudio (or set the repository folder
   as working directory). **All paths are relative to the repository root.**
2. Install the packages (once):

   ```r
   install.packages(c(
     "sdtm.oak", "admiral", "pharmaverseraw", "pharmaversesdtm",
     "pharmaverseadam", "gtsummary", "gt", "ggplot2", "dplyr", "tidyr",
     "purrr", "stringr", "lubridate", "scales", "logrx", "testthat"
   ))
   ```
   OR
   
   Restore the package versions used for this submission (recorded in
   `renv.lock`, R 4.6.0):
   ```r
   renv::restore()
   ```
   
3. Run each program with a log file, then its tests, e.g. for Question 1:

   ```r
   logrx::axecute("question_1_sdtm/01_create_ds_domain.R",
                  log_name = "01_create_ds_domain.log",
                  log_path = "question_1_sdtm")
   testthat::test_dir("question_1_sdtm/tests/testthat")
   ```

   The exact commands for every program are in the README of each folder.

## Results at a glance

| Question | Result | Tests |
|---|---|---|
| 1 – DS | 850 records, 306 subjects; identical to `pharmaversesdtm::ds` | 24 passed |
| 2 – ADSL | 306 subjects with AGEGR9/AGEGR9N, TRTSDTM/TRTSTMF, ITTFL (254 randomized), LSTAVLDT | 23 passed |
| 3 – TLG | TEAE table (FDA Table 10 layout), severity bar chart, top-10 AE plot with 95% Clopper-Pearson CIs | 49 passed |

Assumptions and data observations are documented in each folder's README.

## Environment

Run with R 4.6.0. The exact R and package versions of each run are recorded
in the session information of the log files.

## Use of AI tools

AI assistants (GitHub Copilot, Claude) were used to draft parts of the code, documentation and
tests. All code was reviewed and run against the specifications and
the pharmaverse reference datasets. AI-drafted tests were reviewed, run and extended.

## Note

The following link provided in the coding assessment is not working anymore: https://pharmaverse.github.io/rinpharma-SDTM-workshop/

