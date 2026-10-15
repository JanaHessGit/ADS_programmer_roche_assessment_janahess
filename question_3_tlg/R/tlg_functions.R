# =============================================================================
# Program : R/tlg_functions.R
# Purpose : Helper functions shared by the TLG programs
#           (01_create_ae_summary_table.R, 02_create_visualizations.R) and the
#           tests (tests/testthat/test-tlg.R). Keeping the calculations in
#           functions makes them testable on small dummy data.
# =============================================================================

#' Severity levels in their natural (ordinal) order
severity_levels <- c("MILD", "MODERATE", "SEVERE")

#' Number of AE records by treatment arm and severity
#'
#' @param adae ADAE dataset with ACTARM and AESEV.
#' @return Tibble with ACTARM, AESEV (factor, ordered MILD < MODERATE < SEVERE)
#'   and n (number of AE records). Arm/severity combinations without records
#'   are included with n = 0.
count_ae_by_severity <- function(adae) {
  stopifnot(all(c("ACTARM", "AESEV") %in% names(adae)))
  stopifnot(all(adae$AESEV %in% c(severity_levels, NA)))

  # .data pronoun: refer to dataset columns explicitly inside functions
  adae %>%
    dplyr::filter(!is.na(.data$AESEV)) %>%
    dplyr::mutate(
      ACTARM = factor(.data$ACTARM),
      AESEV  = factor(.data$AESEV, levels = severity_levels)
    ) %>%
    # .drop = FALSE keeps arm/severity combinations without records (n = 0)
    dplyr::count(.data$ACTARM, .data$AESEV, name = "n", .drop = FALSE) %>%
    dplyr::mutate(ACTARM = as.character(.data$ACTARM))
}

#' Top AE terms by subject incidence, with exact 95% confidence intervals
#'
#' Incidence = number of subjects with at least one record of the term divided
#' by the number of subjects in the denominator. 95% CIs are exact
#' Clopper-Pearson intervals (stats::binom.test).
#'
#' @param adae ADAE dataset with USUBJID and AETERM.
#' @param n_top Number of terms to return.
#' @param denominator Number of subjects used as denominator. Default: all
#'   subjects in `adae` (as in the assessment's sample output).
#' @return Tibble with AETERM, n, N, pct, ci_low, ci_high (proportions 0-1),
#'   sorted by descending n (ties sorted alphabetically).
top_ae_incidence <- function(adae, n_top = 10,
                             denominator = dplyr::n_distinct(adae$USUBJID)) {
  stopifnot(all(c("USUBJID", "AETERM") %in% names(adae)))
  stopifnot(denominator >= dplyr::n_distinct(adae$USUBJID))

  adae %>%
    dplyr::filter(!is.na(.data$AETERM)) %>%
    # a subject counts once per term, however many records it has
    dplyr::distinct(.data$USUBJID, .data$AETERM) %>%
    dplyr::count(.data$AETERM, name = "n") %>%
    dplyr::arrange(dplyr::desc(.data$n), .data$AETERM) %>%
    dplyr::slice_head(n = n_top) %>%
    dplyr::mutate(
      N   = denominator,
      pct = .data$n / .data$N,
      # exact (Clopper-Pearson) 95% CI; binom.test() takes one count at a
      # time, so it is run once per term and returns c(lower, upper)
      ci  = purrr::map2(.data$n, .data$N,
                        \(k, total) stats::binom.test(k, total)$conf.int),
      ci_low  = purrr::map_dbl(.data$ci, 1),
      ci_high = purrr::map_dbl(.data$ci, 2)
    ) %>%
    dplyr::select(-"ci")
}
