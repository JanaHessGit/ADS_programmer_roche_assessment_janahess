# =============================================================================
# Program     : 01_create_ae_summary_table.R
# Purpose     : Summary table of treatment-emergent adverse events (TEAEs) by
#               primary system organ class and reported term, using
#               {gtsummary} (layout as FDA Table 10 / assessment sample).
# Input       : pharmaverseadam::adae - Adverse Events Analysis Dataset
#               pharmaverseadam::adsl - Subject-Level Analysis Dataset
# Output      : question_3_tlg/output/ae_summary_table.html - the table
#               question_3_tlg/output/ae_summary_table.rds  - gtsummary object
#                                                           (used by the tests)
#
# Specification:
#   * TEAEs: ADAE records with TRTEMFL == "Y"
#   * Rows: AESOC (system organ class) with AETERM (reported term) nested
#     below, plus an overall "Treatment Emergent AEs" row
#   * Columns: treatment groups (ACTARM) and a Total column
#   * Cells: n (%) = number of SUBJECTS with at least one TEAE (a subject is
#     counted once per row) and percentage of the subjects in the column
#   * Denominator (N): safety population in ADSL (SAFFL == "Y") per ACTARM
#   * Sorted by descending frequency (SOCs, and terms within each SOC)
#
# How to run  : from the repository root, with log file (see README.md):
#                 logrx::axecute("question_3_tlg/01_create_ae_summary_table.R",
#                                log_name = "01_create_ae_summary_table.log",
#                                log_path = "question_3_tlg")
#
# =============================================================================
library(pharmaverseadam)
library(gtsummary)
library(webshot2)
library(dplyr, warn.conflicts = FALSE)

prog_dir <- "question_3_tlg"
out_dir  <- file.path(prog_dir, "output")
dir.create(out_dir, showWarnings = FALSE, recursive = TRUE)

# -----------------------------------------------------------------------------
# 1. Input data
# -----------------------------------------------------------------------------
# Denominator: safety population (subjects who received study treatment)
adsl <- pharmaverseadam::adsl %>%
  filter(SAFFL == "Y") %>%
  select(USUBJID, ACTARM)

# Treatment-emergent AEs of safety-population subjects
adae <- pharmaverseadam::adae %>%
  filter(TRTEMFL == "Y", USUBJID %in% adsl$USUBJID)


message("Safety population: ", nrow(adsl), " subjects; TEAE records: ",
        nrow(adae), " from ", n_distinct(adae$USUBJID), " subjects")

# -----------------------------------------------------------------------------
# 2. Hierarchical TEAE table
# -----------------------------------------------------------------------------
# tbl_hierarchical() counts subjects (id = USUBJID) per SOC and per term, with
# the column totals (N) taken from the `denominator` dataset.
ae_table <- adae %>%
  tbl_hierarchical(
    variables   = c(AESOC, AETERM),
    by          = ACTARM,
    id          = USUBJID,
    denominator = adsl,
    overall_row = TRUE,
    label       = list(..ard_hierarchical_overall.. = "Treatment Emergent AEs")
  ) %>%
  # Total column with all subjects, placed after the treatment columns
  add_overall(last = TRUE, col_label = "**Total**  \nN = {style_number(N)}") %>%
  # Descending frequency: SOCs by number of subjects, terms within each SOC
  sort_hierarchical(sort = everything() ~ "descending") %>%
  modify_caption("**Treatment-Emergent Adverse Events by System Organ Class
                 and Reported Term (Safety Population)**") %>%
  modify_footnote_header(
    footnote = "n (%) = number (percentage) of subjects with at least one
                event; a subject is counted once per row.",
    columns = all_stat_cols()
  )

# Preview in the log
print(as_tibble(ae_table), n = 15)

# -----------------------------------------------------------------------------
# 3. Save the output
# -----------------------------------------------------------------------------
gt::gtsave(as_gt(ae_table), file.path(out_dir, "ae_summary_table.html"))
gt::gtsave(as_gt(ae_table), file.path(out_dir, "ae_summary_table.docx"))
gt::gtsave(as_gt(ae_table), file.path(out_dir, "ae_summary_table.pdf"))
saveRDS(ae_table, file.path(out_dir, "ae_summary_table.rds"))

message("AE summary table saved to ", out_dir)
