# Question 3 – TLG: Adverse Events Reporting

Creates a summary table of treatment-emergent adverse events with
{gtsummary} and two adverse event visualizations with {ggplot2}, from
`pharmaverseadam::adae` and `pharmaverseadam::adsl`.

## Files

| File | Content |
|---|---|
| `01_create_ae_summary_table.R` | TEAE summary table (deliverable) |
| `02_create_visualizations.R` | Severity bar chart and top-10 AE plot (deliverable) |
| `R/tlg_functions.R` | Helper functions used by `02_create_visualizations.R` and the tests: `count_ae_by_severity()`, `top_ae_incidence()` |
| `01_create_ae_summary_table.log`, `02_create_visualizations.log` | {logrx} logs – evidence that both programs run without errors or warnings |
| `output/ae_summary_table.html`, `output/ae_summary_table.docx` | TEAE summary table (HTML; DOCX as editable copy) |
| `output/ae_severity_by_treatment.png` | Plot 1 – AE severity distribution by treatment |
| `output/top10_ae_incidence.png` | Plot 2 – Top 10 most frequent AEs with 95% CIs |
| `output/*.csv`, `output/ae_summary_table.rds` | Data behind the plots and the table object, used for QC/tests |
| `tests/testthat/test-tlg.R` | Unit tests, independent QC of the table and plot data, output checks |

## How to run

Install the packages once:

Recommended: run renv::restore() from the repository root (see main README).

OR

```r
install.packages(c("gtsummary", "gt", "ggplot2", "dplyr", "tidyr", "purrr",
                   "scales", "pharmaverseadam", "logrx", "testthat"))
```

All commands are run **from the repository root**, i.e. with the repository
folder as working directory (e.g. open the RStudio project).

**Step 1 – Run the programs and create the log files**

```r
logrx::axecute(
  file     = "question_3_tlg/01_create_ae_summary_table.R",
  log_name = "01_create_ae_summary_table.log",
  log_path = "question_3_tlg"
)
logrx::axecute(
  file     = "question_3_tlg/02_create_visualizations.R",
  log_name = "02_create_visualizations.log",
  log_path = "question_3_tlg"
)
```

The **Errors** and **Warnings** sections of both logs are empty when the
programs run error-free. The outputs are written to `question_3_tlg/output/`.

Alternative in a terminal (without {logrx}, console output only):

```
Rscript question_3_tlg/01_create_ae_summary_table.R > question_3_tlg/01_create_ae_summary_table.log 2>&1
Rscript question_3_tlg/02_create_visualizations.R > question_3_tlg/02_create_visualizations.log 2>&1
```

**Step 2 – Run the tests (after step 1)**

```r
testthat::test_dir("question_3_tlg/tests/testthat")
```

All tests should pass (`[ FAIL 0 | WARN 0 | SKIP 0 | PASS 41 ]`).

## Outputs and derivations

### TEAE summary table (`{gtsummary}`, FDA Table 10 layout)

| Requirement | Implementation |
|---|---|
| Treatment-emergent AEs | ADAE records with `TRTEMFL == "Y"` |
| Rows: AESOC / AETERM | `tbl_hierarchical(variables = c(AESOC, AETERM))`, plus an overall "Treatment Emergent AEs" row |
| Columns: ACTARM | `by = ACTARM` |
| n (%) | Number and percentage of **subjects** (`id = USUBJID`): a subject is counted once per row |
| Denominator | Safety population in ADSL (`SAFFL == "Y"`): Placebo N = 86, Xanomeline High Dose N = 72, Xanomeline Low Dose N = 96 |
| Total column | `add_overall(last = TRUE)`, N = 254 |
| Sort by descending frequency | `sort_hierarchical()`: SOCs by number of subjects, terms within each SOC |

### Plot 1 – AE severity distribution by treatment

Stacked bars of the number of AE **records** in ADAE by `ACTARM` and `AESEV`
(MILD, MODERATE, SEVERE), as in the sample output.

### Plot 2 – Top 10 most frequent AEs

Subject incidence per `AETERM` (subjects with at least one record of the
term), the 10 most frequent terms, with exact **95% Clopper-Pearson**
confidence intervals (`stats::binom.test()`).

## Assumptions

1. **Plots use all ADAE records** (not only TEAEs) and Plot 2 uses all
   **225 subjects in ADAE** as denominator, to match the sample output in the
   assessment (e.g. Pruritus 57/225 = 25.3%). A conventional incidence rate
   would use the safety population (N = 254) as denominator;
   `top_ae_incidence()` has a `denominator` argument for this.
2. **Table denominator:** the safety population (`SAFFL == "Y"`), which gives
   exactly the column N's of the sample output (86 / 72 / 96).
3. **Ties** in the top-10 plot are ordered alphabetically.

## Tests

`tests/testthat/test-tlg.R` contains 13 tests (41 expectations):

- **Unit tests** of `count_ae_by_severity()` and `top_ae_incidence()` on
  dummy data: zero counts, unknown severities, subjects counted once,
  ties, exact CIs, custom denominator.
- **Independent QC of the table:** column N's, the overall TEAE row and the
  subject counts for every SOC/term and arm (incl. Total) are re-derived with
  plain dplyr; percentages and the descending sort order are checked.
- **Plot data QC:** severity counts and top-10 incidences/CIs are
  re-derived from ADAE and compared with the saved plot data.
- **Output files** exist and are not empty.
