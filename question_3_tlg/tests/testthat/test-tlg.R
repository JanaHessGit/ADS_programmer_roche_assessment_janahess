# =============================================================================
# Tests for question_3_tlg (AE summary table and visualizations)
#
# Three types of tests:
#   1. Unit tests of the helper functions in R/tlg_functions.R on small dummy
#      data with known results (incl. zero counts and ties).
#   2. Independent QC ("double programming") of the summary table: subject
#      counts and percentages are re-derived with plain dplyr and compared
#      with the gtsummary table; the sort order is checked.
#   3. QC of the plot data and checks that all output files exist.
#
# Prerequisite: both programs have been run (files in output/ exist).
# Run from the repository root:
#   testthat::test_dir("question_3_tlg/tests/testthat")
# =============================================================================



library(testthat, warn.conflicts = FALSE)
library(dplyr, warn.conflicts = FALSE)
library(pharmaverseadam)

local_edition(3)

# testthat runs the tests with tests/testthat as working directory
source(test_path("..", "..", "R", "tlg_functions.R"))
out_dir <- test_path("..", "..", "output")

adsl_saf <- pharmaverseadam::adsl %>% filter(SAFFL == "Y")
adae <- pharmaverseadam::adae
teae <- adae %>% filter(TRTEMFL == "Y", USUBJID %in% adsl_saf$USUBJID)

# Helper: "65 (76%)" -> 65
parse_n <- function(x) as.integer(sub("\\s*\\(.*$", "", x))

# =============================================================================
# 1. Unit tests of the helper functions
# =============================================================================
test_that("count_ae_by_severity counts records and fills missing combos", {
  dummy <- tibble(
    ACTARM = c("A", "A", "A", "B"),
    AESEV  = c("MILD", "MILD", "SEVERE", "MODERATE")
  )
  out <- count_ae_by_severity(dummy)

  expect_equal(nrow(out), 6) # 2 arms x 3 severities
  expect_equal(out$n[out$ACTARM == "A" & out$AESEV == "MILD"], 2)
  expect_equal(out$n[out$ACTARM == "A" & out$AESEV == "MODERATE"], 0)
  expect_equal(out$n[out$ACTARM == "B" & out$AESEV == "MODERATE"], 1)
  expect_identical(levels(out$AESEV), c("MILD", "MODERATE", "SEVERE"))
})

test_that("count_ae_by_severity rejects unknown severity values", {
  dummy <- tibble(ACTARM = "A", AESEV = "LIFE THREATENING")
  expect_error(count_ae_by_severity(dummy))
})

test_that("top_ae_incidence counts subjects once and gives exact CIs", {
  dummy <- tibble(
    USUBJID = c("1", "1", "2", "3", "3", "4"),
    AETERM  = c("HEADACHE", "HEADACHE", "HEADACHE", "NAUSEA", "RASH", "RASH")
  )
  out <- top_ae_incidence(dummy, n_top = 2)

  # HEADACHE: subjects 1 and 2 (subject 1 counted once) -> 2/4
  expect_identical(out$AETERM, c("HEADACHE", "RASH")) # tie broken by name
  expect_equal(out$n, c(2, 2))
  expect_equal(out$pct, c(0.5, 0.5))
  # Clopper-Pearson CI for 2/4, from stats::binom.test
  expect_equal(out$ci_low[1], binom.test(2, 4)$conf.int[1])
  expect_equal(out$ci_high[1], binom.test(2, 4)$conf.int[2])
  expect_true(all(out$ci_low <= out$pct & out$pct <= out$ci_high))
})

test_that("top_ae_incidence uses a custom denominator", {
  dummy <- tibble(USUBJID = c("1", "2"), AETERM = c("RASH", "RASH"))
  out <- top_ae_incidence(dummy, denominator = 10)
  expect_equal(out$pct, 0.2)
  expect_error(top_ae_incidence(dummy, denominator = 1))
})

# =============================================================================
# 2. Independent QC of the AE summary table
# =============================================================================
ae_table <- readRDS(file.path(out_dir, "ae_summary_table.rds"))
# table_body: one row per table row, with variable (AESOC/AETERM), label,
# group1_level (the SOC of a term row) and the cell strings stat_*
tbl_df <- ae_table$table_body

# Column order of the table: one column per arm (alphabetical), then Total
arms <- sort(unique(adsl_saf$ACTARM))
stat_cols <- c(paste0("stat_", seq_along(arms)), "stat_0")

test_that("Column headers show the safety-population N per arm and total", {
  headers <- ae_table$table_styling$header %>%
    filter(column %in% stat_cols) %>%
    arrange(match(column, stat_cols)) %>%
    pull(label)
  n_arm <- adsl_saf %>%
    count(ACTARM) %>%
    arrange(ACTARM)

  expect_match(headers[1], paste0("N = ", n_arm$n[1]))
  expect_match(headers[2], paste0("N = ", n_arm$n[2]))
  expect_match(headers[3], paste0("N = ", n_arm$n[3]))
  expect_match(headers[4], paste0("N = ", nrow(adsl_saf)))
  expect_match(headers[4], "Total")
})

test_that("Overall TEAE row matches an independent count", {
  qc <- teae %>%
    distinct(USUBJID, ACTARM) %>%
    count(ACTARM) %>%
    arrange(ACTARM)
  row <- tbl_df %>% filter(label == "Treatment Emergent AEs")

  expect_equal(
    parse_n(unlist(row[stat_cols])),
    c(qc$n, n_distinct(teae$USUBJID)),
    ignore_attr = TRUE
  )
})

test_that("Subject counts per term match an independent count", {
  qc <- teae %>%
    distinct(USUBJID, ACTARM, AESOC, AETERM) %>%
    count(AESOC, AETERM, ACTARM) %>%
    tidyr::pivot_wider(
      names_from = ACTARM, values_from = n,
      values_fill = 0
    ) %>%
    mutate(Total = rowSums(across(all_of(arms))))

  # Term rows of the table (a term is identified by its SOC and its name)
  prod <- tbl_df %>%
    filter(variable == "AETERM") %>%
    transmute(
      AESOC = group1_level,
      AETERM = label,
      across(all_of(stat_cols), parse_n)
    )

  joined <- inner_join(qc, prod, by = c("AESOC", "AETERM"))
  expect_equal(nrow(joined), nrow(qc)) # every term is in the table
  for (i in seq_along(arms)) {
    expect_equal(joined[[arms[i]]], joined[[stat_cols[i]]],
      ignore_attr = TRUE
    )
  }
  expect_equal(joined$Total, joined$stat_0, ignore_attr = TRUE)
})

test_that("Percentages use the safety-population denominator", {
  # Spot-check: placebo column of the overall row, e.g. "65 (76%)"
  n_pbo <- sum(adsl_saf$ACTARM == "Placebo")
  row <- tbl_df %>% filter(label == "Treatment Emergent AEs")
  pbo <- row[[stat_cols[which(arms == "Placebo")]]]
  expected_pct <- round(parse_n(pbo) / n_pbo * 100)
  expect_match(pbo, paste0("\\(", expected_pct, "%\\)"))
})

test_that("SOCs are sorted by descending frequency", {
  soc_rows <- tbl_df %>%
    filter(variable == "AESOC") %>%
    mutate(n_total = parse_n(stat_0))
  expect_false(is.unsorted(rev(soc_rows$n_total)))
})

test_that("Terms within each SOC are sorted by descending frequency", {
  rows <- tbl_df %>%
    filter(variable %in% c("AESOC", "AETERM")) %>%
    mutate(
      soc = cumsum(variable == "AESOC"),
      n_total = parse_n(stat_0)
    ) %>%
    filter(variable == "AETERM")
  sorted_ok <- rows %>%
    group_by(soc) %>%
    summarise(ok = !is.unsorted(rev(n_total)))
  expect_true(all(sorted_ok$ok))
})

# =============================================================================
# 3. Plot data QC and output files
# =============================================================================
test_that("Severity plot data match an independent count of ADAE", {
  plot_data <- read.csv(file.path(out_dir, "ae_severity_by_treatment.csv"))
  qc <- adae %>% count(ACTARM, AESEV)

  joined <- inner_join(qc, plot_data,
    by = c("ACTARM", "AESEV"),
    suffix = c("_qc", "_plot")
  )
  expect_equal(nrow(joined), nrow(qc))
  expect_equal(joined$n_qc, joined$n_plot)
  expect_equal(sum(plot_data$n), nrow(adae))
})

test_that("Top 10 plot data match an independent incidence calculation", {
  plot_data <- read.csv(file.path(out_dir, "top10_ae_incidence.csv"))
  n_subj <- n_distinct(adae$USUBJID)
  qc <- adae %>%
    distinct(USUBJID, AETERM) %>%
    count(AETERM) %>%
    arrange(desc(n), AETERM) %>%
    slice_head(n = 10)

  expect_equal(plot_data$AETERM, qc$AETERM, ignore_attr = TRUE)
  expect_equal(plot_data$n, qc$n)
  expect_equal(plot_data$pct, qc$n / n_subj)
  expect_equal(
    plot_data$ci_low,
    sapply(qc$n, function(k) binom.test(k, n_subj)$conf.int[1])
  )
})

test_that("All output files exist and are not empty", {
  files <- c(
    "ae_summary_table.html", "ae_severity_by_treatment.png",
    "top10_ae_incidence.png"
  )
  for (f in files) {
    path <- file.path(out_dir, f)
    expect_true(file.exists(path), info = f)
    expect_gt(file.size(path), 1000)
  }
})
